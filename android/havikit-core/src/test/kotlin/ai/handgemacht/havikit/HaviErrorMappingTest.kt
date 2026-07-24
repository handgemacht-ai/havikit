package ai.handgemacht.havikit

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

/** `error.code` -> action table + response classification (wire spec §7). */
class HaviErrorMappingTest {
    @Test
    fun mapCodeCoversTheTable() {
        assertEquals(HaviErrorAction.REAUTH, HaviErrorMapping.mapCode("unauthorized").action)
        assertEquals(HaviErrorAction.REAUTH, HaviErrorMapping.mapCode("workspace_required").action)
        assertEquals(HaviErrorAction.REAUTH, HaviErrorMapping.mapCode("missing_workspace_id").action)
        assertEquals(HaviErrorAction.REAUTH, HaviErrorMapping.mapCode("invalid_workspace_id").action)
        assertEquals(HaviErrorAction.REAUTH, HaviErrorMapping.mapCode("workspace_not_found").action)
        assertEquals(HaviErrorAction.TERMINAL, HaviErrorMapping.mapCode("forbidden").action)
        assertEquals(HaviErrorAction.REENCODE_PNG, HaviErrorMapping.mapCode("unsupported_media_type").action)
        assertEquals(HaviErrorAction.REENCODE_SMALLER, HaviErrorMapping.mapCode("payload_too_large").action)
        assertEquals(HaviErrorAction.TERMINAL, HaviErrorMapping.mapCode("validation_error").action)
        assertEquals(HaviErrorAction.TRANSIENT_RETRY, HaviErrorMapping.mapCode("storage_error").action)
        assertEquals(HaviErrorAction.TERMINAL, HaviErrorMapping.mapCode("not_found").action)
        assertEquals(HaviErrorAction.TERMINAL, HaviErrorMapping.mapCode("something_new").action)
    }

    @Test
    fun classifySuccessReadsOptionalId() {
        val ok = HaviErrorMapping.classify(200, bytes("""{"data":{"id":"anno-1"}}"""))
        assertEquals(HaviResponseClassification.Success("anno-1"), ok)

        val okNoId = HaviErrorMapping.classify(201, bytes("""{"data":{}}"""))
        assertEquals(HaviResponseClassification.Success(null), okNoId)
    }

    @Test
    fun classifyKeysOnErrorCodeNotStatus() {
        val mapped = HaviErrorMapping.classify(400, bytes("""{"error":{"code":"unauthorized"}}"""))
        assertEquals(HaviErrorAction.REAUTH, (mapped as HaviResponseClassification.Mapped).error.action)
    }

    @Test
    fun classify5xxWithoutCodeIsTransientElseTerminal() {
        val transient = HaviErrorMapping.classify(503, bytes("gateway down"))
        assertEquals(HaviErrorAction.TRANSIENT_RETRY, (transient as HaviResponseClassification.Mapped).error.action)

        val terminal = HaviErrorMapping.classify(418, bytes("teapot"))
        assertEquals(HaviErrorAction.TERMINAL, (terminal as HaviResponseClassification.Mapped).error.action)
    }

    /** A rate limit arrives body-less from an edge proxy: retryable, not a dead end. */
    @Test
    fun classifyBare429IsTransient() {
        val empty = HaviErrorMapping.classify(429, bytes(""))
        assertEquals(HaviResponseClassification.Mapped(HaviErrorMapping.transientTransport), empty)

        val html = HaviErrorMapping.classify(429, bytes("<html>Too Many Requests</html>"))
        assertEquals(HaviErrorAction.TRANSIENT_RETRY, (html as HaviResponseClassification.Mapped).error.action)

        // A 429 that DOES carry a code still maps on the code.
        val coded = HaviErrorMapping.classify(429, bytes("""{"error":{"code":"unauthorized"}}"""))
        assertEquals(HaviErrorAction.REAUTH, (coded as HaviResponseClassification.Mapped).error.action)
    }

    private fun bytes(json: String): ByteArray = json.toByteArray(Charsets.UTF_8)
}
