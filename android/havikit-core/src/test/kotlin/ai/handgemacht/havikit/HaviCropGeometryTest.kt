package ai.handgemacht.havikit

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** Crop projection math (wire spec §A4): drop-outside, proportional viewport/image size, no-op on full frame. */
class HaviCropGeometryTest {
    private val crop = HaviRectF(0.25, 0.25, 0.5, 0.5)

    @Test
    fun projectMarksDropsMarksFullyOutsideCrop() {
        val inside = HaviMark(HaviMark.Shape.Rectangle(HaviRectF(0.4, 0.4, 0.2, 0.1)), HaviMarkColor.Red)
        val outside = HaviMark(HaviMark.Shape.Rectangle(HaviRectF(0.85, 0.85, 0.1, 0.1)), HaviMarkColor.Blue)
        val projected = HaviCropGeometry.projectMarks(listOf(inside, outside), crop)
        assertEquals(1, projected.size)
    }

    @Test
    fun projectMarksIsNoOpOnFullFrame() {
        val marks = listOf(HaviMark(HaviMark.Shape.Rectangle(HaviRectF(0.4, 0.4, 0.2, 0.1)), HaviMarkColor.Red))
        assertEquals(marks, HaviCropGeometry.projectMarks(marks, HaviCropGeometry.fullFrame))
    }

    @Test
    fun projectedSizesAreProportional() {
        assertEquals(HaviSize(400, 800), HaviCropGeometry.projectedImageSize(HaviSize(800, 1600), crop))
        assertEquals(HaviSize(200, 400), HaviCropGeometry.projectedViewport(HaviSize(400, 800), crop))
    }

    @Test
    fun resizeNeverCollapsesBelowMinFraction() {
        val resized = HaviCropGeometry.resize(HaviRectF(0.0, 0.0, 1.0, 1.0), HaviCropGeometry.Handle.RIGHT, HaviPointF(0.0, 0.5))
        assertTrue(resized.width >= HaviCropGeometry.MIN_CROP_FRACTION)
    }

    @Test
    fun canvasRoundTripIsIdentityOnFullFrame() {
        val normalized = HaviCropGeometry.normalizedFromCanvas(50.0, 100.0, 200.0, 400.0, HaviCropGeometry.fullFrame)
        assertEquals(0.25, normalized.x, 1e-9)
        assertEquals(0.25, normalized.y, 1e-9)
        val canvas = HaviCropGeometry.canvasFromNormalized(normalized, 200.0, 400.0, HaviCropGeometry.fullFrame)
        assertEquals(50.0, canvas.x, 1e-9)
        assertEquals(100.0, canvas.y, 1e-9)
    }

    @Test
    fun canvasMapsIntoZoomedVisibleRegion() {
        // Center of the content maps to the center of the visible crop, in full-image space.
        val normalized = HaviCropGeometry.normalizedFromCanvas(100.0, 200.0, 200.0, 400.0, crop)
        assertEquals(crop.midX, normalized.x, 1e-9)
        assertEquals(crop.midY, normalized.y, 1e-9)
    }

    @Test
    fun meaningfulMarkRejectsTapButKeepsDeliberateStroke() {
        val tap = HaviMark(HaviMark.Shape.Pen(listOf(HaviPointF(0.5, 0.5), HaviPointF(0.5005, 0.5005))), HaviMarkColor.Red)
        val stroke = HaviMark(HaviMark.Shape.Pen(listOf(HaviPointF(0.2, 0.2), HaviPointF(0.6, 0.6))), HaviMarkColor.Red)
        assertTrue(!HaviCropGeometry.isMeaningfulMark(tap))
        assertTrue(HaviCropGeometry.isMeaningfulMark(stroke))
    }

    @Test
    fun hitTestIsZoomAwareAcrossVisibleRegion() {
        val mark = HaviMark(HaviMark.Shape.Rectangle(HaviRectF(0.4, 0.4, 0.1, 0.1)), HaviMarkColor.Red)
        // A point just outside the mark in full space is a miss with no zoom...
        assertTrue(!HaviCropGeometry.markHitTest(mark, HaviPointF(0.6, 0.6), 0.03))
        // ...but a point inside the mark hits regardless of the visible region.
        assertTrue(HaviCropGeometry.markHitTest(mark, HaviPointF(0.45, 0.45), 0.03, crop))
    }
}
