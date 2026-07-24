package ai.handgemacht.havikit

import android.app.Activity
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
 * The runtime wires the capture subsystem (freeze + redact + triggers + activity
 * tracking) together with the credential store, the uploader/connect/label
 * services, and the Activity-scoped capture sheet + connect UI.
 */
public object Havi {
    internal val logBuffer: HaviLogBuffer = HaviLogBuffer()
    internal val contextStore: HaviContextStore = HaviContextStore()

    private val mainHandler = Handler(Looper.getMainLooper())

    @Volatile
    private var runtime: HaviRuntime? = null

    @Volatile
    private var appContext: Context? = null

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

        val appCtx = context.applicationContext
        appContext = appCtx
        HaviAndroidDeviceInfo.configure(appCtx)
        val application = appCtx as? Application
        val created = HaviRuntime(application, config, appCtx, logBuffer, contextStore)
        runtime = created
        isEnabled = true
        created.start()
    }

    /**
     * Names the Activity the user is currently looking at. [start] registers the
     * activity-lifecycle callbacks it tracks windows with, so starting after the first
     * Activity resumed — every React Native / Expo cold start, where JS calls [start]
     * from an effect — leaves the SDK with no window to capture until the app is
     * backgrounded and foregrounded once. Hosts that know the current Activity call this
     * right after [start] to close that gap.
     *
     * Pass a *resumed* Activity. Safe to repeat (re-seeding the tracked Activity is a
     * no-op) and callable from any thread; the seeding itself runs on the main thread.
     * Unnecessary when [start] runs in `Application.onCreate`.
     */
    @JvmStatic
    public fun attachActivity(activity: Activity) {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            runtime?.attachActivity(activity)
        } else {
            mainHandler.post { runtime?.attachActivity(activity) }
        }
    }

    /**
     * Programmatic capture of the resumed activity. No-op unless started. Capture reads
     * View state (decor size, window location), so a call from a background thread hops
     * to the main thread; a call already on the main thread runs inline.
     */
    @JvmStatic
    @JvmOverloads
    public fun capture(screen: String? = null) {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            runtime?.capture(screen)
        } else {
            mainHandler.post { runtime?.capture(screen) }
        }
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

    /**
     * Dev manual-paste: writes a bearer token + workspace id to HaviKit's own
     * credential store, overriding the stamped `HAVI_DEV_TOKEN` / `HAVI_WORKSPACE_ID`.
     */
    @JvmStatic
    public fun signIn(
        token: String,
        workspaceId: String,
    ) {
        resolveStore()?.signIn(token, workspaceId)
    }

    /** Reserved device-code pairing entry point (v1.1); currently always throws. */
    @JvmStatic
    public suspend fun beginDeviceAuthorization(): HaviDeviceFlow = throw HaviException.NotImplemented

    /** Local sign-out: clears this device's stored HAVI credential and the seeded priority. */
    @JvmStatic
    public fun disconnect() {
        resolveStore()?.clear()
        pendingPriority = null
    }

    /** Backward-compatible alias of [disconnect]. */
    @JvmStatic
    public fun signOut(): Unit = disconnect()

    /** Resolved authentication state, mirroring iOS `Havi.authState`. */
    @JvmStatic
    public val authState: HaviAuthState
        get() = runtime?.authState ?: HaviAuthState.Unconfigured

    /** The priority seeded via [setPriority], consumed when the capture sheet opens. */
    internal fun consumePendingPriority(): HaviPriority? = pendingPriority

    internal fun clearPendingPriority() {
        pendingPriority = null
    }

    internal fun clearLogBuffer() {
        logBuffer.clear()
    }

    /**
     * HaviKit's own credential store: the live runtime's when started, else a fresh
     * store over the last known application context (local sign-out from settings
     * before a capture). Null only when the SDK never saw a context.
     */
    private fun resolveStore(): HaviTokenStore? {
        runtime?.let { return it.tokenStore }
        val ctx = appContext ?: return null
        return HaviTokenStore(HaviPrefsCredentialBacking(ctx))
    }
}
