package ai.handgemacht.havikit

import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** In-app approval browser sub-state-machine (wire spec §4.5). */
class HaviConnectBrowserStateTest {
    @Test
    fun opensOnlyWhileAwaiting() {
        val stale = HaviConnectBrowserState().openRequested()
        assertFalse(stale.isPresented, "a tap before awaiting is a no-op")

        val open = HaviConnectBrowserState().beganAwaiting().openRequested()
        assertTrue(open.isPresented)
        assertTrue(open.isAwaitingApproval)
    }

    @Test
    fun browserClosedLeavesAwaitingIntact() {
        val closed = HaviConnectBrowserState().beganAwaiting().openRequested().browserClosed()
        assertFalse(closed.isPresented)
        assertTrue(closed.isAwaitingApproval, "closing the browser never ends the pairing")
    }

    @Test
    fun flowSettledForcesBrowserDownAndClearsAwaiting() {
        val settled = HaviConnectBrowserState().beganAwaiting().openRequested().flowSettled()
        assertFalse(settled.isPresented)
        assertFalse(settled.isAwaitingApproval)
        // a stale tap after settling cannot re-present a dead browser
        assertFalse(settled.openRequested().isPresented)
    }
}
