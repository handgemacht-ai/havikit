package ai.handgemacht.havikit

import android.app.Activity
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertSame
import org.junit.jupiter.api.Test

/**
 * The tracker never calls into the Activity it tracks — it holds identity and hands the
 * reference to the listener — so its seed/clear state machine runs on the plain-JVM unit
 * test path against a bare [Activity] (the mockable `android.jar` returns defaults), with
 * no Robolectric or instrumentation.
 */
class HaviActivityTrackerTest {
    /** Records what the runtime would act on: trigger arming and long-press attach/detach. */
    private class RecordingListener : HaviActivityTracker.Listener {
        val events = mutableListOf<String>()

        override fun onForeground() {
            events += "foreground"
        }

        override fun onBackground() {
            events += "background"
        }

        override fun onResumed(activity: Activity) {
            events += "resumed"
        }

        override fun onPaused(activity: Activity) {
            events += "paused"
        }
    }

    private fun tracker(): Pair<HaviActivityTracker, RecordingListener> {
        val listener = RecordingListener()
        val tracker = HaviActivityTracker()
        tracker.listener = listener
        return tracker to listener
    }

    @Test
    fun `tracks nothing until an activity resumes`() {
        val (tracker, _) = tracker()

        assertNull(tracker.currentActivity())
    }

    @Test
    fun `attach adopts an activity that resumed before the tracker registered`() {
        val (tracker, listener) = tracker()
        val activity = Activity()

        tracker.attach(activity)

        assertSame(activity, tracker.currentActivity())
        assertEquals(listOf("foreground", "resumed"), listener.events)
    }

    @Test
    fun `re-attaching the tracked activity is a no-op`() {
        val (tracker, listener) = tracker()
        val activity = Activity()

        tracker.attach(activity)
        tracker.attach(activity)
        tracker.attach(activity)

        assertEquals(listOf("foreground", "resumed"), listener.events)
    }

    @Test
    fun `an attached activity backgrounds exactly once when it stops`() {
        val (tracker, listener) = tracker()
        val activity = Activity()

        tracker.attach(activity)
        tracker.onActivityPaused(activity)
        tracker.onActivityStopped(activity)

        assertNull(tracker.currentActivity())
        assertEquals(listOf("foreground", "resumed", "paused", "background"), listener.events)
    }

    @Test
    fun `an attached activity that later starts is not counted twice`() {
        val (tracker, listener) = tracker()
        val activity = Activity()

        tracker.attach(activity)
        tracker.onActivityStarted(activity)
        tracker.onActivityResumed(activity)
        tracker.onActivityPaused(activity)
        tracker.onActivityStopped(activity)

        assertEquals(
            listOf("foreground", "resumed", "resumed", "paused", "background"),
            listener.events,
        )
    }

    @Test
    fun `attach survives the activity being replaced by a real resume`() {
        val (tracker, _) = tracker()
        val first = Activity()
        val second = Activity()

        tracker.attach(first)
        tracker.onActivityStarted(second)
        tracker.onActivityResumed(second)
        tracker.onActivityPaused(first)
        tracker.onActivityStopped(first)

        assertSame(second, tracker.currentActivity())
    }

    @Test
    fun `the normal lifecycle path is unchanged when no activity is attached`() {
        val (tracker, listener) = tracker()
        val activity = Activity()

        tracker.onActivityStarted(activity)
        tracker.onActivityResumed(activity)
        assertSame(activity, tracker.currentActivity())

        tracker.onActivityPaused(activity)
        tracker.onActivityStopped(activity)

        assertNull(tracker.currentActivity())
        assertEquals(listOf("foreground", "resumed", "paused", "background"), listener.events)
    }
}
