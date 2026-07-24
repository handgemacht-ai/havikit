package ai.handgemacht.havikit

import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock

/**
 * Fixed-capacity breadcrumb ring (wire spec §6, A6: capacity 200, lock-guarded so
 * `Havi.log` is callable from any thread). The tail rides on the next
 * annotation's diagnostics describing bodies and is cleared on a successful
 * submit.
 *
 * Entry count alone does not bound what the ring costs: 200 megabyte-sized
 * messages would balloon both the retained memory and the diagnostics bodies of
 * the next upload. So two byte caps hold, with the same constants on iOS: each
 * message is capped at [MAX_ENTRY_BYTES] UTF-8 bytes (cut on a scalar boundary,
 * marked with [TRUNCATION_MARKER]) and the ring evicts oldest-first until the
 * retained messages fit [MAX_TOTAL_BYTES].
 */
public class HaviLogBuffer(
    private val capacity: Int = DEFAULT_CAPACITY,
) {
    private val lock = ReentrantLock()
    private val entries = ArrayDeque<HaviLogEntry>()
    private var totalBytes = 0

    public fun append(entry: HaviLogEntry) {
        val capped = entry.copy(message = truncate(entry.message))
        val cost = messageBytes(capped)
        lock.withLock {
            entries.addLast(capped)
            totalBytes += cost
            while (entries.isNotEmpty() && (entries.size > capacity || totalBytes > MAX_TOTAL_BYTES)) {
                totalBytes -= messageBytes(entries.removeFirst())
            }
        }
    }

    public fun snapshot(): List<HaviLogEntry> = lock.withLock { entries.toList() }

    public fun clear(): Unit =
        lock.withLock {
            entries.clear()
            totalBytes = 0
        }

    public companion object {
        public const val DEFAULT_CAPACITY: Int = 200

        /** Per-message cap, marker included. */
        public const val MAX_ENTRY_BYTES: Int = 4 * 1024

        /** Budget across every retained message; the oldest are evicted until it holds. */
        public const val MAX_TOTAL_BYTES: Int = 256 * 1024

        public const val TRUNCATION_MARKER: String = "…[truncated]"

        /**
         * Caps [message] at [MAX_ENTRY_BYTES] UTF-8 bytes including the marker,
         * backing off any continuation byte so a multi-byte character is never
         * split into invalid UTF-8.
         */
        public fun truncate(message: String): String {
            val bytes = message.toByteArray(Charsets.UTF_8)
            if (bytes.size <= MAX_ENTRY_BYTES) return message
            var cut = MAX_ENTRY_BYTES - TRUNCATION_MARKER.toByteArray(Charsets.UTF_8).size
            while (cut > 0 && (bytes[cut].toInt() and 0xC0) == 0x80) {
                cut--
            }
            return String(bytes, 0, cut, Charsets.UTF_8) + TRUNCATION_MARKER
        }

        private fun messageBytes(entry: HaviLogEntry): Int = entry.message.toByteArray(Charsets.UTF_8).size
    }
}
