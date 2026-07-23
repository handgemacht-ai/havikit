package ai.handgemacht.havikit

import android.app.Activity
import android.content.res.Configuration
import android.graphics.Bitmap
import kotlin.math.roundToInt

/** The seam the capture sheet (a later stage) registers on to receive a frozen frame. */
internal fun interface HaviCaptureHandler {
    fun onCaptured(frame: HaviCaptureFrame)
}

/**
 * Orchestrates a single capture (Part B4): resolve the screen name, freeze the window,
 * scan the view tree, burn the redaction masks into the pixels, and assemble an
 * immutable [HaviCaptureFrame]. A [handler] (the capture sheet) consumes the frame and
 * calls [finishCapture] when the sheet closes; with no handler yet the controller
 * simply resets so the next trigger works. A capture already in flight is a no-op,
 * mirroring iOS "presentCapture is a no-op if a sheet is already up".
 */
internal class HaviCaptureController(
    private val config: HaviConfig,
    private val contextStore: HaviContextStore,
    private val logBuffer: HaviLogBuffer,
) {
    private val snapshotter = HaviSnapshotter()

    @Volatile
    var handler: HaviCaptureHandler? = null

    @Volatile
    private var capturing = false

    fun present(
        activity: Activity,
        screenArg: String?,
    ) {
        if (capturing) return
        capturing = true

        val screen = resolveScreen(activity, screenArg)
        snapshotter.capture(activity) { bitmap ->
            if (bitmap == null) {
                capturing = false
                return@capture
            }
            val frame = buildFrame(activity, bitmap, screen)
            val consumer = handler
            if (consumer != null) {
                consumer.onCaptured(frame)
            } else {
                capturing = false
            }
        }
    }

    fun finishCapture() {
        capturing = false
    }

    /**
     * Encodes a captured frame into the immutable [PendingAnnotation] the uploader
     * consumes, honoring `HAVI_IMAGE_FORMAT`. The envelope [input] (marks, diagnostics,
     * dev block) is assembled by the capture sheet in a later stage; this method is the
     * bitmap → upload-model bridge, including the reencoder for the server fallbacks.
     */
    fun encodeToPending(
        frame: HaviCaptureFrame,
        input: HaviEnvelopeInput,
        workspaceId: String?,
        bearerToken: String?,
    ): PendingAnnotation? {
        val bytes = HaviImagePipeline.encode(frame.bitmap, config.imageFormat) ?: return null
        return PendingAnnotation.make(
            input = input,
            imageData = bytes,
            imageFormat = config.imageFormat,
            workspaceId = workspaceId,
            bearerToken = bearerToken,
            reencoder = HaviImagePipeline.reencoder(frame.bitmap),
        )
    }

    private fun buildFrame(
        activity: Activity,
        bitmap: Bitmap,
        screen: String,
    ): HaviCaptureFrame {
        val decor = activity.window.peekDecorView()
        val scan = decor?.let { HaviViewScan.scan(it) } ?: HaviViewScanResult(emptyList(), emptyList())

        val decorOffset = IntArray(2)
        decor?.getLocationInWindow(decorOffset)
        val masks =
            buildMasks(scan.textFields)
                .map { it.translate(-decorOffset[0], -decorOffset[1]) }
        HaviBitmapRedactor.apply(bitmap, masks)

        val density = activity.resources.displayMetrics.density.takeIf { it > 0f } ?: 1f
        val viewport =
            HaviSize(
                width = (bitmap.width / density).roundToInt(),
                height = (bitmap.height / density).roundToInt(),
            )

        return HaviCaptureFrame(
            bitmap = bitmap,
            bundleId = activity.packageName,
            screen = screen,
            viewportPoints = viewport,
            imagePixelSize = HaviSize(bitmap.width, bitmap.height),
            orientation = orientationOf(activity),
            accessibility = scan.accessibility,
            logEntries = logBuffer.snapshot(),
            contexts = contextStore.snapshotContexts(),
            tags = contextStore.snapshotTags(),
        )
    }

    /** Explicit redacted regions always mask; text fields mask unless a reveal region covers them. */
    private fun buildMasks(textFields: List<HaviWindowRect>): List<HaviWindowRect> {
        val snapshot = HaviRedactionRegistry.snapshot()
        val masks = ArrayList<HaviWindowRect>(snapshot.redacted)
        if (config.redaction.maskTextFieldsByDefault) {
            for (field in textFields) {
                if (snapshot.revealed.none { it.containsCenterOf(field) }) {
                    masks.add(field)
                }
            }
        }
        return masks
    }

    private fun resolveScreen(
        activity: Activity,
        screenArg: String?,
    ): String {
        screenArg?.takeIf { it.isNotBlank() }?.let { return it }
        contextStore.currentScreen()?.takeIf { it.isNotBlank() }?.let { return it }
        HaviScreenName.screen(activity.javaClass.name)?.let { return it }
        return "unknown"
    }

    private fun orientationOf(activity: Activity): HaviCaptureOrientation =
        if (activity.resources.configuration.orientation == Configuration.ORIENTATION_LANDSCAPE) {
            HaviCaptureOrientation.LANDSCAPE
        } else {
            HaviCaptureOrientation.PORTRAIT
        }
}
