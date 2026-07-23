package ai.handgemacht.havikit

import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * Pure crop math for the capture sheet's crop tool (wire spec §A4). The crop rect
 * lives in the SAME normalized (0…1) space as the frozen still and the markup
 * marks — fractions of the FULL, uncropped image. Marks stay in that full-image
 * space while editing; only at envelope-build time are they projected into the
 * cropped image's own 0…1 space via [projectMarks], after the real byte crop has
 * produced that image.
 */
public object HaviCropGeometry {
    public val fullFrame: HaviRectF = HaviRectF(0.0, 0.0, 1.0, 1.0)

    /** Below this fraction on either axis a crop stops shrinking further. */
    public const val MIN_CROP_FRACTION: Double = 0.1

    /** The eight handles on the crop rect: four corners plus four edge midpoints. */
    public enum class Handle(public val id: String) {
        TOP_LEFT("topLeft"),
        TOP("top"),
        TOP_RIGHT("topRight"),
        RIGHT("right"),
        BOTTOM_RIGHT("bottomRight"),
        BOTTOM("bottom"),
        BOTTOM_LEFT("bottomLeft"),
        LEFT("left"),
        ;

        public val accessibilityId: String get() = "havi-crop-handle-$id"

        public val movesLeftEdge: Boolean get() = this == TOP_LEFT || this == LEFT || this == BOTTOM_LEFT
        public val movesRightEdge: Boolean get() = this == TOP_RIGHT || this == RIGHT || this == BOTTOM_RIGHT
        public val movesTopEdge: Boolean get() = this == TOP_LEFT || this == TOP || this == TOP_RIGHT
        public val movesBottomEdge: Boolean get() = this == BOTTOM_LEFT || this == BOTTOM || this == BOTTOM_RIGHT
    }

    public fun anchor(
        handle: Handle,
        rect: HaviRectF,
    ): HaviPointF =
        when (handle) {
            Handle.TOP_LEFT -> HaviPointF(rect.minX, rect.minY)
            Handle.TOP -> HaviPointF(rect.midX, rect.minY)
            Handle.TOP_RIGHT -> HaviPointF(rect.maxX, rect.minY)
            Handle.RIGHT -> HaviPointF(rect.maxX, rect.midY)
            Handle.BOTTOM_RIGHT -> HaviPointF(rect.maxX, rect.maxY)
            Handle.BOTTOM -> HaviPointF(rect.midX, rect.maxY)
            Handle.BOTTOM_LEFT -> HaviPointF(rect.minX, rect.maxY)
            Handle.LEFT -> HaviPointF(rect.minX, rect.midY)
        }

    /** [rect] with [handle]'s edge(s) dragged to [point], clamped and never below [MIN_CROP_FRACTION]. */
    public fun resize(
        rect: HaviRectF,
        handle: Handle,
        point: HaviPointF,
    ): HaviRectF {
        val px = min(max(0.0, point.x), 1.0)
        val py = min(max(0.0, point.y), 1.0)

        var minX = rect.minX
        var minY = rect.minY
        var maxX = rect.maxX
        var maxY = rect.maxY
        if (handle.movesLeftEdge) minX = px
        if (handle.movesRightEdge) maxX = px
        if (handle.movesTopEdge) minY = py
        if (handle.movesBottomEdge) maxY = py

        if (maxX - minX < MIN_CROP_FRACTION) {
            if (handle.movesLeftEdge) minX = maxX - MIN_CROP_FRACTION
            if (handle.movesRightEdge) maxX = minX + MIN_CROP_FRACTION
        }
        if (maxY - minY < MIN_CROP_FRACTION) {
            if (handle.movesTopEdge) minY = maxY - MIN_CROP_FRACTION
            if (handle.movesBottomEdge) maxY = minY + MIN_CROP_FRACTION
        }

        return HaviRectF(minX, minY, maxX - minX, maxY - minY)
    }

    /** Defensive clamp of a crop rect into the full-image unit square. */
    public fun clamped(rect: HaviRectF): HaviRectF {
        val s = rect.standardized()
        val minX = min(max(0.0, s.minX), 1.0)
        val minY = min(max(0.0, s.minY), 1.0)
        val maxX = min(max(minX, s.maxX), 1.0)
        val maxY = min(max(minY, s.maxY), 1.0)
        return HaviRectF(minX, minY, maxX - minX, maxY - minY)
    }

    public fun project(
        point: HaviPointF,
        crop: HaviRectF,
    ): HaviPointF {
        if (crop.width <= 0 || crop.height <= 0) return point
        return HaviPointF((point.x - crop.minX) / crop.width, (point.y - crop.minY) / crop.height)
    }

    public fun unproject(
        point: HaviPointF,
        crop: HaviRectF,
    ): HaviPointF = HaviPointF(crop.minX + point.x * crop.width, crop.minY + point.y * crop.height)

    private fun project(
        rect: HaviRectF,
        crop: HaviRectF,
    ): HaviRectF {
        val s = rect.standardized()
        val origin = project(HaviPointF(s.minX, s.minY), crop)
        val far = project(HaviPointF(s.maxX, s.maxY), crop)
        return HaviRectF(origin.x, origin.y, far.x - origin.x, far.y - origin.y)
    }

    /** [mark]'s geometry re-expressed in crop-relative normalized space. */
    public fun project(
        mark: HaviMark,
        crop: HaviRectF,
    ): HaviMark {
        val shape =
            when (val s = mark.shape) {
                is HaviMark.Shape.Pen -> HaviMark.Shape.Pen(s.points.map { project(it, crop) })
                is HaviMark.Shape.Highlighter -> HaviMark.Shape.Highlighter(s.points.map { project(it, crop) })
                is HaviMark.Shape.Arrow -> HaviMark.Shape.Arrow(project(s.from, crop), project(s.to, crop))
                is HaviMark.Shape.Rectangle -> HaviMark.Shape.Rectangle(project(s.rect, crop))
                is HaviMark.Shape.Blur -> HaviMark.Shape.Blur(project(s.rect, crop))
            }
        return mark.copy(shape = shape)
    }

    /** True once [projectedMark]'s bounds share no area with the crop's own unit square. */
    public fun isFullyOutsideCrop(projectedMark: HaviMark): Boolean =
        !fullFrame.intersects(projectedMark.normalizedBounds)

    /**
     * Projects every mark from full-image normalized space into the crop's own
     * normalized space, dropping any that land fully outside it. A no-op when there
     * is no crop.
     */
    public fun projectMarks(
        marks: List<HaviMark>,
        crop: HaviRectF,
    ): List<HaviMark> {
        val clampedCrop = clamped(crop)
        if (clampedCrop == fullFrame) return marks
        return marks
            .map { project(it, clampedCrop) }
            .filterNot { isFullyOutsideCrop(it) }
    }

    /** The `viewport=WxH` value (points) for the cropped image, proportional to the original. */
    public fun projectedViewport(
        viewport: HaviSize,
        crop: HaviRectF,
    ): HaviSize {
        val clampedCrop = clamped(crop)
        if (clampedCrop == fullFrame) return viewport
        return HaviSize(
            width = max(1, (viewport.width * clampedCrop.width).roundToInt()),
            height = max(1, (viewport.height * clampedCrop.height).roundToInt()),
        )
    }

    /** The pixel size of [imageSize] after cropping to [crop]. */
    public fun projectedImageSize(
        imageSize: HaviSize,
        crop: HaviRectF,
    ): HaviSize {
        val clampedCrop = clamped(crop)
        if (clampedCrop == fullFrame) return imageSize
        return HaviSize(
            width = max(1, (imageSize.width * clampedCrop.width).roundToInt()),
            height = max(1, (imageSize.height * clampedCrop.height).roundToInt()),
        )
    }

    // Display transform (canvas point <-> full-image normalized). The canvas shows
    // only [visibleRegion] of the still, scaled to fill a content box of
    // [contentWidth] x [contentHeight]; marks + gestures always speak full-image
    // normalized (0..1) space, so these two are the only bridge to canvas pixels.
    // With [visibleRegion] == [fullFrame] both reduce to the plain point / size map.

    /** A content-local canvas point → full-image normalized point, clamped into [visibleRegion]. */
    public fun normalizedFromCanvas(
        canvasX: Double,
        canvasY: Double,
        contentWidth: Double,
        contentHeight: Double,
        visibleRegion: HaviRectF,
    ): HaviPointF {
        if (contentWidth <= 0 || contentHeight <= 0) return HaviPointF(visibleRegion.minX, visibleRegion.minY)
        val relative =
            HaviPointF(
                x = min(max(0.0, canvasX / contentWidth), 1.0),
                y = min(max(0.0, canvasY / contentHeight), 1.0),
            )
        return unproject(relative, visibleRegion)
    }

    /** A full-image normalized point → content-local canvas point within [visibleRegion]. */
    public fun canvasFromNormalized(
        point: HaviPointF,
        contentWidth: Double,
        contentHeight: Double,
        visibleRegion: HaviRectF,
    ): HaviPointF {
        val relative = project(point, visibleRegion)
        return HaviPointF(relative.x * contentWidth, relative.y * contentHeight)
    }

    /**
     * Whether [mark] is a deliberate mark rather than an accidental tap, judged by
     * its on-screen extent: the mark is projected into [visibleRegion]'s own 0..1
     * space so [HaviCaptureGeometry.MIN_MARKUP_FRACTION] always means the same
     * fraction of the visible (possibly zoomed) view. Identity when
     * [visibleRegion] == [fullFrame].
     */
    public fun isMeaningfulMark(
        mark: HaviMark,
        visibleRegion: HaviRectF = fullFrame,
    ): Boolean =
        when (val s = project(mark, visibleRegion).shape) {
            is HaviMark.Shape.Pen -> s.points.size >= 2 && markSpan(s.points) >= HaviCaptureGeometry.MIN_MARKUP_FRACTION
            is HaviMark.Shape.Highlighter ->
                s.points.size >= 2 && markSpan(s.points) >= HaviCaptureGeometry.MIN_MARKUP_FRACTION
            is HaviMark.Shape.Arrow -> {
                val dx = s.to.x - s.from.x
                val dy = s.to.y - s.from.y
                kotlin.math.hypot(dx, dy) >= HaviCaptureGeometry.MIN_MARKUP_FRACTION
            }
            is HaviMark.Shape.Rectangle -> HaviCaptureGeometry.isMeaningful(s.rect.standardized())
            is HaviMark.Shape.Blur -> HaviCaptureGeometry.isMeaningful(s.rect.standardized())
        }

    /**
     * The select-tool hit test made zoom-aware: both the tap [point] and the
     * [mark] are projected into [visibleRegion]'s own 0..1 space, so the fixed
     * [tolerance] covers the same on-screen distance at any zoom.
     */
    public fun markHitTest(
        mark: HaviMark,
        point: HaviPointF,
        tolerance: Double,
        visibleRegion: HaviRectF = fullFrame,
    ): Boolean = project(mark, visibleRegion).hitTest(project(point, visibleRegion), tolerance)

    private fun markSpan(points: List<HaviPointF>): Double {
        val bounds = HaviRectF.boundsOf(points)
        return max(bounds.width, bounds.height)
    }
}
