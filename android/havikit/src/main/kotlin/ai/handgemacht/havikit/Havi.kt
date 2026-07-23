package ai.handgemacht.havikit

import android.app.Application
import android.content.Context
import android.os.Handler
import android.os.Looper

/**
 * The public HaviKit facade for Android (Part B1) — a process-wide singleton mirroring
 * the iOS `Havi` enum. Inert until [start] resolves an enabled [HaviConfig]; repeat
 * [start] calls are ignored (idempotent). The breadcrumb ring and the context/screen
 * registry are process-global, so [log] / [setContext] / [setTag] / [setScreen] record
 * even before [start] (and when the SDK ships inert), matching the iOS "still records
 * when inert" contract.
 *
 * This stage wires the capture subsystem (freeze + redact + triggers + activity
 * tracking); the connect/auth surface (`signIn`, `disconnect`, `authState`) and the
 * capture sheet UI land in later stages on top of the same runtime.
 */
public object Havi {
    internal val logBuffer: HaviLogBuffer = HaviLogBuffer()
    internal val contextStore: HaviContextStore = HaviContextStore()

    private val mainHandler = Handler(Looper.getMainLooper())

    @Volatile
    private var runtime: HaviRuntime? = null

    @Volatile
    private var pendingPriority: HaviPriority? = null

    @JvmStatic
    public var isEnabled: Boolean = false
        private set

    /**
     * Builds the capture runtime from the stamped config and arms the triggers.
     * Inert config → returns immediately; a live runtime already present → returns
     * (idempotent). Needs an [Application] context to own the activity tracker and
     * the shake sensor.
     */
    @JvmStatic
    @JvmOverloads
    public fun start(
        context: Context,
        config: HaviConfig = HaviConfig.fromManifest(context),
    ) {
        if (!config.isEnabled) return
        if (runtime != null) return

        val application = context.applicationContext as? Application
        val created = HaviRuntime(application, config, logBuffer, contextStore)
        runtime = created
        isEnabled = true
        created.start()
    }

    /** Programmatic capture of the resumed activity. No-op unless started. */
    @JvmStatic
    @JvmOverloads
    public fun capture(screen: String? = null) {
        runtime?.capture(screen)
    }

    /** Thread-free trigger (shake / long-press callbacks) — hops to the main thread. */
    @JvmStatic
    @JvmOverloads
    public fun triggerCapture(screen: String? = null) {
        mainHandler.post { capture(screen) }
    }

    /**
     * Appends a breadcrumb. `error`-level entries in a non-`network` category surface
     * as console errors and the rest as app-logs at capture time (the split lives in
     * the core diagnostics builder). Callable from any thread; records even when inert.
     */
    @JvmStatic
    @JvmOverloads
    public fun log(
        message: String,
        level: HaviLogLevel = HaviLogLevel.INFO,
        category: String = "app",
    ) {
        logBuffer.append(HaviLogEntry(level = level, category = category, message = message))
    }

    /** Records a network/RPC failure — pass a preformatted "METHOD url status statusText" line. */
    @JvmStatic
    public fun logNetworkError(message: String) {
        logBuffer.append(HaviLogEntry(level = HaviLogLevel.ERROR, category = "network", message = message))
    }

    /** Structured context merged into `x:havi.contexts` (secret-scrubbed before send). Ignored when the namespace is empty. */
    @JvmStatic
    public fun setContext(
        namespace: String,
        values: Map<String, String>,
    ) {
        if (namespace.isEmpty()) return
        contextStore.setContext(namespace, values)
    }

    /** A single tag into `x:havi.tags`. Ignored when the key is empty. */
    @JvmStatic
    public fun setTag(
        key: String,
        value: String,
    ) {
        if (key.isEmpty()) return
        contextStore.setTag(key, value)
    }

    /** Names the current screen for the next capture; `null` clears it. Imperative twin of [HaviScreen]. */
    @JvmStatic
    public fun setScreen(name: String?) {
        contextStore.setScreen(name)
    }

    /** Seeds the priority for the next capture (overridable in the sheet). */
    @JvmStatic
    public fun setPriority(priority: HaviPriority?) {
        pendingPriority = priority
    }

    /** The priority seeded via [setPriority], consumed when the capture sheet opens. */
    internal fun consumePendingPriority(): HaviPriority? = pendingPriority
}
