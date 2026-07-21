import Foundation

/// MainActor-isolated live state assembled at `Havi.start`: the immutable
/// config, HaviKit's own Keychain store, the uploader actor, the observable
/// capture presenter, and the priority applied to the next capture.
@MainActor
final class HaviRuntime {
    let config: HaviConfig
    let tokenStore: HaviTokenStore
    let uploader: HaviUploader
    var pendingPriority: HaviPriority?

    #if canImport(UIKit)
    let presenter = HaviCapturePresenter()
    #endif

    init(config: HaviConfig, tokenStore: HaviTokenStore) {
        self.config = config
        self.tokenStore = tokenStore
        self.uploader = HaviUploader(config: config)
    }

    #if canImport(UIKit)
    /// Freezes the key window (redaction painted before any bytes exist) and
    /// presents the capture sheet (design §2). The single entry point for both
    /// the shake trigger and programmatic `Havi.capture()`; a no-op if a sheet is
    /// already up or the snapshot cannot be taken.
    func presentCapture(screen: String?) {
        guard presenter.session == nil else { return }
        guard let snapshot = HaviSnapshotter.capture(policy: config.redaction) else { return }
        let resolvedScreen = screen ?? HaviContextStore.shared.currentScreen() ?? "unknown"
        presenter.present(HaviCaptureSession(
            image: snapshot.image,
            viewport: snapshot.viewport,
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
