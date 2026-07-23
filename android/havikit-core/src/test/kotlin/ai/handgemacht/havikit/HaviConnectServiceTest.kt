package ai.handgemacht.havikit

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertInstanceOf
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test
import java.net.URI
import java.time.Instant
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong

/**
 * Device-code poll state-machine tests (wire spec §4), mirroring the iOS
 * `HaviConnectServiceTests`: pending->approved (session persisted),
 * pending->expired via the client TTL, gone code, cancel — all against a scripted
 * transport with an injected clock / no-op sleep. Plus the pure classify / parse /
 * same-origin-guard seams.
 */
class HaviConnectServiceTest {
    private val approvedJson =
        """
        {"data":{"status":"approved","client_type":"mobile","token":"tok-abc","token_type":"Bearer",
        "expires_at":"2026-10-19T10:30:00Z","user":{"id":"u1","email":"marco@alimax.at"},
        "workspace":{"id":"ws-9","name":"Team HAVI","type":"team"}}}
        """.trimIndent().replace("\n", "")

    private val pendingJson = """{"data":{"status":"pending","token_returned":false}}"""

    private val base = URI("https://havi.example.test")

    private fun config(baseUrl: URI? = base) =
        HaviConfig(
            isEnabled = true,
            baseUrl = baseUrl,
            workspaceId = null,
            project = null,
            worktree = null,
            branch = null,
            commit = null,
            imageFormat = HaviImageFormat.PNG,
            devToken = null,
        )

    private fun link(expiresAtSeconds: Long = 1_000_000) =
        HaviSetupLink(
            deviceCode = "dev-1",
            approveUrl = URI("https://havi.example.test/?setup_code=dev-1"),
            expiresAt = Instant.ofEpochSecond(expiresAtSeconds),
        )

    @Test
    fun pendingThenApprovedPersistsSession() {
        val transport = StubTransport().enqueue(202, pendingJson).enqueue(201, approvedJson)
        val store = HaviTokenStore()
        val service =
            HaviConnectService(config(), store, transport, now = { Instant.ofEpochSecond(0) }, sleep = {})

        val result = service.runExchange(link(), intervalMillis = 0) { false }

        val connected = assertInstanceOf(HaviConnectResult.Connected::class.java, result)
        assertEquals("tok-abc", connected.session.accessToken)
        assertEquals("ws-9", connected.session.workspaceId)
        assertEquals("marco@alimax.at", connected.session.userName)
        assertEquals("Team HAVI", connected.session.workspaceName)
        assertNull(connected.session.refreshToken)

        assertEquals("tok-abc", store.accessToken)
        assertEquals("ws-9", store.workspaceId)
        assertEquals("marco@alimax.at", store.userName)
        assertEquals("Team HAVI", store.workspaceName)
        assertEquals(2, transport.consumedCount)
    }

    @Test
    fun pendingThenExpiredViaTtl() {
        val transport = StubTransport().enqueue(202, pendingJson).enqueue(202, pendingJson)
        val clock = AtomicLong(0)
        val store = HaviTokenStore()
        val service =
            HaviConnectService(
                config(),
                store,
                transport,
                now = { Instant.ofEpochSecond(clock.get()) },
                sleep = { clock.addAndGet(100) },
            )

        val result = service.runExchange(link(expiresAtSeconds = 50), intervalMillis = 0) { false }

        assertEquals(HaviConnectResult.Expired, result)
        assertEquals(1, transport.consumedCount)
        assertNull(store.accessToken)
    }

    @Test
    fun serverGoneCodeYieldsExpired() {
        val transport = StubTransport().enqueue(410, """{"error":{"code":"setup_code_expired"}}""")
        val store = HaviTokenStore()
        val service =
            HaviConnectService(config(), store, transport, now = { Instant.ofEpochSecond(0) }, sleep = {})

        assertEquals(HaviConnectResult.Expired, service.runExchange(link(), intervalMillis = 0) { false })
    }

    @Test
    fun cancelStopsPolling() {
        val transport = StubTransport().enqueue(202, pendingJson).enqueue(202, pendingJson)
        val cancelled = AtomicBoolean(false)
        val store = HaviTokenStore()
        val service =
            HaviConnectService(
                config(),
                store,
                transport,
                now = { Instant.ofEpochSecond(0) },
                sleep = { cancelled.set(true) },
            )

        val result = service.runExchange(link(), intervalMillis = 0) { cancelled.get() }

        assertEquals(HaviConnectResult.Cancelled, result)
        assertEquals(1, transport.consumedCount)
        assertNull(store.accessToken)
    }

    // MARK: - Pure classify / parse seams

    @Test
    fun classifyExchange() {
        assertEquals(HaviExchangeStep.Pending, HaviConnectService.classifyExchange(202, bytes("{}")))
        val approved = HaviConnectService.classifyExchange(201, bytes(approvedJson))
        assertEquals("tok-abc", (approved as HaviExchangeStep.Approved).session.accessToken)
        assertEquals(HaviExchangeStep.Gone, HaviConnectService.classifyExchange(410, bytes("""{"error":{"code":"setup_code_expired"}}""")))
        assertEquals(HaviExchangeStep.Gone, HaviConnectService.classifyExchange(409, bytes("""{"error":{"code":"setup_code_used"}}""")))
        assertEquals(HaviExchangeStep.Gone, HaviConnectService.classifyExchange(410, bytes("""{"error":{"code":"setup_code_revoked"}}""")))
        assertEquals(HaviExchangeStep.Transient, HaviConnectService.classifyExchange(500, bytes("boom")))
        assertEquals(HaviExchangeStep.Transient, HaviConnectService.classifyExchange(400, bytes("""{"error":{"code":"whatever"}}""")))
    }

    @Test
    fun parseSetupLinkResolvesRelativeApproveUrl() {
        val json =
            """{"data":{"device_code":"abc","status":"pending","client_type":"mobile",""" +
                """"approve_url":"/?setup_code=abc","expires_at":"2026-10-19T10:30:00Z"}}"""
        val parsed = HaviConnectService.parseSetupLink(bytes(json), base, Instant.ofEpochSecond(0))
        assertEquals("abc", parsed?.deviceCode)
        assertEquals("https://havi.example.test/?setup_code=abc", parsed?.approveUrl.toString())
    }

    @Test
    fun parseSetupLinkFallsBackToTtlWhenNoExpiry() {
        val json = """{"data":{"device_code":"abc","approve_url":"/?setup_code=abc"}}"""
        val parsed = HaviConnectService.parseSetupLink(bytes(json), URI("https://x.test"), Instant.ofEpochSecond(0))
        assertEquals(Instant.ofEpochSecond(HaviConnectService.LINK_TTL_SECONDS), parsed?.expiresAt)
    }

    @Test
    fun parseSessionHardCodesRefreshTokenNull() {
        val json =
            """{"data":{"token":"t","refresh_token":"should-be-ignored","workspace":{"id":"w"}}}"""
        val session = HaviConnectService.parseSession(bytes(json))
        assertEquals("t", session?.accessToken)
        assertEquals("w", session?.workspaceId)
        assertNull(session?.refreshToken)
    }

    @Test
    fun parseSessionRejectsMissingTokenOrWorkspace() {
        assertNull(HaviConnectService.parseSession(bytes("""{"data":{"workspace":{"id":"w"}}}""")))
        assertNull(HaviConnectService.parseSession(bytes("""{"data":{"token":"t"}}""")))
        assertNull(HaviConnectService.parseSession(bytes("""{"data":{"token":"","workspace":{"id":"w"}}}""")))
        assertNull(HaviConnectService.parseSession(bytes("""{"data":{"token":"t","workspace":{"id":""}}}""")))
    }

    // MARK: - Approve-URL same-origin guard (security-load-bearing)

    @Test
    fun resolveApproveUrlIsTrailingSlashInvariant() {
        val path = "/connect/approve?setup_code=abc123"
        val expected = "https://havi.handgemacht.ai/connect/approve?setup_code=abc123"
        assertEquals(expected, HaviConnectService.resolveApproveUrl(path, URI("https://havi.handgemacht.ai")).toString())
        assertEquals(expected, HaviConnectService.resolveApproveUrl(path, URI("https://havi.handgemacht.ai/")).toString())
    }

    @Test
    fun resolveApproveUrlReplacesBasePath() {
        assertEquals(
            "https://havi.handgemacht.ai/connect/approve?setup_code=z9",
            HaviConnectService.resolveApproveUrl(
                "/connect/approve?setup_code=z9",
                URI("https://havi.handgemacht.ai/app/"),
            ).toString(),
        )
    }

    @Test
    fun resolveApproveUrlAllowsSameHostAbsoluteRejectsCrossHost() {
        val sameHost = "https://havi.handgemacht.ai/connect/approve?setup_code=xyz"
        assertEquals(sameHost, HaviConnectService.resolveApproveUrl(sameHost, URI("https://havi.handgemacht.ai")).toString())
        assertNull(
            HaviConnectService.resolveApproveUrl(
                "https://evil.example/connect/approve?setup_code=xyz",
                URI("https://havi.handgemacht.ai"),
            ),
        )
    }

    @Test
    fun resolveApproveUrlRejectsProtocolRelativeCrossHost() {
        assertNull(
            HaviConnectService.resolveApproveUrl(
                "//evil.example/connect/approve?setup_code=xyz",
                URI("https://havi.handgemacht.ai"),
            ),
        )
    }

    @Test
    fun resolveApproveUrlRejectsHttpDowngradeOnHttpsBase() {
        assertNull(
            HaviConnectService.resolveApproveUrl(
                "http://havi.handgemacht.ai/connect/approve?setup_code=xyz",
                URI("https://havi.handgemacht.ai"),
            ),
        )
    }

    @Test
    fun resolveApproveUrlRejectsMatchingHostDifferentPort() {
        assertNull(
            HaviConnectService.resolveApproveUrl(
                "https://havi.handgemacht.ai:8443/connect/approve?setup_code=xyz",
                URI("https://havi.handgemacht.ai"),
            ),
        )
    }

    @Test
    fun resolveApproveUrlAllowsHttpLoopbackDevBase() {
        val devBase = URI("http://127.0.0.1:25004")
        assertEquals(
            "http://127.0.0.1:25004/connect/approve?setup_code=abc",
            HaviConnectService.resolveApproveUrl("/connect/approve?setup_code=abc", devBase).toString(),
        )
        assertEquals(
            "http://127.0.0.1:25004/connect/approve?setup_code=abc",
            HaviConnectService.resolveApproveUrl("http://127.0.0.1:25004/connect/approve?setup_code=abc", devBase).toString(),
        )
        assertNull(HaviConnectService.resolveApproveUrl("http://127.0.0.1:25099/connect/approve?setup_code=abc", devBase))
    }

    @Test
    fun createSetupLinkSuccess() {
        val json =
            """{"data":{"device_code":"dev-9","approve_url":"/connect/approve?setup_code=dev-9",""" +
                """"expires_at":"2026-10-19T10:30:00Z"}}"""
        val transport = StubTransport().enqueue(201, json)
        val service = HaviConnectService(config(), HaviTokenStore(), transport, now = { Instant.ofEpochSecond(0) }, sleep = {})

        val result = service.createSetupLink()
        val link = assertInstanceOf(HaviCreateLinkResult.Success::class.java, result).link
        assertEquals("dev-9", link.deviceCode)
        assertEquals("https://havi.example.test/connect/approve?setup_code=dev-9", link.approveUrl.toString())
        assertEquals("POST", transport.requests.single().method)
        assertEquals("https://havi.example.test/api/setup/link", transport.requests.single().url.toString())
    }

    @Test
    fun createSetupLinkMapsExpiredCode() {
        val transport = StubTransport().enqueue(410, """{"error":{"code":"setup_code_expired"}}""")
        val service = HaviConnectService(config(), HaviTokenStore(), transport, now = { Instant.ofEpochSecond(0) }, sleep = {})
        val failure = assertInstanceOf(HaviCreateLinkResult.Failure::class.java, service.createSetupLink())
        assertEquals("That link expired — get a new one.", failure.failure.userMessage)
    }

    @Test
    fun createSetupLinkTransportFailureIsFriendly() {
        val transport = StubTransport().enqueueFailure()
        val service = HaviConnectService(config(), HaviTokenStore(), transport, now = { Instant.ofEpochSecond(0) }, sleep = {})
        val failure = assertInstanceOf(HaviCreateLinkResult.Failure::class.java, service.createSetupLink())
        assertEquals("No connection to HAVI — try again.", failure.failure.userMessage)
    }

    @Test
    fun parseDateWithAndWithoutFractionalSeconds() {
        assertEquals(Instant.parse("2026-10-19T10:30:00Z"), HaviConnectService.parseDate("2026-10-19T10:30:00Z"))
        assertEquals(Instant.parse("2026-10-19T10:30:00.123Z"), HaviConnectService.parseDate("2026-10-19T10:30:00.123Z"))
        assertNull(HaviConnectService.parseDate("not-a-date"))
    }

    private fun bytes(json: String): ByteArray = json.toByteArray(Charsets.UTF_8)
}
