package ai.handgemacht.havikit

import java.net.URI

/** One HTTP request the SDK issues. Bodies are raw bytes (JSON or multipart). */
public data class HaviHttpRequest(
    val method: String,
    val url: URI,
    val headers: Map<String, String> = emptyMap(),
    val body: ByteArray? = null,
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is HaviHttpRequest) return false
        return method == other.method &&
            url == other.url &&
            headers == other.headers &&
            (body?.contentEquals(other.body) ?: (other.body == null))
    }

    override fun hashCode(): Int {
        var result = method.hashCode()
        result = 31 * result + url.hashCode()
        result = 31 * result + headers.hashCode()
        result = 31 * result + (body?.contentHashCode() ?: 0)
        return result
    }
}

/** A completed HTTP round-trip: the status code and the raw response body. */
public data class HaviHttpResponse(
    val statusCode: Int,
    val body: ByteArray,
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is HaviHttpResponse) return false
        return statusCode == other.statusCode && body.contentEquals(other.body)
    }

    override fun hashCode(): Int = 31 * statusCode + body.contentHashCode()
}

/** A transport-level failure (no HTTP response arrived): connection reset, timeout, DNS, etc. */
public class HaviTransportException(
    message: String,
    cause: Throwable? = null,
) : Exception(message, cause)

/**
 * The single seam between the SDK and the network (wire spec §1). Kept an
 * interface so the pure-JVM core stays testable with an in-memory stub and the
 * Android module can inject a platform client (OkHttp, or the same java.net.http
 * client wrapped on a background dispatcher). [execute] is synchronous and blocks;
 * a successful HTTP round-trip returns a [HaviHttpResponse] for any status code,
 * while a failure to reach the server throws [HaviTransportException].
 */
public fun interface HaviHttpTransport {
    @Throws(HaviTransportException::class)
    public fun execute(request: HaviHttpRequest): HaviHttpResponse
}
