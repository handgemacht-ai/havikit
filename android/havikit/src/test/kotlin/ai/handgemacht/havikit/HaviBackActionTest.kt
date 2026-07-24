package ai.handgemacht.havikit

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

/**
 * Back while the capture sheet is up. Every case matters: unhandled, Back reaches
 * the host app and navigates (or finishes it) underneath a sheet that stays on
 * screen; handled too eagerly, it tears down a report mid-upload or closes the whole
 * flow when the user only wanted to leave the connect sheet.
 */
class HaviBackActionTest {
    @Test
    fun `back closes the sheet like the Close affordance`() {
        assertEquals(
            HaviBackAction.DISMISS,
            HaviBackAction.resolve(isSubmitting = false, connectOpen = false),
        )
    }

    @Test
    fun `back does nothing while the sheet is locked for a submit`() {
        assertEquals(
            HaviBackAction.IGNORE,
            HaviBackAction.resolve(isSubmitting = true, connectOpen = false),
        )
    }

    @Test
    fun `back leaves the connect sheet before it leaves the capture flow`() {
        assertEquals(
            HaviBackAction.CLOSE_CONNECT,
            HaviBackAction.resolve(isSubmitting = false, connectOpen = true),
        )
    }

    @Test
    fun `a submit outranks an open connect sheet`() {
        assertEquals(
            HaviBackAction.IGNORE,
            HaviBackAction.resolve(isSubmitting = true, connectOpen = true),
        )
    }
}
