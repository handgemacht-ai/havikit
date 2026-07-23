package ai.handgemacht.havikit

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test

/** Downscale planner math (wire spec §9.2). */
class HaviImagePlanTest {
    @Test
    fun scaleNeverUpscales() {
        assertEquals(1.0, HaviImagePlan.scale(800, 600, 1600))
        assertEquals(0.5, HaviImagePlan.scale(3200, 1600, 1600))
    }

    @Test
    fun targetSizePreservesAspectRatio() {
        assertEquals(HaviSize(1600, 800), HaviImagePlan.targetSize(3200, 1600, 1600))
        assertEquals(HaviSize(1200, 1600), HaviImagePlan.targetSize(1200, 1600, 1600))
    }

    @Test
    fun ladderStepsDownAndFloors() {
        assertEquals(1280, HaviImagePlan.nextStepDown(below = 1600))
        assertEquals(1024, HaviImagePlan.nextStepDown(below = 1280))
        assertEquals(900, HaviImagePlan.nextStepDown(below = 1024))
        assertNull(HaviImagePlan.nextStepDown(below = 900))
    }

    @Test
    fun formatCapsAndPartsMatchSpec() {
        assertEquals(2_097_152, HaviImageFormat.PNG.maxUploadBytes)
        assertEquals(5_242_880, HaviImageFormat.JPEG.maxUploadBytes)
        assertEquals("screenshot.png", HaviImageFormat.PNG.multipartFilename)
        assertEquals("screenshot.jpg", HaviImageFormat.JPEG.multipartFilename)
        assertEquals("image/png", HaviImageFormat.PNG.multipartContentType)
        assertEquals("image/jpeg", HaviImageFormat.JPEG.multipartContentType)
    }
}
