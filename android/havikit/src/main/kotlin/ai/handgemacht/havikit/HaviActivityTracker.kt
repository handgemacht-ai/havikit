package ai.handgemacht.havikit

import android.app.Activity
import android.app.Application
import android.os.Bundle
import java.lang.ref.WeakReference

/**
 * Tracks the resumed activity (Part B4) so a capture always targets the window the
 * user is looking at, and reports foreground/background transitions via a started-count
 * so the shake sensor is armed only while the app is on screen. The resumed activity is
 * held weakly so the tracker never leaks it.
 *
 * Lifecycle callbacks only arrive once [HaviRuntime.start] registers them, so an
 * Activity that resumed before the SDK started is invisible here until the next
 * foreground cycle — the React Native / Expo case, where JS calls `Havi.start` long
 * after the first Activity resumed. [attach] closes that gap for hosts that can name
 * the current window.
 */
internal class HaviActivityTracker : Application.ActivityLifecycleCallbacks {
    interface Listener {
        fun onForeground() {}

        fun onBackground() {}

        fun onResumed(activity: Activity) {}

        fun onPaused(activity: Activity) {}

        fun onDestroyed(activity: Activity) {}
    }

    var listener: Listener? = null

    private var currentRef: WeakReference<Activity>? = null
    private var seededRef: WeakReference<Activity>? = null
    private var startedCount = 0

    fun currentActivity(): Activity? = currentRef?.get()

    /**
     * Adopts [activity] as the resumed window, standing in for the `onActivityStarted` /
     * `onActivityResumed` pair the tracker missed by registering late. Re-seeding the
     * Activity already tracked is a no-op, so callers may seed defensively. Main-thread
     * only: the listener attaches the long-press trigger to the Activity's window.
     */
    fun attach(activity: Activity) {
        if (currentRef?.get() === activity) return
        currentRef = WeakReference(activity)
        if (startedCount == 0) {
            startedCount = 1
            seededRef = WeakReference(activity)
            listener?.onForeground()
        }
        listener?.onResumed(activity)
    }

    override fun onActivityStarted(activity: Activity) {
        // A seeded Activity that had not actually started yet still delivers its own
        // start; counting it twice would leave the shake sensor armed in the background.
        if (seededRef?.get() === activity) {
            seededRef = null
            return
        }
        if (startedCount == 0) listener?.onForeground()
        startedCount++
    }

    override fun onActivityResumed(activity: Activity) {
        currentRef = WeakReference(activity)
        listener?.onResumed(activity)
    }

    override fun onActivityPaused(activity: Activity) {
        if (currentRef?.get() === activity) currentRef = null
        listener?.onPaused(activity)
    }

    override fun onActivityStopped(activity: Activity) {
        if (seededRef?.get() === activity) seededRef = null
        startedCount--
        if (startedCount <= 0) {
            startedCount = 0
            listener?.onBackground()
        }
    }

    override fun onActivityCreated(
        activity: Activity,
        savedInstanceState: Bundle?,
    ) = Unit

    override fun onActivitySaveInstanceState(
        activity: Activity,
        outState: Bundle,
    ) = Unit

    override fun onActivityDestroyed(activity: Activity) {
        listener?.onDestroyed(activity)
    }
}
