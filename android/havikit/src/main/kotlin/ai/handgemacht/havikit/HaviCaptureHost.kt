package ai.handgemacht.havikit

import android.app.Activity
import android.content.Context
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
 * The host, not the composition, owns the capture **session** (the
 * [HaviCaptureViewModel] and with it the frozen frame, the markup, the comment and
 * the submit phase). A configuration change — rotation, dark-mode/font/locale
 * toggle, multi-window resize — destroys the Activity and the overlay with it, but
 * the session survives: [onHostDestroyed] only detaches the view, and
 * [onHostResumed] re-mounts the same session onto the recreated Activity. The submit
 * itself runs on [HaviRuntime]'s scope, so it keeps going while no view is attached
 * and its outcome lands on the re-mounted sheet — or, if it finishes first, as the
 * usual dismissal plus confirmation. Only a real dismiss ends the session.
 */
internal class HaviCaptureHost(
    private val runtime: HaviRuntime,
    appContext: Context,
    private val activityProvider: () -> Activity?,
) {
    private val appContext = appContext.applicationContext

    private var overlay: ComposeView? = null
    private var host: Activity? = null
    private var session: HaviCaptureViewModel? = null

    /** Freeze delivered — mount the sheet over the current Activity. Main-thread only. */
    fun present(frame: HaviCaptureFrame) {
        if (session != null) {
            runtime.finishCapture()
            return
        }
        val activity = activityProvider()
        if (activity == null) {
            runtime.finishCapture()
            return
        }

        val model =
            HaviCaptureViewModel(
                frame = frame,
                runtime = runtime,
                scope = runtime.submitScope,
                initialPriority = Havi.consumePendingPriority() ?: HaviPriority.MEDIUM,
                onSubmitSuccess = { confirmSubmission() },
            )
        session = model
        if (!mount(activity, model)) {
            session = null
            runtime.finishCapture()
        }
    }

    /**
     * An Activity resumed. When a configuration change left a session without a view,
     * this is the recreated Activity — put the sheet back, in the state the user left
     * it (screen, markup, comment, and a submit that never stopped running).
     */
    fun onHostResumed(activity: Activity) {
        if (overlay != null) return
        val model = session ?: return
        mount(activity, model)
    }

    /**
     * The Activity hosting the overlay was destroyed. A configuration change hands the
     * session to the Activity that replaces it; anything else (the host app finishing
     * the Activity under the sheet) is a real dismiss, so the controller is released
     * and neither the destroyed Activity nor its detached ComposeView is retained.
     * Main-thread only.
     */
    fun onHostDestroyed(activity: Activity) {
        if (host !== activity) return
        if (session != null && activity.isChangingConfigurations) {
            detach()
        } else {
            dismiss()
        }
    }

    fun dismiss() {
        if (session == null && overlay == null) return
        detach()
        session = null
        runtime.cancelSubmission()
        runtime.finishCapture()
    }

    private fun mount(
        activity: Activity,
        model: HaviCaptureViewModel,
    ): Boolean {
        val content = activity.findViewById<ViewGroup>(android.R.id.content) ?: return false
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
                        model = model,
                        runtime = runtime,
                        onClose = { dismiss() },
                    )
                }
            }

        overlay = view
        host = activity
        content.addView(view)
        return true
    }

    private fun detach() {
        val view = overlay ?: return
        (view.parent as? ViewGroup)?.removeView(view)
        overlay = null
        host = null
    }

    private fun confirmSubmission() {
        dismiss()
        Toast.makeText(appContext, "Report sent", Toast.LENGTH_SHORT).show()
    }
}
