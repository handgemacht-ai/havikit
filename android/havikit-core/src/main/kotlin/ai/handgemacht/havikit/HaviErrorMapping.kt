package ai.handgemacht.havikit

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/**
 * What the uploader should do next for a given failure (wire spec §7). The
 * re-encode actions are handled inside the uploader; the others fall through to a
 * [HaviSubmitFailure] the capture sheet surfaces.
 */
public enum class HaviErrorAction {
    /** `unsupported_media_type` — re-encode to PNG once and retry. */
    REENCODE_PNG,

    /** `payload_too_large` — re-encode at 1024 longest side and retry. */
    REENCODE_SMALLER,

    /** Network / timeout / `storage_error` — one in-memory retry, then Retry. */
    TRANSIENT_RETRY,

    /** Auth / workspace — route to the reconnect path, never blind-retry. */
    REAUTH,

    /** `validation_error` / `forbidden` / `not_found` — do not retry. */
    TERMINAL,
}

public data class HaviMappedError(
    val code: String?,
    val userMessage: String,
    val action: HaviErrorAction,
)

/** The outcome of one completed HTTP round-trip, before any fallback handling. */
public sealed interface HaviResponseClassification {
    public data class Success(val id: String?) : HaviResponseClassification

    public data class Mapped(val error: HaviMappedError) : HaviResponseClassification
}

/**
 * Decodes the standard error envelope and maps on `error.code`, never HTTP status
 * (wire spec §7 — the controller returns stable codes while statuses vary).
 */
public object HaviErrorMapping {
    private val json = Json { ignoreUnknownKeys = true }

    public fun mapCode(code: String?): HaviMappedError =
        when (code) {
            "unauthorized" ->
                HaviMappedError(code, "HAVI sign-in expired — reconnect.", HaviErrorAction.REAUTH)

            "workspace_required", "missing_workspace_id", "invalid_workspace_id", "workspace_not_found" ->
                HaviMappedError(code, "HAVI workspace not set up — reconnect.", HaviErrorAction.REAUTH)

            "forbidden" ->
                HaviMappedError(code, "Not allowed for this workspace.", HaviErrorAction.TERMINAL)

            "unsupported_media_type" ->
                HaviMappedError(code, "Screenshot format rejected.", HaviErrorAction.REENCODE_PNG)

            "payload_too_large" ->
                HaviMappedError(code, "Screenshot too large — retrying smaller.", HaviErrorAction.REENCODE_SMALLER)

            "validation_error" ->
                HaviMappedError(code, "Couldn't submit annotation (validation).", HaviErrorAction.TERMINAL)

            "storage_error" ->
                HaviMappedError(code, "Server storage hiccup — retry.", HaviErrorAction.TRANSIENT_RETRY)

            "not_found" ->
                HaviMappedError(code, "Annotation not found.", HaviErrorAction.TERMINAL)

            else ->
                HaviMappedError(code, "Couldn't submit annotation.", HaviErrorAction.TERMINAL)
        }

    /** Transport-class failure (no HTTP response, or a thrown request): transient. */
    public val transientTransport: HaviMappedError =
        HaviMappedError(
            code = null,
            userMessage = "No connection to HAVI — retry.",
            action = HaviErrorAction.TRANSIENT_RETRY,
        )

    public fun classify(
        status: Int,
        body: ByteArray,
    ): HaviResponseClassification {
        if (status in 200..299) {
            return HaviResponseClassification.Success(id = createdId(body))
        }
        errorCode(body)?.let { return HaviResponseClassification.Mapped(mapCode(it)) }
        // No JSON error.code: classify by transport class — 5xx and a bare 429
        // (rate limit / edge throttle, often body-less) transient, else terminal.
        if (status == TOO_MANY_REQUESTS) {
            return HaviResponseClassification.Mapped(transientTransport)
        }
        if (status >= 500) {
            return HaviResponseClassification.Mapped(transientTransport)
        }
        return HaviResponseClassification.Mapped(
            HaviMappedError(code = null, userMessage = "Couldn't submit annotation.", action = HaviErrorAction.TERMINAL),
        )
    }

    private fun createdId(body: ByteArray): String? {
        val root = parseObject(body) ?: return null
        val data = root["data"] as? JsonObject ?: return null
        return (data["id"] as? JsonPrimitive)?.takeIf { it.isString }?.content
    }

    private fun errorCode(body: ByteArray): String? {
        val root = parseObject(body) ?: return null
        val error = root["error"] as? JsonObject ?: return null
        return (error["code"] as? JsonPrimitive)?.takeIf { it.isString }?.content
    }

    private fun parseObject(body: ByteArray): JsonObject? =
        runCatching { json.parseToJsonElement(body.toString(Charsets.UTF_8)) as? JsonObject }.getOrNull()

    private const val TOO_MANY_REQUESTS = 429
}
