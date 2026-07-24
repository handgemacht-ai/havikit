import Foundation

/// Fixed-capacity breadcrumb ring (design §1: capacity 200, lock-guarded so
/// `Havi.log` is `nonisolated`). The tail rides on the next annotation's
/// `app-logs` describing body.
///
/// Entry count alone does not bound what the ring costs: 200 megabyte-sized
/// messages would balloon both the retained memory and the `app-logs` body of the
/// next upload. So two byte caps hold, with the same constants on Android: each
/// message is capped at `maxEntryBytes` UTF-8 bytes (cut on a scalar boundary,
/// marked with `truncationMarker`) and the ring evicts oldest-first until the
/// retained messages fit `maxTotalBytes`.
final class HaviLogBuffer: @unchecked Sendable {
    static let shared = HaviLogBuffer()

    /// Per-message cap, marker included.
    static let maxEntryBytes = 4 * 1024
    /// Budget across every retained message; the oldest are evicted until it holds.
    static let maxTotalBytes = 256 * 1024
    static let truncationMarker = "…[truncated]"

    private let capacity: Int
    private let lock = HaviUnfairLock()
    private var entries: [HaviLogEntry] = []
    private var totalBytes = 0

    init(capacity: Int = 200) {
        self.capacity = capacity
    }

    func append(_ entry: HaviLogEntry) {
        let capped = HaviLogEntry(
            level: entry.level,
            category: entry.category,
            message: Self.truncate(entry.message)
        )
        let cost = capped.message.utf8.count
        lock.withLock {
            entries.append(capped)
            totalBytes += cost
            while !entries.isEmpty, entries.count > capacity || totalBytes > Self.maxTotalBytes {
                totalBytes -= entries.removeFirst().message.utf8.count
            }
        }
    }

    func snapshot() -> [HaviLogEntry] {
        lock.withLock { entries }
    }

    func clear() {
        lock.withLock {
            entries.removeAll(keepingCapacity: true)
            totalBytes = 0
        }
    }

    /// Caps `message` at `maxEntryBytes` UTF-8 bytes including the marker, backing
    /// off any continuation byte so a multi-byte character is never split into
    /// invalid UTF-8.
    static func truncate(_ message: String) -> String {
        let bytes = Array(message.utf8)
        guard bytes.count > maxEntryBytes else { return message }
        var cut = maxEntryBytes - truncationMarker.utf8.count
        while cut > 0, bytes[cut] & 0xC0 == 0x80 {
            cut -= 1
        }
        return String(decoding: bytes[..<cut], as: UTF8.self) + truncationMarker
    }
}
