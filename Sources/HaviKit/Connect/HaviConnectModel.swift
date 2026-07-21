#if canImport(UIKit)
import Foundation
import Observation

/// Drives the connect sheet (design §5): create a `client_type: mobile` pairing,
/// poll the exchange endpoint while the developer approves on their laptop, and
/// resolve to a connected identity, an expired link, or a plain-language error.
/// Manual paste stays available as the secondary path, and a connected identity
/// can be revoked locally. The network + poll state machine live in
/// `HaviConnectService`; this is the `@MainActor`-observable glue the SwiftUI
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
        pollTask = Task { await runFlow() }
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
            phase = .error(failure.userMessage)
        case .success(let link):
            phase = .awaiting(link)
            let result = await runtime.connectService.runExchange(
                link: link,
                isCancelled: { [cancelFlag] in cancelFlag.isCancelled }
            )
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
