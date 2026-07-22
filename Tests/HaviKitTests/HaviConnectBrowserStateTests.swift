import XCTest
@testable import HaviKit

/// The in-app sign-in browser's open / auto-dismiss rules (bead havi-jnjj),
/// extracted into a pure value type so the connect model's browser transitions
/// unit-test on the host with no Simulator. `HaviConnectModel` delegates to these
/// exact mutations: `beganAwaiting` when a link goes pending, `openRequested`
/// behind the "Sign in with HAVI" button, `browserClosed` when the session ends,
/// and `flowSettled` on every terminal poll outcome.
final class HaviConnectBrowserStateTests: XCTestCase {
    func testSignInOpensBrowserOnlyWhileAwaiting() {
        var state = HaviConnectBrowserState()
        // No link pending yet — a "Sign in" tap can't open a browser.
        state.openRequested()
        XCTAssertFalse(state.isPresented)

        state.beganAwaiting()
        state.openRequested()
        XCTAssertTrue(state.isPresented)
        XCTAssertTrue(state.isAwaitingApproval)
    }

    func testSuccessAutoDismissesTheBrowser() {
        var state = HaviConnectBrowserState()
        state.beganAwaiting()
        state.openRequested()
        XCTAssertTrue(state.isPresented)

        // Poll loop connected while the browser was up → it comes down.
        state.flowSettled()
        XCTAssertFalse(state.isPresented)
        XCTAssertFalse(state.isAwaitingApproval)
    }

    func testUserClosingBrowserKeepsAwaitingAndCanReopen() {
        var state = HaviConnectBrowserState()
        state.beganAwaiting()
        state.openRequested()

        // User tapped Done without approving — polling continues, so a later
        // approval can still land and the button can reopen the browser.
        state.browserClosed()
        XCTAssertFalse(state.isPresented)
        XCTAssertTrue(state.isAwaitingApproval)

        state.openRequested()
        XCTAssertTrue(state.isPresented)
    }

    func testOpenAfterFlowSettledIsInert() {
        var state = HaviConnectBrowserState()
        state.beganAwaiting()
        state.flowSettled()
        // A stale "Sign in" tap after the flow ended can't resurrect the browser.
        state.openRequested()
        XCTAssertFalse(state.isPresented)
    }
}
