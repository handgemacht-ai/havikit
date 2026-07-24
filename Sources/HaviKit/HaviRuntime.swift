import Foundation

/// MainActor-isolated live state assembled at `Havi.start`: the immutable
/// config, HaviKit's own Keychain store, the uploader actor, the observable
/// capture presenter, and the priority applied to the next capture.
@MainActor
final class HaviRuntime {
    let config: HaviConfig
    let tokenStore: HaviTokenStore
    let uploader: HaviUploader
    let connectService: HaviConnectService
    let labelService: HaviLabelService
    var pendingPriority: HaviPriority?

    /// The workspace label vocabulary, cached for this connect session so the
    /// details screen resolves it once per workspace instead of re-fetching on
    /// every capture.
    private var labelCache: (workspaceID: String, definitions: [HaviLabelDefinition])?

    #if canImport(UIKit)
    let presenter = HaviCapturePresenter()
    #endif

    init(
        config: HaviConfig,
        tokenStore: HaviTokenStore,
        connectService: HaviConnectService? = nil,
        labelService: HaviLabelService? = nil
    ) {
        self.config = config
        self.tokenStore = tokenStore
        self.uploader = HaviUploader(config: config, tokenStore: tokenStore)
        self.connectService = connectService ?? HaviConnectService(config: config, tokenStore: tokenStore)
        self.labelService = labelService ?? HaviLabelService(config: config)
    }

    /// Resolves the label vocabulary for `workspaceID`, serving the session cache
    /// when present. `nil` on a fetch failure so the caller keeps the built-in
    /// priority control alone. A successful (including empty) result is cached.
    func labelDefinitions(token: String, workspaceID: String) async -> [HaviLabelDefinition]? {
        if let cache = labelCache, cache.workspaceID == workspaceID {
            return cache.definitions
        }
        guard let definitions = await labelService.fetch(token: token, workspaceID: workspaceID) else {
            return nil
        }
        labelCache = (workspaceID, definitions)
        return definitions
    }

    /// Whether a usable credential resolves — a Keychain credential (manual paste
    /// or device-code) or the stamped dev token + workspace. Drives whether the
    /// capture sheet surfaces the connect prompt (design §5).
    var isConnected: Bool {
        if tokenStore.hasCredential { return true }
        return config.workspaceID != nil && config.devToken != nil
    }

    #if canImport(UIKit)
    /// Freezes the key window (redaction painted before any bytes exist) and
    /// presents the capture sheet (design §2). The single entry point for both
    /// the shake trigger and programmatic `Havi.capture()`; a no-op if a sheet is
    /// already up or the snapshot cannot be taken.
    func presentCapture(screen: String?) {
        guard presenter.session == nil else { return }
        guard let snapshot = HaviSnapshotter.capture(policy: config.redaction) else { return }
        // Screen name precedence: an explicit `Havi.capture(screen:)` argument, then
        // the host's `.haviScreen(_:)` / `Havi.setScreen(_:)` context, then a
        // best-effort auto-detected top view-controller name, then "unknown".
        let resolvedScreen = screen
            ?? HaviContextStore.shared.currentScreen()
            ?? HaviSnapshotter.autoDetectedScreen()
            ?? "unknown"
        presenter.present(HaviCaptureSession(
            image: snapshot.image,
            a11yFrames: snapshot.a11yFrames,
            orientation: snapshot.orientation,
            screen: resolvedScreen,
            initialPriority: pendingPriority ?? .medium
        ))
    }
    #else
    func presentCapture(screen: String?) {
        _ = screen
    }
    #endif
}
