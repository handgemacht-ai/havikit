package ai.handgemacht.havikit

/**
 * Fetches the workspace label vocabulary from `GET /api/label-definitions` (wire
 * spec §10), using the same bearer + `x-havi-workspace-id` auth the annotation
 * submit uses. Best-effort and never blocks capture: any failure (no base URL,
 * non-200, transport error, unparseable body) resolves to null, and the details
 * screen falls back to the built-in priority control alone. Synchronous/blocking;
 * the runtime calls [fetch] on a background dispatcher.
 */
internal class HaviLabelService(
    private val config: HaviConfig,
    private val transport: HaviHttpTransport,
) {
    fun fetch(
        token: String,
        workspaceId: String,
    ): List<HaviLabelDefinition>? {
        val baseUrl = config.baseUrl ?: return null
        if (token.isEmpty() || workspaceId.isEmpty()) return null

        val request =
            HaviHttpRequest(
                method = "GET",
                url = HaviUrls.endpoint(baseUrl, "api/label-definitions"),
                headers =
                    mapOf(
                        "Authorization" to "Bearer $token",
                        "x-havi-workspace-id" to workspaceId,
                    ),
            )

        return try {
            val response = transport.execute(request)
            if (response.statusCode != 200) return null
            HaviLabelDefinition.parseList(response.body)
        } catch (_: HaviTransportException) {
            null
        }
    }
}
