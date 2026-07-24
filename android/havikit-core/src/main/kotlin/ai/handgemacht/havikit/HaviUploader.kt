package ai.handgemacht.havikit

/**
 * Owns the annotation send path (wire spec §5, §7). Best-effort foreground
 * delivery — no on-disk outbox: one send attempt, one in-memory retry on a
 * transient failure, then the outcome is surfaced to the capture sheet.
 * Server-driven re-encode fallbacks (`unsupported_media_type` -> PNG,
 * `payload_too_large` -> 1024 px) run transparently once each.
 *
 * Synchronous and blocking: the Android module calls [submit] on a background
 * dispatcher. The transport and the retry sleep are injected so the loop is
 * unit-tested with a stub transport and no wall-clock delay.
 *
 * [tokenStore], when supplied, is cleared the moment the server rejects the
 * credential: the reconnect prompt can be dismissed, and a revoked token left in
 * storage would 401 every later capture forever.
 */
public class HaviUploader(
    private val config: HaviConfig,
    private val transport: HaviHttpTransport,
    private val tokenStore: HaviTokenStore? = null,
    private val retryDelayMillis: Long = 1_500L,
    private val sleep: (Long) -> Unit = { millis -> Thread.sleep(millis) },
) {
    public fun submit(pending: PendingAnnotation): HaviSubmitResult {
        val baseUrl = config.baseUrl
            ?: return reconnectFailure()
        val token = pending.bearerToken?.takeIf { it.isNotEmpty() }
            ?: return reconnectFailure()
        val workspace = pending.workspaceId?.takeIf { it.isNotEmpty() }
            ?: return reconnectFailure()

        var format = pending.imageFormat
        var imageData = pending.imageData
        var didRetryTransient = false
        var didFallBackToPng = false
        var didReencodeSmaller = false

        while (true) {
            val classification =
                sendOnce(
                    baseUrl = baseUrl,
                    token = token,
                    workspace = workspace,
                    annotationJson = pending.annotationJson,
                    imageData = imageData,
                    format = format,
                    siblings = pending.siblings,
                    idempotencyKey = pending.idempotencyKey,
                )

            when (classification) {
                is HaviResponseClassification.Success ->
                    return HaviSubmitResult.Success(id = classification.id)

                is HaviResponseClassification.Mapped -> {
                    val mapped = classification.error
                    when (mapped.action) {
                        HaviErrorAction.REENCODE_PNG -> {
                            val reencoded =
                                if (!didFallBackToPng && format == HaviImageFormat.JPEG) {
                                    pending.reencoder?.reencode(HaviImageFormat.PNG, HaviImagePlan.DEFAULT_MAX_LONGEST_SIDE)
                                } else {
                                    null
                                }
                            if (reencoded != null) {
                                didFallBackToPng = true
                                format = HaviImageFormat.PNG
                                imageData = reencoded
                                continue
                            }
                            return terminalFailure(mapped)
                        }

                        HaviErrorAction.REENCODE_SMALLER -> {
                            val reencoded =
                                if (!didReencodeSmaller) {
                                    pending.reencoder?.reencode(format, HaviImagePlan.PAYLOAD_TOO_LARGE_LONGEST_SIDE)
                                } else {
                                    null
                                }
                            if (reencoded != null) {
                                didReencodeSmaller = true
                                imageData = reencoded
                                continue
                            }
                            return terminalFailure(mapped)
                        }

                        HaviErrorAction.TRANSIENT_RETRY -> {
                            if (!didRetryTransient) {
                                didRetryTransient = true
                                sleep(retryDelayMillis)
                                continue
                            }
                            return HaviSubmitResult.Failure(
                                HaviSubmitFailure(mapped.userMessage, HaviSubmitFailureKind.RETRY, mapped.code),
                            )
                        }

                        HaviErrorAction.REAUTH -> {
                            tokenStore?.clear()
                            return HaviSubmitResult.Failure(
                                HaviSubmitFailure(mapped.userMessage, HaviSubmitFailureKind.RECONNECT, mapped.code),
                            )
                        }

                        HaviErrorAction.TERMINAL ->
                            return terminalFailure(mapped)
                    }
                }
            }
        }
    }

    private fun sendOnce(
        baseUrl: java.net.URI,
        token: String,
        workspace: String,
        annotationJson: String,
        imageData: ByteArray?,
        format: HaviImageFormat,
        siblings: Map<String, String>,
        idempotencyKey: String,
    ): HaviResponseClassification {
        val boundary = HaviMultipart.boundary()
        val request =
            HaviHttpRequest(
                method = "POST",
                url = HaviUrls.endpoint(baseUrl, "api/annotations"),
                headers =
                    mapOf(
                        "Content-Type" to "multipart/form-data; boundary=$boundary",
                        "Authorization" to "Bearer $token",
                        "x-havi-workspace-id" to workspace,
                        "Idempotency-Key" to idempotencyKey,
                    ),
                body =
                    HaviMultipart.body(
                        boundary = boundary,
                        annotationJson = annotationJson,
                        imageData = imageData,
                        imageFilename = format.multipartFilename,
                        imageContentType = format.multipartContentType,
                        siblings = siblings,
                    ),
            )

        return try {
            val response = transport.execute(request)
            HaviErrorMapping.classify(status = response.statusCode, body = response.body)
        } catch (_: HaviTransportException) {
            HaviResponseClassification.Mapped(HaviErrorMapping.transientTransport)
        }
    }

    private fun reconnectFailure(): HaviSubmitResult =
        HaviSubmitResult.Failure(
            HaviSubmitFailure("HAVI workspace not set up — reconnect.", HaviSubmitFailureKind.RECONNECT, null),
        )

    private fun terminalFailure(mapped: HaviMappedError): HaviSubmitResult =
        HaviSubmitResult.Failure(
            HaviSubmitFailure(mapped.userMessage, HaviSubmitFailureKind.TERMINAL, mapped.code),
        )
}
