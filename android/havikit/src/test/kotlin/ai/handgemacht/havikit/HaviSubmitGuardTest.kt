package ai.handgemacht.havikit

import kotlinx.coroutines.CancellationException
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertThrows

/**
 * The submit pipeline is the only place in HaviKit that touches raw bitmap memory,
 * and it runs inside a coroutine the host app never sees. Anything escaping it
 * crashes the host over a feedback report, so the guard is pinned on the exact
 * failures the pipeline can produce: a degenerate crop rect (`Bitmap.createBitmap`
 * throws), an exhausted heap (an `Error`, not an `Exception`), and cancellation,
 * which must stay cancellation.
 */
class HaviSubmitGuardTest {
    @Test
    fun `a successful preparation passes its value through`() {
        assertEquals("prepared", HaviSubmitPipeline.guarded { "prepared" })
    }

    @Test
    fun `a pipeline that cannot encode stays null`() {
        assertNull(HaviSubmitPipeline.guarded<String> { null })
    }

    @Test
    fun `a degenerate crop is a failure, not a crash`() {
        assertNull(HaviSubmitPipeline.guarded<String> { throw IllegalArgumentException("width must be > 0") })
    }

    @Test
    fun `an exhausted heap is a failure, not a crash`() {
        assertNull(HaviSubmitPipeline.guarded<String> { throw OutOfMemoryError("Failed to allocate a 34992012 byte allocation") })
    }

    @Test
    fun `cancellation is never swallowed`() {
        assertThrows<CancellationException> {
            HaviSubmitPipeline.guarded<String> { throw CancellationException("sheet dismissed") }
        }
    }

    @Test
    fun `the terminal failure matches the iOS wording`() {
        val failure = HaviSubmitPipeline.preparationFailure

        assertEquals("Couldn't prepare the screenshot.", failure.userMessage)
        assertEquals(HaviSubmitFailureKind.TERMINAL, failure.kind)
        assertNull(failure.code)
    }
}
