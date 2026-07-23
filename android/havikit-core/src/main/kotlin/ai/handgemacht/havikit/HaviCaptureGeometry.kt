package ai.handgemacht.havikit

import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * Pure coordinate math for the capture sheet (wire spec §6.3, §9.3). Markup is
 * tracked normalized (0…1 in image space) so it is resolution-independent; at
 * submit time it is projected into the downscaled image-pixel space of the encoded
 * screenshot — the space the `FragmentSelector` / `SvgSelector` coordinates live in.
 */
public object HaviCaptureGeometry {
    public const val MIN_MARKUP_FRACTION: Double = 0.01

    /**
     * Projects a normalized rect (0…1 in image space) onto integer image pixels,
     * clamped to the image bounds. A zero-area result is treated by the caller as
     * "no markup".
     */
    public fun imagePixelRect(
        fraction: HaviRectF,
        imageSize: HaviSize,
    ): HaviRect {
        val clamped = clampUnit(fraction)
        val x = (clamped.minX * imageSize.width).roundToInt()
        val y = (clamped.minY * imageSize.height).roundToInt()
        val w = (clamped.width * imageSize.width).roundToInt()
        val h = (clamped.height * imageSize.height).roundToInt()
        val clampedX = min(max(0, x), imageSize.width)
        val clampedY = min(max(0, y), imageSize.height)
        return HaviRect(
            x = clampedX,
            y = clampedY,
            width = max(0, min(w, imageSize.width - clampedX)),
            height = max(0, min(h, imageSize.height - clampedY)),
        )
    }

    /** The full-frame region used for the `FragmentSelector` when there is no markup. */
    public fun fullFrameRect(imageSize: HaviSize): HaviRect =
        HaviRect(x = 0, y = 0, width = imageSize.width, height = imageSize.height)

    /** A drawn rectangle is meaningful only when it covers a non-trivial area. */
    public fun isMeaningful(fraction: HaviRectF): Boolean {
        val clamped = clampUnit(fraction)
        return clamped.width >= MIN_MARKUP_FRACTION && clamped.height >= MIN_MARKUP_FRACTION
    }

    /** The display-only `CssSelector` value: `"<screen>"`, or `"<screen> > <a11y-id>"`. */
    public fun cssPath(
        screen: String,
        hint: String?,
    ): String = if (hint.isNullOrEmpty()) screen else "$screen > $hint"

    private fun clampUnit(rect: HaviRectF): HaviRectF {
        val x = min(max(0.0, rect.minX), 1.0)
        val y = min(max(0.0, rect.minY), 1.0)
        val maxX = min(max(0.0, rect.maxX), 1.0)
        val maxY = min(max(0.0, rect.maxY), 1.0)
        return HaviRectF(x, y, max(0.0, maxX - x), max(0.0, maxY - y))
    }
}
