package ai.handgemacht.havikit

import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock

/**
 * Lock-guarded store for `Havi.setContext` / `setTag` and the active screen name
 * (wire spec §A1). Snapshotted (copied) at capture time so later mutation cannot
 * race an in-flight send.
 */
public class HaviContextStore {
    private val lock = ReentrantLock()
    private val contexts = LinkedHashMap<String, Map<String, String>>()
    private val tags = LinkedHashMap<String, String>()
    private var screen: String? = null

    public fun setContext(
        namespace: String,
        values: Map<String, String>,
    ): Unit = lock.withLock { contexts[namespace] = values.toMap() }

    public fun setTag(
        key: String,
        value: String,
    ): Unit = lock.withLock { tags[key] = value }

    public fun setScreen(name: String?): Unit = lock.withLock { screen = name }

    public fun snapshotContexts(): Map<String, Map<String, String>> = lock.withLock { contexts.toMap() }

    public fun snapshotTags(): Map<String, String> = lock.withLock { tags.toMap() }

    public fun currentScreen(): String? = lock.withLock { screen }

    public fun clear(): Unit =
        lock.withLock {
            contexts.clear()
            tags.clear()
            screen = null
        }
}
