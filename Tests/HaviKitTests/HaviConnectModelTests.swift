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
    private func stubbedModel(store: HaviTokenStore, enteredSleep: AsyncGate? = nil) -> HaviConnectModel {
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
}
#endif
