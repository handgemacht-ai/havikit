import Foundation

/// Fixed-capacity breadcrumb ring (design §1: capacity 200, lock-guarded so
/// `Havi.log` is `nonisolated`). The tail rides on the next annotation's
/// `app-logs` describing body.
final class HaviLogBuffer: @unchecked Sendable {
    static let shared = HaviLogBuffer()

    private let capacity: Int
    private let lock = HaviUnfairLock()
    private var entries: [HaviLogEntry] = []

    init(capacity: Int = 200) {
        self.capacity = capacity
    }

    func append(_ entry: HaviLogEntry) {
        lock.withLock {
            entries.append(entry)
            if entries.count > capacity {
                entries.removeFirst(entries.count - capacity)
            }
        }
    }

    func snapshot() -> [HaviLogEntry] {
        lock.withLock { entries }
    }

    func clear() {
        lock.withLock { entries.removeAll(keepingCapacity: true) }
    }
}
