package ai.handgemacht.havikit

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancelChildren
import kotlin.coroutines.CoroutineContext

/**
 * The SDK-owned scope a submit runs on, owned by [HaviRuntime] rather than by the
 * capture sheet's composition.
 *
 * The sheet lives in a `ComposeView` attached to the host Activity's content view, so
 * every configuration change — rotation, dark-mode toggle, font-scale change,
 * split-screen resize — destroys the Activity, detaches the view and disposes the
 * composition. A `rememberCoroutineScope()` dies with that composition, which
 * cancelled an in-flight submit at whatever suspension point it had reached. The
 * blocking upload may already have landed server-side, so the user saw a lost report
 * while the workspace recorded one.
 *
 * A [SupervisorJob] here outlives the Activity: only a real dismiss (close, terminal
 * failure, successful send) calls [cancelInFlight], and cancelling children keeps the
 * scope usable for the next capture.
 */
internal class HaviSubmitScope(
    dispatcher: CoroutineContext = Dispatchers.Main.immediate,
) {
    private val job = SupervisorJob()

    val scope: CoroutineScope = CoroutineScope(job + dispatcher)

    fun cancelInFlight() {
        job.cancelChildren()
    }
}
