package ai.handgemacht.havikit

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.net.URI
import java.time.Instant
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Drives the connect sheet (Part B5), mirroring iOS `HaviConnectModel`: create a
 * `client_type: mobile` pairing, open the approval page in the browser, poll the
 * exchange endpoint while the developer approves, and resolve to a connected
 * identity, an expired link, or a plain-language error. The network + poll state
 * machine live in the pure `HaviConnectService`; the browser open / auto-dismiss
 * rules in the pure [HaviConnectBrowserState]; this is the Compose-observable glue.
 *
 * The load-bearing invariants are preserved: a single in-flight flow (no second
 * concurrent create that would orphan an approved code), resume on the SAME
 * `device_code` after a background stop, the store as source of truth for
 * "connected", and the reconnect guard that refuses to settle back to the rejected
 * token.
 */
internal class HaviConnectController(
    private val runtime: HaviRuntime,
    reconnect: Boolean,
    private val scope: CoroutineScope,
) {
    sealed interface Phase {
        data class Connected(val session: HaviConnectedSession) : Phase

        data object Creating : Phase

        data class Awaiting(val link: HaviSetupLink) : Phase

        data object Expired : Phase

        data class Error(val message: String) : Phase
    }

    var phase by mutableStateOf<Phase>(Phase.Creating)
        private set

    var browser by mutableStateOf(HaviConnectBrowserState())
        private set

    var pasteToken by mutableStateOf("")
    var pasteWorkspaceId by mutableStateOf("")

    private val cancelFlag = AtomicBoolean(false)
    private var flowJob: Job? = null
    private var flowActive = false
    private var pendingLink: HaviSetupLink? = null
    private var didStart = false
    private val rejectedToken: String?

    init {
        val existing = runtime.tokenStore.connectedSession
        if (!reconnect && existing != null) {
            phase = Phase.Connected(existing)
            didStart = true
            rejectedToken = null
        } else {
            phase = Phase.Creating
            rejectedToken = if (reconnect) runtime.tokenStore.accessToken else null
        }
    }

    val connectedSession: HaviConnectedSession? get() = (phase as? Phase.Connected)?.session

    val approveUrl: URI? get() = (phase as? Phase.Awaiting)?.link?.approveUrl

    fun onAppear() {
        if (reconcileFromStore()) return
        if (didStart) resumePollingIfNeeded() else start()
    }

    fun applicationBecameActive() {
        if (reconcileFromStore()) return
        resumePollingIfNeeded()
    }

    /** The store is the source of truth for "connected"; a fresh, different token settles the sheet. */
    private fun reconcileFromStore(): Boolean {
        val session = runtime.tokenStore.connectedSession ?: return false
        if (phase is Phase.Connected) return true
        if (rejectedToken != null && session.accessToken == rejectedToken) return false
        cancelFlag.set(true)
        flowJob?.cancel()
        flowActive = false
        pendingLink = null
        browser = browser.flowSettled()
        phase = Phase.Connected(session)
        return true
    }

    private fun resumePollingIfNeeded() {
        if (flowActive) return
        val link = pendingLink ?: return
        if (!Instant.now().isBefore(link.expiresAt)) {
            pendingLink = null
            browser = browser.flowSettled()
            phase = Phase.Expired
            return
        }
        flowActive = true
        cancelFlag.set(false)
        flowJob?.cancel()
        flowJob = scope.launch { poll(link); flowActive = false }
    }

    fun start() {
        didStart = true
        flowActive = true
        flowJob?.cancel()
        cancelFlag.set(false)
        phase = Phase.Creating
        browser = HaviConnectBrowserState()
        pendingLink = null
        flowJob = scope.launch { runFlow(); flowActive = false }
    }

    fun openApproval() {
        browser = browser.openRequested()
    }

    fun browserClosed() {
        browser = browser.browserClosed()
    }

    fun cancel() {
        cancelFlag.set(true)
        flowJob?.cancel()
        flowActive = false
        pendingLink = null
    }

    fun usePastedToken() {
        val token = pasteToken.trim()
        val workspace = pasteWorkspaceId.trim()
        if (token.isEmpty() || workspace.isEmpty()) return
        cancel()
        browser = browser.flowSettled()
        runtime.tokenStore.signIn(token, workspace)
        phase =
            Phase.Connected(
                runtime.tokenStore.connectedSession
                    ?: HaviConnectedSession(accessToken = token, workspaceId = workspace),
            )
    }

    fun disconnect() {
        cancel()
        runtime.tokenStore.clear()
        Havi.clearPendingPriority()
        start()
    }

    private suspend fun runFlow() {
        when (val result = withContext(Dispatchers.IO) { runtime.connectService.createSetupLink() }) {
            is HaviCreateLinkResult.Failure -> {
                browser = browser.flowSettled()
                phase = Phase.Error(result.failure.userMessage)
            }
            is HaviCreateLinkResult.Success -> {
                pendingLink = result.link
                phase = Phase.Awaiting(result.link)
                browser = browser.beganAwaiting()
                poll(result.link)
            }
        }
    }

    private suspend fun poll(link: HaviSetupLink) {
        val result =
            withContext(Dispatchers.IO) {
                runtime.connectService.runExchange(link = link, isCancelled = { cancelFlag.get() })
            }
        when (result) {
            is HaviConnectResult.Connected -> {
                pendingLink = null
                browser = browser.flowSettled()
                phase = Phase.Connected(result.session)
            }
            HaviConnectResult.Expired -> {
                pendingLink = null
                browser = browser.flowSettled()
                phase = Phase.Expired
            }
            is HaviConnectResult.Failed -> {
                pendingLink = null
                browser = browser.flowSettled()
                phase = Phase.Error(result.failure.userMessage)
            }
            HaviConnectResult.Cancelled -> Unit
        }
    }
}
