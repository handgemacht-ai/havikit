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

    init(runtime: HaviRuntime, reconnect: Bool) {
        self.runtime = runtime
        if !reconnect, let session = runtime.tokenStore.connectedSession {
            self.phase = .connected(session)
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
        if case .connected = phase { return }
        start()
    }

    /// Requests a fresh link and begins polling. Also the "Get a new link" and
    /// post-disconnect entry point.
    func start() {
        pollTask?.cancel()
        cancelFlag.reset()
        phase = .creating
        browser = HaviConnectBrowserState()
        pollTask = Task { await runFlow() }
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

    /// Cancel button on the waiting state — stops polling. The sheet dismisses.
    func cancel() {
        cancelFlag.cancel()
        pollTask?.cancel()
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
            phase = .awaiting(link)
            browser.beganAwaiting()
            let result = await runtime.connectService.runExchange(
                link: link,
                isCancelled: { [cancelFlag] in cancelFlag.isCancelled }
            )
            // A terminal outcome forces the sign-in browser down, so approving
            // (or expiry/error) while it is up auto-dismisses it.
            browser.flowSettled()
            switch result {
            case .connected(let session): phase = .connected(session)
            case .expired: phase = .expired
            case .cancelled: break
            case .failed(let failure): phase = .error(failure.userMessage)
            }
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
