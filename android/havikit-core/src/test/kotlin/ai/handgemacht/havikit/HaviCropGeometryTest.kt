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
}
