#if canImport(UIKit)
import Foundation
import Observation

/// Drives the connect sheet (design §5): create a `client_type: mobile` pairing,
/// open the approval page in the in-app sign-in browser, poll the exchange
/// endpoint while the developer approves, and resolve to a connected identity, an
/// expired link, or a plain-language error. Approving on another signed-in device
/// and manual paste stay available as secondary paths, and a connected identity
/// can be revoked locally. The network + poll state machine live in
/// `HaviConnectService`; the browser open / auto-dismiss rules live in the pure
/// `HaviConnectBrowserState`; this is the `@MainActor`-observable glue the SwiftUI
/// sheet binds to.
@MainActor
@Observable
final class HaviConnectModel {
    enum Phase: Equatable {
        case connected(HaviConnectedSession)
        case creating
        case awaiting(HaviSetupLink)
        case expired
        case error(String)
    }

    private(set) var phase: Phase
    private(set) var browser = HaviConnectBrowserState()
    var pasteToken: String = ""
    var pasteWorkspaceID: String = ""

    private let runtime: HaviRuntime
    private let cancelFlag = HaviConnectCancelFlag()
    private var pollTask: Task<Void, Never>?
    /// True while a create/poll flow is in flight. Guards against launching a
    /// second, concurrent flow (which would mint a new link and orphan the code
    /// the developer already approved).
    private var flowActive = false
    /// The link currently pending approval. Kept so a poll that stopped without a
    /// terminal outcome (task cancelled by the system while backgrounded, a
    /// transient teardown) can be **resumed on the same code** — never restarted
    /// with a fresh one — when the app returns to the foreground.
    private var pendingLink: HaviSetupLink?
    /// The initial flow is kicked exactly once. A repeated `onAppear` (SwiftUI can
    /// re-run it when the in-app browser covers and then uncovers the sheet) must
    /// not restart the flow and orphan the in-flight approval.
    private var didStart = false

    init(runtime: HaviRuntime, reconnect: Bool) {
        self.runtime = runtime
        if !reconnect, let session = runtime.tokenStore.connectedSession {
            self.phase = .connected(session)
            self.didStart = true
        } else {
            self.phase = .creating
        }
    }

    var connectedSession: HaviConnectedSession? {
        if case .connected(let session) = phase { return session }
        return nil
    }

    /// The absolute approve URL the in-app sign-in browser opens, resolved by the
    /// service from the create response's relative `approve_url`. Present only
    /// while a link is pending approval.
    var approveURL: URL? {
        if case .awaiting(let link) = phase { return link.approveURL }
        return nil
    }

    func onAppear() {
        if reconcileFromStore() { return }
        if didStart {
            // A repeat appear (e.g. the in-app browser uncovered the sheet): make
            // sure the poll is still alive on the SAME link rather than orphaning
            // the code the developer may have already approved.
            resumePollingIfNeeded()
        } else {
            start()
        }
    }

    /// The app returned to the foreground — from the in-app sign-in browser, or a
    /// background magic-link round trip. If the approval landed while we were away
    /// (this device's poll stored it, or the developer approved on another
    /// device), settle to the stored identity; otherwise make sure the poll is
    /// still running on the same pending link so a stalled/killed poll resumes
    /// without minting a new code.
    func applicationBecameActive() {
        if reconcileFromStore() { return }
        resumePollingIfNeeded()
    }

    /// The store is the source of truth for "connected". If a credential is
    /// present and we are not already showing it, tear the flow down and settle to
    /// `.connected` — this is what recovers the UI when a poll stored the token but
    /// the visible phase never caught up (design §5, phone-QA finding 2).
    @discardableResult
    private func reconcileFromStore() -> Bool {
        guard let session = runtime.tokenStore.connectedSession else { return false }
        if case .connected = phase { return true }
        cancelFlag.cancel()
        pollTask?.cancel()
        flowActive = false
        pendingLink = nil
        browser.flowSettled()
        phase = .connected(session)
        return true
    }

    /// Re-arm polling on the existing pending link when no flow is running — never
    /// creates a new link. A no-op if already connected, a flow is live, or the
    /// link's TTL has passed.
    private func resumePollingIfNeeded() {
        guard !flowActive, let link = pendingLink, Date() < link.expiresAt else { return }
        flowActive = true
        cancelFlag.reset()
        pollTask?.cancel()
        pollTask = Task {
            await self.poll(on: link)
            self.flowActive = false
        }
    }

    /// Requests a fresh link and begins polling. Also the "Get a new link" and
    /// post-disconnect entry point.
    func start() {
        didStart = true
        flowActive = true
        pollTask?.cancel()
        cancelFlag.reset()
        phase = .creating
        browser = HaviConnectBrowserState()
        pendingLink = nil
        pollTask = Task {
            await self.runFlow()
            self.flowActive = false
        }
    }

    /// "Sign in with HAVI": open the approval page in the in-app browser. A no-op
    /// unless a link is pending approval.
    func openApproval() {
        browser.openRequested()
    }

    /// The in-app sign-in browser closed — user tapped Done, or the poll loop
    /// succeeded and we tore it down. Polling is untouched, so a background
    /// approval still lands.
    func browserClosed() {
        browser.browserClosed()
    }

    /// Cancel button on the waiting state, or the sheet being dismissed for real —
    /// stops polling and drops the pending link so it is not resumed.
    func cancel() {
        cancelFlag.cancel()
        pollTask?.cancel()
        flowActive = false
        pendingLink = nil
    }

    /// Test seam: awaits the in-flight create/poll flow to completion so a state
    /// machine test can assert the terminal phase deterministically.
    func awaitFlowForTesting() async {
        await pollTask?.value
    }

    func usePastedToken() {
        let token = pasteToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let workspace = pasteWorkspaceID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty, !workspace.isEmpty else { return }
        cancel()
        browser.flowSettled()
        runtime.tokenStore.signIn(token: token, workspaceID: workspace)
        phase = .connected(runtime.tokenStore.connectedSession
            ?? HaviConnectedSession(accessToken: token, workspaceID: workspace))
    }

    /// Local revocation (design §5): clear the Keychain credential — server-side
    /// revoke is out of scope — then offer a fresh connect.
    func disconnect() {
        cancel()
        runtime.tokenStore.clear()
        runtime.pendingPriority = nil
        start()
    }

    private func runFlow() async {
        switch await runtime.connectService.createSetupLink() {
        case .failure(let failure):
            browser.flowSettled()
            phase = .error(failure.userMessage)
        case .success(let link):
            pendingLink = link
            phase = .awaiting(link)
            browser.beganAwaiting()
            await poll(on: link)
        }
    }

    /// Polls the exchange endpoint to a terminal outcome. Reused verbatim by a
    /// foreground resume so a poll that stopped without settling continues on the
    /// SAME code. Every settling outcome clears `pendingLink` and forces the
    /// sign-in browser down (so approving while it is up auto-dismisses it); a
    /// `.cancelled` leaves `pendingLink` intact so `applicationBecameActive` can
    /// resume it.
    private func poll(on link: HaviSetupLink) async {
        let result = await runtime.connectService.runExchange(
            link: link,
            isCancelled: { [cancelFlag] in cancelFlag.isCancelled }
        )
        switch result {
        case .connected(let session):
            pendingLink = nil
            browser.flowSettled()
            phase = .connected(session)
        case .expired:
            pendingLink = nil
            browser.flowSettled()
            phase = .expired
        case .failed(let failure):
            pendingLink = nil
            browser.flowSettled()
            phase = .error(failure.userMessage)
        case .cancelled:
            break
        }
    }
}

/// A lock-guarded cancellation flag the poll loop reads from the actor while the
/// sheet flips it on the main actor.
final class HaviConnectCancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock(); cancelled = true; lock.unlock()
    }

    func reset() {
        lock.lock(); cancelled = false; lock.unlock()
    }
}
#endif
