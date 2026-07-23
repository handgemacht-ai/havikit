package ai.handgemacht.havikit

import android.app.Activity
import android.app.Application
import android.os.Handler
import android.os.Looper

/**
 * The Android capture runtime, built once by [Havi.start]. It owns the activity
 * tracker, the capture controller (freeze + redact + build a [HaviCaptureFrame]), and
 * the triggers, wiring them to the app foreground/resume lifecycle: the shake sensor
 * is armed while any activity is started and the long-press observer rides the resumed
 * window. Every trigger funnels through the main thread before a capture starts.
 */
internal class HaviRuntime(
    private val application: Application?,
    private val config: HaviConfig,
    logBuffer: HaviLogBuffer,
    contextStore: HaviContextStore,
) {
    private val mainHandler = Handler(Looper.getMainLooper())
    private val activityTracker = HaviActivityTracker()
    private val captureController = HaviCaptureController(config, contextStore, logBuffer)
    private val triggers =
        HaviTriggerController(
            context = application,
            longPressEnabled = LONG_PRESS_ENABLED,
            onTrigger = { fireCapture() },
        )

    @Volatile
    private var started = false

    fun start() {
        if (started) return
        started = true

        val app = application ?: return
        activityTracker.listener =
            object : HaviActivityTracker.Listener {
                override fun onForeground() = triggers.armShake()

                override fun onBackground() = triggers.disarmShake()

                override fun onResumed(activity: Activity) = triggers.attachLongPress(activity)

                override fun onPaused(activity: Activity) = triggers.detachLongPress()
            }
        app.registerActivityLifecycleCallbacks(activityTracker)
    }

    /** Captures the resumed activity. No-op when disabled or when no activity is resumed. */
    fun capture(screen: String?) {
        if (!config.isEnabled) return
        val activity = activityTracker.currentActivity() ?: return
        captureController.present(activity, screen)
    }

    private fun fireCapture() {
        mainHandler.post { capture(null) }
    }

    private companion object {
        // The two-finger long-press is a secondary trigger for emulators without a
        // usable shake sensor; on by default, harmless in normal use (0.6 s, 2 fingers).
        const val LONG_PRESS_ENABLED = true
    }
}
