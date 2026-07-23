package ai.handgemacht.havikit

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import kotlin.math.max
import kotlin.math.roundToInt

/**
 * The Android submit pipeline (wire spec §5 privacy posture, §9), matching the
 * iOS `HaviCaptureModel.submit` order exactly so the same privacy guarantees hold:
 *
 *  1. **byte-crop first** — pixels outside the crop never leave the device;
 *  2. project surviving marks into the cropped image's own 0..1 space (fully
 *     outside dropped, partial clipped downstream);
 *  3. **burn blur/redact** regions into the cropped bytes before any encode;
 *  4. encode + downscale to the format cap ([HaviImagePipeline]);
 *  5. build the W3C envelope (marks → image-pixel SVG + FragmentSelector, the
 *     CssSelector a11y hint, diagnostics, dev block, secret-scrubbed context).
 *
 * Everything geometric is delegated to the pure `:havikit-core` (`HaviCropGeometry`,
 * `HaviMarkupSerializer`, `HaviCaptureGeometry`), so the envelope bytes stay
 * byte-identical to the shared golden fixture.
 */
internal object HaviSubmitPipeline {
    data class Prepared(
        val pending: PendingAnnotation,
        val outgoing: Bitmap,
    )

    /** Input the capture form gathers for a submit; the bitmap + a11y come from the frozen frame. */
    data class Draft(
        val cropRect: HaviRectF,
        val marks: List<HaviMark>,
        val comment: String?,
        val priority: String?,
        val labels: List<HaviLabel>,
        val includeConsoleErrors: Boolean,
        val includeNetworkErrors: Boolean,
    )

    /**
     * Runs the pipeline over a frozen [frame], returning the immutable
     * [PendingAnnotation] the uploader consumes, or null when the screenshot
     * cannot be encoded. [workspaceId]/[bearerToken] are snapshotted by the caller.
     */
    fun prepare(
        frame: HaviCaptureFrame,
        draft: Draft,
        config: HaviConfig,
        workspaceId: String?,
        bearerToken: String?,
    ): Prepared? {
        val cropped = cropBitmap(frame.bitmap, draft.cropRect)
        val projectedMarks = HaviCropGeometry.projectMarks(draft.marks, draft.cropRect)
        val outgoing = burnBlurRegions(cropped, projectedMarks)

        val encodedBytes = HaviImagePipeline.encode(outgoing, config.imageFormat) ?: return null
        val imageSize = HaviSize(outgoing.width, outgoing.height)

        val input =
            buildInput(
                frame = frame,
                draft = draft,
                projectedMarks = projectedMarks,
                imageSize = imageSize,
                config = config,
            )

        val pending =
            PendingAnnotation.make(
                input = input,
                imageData = encodedBytes,
                imageFormat = config.imageFormat,
                workspaceId = workspaceId,
                bearerToken = bearerToken,
                reencoder = HaviImagePipeline.reencoder(outgoing),
            )
        return Prepared(pending, outgoing)
    }

    private fun buildInput(
        frame: HaviCaptureFrame,
        draft: Draft,
        projectedMarks: List<HaviMark>,
        imageSize: HaviSize,
        config: HaviConfig,
    ): HaviEnvelopeInput {
        val markupSvg = HaviMarkupSerializer.svg(projectedMarks, imageSize)
        val fragment =
            HaviMarkupSerializer.boundingBox(projectedMarks, imageSize)
                ?: HaviCaptureGeometry.fullFrameRect(imageSize)

        // The CssSelector hint stays in full-image / window-pixel space (where the
        // a11y frames were captured), so it uses the surviving marks' ORIGINAL
        // (pre-crop) geometry, not the crop-relative marks above.
        val survivingIds = projectedMarks.map { it.id }.toSet()
        val hintSourceMarks = draft.marks.filter { it.id in survivingIds }
        val hint =
            HaviMarkupSerializer.normalizedBoundingBox(hintSourceMarks)?.let { bounds ->
                val cx = (bounds.midX * frame.imagePixelSize.width).roundToInt()
                val cy = (bounds.midY * frame.imagePixelSize.height).roundToInt()
                nearestIdentifier(cx, cy, frame.accessibility)
            }

        val split = HaviDiagnostics.split(frame.logEntries)
        val consoleErrors =
            if (draft.includeConsoleErrors) HaviDiagnostics.formatConsole(split.consoleErrors).ifEmpty { null } else null
        val networkErrors =
            if (draft.includeNetworkErrors) HaviDiagnostics.formatNetwork(split.networkErrors).ifEmpty { null } else null
        val appLogs = HaviDiagnostics.formatConsole(split.breadcrumbs).ifEmpty { null }

        return HaviEnvelopeInput(
            bundleId = frame.bundleId,
            screen = frame.screen,
            viewport = HaviCropGeometry.projectedViewport(frame.viewportPoints, draft.cropRect),
            fragment = fragment,
            markupSvg = markupSvg,
            cssPath = HaviCaptureGeometry.cssPath(frame.screen, hint),
            comment = draft.comment,
            priority = draft.priority,
            labels = draft.labels,
            deviceInfo = HaviAndroidDeviceInfo.describe(frame.orientation),
            consoleErrors = consoleErrors,
            networkErrors = networkErrors,
            appLogs = appLogs,
            dev =
                HaviDev(
                    project = config.project,
                    worktree = config.worktree,
                    branch = config.branch,
                    commit = config.commit,
                ),
            contexts = frame.contexts,
            tags = frame.tags,
        )
    }

    /** iOS `nearestIdentifier`: frames containing the point, smallest area wins. */
    private fun nearestIdentifier(
        x: Int,
        y: Int,
        frames: List<HaviAccessibilityFrame>,
    ): String? =
        frames
            .filter { it.rect.left <= x && x <= it.rect.right && it.rect.top <= y && y <= it.rect.bottom }
            .minByOrNull { it.rect.width.toLong() * it.rect.height.toLong() }
            ?.id

    /** Crops [bitmap] to a normalized [crop] rect, clamped into the pixel bounds. */
    private fun cropBitmap(
        bitmap: Bitmap,
        crop: HaviRectF,
    ): Bitmap {
        val clamped = HaviCropGeometry.clamped(crop)
        if (clamped == HaviCropGeometry.fullFrame) return bitmap
        val x = (clamped.minX * bitmap.width).roundToInt().coerceIn(0, bitmap.width - 1)
        val y = (clamped.minY * bitmap.height).roundToInt().coerceIn(0, bitmap.height - 1)
        val w = max(1, (clamped.width * bitmap.width).roundToInt()).coerceAtMost(bitmap.width - x)
        val h = max(1, (clamped.height * bitmap.height).roundToInt()).coerceAtMost(bitmap.height - y)
        return Bitmap.createBitmap(bitmap, x, y, w, h)
    }

    /**
     * Burns opaque black rects over the blur/redact regions (normalized to the
     * cropped image's own space) before any bytes exist — the marks never appear
     * in the SVG/selectors, only in the pixels. Works on a mutable copy so the
     * original frozen frame stays intact for a retry.
     */
    private fun burnBlurRegions(
        bitmap: Bitmap,
        projectedMarks: List<HaviMark>,
    ): Bitmap {
        val blurRects = HaviMarkupSerializer.blurRects(projectedMarks)
        if (blurRects.isEmpty()) return bitmap
        val mutable = if (bitmap.isMutable) bitmap else bitmap.copy(Bitmap.Config.ARGB_8888, true)
        val canvas = Canvas(mutable)
        val paint =
            Paint().apply {
                color = Color.BLACK
                style = Paint.Style.FILL
                isAntiAlias = false
            }
        val size = HaviSize(mutable.width, mutable.height)
        for (rect in blurRects) {
            val px = HaviCaptureGeometry.imagePixelRect(rect, size)
            if (px.width <= 0 || px.height <= 0) continue
            val left = px.x.toFloat()
            val top = px.y.toFloat()
            canvas.drawRect(left, top, left + px.width, top + px.height, paint)
        }
        return mutable
    }
}
