package ai.handgemacht.havikit

import android.app.Activity
import android.app.Application
import android.content.Context
import android.os.Handler
import android.os.Looper

/**
 * The Android capture runtime, built once by [Havi.start]. It owns the immutable
 * config, HaviKit's own credential store, the uploader / connect / label services
 * over the Android HTTP transport, the activity tracker, the capture controller
 * (freeze + redact → [HaviCaptureFrame]), the triggers, and the Activity-scoped
 * capture host that presents the sheet. Triggers are wired to the app
 * foreground/resume lifecycle; every trigger funnels through the main thread.
 */
internal class HaviRuntime(
    private val application: Application?,
    val config: HaviConfig,
    context: Context,
    private val logBuffer: HaviLogBuffer,
    contextStore: HaviContextStore,
) {
    private val mainHandler = Handler(Looper.getMainLooper())
    private val activityTracker = HaviActivityTracker()
    private val transport: HaviHttpTransport = HaviAndroidHttpTransport()

    val tokenStore: HaviTokenStore = HaviTokenStore(HaviPrefsCredentialBacking(context))
    val uploader: HaviUploader = HaviUploader(config, transport)
    val connectService: HaviConnectService = HaviConnectService(config, tokenStore, transport)
    private val labelService: HaviLabelService = HaviLabelService(config, transport)

    private val captureController = HaviCaptureController(config, contextStore, logBuffer)
    private val captureHost = HaviCaptureHost(this, activityTracker::currentActivity)
    private val triggers =
        HaviTriggerController(
            context = application,
            longPressEnabled = LONG_PRESS_ENABLED,
            onTrigger = { fireCapture() },
        )

    /** The workspace label vocabulary, cached per workspace for this connect session. */
    private var labelCache: Pair<String, List<HaviLabelDefinition>>? = null

    @Volatile
    private var started = false

    fun start() {
        if (started) return
        started = true
        captureController.handler = HaviCaptureHandler { frame -> captureHost.present(frame) }

        val app = application ?: return
        activityTracker.listener =
            object : HaviActivityTracker.Listener {
                override fun onForeground() = triggers.armShake()

                override fun onBackground() = triggers.disarmShake()

                override fun onResumed(activity: Activity) = triggers.attachLongPress(activity)

                override fun onPaused(activity: Activity) = triggers.detachLongPress()

                override fun onDestroyed(activity: Activity) = captureHost.onHostDestroyed(activity)
            }
        app.registerActivityLifecycleCallbacks(activityTracker)
    }

    /** Adopts an already-resumed Activity the tracker registered too late to see. Main-thread only. */
    fun attachActivity(activity: Activity) {
        activityTracker.attach(activity)
    }

    /** Captures the resumed activity. No-op when disabled or when no activity is resumed. */
    fun capture(screen: String?) {
        if (!config.isEnabled) return
        val activity = activityTracker.currentActivity()
        if (activity == null) {
            logBuffer.append(
                HaviLogEntry(
                    level = HaviLogLevel.WARNING,
                    category = "app",
                    message = NO_ACTIVITY_MESSAGE,
                ),
            )
            return
        }
        captureController.present(activity, screen)
    }

    /** The capture sheet was dismissed — release the in-flight capture so the next trigger works. */
    fun finishCapture() {
        captureController.finishCapture()
    }

    /** Credential resolution at submit (wire spec §1.1): stored token overrides the stamped dev token. */
    fun resolvedToken(): String? = (tokenStore.accessToken ?: config.devToken)?.takeIf { it.isNotEmpty() }

    fun resolvedWorkspaceId(): String? = (tokenStore.workspaceId ?: config.workspaceId)?.takeIf { it.isNotEmpty() }

    /** Whether a usable credential resolves — a stored credential, or the stamped dev token + workspace. */
    val isConnected: Boolean
        get() = tokenStore.hasCredential || (config.workspaceId != null && config.devToken != null)

    val authState: HaviAuthState
        get() =
            when {
                !config.isEnabled -> HaviAuthState.Unconfigured
                tokenStore.hasCredential -> HaviAuthState.Authenticated(tokenStore.workspaceId ?: "")
                config.devToken != null && config.workspaceId != null ->
                    HaviAuthState.Authenticated(config.workspaceId ?: "")
                else -> HaviAuthState.NeedsReconnect
            }

    /** Resolves (and caches) the label vocabulary for [workspaceId]; null on any fetch failure. */
    fun labelDefinitions(
        token: String,
        workspaceId: String,
    ): List<HaviLabelDefinition>? {
        labelCache?.let { (cachedWorkspace, definitions) ->
            if (cachedWorkspace == workspaceId) return definitions
        }
        val definitions = labelService.fetch(token, workspaceId) ?: return null
        labelCache = workspaceId to definitions
        return definitions
    }

    private fun fireCapture() {
        mainHandler.post { capture(null) }
    }

    private companion object {
        // Secondary trigger for emulators without a usable shake sensor; on by default.
        const val LONG_PRESS_ENABLED = true

        const val NO_ACTIVITY_MESSAGE =
            "Havi.capture() did nothing — HaviKit is not tracking a resumed Activity. " +
                "Start the SDK from Application.onCreate, or call Havi.attachActivity(activity) " +
                "once after Havi.start when starting later."
    }
}
