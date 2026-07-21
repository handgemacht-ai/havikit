import Foundation

/// Lock-guarded store for `Havi.setContext` / `setTag` and the active screen
/// name (design §1). Snapshotted (copied) at capture time so later mutation
/// cannot race an in-flight send.
final class HaviContextStore: @unchecked Sendable {
    static let shared = HaviContextStore()

    private let lock = HaviUnfairLock()
    private var contexts: [String: [String: String]] = [:]
    private var tags: [String: String] = [:]
    private var screen: String?

    func setContext(_ namespace: String, _ values: [String: String]) {
        lock.withLock { contexts[namespace] = values }
    }

    func setTag(_ key: String, _ value: String) {
        lock.withLock { tags[key] = value }
    }

    func setScreen(_ name: String?) {
        lock.withLock { screen = name }
    }

    func snapshotContexts() -> [String: [String: String]] {
        lock.withLock { contexts }
    }

    func snapshotTags() -> [String: String] {
        lock.withLock { tags }
    }

    func currentScreen() -> String? {
        lock.withLock { screen }
    }

    func clear() {
        lock.withLock {
            contexts.removeAll()
            tags.removeAll()
            screen = nil
        }
    }
}
