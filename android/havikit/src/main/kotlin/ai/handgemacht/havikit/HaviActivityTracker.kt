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
    private var startedCount = 0

    fun currentActivity(): Activity? = currentRef?.get()

    override fun onActivityStarted(activity: Activity) {
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
