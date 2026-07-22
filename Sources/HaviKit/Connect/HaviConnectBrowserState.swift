import Foundation

/// Pure sub-state-machine for the in-app approval browser, kept free of UIKit so
/// the open / auto-dismiss transitions unit-test on the host without a Simulator.
/// `HaviConnectModel` owns one and mirrors `isPresented` into the SwiftUI sheet,
/// which starts and tears down the `ASWebAuthenticationSession` from it.
///
/// The three rules it encodes:
/// - the sign-in browser may open only while a link is pending approval,
/// - closing the browser (user tapped Done, or we tore it down) never ends the
///   pairing — the poll loop keeps running so a background approval still lands,
/// - reaching any terminal poll outcome forces the browser down, which is what
///   auto-dismisses it on success.
public struct HaviConnectBrowserState: Sendable, Equatable {
    /// A link is currently pending approval (the model's `.awaiting` phase).
    public private(set) var isAwaitingApproval: Bool
    /// The in-app approval browser should be on screen.
    public private(set) var isPresented: Bool

    public init(isAwaitingApproval: Bool = false, isPresented: Bool = false) {
        self.isAwaitingApproval = isAwaitingApproval
        self.isPresented = isPresented
    }

    /// A fresh link became pending — "Sign in with HAVI" is now actionable.
    public mutating func beganAwaiting() {
        isAwaitingApproval = true
    }

    /// The user tapped "Sign in with HAVI". Opens only while awaiting so a stale
    /// tap after the flow settled can't re-present a dead browser.
    public mutating func openRequested() {
        guard isAwaitingApproval else { return }
        isPresented = true
    }

    /// The in-app browser closed — user tapped Done, or the session was torn down
    /// programmatically. Polling is untouched.
    public mutating func browserClosed() {
        isPresented = false
    }

    /// The poll loop reached a terminal outcome (connected / expired / error /
    /// cancelled): leave `awaiting` and force the browser down so a success while
    /// the browser is up dismisses it automatically.
    public mutating func flowSettled() {
        isAwaitingApproval = false
        isPresented = false
    }
}
