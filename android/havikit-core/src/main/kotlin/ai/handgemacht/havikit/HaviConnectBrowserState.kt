package ai.handgemacht.havikit

/**
 * Pure sub-state-machine for the in-app approval browser (Custom Tab on Android),
 * kept free of any UI so the open / auto-dismiss transitions unit-test on the JVM
 * (wire spec §4.5). The connect flow owns one and mirrors [isPresented] into the
 * sheet, which starts and tears down the Custom Tab from it.
 *
 * The three rules it encodes:
 *  - the sign-in browser may open only while a link is pending approval,
 *  - closing the browser never ends the pairing — the poll loop keeps running so a
 *    background approval still lands,
 *  - reaching any terminal poll outcome forces the browser down (auto-dismiss on
 *    success).
 *
 * Immutable value with copy-on-transition semantics (parity with the Swift
 * `mutating` methods), so it composes cleanly into any state holder.
 */
public data class HaviConnectBrowserState(
    /** A link is currently pending approval (the flow's `awaiting` phase). */
    val isAwaitingApproval: Boolean = false,
    /** The in-app approval browser should be on screen. */
    val isPresented: Boolean = false,
) {
    /** A fresh link became pending — "Sign in with HAVI" is now actionable. */
    public fun beganAwaiting(): HaviConnectBrowserState = copy(isAwaitingApproval = true)

    /**
     * The user tapped "Sign in with HAVI". Opens only while awaiting so a stale
     * tap after the flow settled can't re-present a dead browser.
     */
    public fun openRequested(): HaviConnectBrowserState = if (isAwaitingApproval) copy(isPresented = true) else this

    /** The browser closed — user dismissed it, or it was torn down. Polling is untouched. */
    public fun browserClosed(): HaviConnectBrowserState = copy(isPresented = false)

    /**
     * The poll loop reached a terminal outcome (connected / expired / error /
     * cancelled): leave `awaiting` and force the browser down so a success while
     * the browser is up dismisses it automatically.
     */
    public fun flowSettled(): HaviConnectBrowserState = copy(isAwaitingApproval = false, isPresented = false)
}
