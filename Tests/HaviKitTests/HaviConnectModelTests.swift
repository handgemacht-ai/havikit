#if canImport(UIKit)
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import HaviKit

/// The connect model's browser wiring (bead havi-jnjj), driven with an inert
/// config so nothing touches the network: `createSetupLink` fails fast (no base
/// URL), so no `.awaiting` phase is reached and the sign-in browser stays inert —
/// the pending→open→dismiss transitions themselves are covered deterministically
/// by `HaviConnectBrowserStateTests`.
///
/// The phone-QA finding-2 tests drive a full begin→awaiting→browser→active-cycle
/// sequence with a stubbed `HaviConnectService` (stub `URLProtocol` + injected
/// clock/sleep) so nothing touches the network or wall time.
@MainActor
final class HaviConnectModelTests: XCTestCase {
    private func inertModel() -> HaviConnectModel {
        let runtime = HaviRuntime(
            config: .inert,
            tokenStore: HaviTokenStore(backing: HaviInMemoryCredentialBacking())
        )
        return HaviConnectModel(runtime: runtime, reconnect: true)
    }

    // MARK: - Stubbed-service helpers (phone-QA finding 2)

    private let createLinkJSON = """
    {"data":{"device_code":"dev-9","status":"pending","client_type":"mobile",\
    "approve_url":"/connect/approve?setup_code=dev-9","expires_at":"2099-01-01T00:00:00Z"}}
    """
    private let pendingJSON = #"{"data":{"status":"pending","token_returned":false}}"#
    private let approvedJSON = """
    {"data":{"status":"approved","client_type":"mobile","token":"tok-abc","token_type":"Bearer",\
    "expires_at":"2099-01-01T00:00:00Z","user":{"id":"u1","email":"marco@alimax.at"},\
    "workspace":{"id":"ws-9","name":"Team HAVI","type":"team"}}}
    """

    private func connectConfig() -> HaviConfig {
        HaviConfig(
            isEnabled: true,
            baseURL: URL(string: "https://havi.example.test")!,
            workspaceID: nil, project: nil, worktree: nil, branch: nil, commit: nil,
            imageFormat: .png, devToken: nil, redaction: HaviRedactionPolicy()
        )
    }

    private func stubSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    /// A runtime whose connect service is the stub-backed one, with a no-op sleep
    /// (fast) or a parking sleep that opens `enteredSleep` and then blocks so a
    /// test can catch the loop at `.awaiting`.
    private func stubbedModel(store: HaviTokenStore, reconnect: Bool = true, enteredSleep: AsyncGate? = nil) -> HaviConnectModel {
        let service = HaviConnectService(
            config: connectConfig(),
            tokenStore: store,
            session: stubSession(),
            now: { Date(timeIntervalSince1970: 0) },
            sleep: { _ in
                enteredSleep?.open()
                if enteredSleep != nil { try? await Task.sleep(nanoseconds: 10_000_000_000) }
            }
        )
        let runtime = HaviRuntime(config: connectConfig(), tokenStore: store, connectService: service)
        return HaviConnectModel(runtime: runtime, reconnect: reconnect)
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

    // MARK: - Finding 2: state settles to .connected across the browser + app cycle

    /// The reported bug: after browser sign-in the sheet stayed on the connect
    /// prompt. Sequence: begin polling → link pending (.awaiting) → in-app browser
    /// presented → app resigns active → the developer approves on ANOTHER device so
    /// the credential lands in the store out-of-band (this device's poll only saw
    /// 'pending') → app becomes active → the model MUST settle to .connected and
    /// dismiss the sign-in browser.
    func testApprovalOnAnotherDeviceAcrossActiveCycleSettlesConnected() async {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(status: 201, json: createLinkJSON) // createSetupLink
        StubURLProtocol.enqueue(status: 202, json: pendingJSON)    // one poll: still pending

        let store = HaviTokenStore(backing: HaviInMemoryCredentialBacking())
        let enteredSleep = AsyncGate()
        let model = stubbedModel(store: store, enteredSleep: enteredSleep)

        model.onAppear()          // create link → .awaiting, then park after one pending poll
        await enteredSleep.opened()

        guard case .awaiting = model.phase else {
            return XCTFail("expected awaiting after the link is created, got \(model.phase)")
        }

        model.openApproval()      // "Sign in with HAVI" → in-app browser presented
        XCTAssertTrue(model.browser.isPresented)

        // Approval lands on another device while the app is away.
        store.store(HaviConnectedSession(
            accessToken: "tok-x", workspaceID: "ws-x",
            userName: "marco@alimax.at", workspaceName: "Team HAVI"
        ))
        model.applicationBecameActive()

        guard case .connected(let session) = model.phase else {
            return XCTFail("expected connected after the active cycle, got \(model.phase)")
        }
        XCTAssertEqual(session.workspaceID, "ws-x")
        XCTAssertFalse(model.browser.isPresented, "connecting dismisses the in-app sign-in browser")

        model.cancel()
    }

    /// The primary path: this device's own poll receives the 201 approval. The
    /// model's phase must reflect .connected (not just the token store), with the
    /// browser dismissed.
    func testThisDevicePollLandingApprovalSettlesConnected() async {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(status: 201, json: createLinkJSON) // createSetupLink
        StubURLProtocol.enqueue(status: 202, json: pendingJSON)    // pending
        StubURLProtocol.enqueue(status: 201, json: approvedJSON)   // approved

        let store = HaviTokenStore(backing: HaviInMemoryCredentialBacking())
        let model = stubbedModel(store: store) // no-op sleep → runs to completion

        model.onAppear()
        await model.awaitFlowForTesting()

        guard case .connected(let session) = model.phase else {
            return XCTFail("expected connected, got \(model.phase)")
        }
        XCTAssertEqual(session.workspaceID, "ws-9")
        XCTAssertFalse(model.browser.isPresented)
    }

    /// Reconnect regression: the sheet opened with `reconnect: true` precisely
    /// because the stored token was REJECTED (a 401 drove the reconnect). `onAppear`
    /// must NOT reconcile the sheet back to `.connected` from that dead credential —
    /// it must run a fresh pairing and only settle once a NEW token lands. On the
    /// pre-fix branch `onAppear` reconciles straight to `.connected(stale)` and the
    /// flow never starts, so the first assertion fails there.
    func testReconnectDoesNotSettleConnectedFromRejectedTokenUntilFreshPairing() async {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(status: 201, json: createLinkJSON) // createSetupLink
        StubURLProtocol.enqueue(status: 202, json: pendingJSON)    // pending
        StubURLProtocol.enqueue(status: 201, json: approvedJSON)   // approved → fresh token

        let store = HaviTokenStore(backing: HaviInMemoryCredentialBacking())
        store.store(HaviConnectedSession(accessToken: "stale-rejected", workspaceID: "ws-old"))

        let model = stubbedModel(store: store) // reconnect: true, no-op sleep → runs to completion

        model.onAppear()
        if case .connected = model.phase {
            return XCTFail("reconnect must not settle connected from the rejected credential")
        }

        await model.awaitFlowForTesting()

        guard case .connected(let session) = model.phase else {
            return XCTFail("expected connected after a fresh pairing, got \(model.phase)")
        }
        XCTAssertEqual(session.accessToken, "tok-abc", "settled on the FRESH token, not the rejected one")
        XCTAssertEqual(session.workspaceID, "ws-9")
        XCTAssertFalse(model.browser.isPresented)
    }

    /// A repeat `onAppear` (SwiftUI re-running it when the in-app browser uncovers
    /// the sheet) must NOT mint a new code and orphan the approval the developer
    /// already gave — it must keep awaiting the SAME link with no extra network.
    func testRepeatOnAppearDoesNotRestartAndOrphanTheInFlightApproval() async {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(status: 201, json: createLinkJSON)
        StubURLProtocol.enqueue(status: 202, json: pendingJSON)

        let store = HaviTokenStore(backing: HaviInMemoryCredentialBacking())
        let enteredSleep = AsyncGate()
        let model = stubbedModel(store: store, enteredSleep: enteredSleep)

        model.onAppear()
        await enteredSleep.opened()
        guard case .awaiting(let firstLink) = model.phase else {
            return XCTFail("expected awaiting, got \(model.phase)")
        }

        model.onAppear() // repeat appear — must be a no-op for the in-flight flow

        guard case .awaiting(let secondLink) = model.phase else {
            return XCTFail("must still be awaiting the same link, got \(model.phase)")
        }
        XCTAssertEqual(firstLink.deviceCode, secondLink.deviceCode, "onAppear must not mint a new code")
        XCTAssertEqual(StubURLProtocol.consumedCount, 2, "no second create-link request")

        model.cancel()
    }

    // MARK: - Reachable sign-out (connect-sheet entry point)

    /// The new entry point: a CONNECTED developer opens the connect sheet
    /// (`reconnect: false`) from the capture details screen's status row. With a
    /// credential in the store the model must open on the connected card — the only
    /// place Sign out is reachable — rather than kicking a fresh pairing.
    func testOpeningWhileConnectedLandsOnConnectedCard() {
        let store = HaviTokenStore(backing: HaviInMemoryCredentialBacking())
        store.store(HaviConnectedSession(
            accessToken: "tok-live", workspaceID: "ws-live",
            userName: "marco@alimax.at", workspaceName: "Team HAVI"
        ))
        let runtime = HaviRuntime(config: .inert, tokenStore: store)
        let model = HaviConnectModel(runtime: runtime, reconnect: false)

        guard case .connected(let session) = model.phase else {
            return XCTFail("connected entry point must open the connected card, got \(model.phase)")
        }
        XCTAssertEqual(session.workspaceID, "ws-live")
        XCTAssertEqual(session.workspaceName, "Team HAVI")
        XCTAssertNotNil(model.connectedSession)
    }

    /// After confirming Sign out, the credential is cleared and the sheet lands back
    /// on the normal connect prompt (a fresh `.awaiting` link) so a new sign-in can
    /// be tested immediately.
    func testSignOutClearsCredentialAndLandsOnConnectPrompt() async {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(status: 201, json: createLinkJSON)
        StubURLProtocol.enqueue(status: 202, json: pendingJSON)

        let store = HaviTokenStore(backing: HaviInMemoryCredentialBacking())
        store.store(HaviConnectedSession(
            accessToken: "tok-live", workspaceID: "ws-live",
            userName: "marco@alimax.at", workspaceName: "Team HAVI"
        ))
        let enteredSleep = AsyncGate()
        let model = stubbedModel(store: store, reconnect: false, enteredSleep: enteredSleep)

        guard case .connected = model.phase else {
            return XCTFail("expected connected on open, got \(model.phase)")
        }

        model.disconnect() // "Sign out" confirmed
        XCTAssertFalse(store.hasCredential, "sign-out clears the stored credential")

        await enteredSleep.opened()
        guard case .awaiting = model.phase else {
            return XCTFail("expected the connect prompt (awaiting) after sign-out, got \(model.phase)")
        }
        XCTAssertNil(model.connectedSession)

        model.cancel()
    }

    /// After sign-out, a subsequent reconcile (app returning to the foreground) must
    /// NOT resurrect the connected state from the now-empty store.
    func testSignOutIsNotResurrectedByReconcile() async {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(status: 201, json: createLinkJSON)
        StubURLProtocol.enqueue(status: 202, json: pendingJSON)

        let store = HaviTokenStore(backing: HaviInMemoryCredentialBacking())
        store.store(HaviConnectedSession(accessToken: "tok-live", workspaceID: "ws-live"))
        let enteredSleep = AsyncGate()
        let model = stubbedModel(store: store, reconnect: false, enteredSleep: enteredSleep)

        model.disconnect()
        await enteredSleep.opened()
        XCTAssertFalse(store.hasCredential)

        model.applicationBecameActive() // reconcile from the empty store
        if case .connected = model.phase {
            return XCTFail("sign-out must not be resurrected by reconcile")
        }
        XCTAssertNil(model.connectedSession)

        model.cancel()
    }
}
#endif
