package ai.handgemacht.havikit

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.net.URI
import java.time.Instant
import java.time.OffsetDateTime

/**
 * A pending device-code pairing (wire spec §4): the poll [deviceCode], the full
 * [approveUrl] (the relative `approve_url` from create resolved against the base),
 * and the client-side TTL deadline after which the link is treated as expired.
 */
public data class HaviSetupLink(
    val deviceCode: String,
    val approveUrl: URI,
    val expiresAt: Instant,
)

public data class HaviConnectFailure(
    val userMessage: String,
)

/** Result of the unauthenticated create-setup-link call. */
public sealed interface HaviCreateLinkResult {
    public data class Success(val link: HaviSetupLink) : HaviCreateLinkResult

    public data class Failure(val failure: HaviConnectFailure) : HaviCreateLinkResult
}

/** Terminal outcome of the exchange poll loop (wire spec §4). */
public sealed interface HaviConnectResult {
    public data class Connected(val session: HaviConnectedSession) : HaviConnectResult

    public data object Expired : HaviConnectResult

    public data object Cancelled : HaviConnectResult

    public data class Failed(val failure: HaviConnectFailure) : HaviConnectResult
}

/** One completed exchange round-trip before the loop decides what to do next (wire spec §4.2). */
public sealed interface HaviExchangeStep {
    public data object Pending : HaviExchangeStep

    public data class Approved(val session: HaviConnectedSession) : HaviExchangeStep

    public data object Gone : HaviExchangeStep

    public data object Transient : HaviExchangeStep
}

/**
 * Device-code login client (wire spec §4). [createSetupLink] requests a
 * `client_type: mobile` pairing; [runExchange] polls the exchange endpoint until
 * the developer approves, the link's TTL expires, or the flow is cancelled. On
 * approval the resolved session is persisted to [HaviTokenStore] before returning.
 *
 * Synchronous and blocking; the clock ([now]) and the between-poll sleep ([sleep])
 * are injected so the state machine is unit-tested without the network or wall
 * time. The pure classify/parse/resolve seams are exposed as companion functions
 * (parity with the iOS `static` seams) and tested directly.
 */
public class HaviConnectService(
    private val config: HaviConfig,
    private val tokenStore: HaviTokenStore,
    private val transport: HaviHttpTransport,
    private val now: () -> Instant = { Instant.now() },
    private val sleep: (Long) -> Unit = { millis -> Thread.sleep(millis) },
) {
    public fun createSetupLink(): HaviCreateLinkResult {
        val baseUrl = config.baseUrl
            ?: return HaviCreateLinkResult.Failure(HaviConnectFailure("HAVI isn't configured on this build."))

        val request =
            HaviHttpRequest(
                method = "POST",
                url = HaviUrls.endpoint(baseUrl, "api/setup/link"),
                headers = mapOf("Content-Type" to "application/json"),
                body = buildJsonObject { put("client_type", "mobile") }.toString().toByteArray(Charsets.UTF_8),
            )

        return try {
            val response = transport.execute(request)
            val link =
                if (response.statusCode == 201) {
                    parseSetupLink(response.body, baseUrl, now())
                } else {
                    null
                }
            if (link != null) {
                HaviCreateLinkResult.Success(link)
            } else {
                HaviCreateLinkResult.Failure(
                    HaviConnectFailure(createFailureMessage(response.statusCode, response.body)),
                )
            }
        } catch (_: HaviTransportException) {
            HaviCreateLinkResult.Failure(HaviConnectFailure("No connection to HAVI — try again."))
        }
    }

    /**
     * Polls the exchange endpoint on [intervalMillis] until the developer approves,
     * the link's TTL passes ([HaviConnectResult.Expired]), or the run is cancelled
     * ([HaviConnectResult.Cancelled]). A transient blip keeps polling — the TTL
     * bounds the loop — while a server `setup_code_*` code short-circuits to
     * expired. Cancellation is checked before each poll, again immediately after an
     * `approved` response (so a cancel racing approval does not double-store), and
     * after a pending/transient response before sleeping (wire spec §4.1).
     */
    public fun runExchange(
        link: HaviSetupLink,
        intervalMillis: Long = 3_000L,
        isCancelled: () -> Boolean,
    ): HaviConnectResult {
        val baseUrl = config.baseUrl
            ?: return HaviConnectResult.Failed(HaviConnectFailure("HAVI isn't configured on this build."))

        while (true) {
            if (isCancelled()) return HaviConnectResult.Cancelled
            if (!now().isBefore(link.expiresAt)) return HaviConnectResult.Expired

            when (val step = exchangeStep(baseUrl, link.deviceCode)) {
                is HaviExchangeStep.Approved -> {
                    if (isCancelled()) return HaviConnectResult.Cancelled
                    tokenStore.store(step.session)
                    return HaviConnectResult.Connected(step.session)
                }

                HaviExchangeStep.Gone -> return HaviConnectResult.Expired

                HaviExchangeStep.Pending, HaviExchangeStep.Transient -> {
                    if (isCancelled()) return HaviConnectResult.Cancelled
                    sleep(intervalMillis)
                }
            }
        }
    }

    private fun exchangeStep(
        baseUrl: URI,
        deviceCode: String,
    ): HaviExchangeStep {
        val request =
            HaviHttpRequest(
                method = "POST",
                url = HaviUrls.endpoint(baseUrl, "api/setup/link/exchange"),
                headers = mapOf("Content-Type" to "application/json"),
                body = buildJsonObject { put("device_code", deviceCode) }.toString().toByteArray(Charsets.UTF_8),
            )
        return try {
            val response = transport.execute(request)
            classifyExchange(response.statusCode, response.body)
        } catch (_: HaviTransportException) {
            HaviExchangeStep.Transient
        }
    }

    public companion object {
        public const val LINK_TTL_SECONDS: Long = 600

        private val json = Json { ignoreUnknownKeys = true }

        private val goneCodes =
            setOf("setup_code_expired", "setup_code_used", "setup_code_not_found", "setup_code_revoked")

        /**
         * Maps one exchange round-trip: 201 -> approved (session parsed from the
         * envelope, else transient), 202 -> pending, a `setup_code_*` gone code ->
         * gone, everything else -> transient (wire spec §4.2). Classification keys
         * on `error.code`, not HTTP status.
         */
        public fun classifyExchange(
            status: Int,
            body: ByteArray,
        ): HaviExchangeStep {
            if (status == 201) {
                return parseSession(body)?.let { HaviExchangeStep.Approved(it) } ?: HaviExchangeStep.Transient
            }
            if (status == 202) {
                return HaviExchangeStep.Pending
            }
            val code = errorCode(body)
            return if (code != null && code in goneCodes) HaviExchangeStep.Gone else HaviExchangeStep.Transient
        }

        public fun parseSetupLink(
            body: ByteArray,
            baseUrl: URI,
            now: Instant,
        ): HaviSetupLink? {
            val data = dataObject(body) ?: return null
            val deviceCode = data.string("device_code")?.takeIf { it.isNotEmpty() } ?: return null
            val approvePath = data.string("approve_url") ?: return null
            val approveUrl = resolveApproveUrl(approvePath, baseUrl) ?: return null
            val expiresAt = data.string("expires_at")?.let { parseDate(it) } ?: now.plusSeconds(LINK_TTL_SECONDS)
            return HaviSetupLink(deviceCode = deviceCode, approveUrl = approveUrl, expiresAt = expiresAt)
        }

        /**
         * Resolves the server's relative `approve_url` against the base and accepts
         * it only when same-origin (wire spec §4.6). The absolute leading-slash path
         * replaces the base's own path. Rejects (null) an http downgrade against an
         * https base, a different host (absolute or protocol-relative), or a
         * different port. Only https is trusted, except a dev base served over http
         * may keep its own http scheme.
         */
        public fun resolveApproveUrl(
            approvePath: String,
            baseUrl: URI,
        ): URI? {
            val resolved = runCatching { baseUrl.resolve(approvePath) }.getOrNull() ?: return null
            val scheme = resolved.scheme?.lowercase() ?: return null
            val host = resolved.host ?: return null

            val baseScheme = baseUrl.scheme?.lowercase()
            if (!(scheme == "https" || (baseScheme == "http" && scheme == baseScheme))) {
                return null
            }
            if (!host.equals(baseUrl.host ?: "", ignoreCase = true) || resolved.port != baseUrl.port) {
                return null
            }
            return resolved
        }

        public fun parseSession(body: ByteArray): HaviConnectedSession? {
            val data = dataObject(body) ?: return null
            val token = data.string("token")?.takeIf { it.isNotEmpty() } ?: return null
            val workspace = data["workspace"] as? JsonObject ?: return null
            val workspaceId = workspace.string("id")?.takeIf { it.isNotEmpty() } ?: return null
            val user = data["user"] as? JsonObject
            return HaviConnectedSession(
                accessToken = token,
                workspaceId = workspaceId,
                refreshToken = null,
                expiresAt = data.string("expires_at")?.let { parseDate(it) },
                userName = user?.string("email"),
                workspaceName = workspace.string("name"),
            )
        }

        public fun createFailureMessage(
            status: Int,
            body: ByteArray,
        ): String {
            val code = errorCode(body)
            return when (code) {
                "setup_code_expired", "setup_code_used" -> "That link expired — get a new one."
                else -> "Couldn't start HAVI sign-in — try again."
            }
        }

        /**
         * Parses an RFC 3339 timestamp with or without fractional seconds (Elixir's
         * `DateTime.to_iso8601` emits either), mirroring iOS `parseDate` (wire spec §12).
         */
        public fun parseDate(value: String): Instant? =
            runCatching { OffsetDateTime.parse(value).toInstant() }.getOrNull()
                ?: runCatching { Instant.parse(value) }.getOrNull()

        private fun dataObject(body: ByteArray): JsonObject? = rootObject(body)?.get("data") as? JsonObject

        private fun errorCode(body: ByteArray): String? {
            val error = rootObject(body)?.get("error") as? JsonObject ?: return null
            return error.string("code")
        }

        private fun rootObject(body: ByteArray): JsonObject? =
            runCatching { json.parseToJsonElement(body.toString(Charsets.UTF_8)) as? JsonObject }.getOrNull()

        private fun JsonObject.string(key: String): String? =
            (this[key] as? JsonPrimitive)?.takeIf { it.isString }?.content
    }
}
