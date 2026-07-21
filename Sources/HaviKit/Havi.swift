import Foundation

/// HaviKit public facade (design §1). Config-gated and no-op when unconfigured,
/// mirroring `SentryReporting`: until a base URL resolves (`HAVI_ENABLED` +
/// `HAVI_BASE_URL`), every entry point is inert, so a store build without HAVI
/// keys carries zero cost.
public enum Havi {
    public private(set) static var isEnabled: Bool = false

    @MainActor
    private static var runtime: HaviRuntime?

    /// Lifecycle. Inert until config enables it; idempotent across repeat calls.
    @MainActor
    public static func start(config: HaviConfig = .fromBundle()) {
        guard config.isEnabled else { return }
        guard runtime == nil else { return }
        runtime = HaviRuntime(config: config, tokenStore: HaviTokenStore())
        isEnabled = true
    }

    /// Programmatic capture (in addition to shake). Presents the capture sheet.
    @MainActor
    public static func capture(screen: String? = nil) {
        guard isEnabled, let runtime else { return }
        runtime.presentCapture(screen: screen)
    }

    /// Breadcrumb log ring — callable from any thread/actor. Also the v1
    /// network-context path: RPC / network failures pushed here ride on the next
    /// annotation's `app-logs` body.
    public nonisolated static func log(_ message: String, level: HaviLogLevel = .info, category: String = "app") {
        HaviLogBuffer.shared.append(HaviLogEntry(level: level, category: category, message: message))
    }

    /// Structured context, merged into `x:havi.contexts` and secret-scrubbed
    /// before send.
    public nonisolated static func setContext(_ namespace: String, _ values: [String: String]) {
        guard !namespace.isEmpty else { return }
        HaviContextStore.shared.setContext(namespace, values)
    }

    public nonisolated static func setTag(_ key: String, _ value: String) {
        guard !key.isEmpty else { return }
        HaviContextStore.shared.setTag(key, value)
    }

    /// Priority applied to the next capture (overridable in the sheet).
    @MainActor
    public static func setPriority(_ priority: HaviPriority?) {
        runtime?.pendingPriority = priority
    }

    /// Dev manual-paste: a bearer token + workspace id copied from the dashboard,
    /// written to HaviKit's own Keychain, overriding the stamped values.
    @MainActor
    public static func signIn(token: String, workspaceID: String) {
        HaviTokenStore().signIn(token: token, workspaceID: workspaceID)
    }

    /// Device-code pairing (design §5) — ships v1.1.
    @MainActor
    public static func beginDeviceAuthorization() async throws -> HaviDeviceFlow {
        throw HaviError.notImplemented
    }

    @MainActor
    public static func signOut() {
        HaviTokenStore().clear()
        runtime?.pendingPriority = nil
    }

    @MainActor
    public static var authState: HaviAuthState {
        guard isEnabled, let runtime else { return .unconfigured }
        let store = runtime.tokenStore
        if store.hasCredential, let workspaceID = store.workspaceID {
            return .authenticated(workspaceID: workspaceID)
        }
        if let workspaceID = runtime.config.workspaceID, runtime.config.devToken != nil {
            return .authenticated(workspaceID: workspaceID)
        }
        return .needsReconnect
    }
}
