package ai.handgemacht.havikit

import android.app.Activity
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.Toast
import androidx.compose.ui.platform.ComposeView
import androidx.compose.ui.platform.ViewCompositionStrategy

/**
 * Presents the capture sheet as an **Activity-scoped overlay** (Part B3), attaching
 * a [ComposeView] to the resumed Activity's content view — no `SYSTEM_ALERT_WINDOW`
 * permission, no separate window. One sheet at a time: a capture already on screen
 * is a no-op (the capture controller guards the same way). On close the overlay is
 * detached and the controller released via [HaviRuntime.finishCapture]; a
 * successful submit dismisses the sheet and raises the brief "Report sent"
 * confirmation.
 *
 * If the host Activity is torn down while the sheet is up (a configuration change —
 * rotation, dark-mode/font/locale toggle, multi-window resize — recreates it),
 * [onHostDestroyed] detaches the overlay and releases the controller so capture is
 * not left permanently disabled with a leaked Activity.
 */
internal class HaviCaptureHost(
    private val runtime: HaviRuntime,
    private val activityProvider: () -> Activity?,
) {
    private var overlay: ComposeView? = null
    private var host: Activity? = null

    /** Freeze delivered — mount the sheet over the current Activity. Main-thread only. */
    fun present(frame: HaviCaptureFrame) {
        if (overlay != null) {
            runtime.finishCapture()
            return
        }
        val activity = activityProvider()
        val content = activity?.findViewById<ViewGroup>(android.R.id.content)
        if (activity == null || content == null) {
            runtime.finishCapture()
            return
        }

        val view =
            ComposeView(activity).apply {
                setViewCompositionStrategy(ViewCompositionStrategy.DisposeOnDetachedFromWindow)
                layoutParams =
                    FrameLayout.LayoutParams(
                        FrameLayout.LayoutParams.MATCH_PARENT,
                        FrameLayout.LayoutParams.MATCH_PARENT,
                    )
                setContent {
                    HaviCaptureFlow(
                        frame = frame,
                        runtime = runtime,
                        onClose = { dismiss() },
                        onSubmitSuccess = { confirmSubmission(activity) },
                    )
                }
            }

        overlay = view
        host = activity
        content.addView(view)
    }

    private fun confirmSubmission(activity: Activity) {
        dismiss()
        Toast.makeText(activity.applicationContext, "Report sent", Toast.LENGTH_SHORT).show()
    }

    /**
     * The Activity hosting the overlay was destroyed (e.g. a configuration change
     * recreated it). Tear the sheet down so the controller is released and neither the
     * destroyed Activity nor its detached ComposeView is retained. Main-thread only.
     */
    fun onHostDestroyed(activity: Activity) {
        if (host === activity) dismiss()
    }

    fun dismiss() {
        val view = overlay ?: return
        (view.parent as? ViewGroup)?.removeView(view)
        overlay = null
        host = null
        runtime.finishCapture()
    }
}
