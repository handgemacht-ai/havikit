#if canImport(UIKit)
import Foundation
import XCTest
@testable import HaviKit

/// The connect model's browser wiring (bead havi-jnjj), driven with an inert
/// config so nothing touches the network: `createSetupLink` fails fast (no base
/// URL), so no `.awaiting` phase is reached and the sign-in browser stays inert —
/// the pending→open→dismiss transitions themselves are covered deterministically
/// by `HaviConnectBrowserStateTests`.
@MainActor
final class HaviConnectModelTests: XCTestCase {
    private func inertModel() -> HaviConnectModel {
        let runtime = HaviRuntime(
            config: .inert,
            tokenStore: HaviTokenStore(backing: HaviInMemoryCredentialBacking())
        )
        return HaviConnectModel(runtime: runtime, reconnect: true)
    }

    func testNoApproveURLAndSignInInertBeforeALinkIsPending() {
        let model = inertModel() // phase .creating, no link yet
        XCTAssertNil(model.approveURL)

        model.openApproval() // "Sign in with HAVI" tapped too early
        XCTAssertFalse(model.browser.isPresented)
    }

    func testBrowserClosedKeepsPresentationCleared() {
        let model = inertModel()
        model.browserClosed()
        XCTAssertFalse(model.browser.isPresented)
    }

    func testStartReseedsBrowserState() {
        let model = inertModel()
        model.start() // inert config → runFlow fails fast, no network
        XCTAssertFalse(model.browser.isPresented)
        XCTAssertFalse(model.browser.isAwaitingApproval)
        model.cancel()
    }
}
#endif
