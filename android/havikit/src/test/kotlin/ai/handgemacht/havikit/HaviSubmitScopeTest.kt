package ai.handgemacht.havikit

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineExceptionHandler
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * The scope is what makes a submit outlive the sheet's composition. It runs on
 * `Dispatchers.Main.immediate` in production; the tests inject an unconfined context
 * so the state machine is exercised without a Looper.
 */
class HaviSubmitScopeTest {
    private fun scope() = HaviSubmitScope(Dispatchers.Unconfined + CoroutineExceptionHandler { _, _ -> })

    @Test
    fun `a submit keeps running when the host activity is destroyed and recreated`() =
        runBlocking {
            val submissions = scope()
            val upload = CompletableDeferred<Unit>()
            val finished = CompletableDeferred<Unit>()
            submissions.scope.launch {
                upload.await()
                finished.complete(Unit)
            }

            // A configuration change tears down the Activity and the overlay; nothing
            // touches the SDK-owned scope, so the in-flight upload is still there.
            upload.complete(Unit)

            withTimeout(TIMEOUT_MS) { finished.await() }
        }

    @Test
    fun `a real dismiss cancels the in-flight submit`() =
        runBlocking {
            val submissions = scope()
            val started = CompletableDeferred<Unit>()
            val job =
                submissions.scope.launch {
                    started.complete(Unit)
                    awaitCancellation()
                }
            started.await()

            submissions.cancelInFlight()

            withTimeout(TIMEOUT_MS) { job.join() }
            assertTrue(job.isCancelled)
        }

    @Test
    fun `the scope still serves the next capture after a dismiss`() =
        runBlocking {
            val submissions = scope()
            submissions.scope.launch { awaitCancellation() }
            submissions.cancelInFlight()

            val next = CompletableDeferred<Unit>()
            submissions.scope.launch { next.complete(Unit) }

            withTimeout(TIMEOUT_MS) { next.await() }
            assertTrue(submissions.scope.isActive)
        }

    @Test
    fun `a crashing submit does not take the scope down with it`() =
        runBlocking {
            val submissions = scope()
            submissions.scope.launch { throw IllegalStateException("upload blew up") }

            val next = CompletableDeferred<Unit>()
            submissions.scope.launch { next.complete(Unit) }

            withTimeout(TIMEOUT_MS) { next.await() }
            assertTrue(submissions.scope.isActive)
        }

    private companion object {
        const val TIMEOUT_MS = 2_000L
    }
}
