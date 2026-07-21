import Foundation

/// HaviKit public facade (design §1). Config-gated and no-op when unconfigured,
/// mirroring `SentryReporting`: until a base URL resolves (`HAVI_ENABLED` +
/// `HAVI_BASE_URL`), every entry point is inert, so a store build without HAVI
/// keys carries zero cost.
public enum Havi {
    public private(set) static var isEnabled: Bool = false

    @MainActor
    private static var runtime: HaviRuntime?

    /// The live runtime, exposed to the SwiftUI overlay host so `.haviOverlay()`
    /// can present the capture sheet. `nil` until `start` enables the SDK (the
    /// Release path), where the overlay is a pure passthrough.
    @MainActor
    static var captureRuntime: HaviRuntime? { isEnabled ? runtime : nil }

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

    /// Trigger a capture from a non-isolated context (the shake / long-press
    /// callbacks), hopping to the main actor. Cheap no-op when the SDK is inert.
    public nonisolated static func triggerCapture(screen: String? = nil) {
        Task { @MainActor in capture(screen: screen) }
    }

    /// Breadcrumb log ring — callable from any thread/actor. `error`-level entries
    /// (with a non-`network` category) surface as the capture sheet's console-error
    /// count and the annotation's `console-errors` describing body; the rest ride
    /// in `app-logs`.
    public nonisolated static func log(_ message: String, level: HaviLogLevel = .info, category: String = "app") {
        HaviLogBuffer.shared.append(HaviLogEntry(level: level, category: category, message: message))
    }

    /// Records a network/RPC failure. Category `"network"` routes it to the capture
    /// sheet's network-error count and the annotation's `network-errors` describing
    /// body (mirroring the browser extension). Pass a preformatted
    /// `"METHOD url status statusText"` line to match the web value shape.
    public nonisolated static func logNetworkError(_ message: String) {
        HaviLogBuffer.shared.append(
            HaviLogEntry(level: .error, category: HaviDiagnostics.networkCategory, message: message)
        )
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
