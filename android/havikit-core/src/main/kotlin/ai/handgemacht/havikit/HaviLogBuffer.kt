package ai.handgemacht.havikit

import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock

/**
 * Fixed-capacity breadcrumb ring (wire spec §6, A6: capacity 200, lock-guarded so
 * `Havi.log` is callable from any thread). The tail rides on the next
 * annotation's diagnostics describing bodies and is cleared on a successful
 * submit.
 */
public class HaviLogBuffer(
    private val capacity: Int = DEFAULT_CAPACITY,
) {
    private val lock = ReentrantLock()
    private val entries = ArrayDeque<HaviLogEntry>()

    public fun append(entry: HaviLogEntry): Unit =
        lock.withLock {
            entries.addLast(entry)
            while (entries.size > capacity) {
                entries.removeFirst()
            }
        }

    public fun snapshot(): List<HaviLogEntry> = lock.withLock { entries.toList() }

    public fun clear(): Unit = lock.withLock { entries.clear() }

    public companion object {
        public const val DEFAULT_CAPACITY: Int = 200
    }
}
