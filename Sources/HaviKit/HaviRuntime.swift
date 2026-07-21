import Foundation

/// MainActor-isolated live state assembled at `Havi.start`: the immutable
/// config, HaviKit's own Keychain store, the uploader actor, and the priority
/// applied to the next capture. The capture UI (shake → sheet → snapshot →
/// submit) is `@MainActor` and lands in SDK-4.
@MainActor
final class HaviRuntime {
    let config: HaviConfig
    let tokenStore: HaviTokenStore
    let uploader: HaviUploader
    var pendingPriority: HaviPriority?

    init(config: HaviConfig, tokenStore: HaviTokenStore) {
        self.config = config
        self.tokenStore = tokenStore
        self.uploader = HaviUploader(config: config)
    }

    /// Presents the capture sheet (design §2). Wired in SDK-4; a no-op seam
    /// today so `Havi.capture` and the shake trigger have a single entry point.
    func presentCapture(screen: String?) {
        _ = screen
    }
}
