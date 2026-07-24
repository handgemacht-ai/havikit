package ai.handgemacht.havikit

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.net.URI

/**
 * Submit retry / fallback loop (wire spec §7.3): success, once-each PNG and
 * smaller re-encodes, single transient retry, immediate reconnect on auth, and the
 * pre-request reconnect guard when the credential is missing. Plus the two
 * protocol guarantees around that loop: one idempotency key per annotation across
 * every send of it, and a rejected credential dropped from the store.
 */
class HaviUploaderTest {
    private val config =
        HaviConfig(
            isEnabled = true,
            baseUrl = URI("https://havi.example.test"),
            workspaceId = null,
            project = null,
            worktree = null,
            branch = null,
            commit = null,
            imageFormat = HaviImageFormat.PNG,
            devToken = null,
        )

    private fun pending(
        format: HaviImageFormat = HaviImageFormat.PNG,
        reencoder: HaviImageReencoder? = null,
    ) = PendingAnnotation(
        annotationJson = """{"type":"Annotation"}""",
        imageData = byteArrayOf(1, 2, 3),
        imageFormat = format,
        siblings = mapOf("project" to "lesewerkstatt"),
        workspaceId = "ws-9",
        bearerToken = "tok",
        reencoder = reencoder,
    )

    private fun uploader(
        transport: StubTransport,
        tokenStore: HaviTokenStore? = null,
    ) = HaviUploader(config, transport, tokenStore, retryDelayMillis = 0, sleep = {})

    private fun connectedStore() =
        HaviTokenStore().apply { signIn(token = "revoked-tok", workspaceId = "ws-9") }

    @Test
    fun successReturnsId() {
        val transport = StubTransport().enqueue(201, """{"data":{"id":"anno-1"}}""")
        assertEquals(HaviSubmitResult.Success("anno-1"), uploader(transport).submit(pending()))
        assertEquals(1, transport.consumedCount)
        val request = transport.requests.single()
        assertEquals("Bearer tok", request.headers["Authorization"])
        assertEquals("ws-9", request.headers["x-havi-workspace-id"])
        assertEquals("https://havi.example.test/api/annotations", request.url.toString())
    }

    @Test
    fun missingCredentialReturnsReconnectWithoutRequest() {
        val transport = StubTransport()
        val result = uploader(transport).submit(pending().copy(bearerToken = null))
        assertEquals(HaviSubmitFailureKind.RECONNECT, (result as HaviSubmitResult.Failure).failure.kind)
        assertEquals(0, transport.consumedCount)
    }

    @Test
    fun unauthorizedMapsToReconnectImmediately() {
        val transport = StubTransport().enqueue(401, """{"error":{"code":"unauthorized"}}""")
        val result = uploader(transport).submit(pending())
        assertEquals(HaviSubmitFailureKind.RECONNECT, (result as HaviSubmitResult.Failure).failure.kind)
        assertEquals(1, transport.consumedCount)
    }

    @Test
    fun unsupportedMediaTypeReencodesToPngOnceThenSucceeds() {
        val transport =
            StubTransport()
                .enqueue(415, """{"error":{"code":"unsupported_media_type"}}""")
                .enqueue(201, """{"data":{"id":"anno-2"}}""")
        var reencodeCalls = 0
        val reencoder =
            HaviImageReencoder { format, longestSide ->
                reencodeCalls++
                assertEquals(HaviImageFormat.PNG, format)
                assertEquals(HaviImagePlan.DEFAULT_MAX_LONGEST_SIDE, longestSide)
                byteArrayOf(9, 9)
            }
        val result = uploader(transport).submit(pending(format = HaviImageFormat.JPEG, reencoder = reencoder))
        assertEquals(HaviSubmitResult.Success("anno-2"), result)
        assertEquals(1, reencodeCalls)
        assertEquals(2, transport.consumedCount)
    }

    @Test
    fun payloadTooLargeReencodesSmallerOnce() {
        val transport =
            StubTransport()
                .enqueue(413, """{"error":{"code":"payload_too_large"}}""")
                .enqueue(200, """{"data":{"id":"anno-3"}}""")
        var longest = -1
        val reencoder =
            HaviImageReencoder { _, longestSide ->
                longest = longestSide
                byteArrayOf(7)
            }
        val result = uploader(transport).submit(pending(reencoder = reencoder))
        assertEquals(HaviSubmitResult.Success("anno-3"), result)
        assertEquals(HaviImagePlan.PAYLOAD_TOO_LARGE_LONGEST_SIDE, longest)
    }

    @Test
    fun payloadTooLargeWithoutReencoderIsTerminal() {
        val transport = StubTransport().enqueue(413, """{"error":{"code":"payload_too_large"}}""")
        val result = uploader(transport).submit(pending(reencoder = null))
        assertEquals(HaviSubmitFailureKind.TERMINAL, (result as HaviSubmitResult.Failure).failure.kind)
        assertEquals(1, transport.consumedCount)
    }

    @Test
    fun transientRetriesOnceThenReturnsRetry() {
        val transport =
            StubTransport()
                .enqueue(500, "boom")
                .enqueue(500, "boom again")
        val result = uploader(transport).submit(pending())
        assertEquals(HaviSubmitFailureKind.RETRY, (result as HaviSubmitResult.Failure).failure.kind)
        assertEquals(2, transport.consumedCount)
    }

    @Test
    fun transportFailureIsTransient() {
        val transport = StubTransport().enqueueFailure().enqueue(201, """{"data":{"id":"anno-4"}}""")
        assertEquals(HaviSubmitResult.Success("anno-4"), uploader(transport).submit(pending()))
        assertEquals(2, transport.consumedCount)
    }

    @Test
    fun bare429RetriesInsteadOfDeadEnding() {
        val transport = StubTransport().enqueue(429, "").enqueue(201, """{"data":{"id":"anno-5"}}""")
        assertEquals(HaviSubmitResult.Success("anno-5"), uploader(transport).submit(pending()))
        assertEquals(2, transport.consumedCount)
    }

    // Idempotency: one key per annotation, on every send of it.

    @Test
    fun idempotencyKeyIsSentAndStableAcrossRetriesAndReencodeFallbacks() {
        val transport =
            StubTransport()
                .enqueue(415, """{"error":{"code":"unsupported_media_type"}}""")
                .enqueue(413, """{"error":{"code":"payload_too_large"}}""")
                .enqueueFailure()
                .enqueue(201, """{"data":{"id":"anno-6"}}""")
        val annotation =
            pending(
                format = HaviImageFormat.JPEG,
                reencoder = HaviImageReencoder { _, _ -> byteArrayOf(4, 2) },
            )

        assertEquals(HaviSubmitResult.Success("anno-6"), uploader(transport).submit(annotation))
        assertEquals(4, transport.consumedCount)
        val keys = transport.requests.map { it.headers["Idempotency-Key"] }
        assertTrue(annotation.idempotencyKey.isNotEmpty())
        assertEquals(List(4) { annotation.idempotencyKey }, keys)
    }

    @Test
    fun eachPendingAnnotationMintsItsOwnKey() {
        assertNotEquals(pending().idempotencyKey, pending().idempotencyKey)
    }

    // Reauth: the credential the server just rejected must not survive in the store.

    @Test
    fun reauthClearsTheRejectedCredential() {
        val store = connectedStore()
        val transport = StubTransport().enqueue(401, """{"error":{"code":"unauthorized"}}""")

        val result = uploader(transport, store).submit(pending())

        assertEquals(HaviSubmitFailureKind.RECONNECT, (result as HaviSubmitResult.Failure).failure.kind)
        assertFalse(store.hasCredential, "a rejected credential must not stay in the store")
    }

    @Test
    fun workspaceReauthClearsTheRejectedCredential() {
        val store = connectedStore()
        val transport = StubTransport().enqueue(400, """{"error":{"code":"workspace_not_found"}}""")

        uploader(transport, store).submit(pending())

        assertFalse(store.hasCredential)
    }

    @Test
    fun nonAuthFailuresKeepTheCredential() {
        val store = connectedStore()
        val transport = StubTransport().enqueue(422, """{"error":{"code":"validation_error"}}""")

        uploader(transport, store).submit(pending())

        assertTrue(store.hasCredential, "only an auth rejection drops the credential")
    }
}
