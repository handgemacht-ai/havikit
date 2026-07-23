package ai.handgemacht.havikit

import java.io.ByteArrayOutputStream
import java.net.HttpURLConnection
import java.net.URL

/**
 * The Android [HaviHttpTransport], over `HttpURLConnection` (the core's
 * `JavaNetHttpTransport` uses `java.net.http`, which is not part of the Android
 * platform, so the runtime injects this instead). Ephemeral by construction — a
 * fresh connection per call, no shared cookie/cache state for API calls (wire spec
 * §1) — with the 30 s request timeout the uploader/connect service expect. A
 * failure to reach the server surfaces as [HaviTransportException]; any HTTP
 * response (including 4xx/5xx) returns a [HaviHttpResponse] the callers classify.
 */
internal class HaviAndroidHttpTransport(
    private val connectTimeoutMillis: Int = 30_000,
    private val readTimeoutMillis: Int = 30_000,
) : HaviHttpTransport {
    override fun execute(request: HaviHttpRequest): HaviHttpResponse {
        val connection =
            try {
                (URL(request.url.toString()).openConnection() as HttpURLConnection).apply {
                    requestMethod = request.method
                    connectTimeout = connectTimeoutMillis
                    readTimeout = readTimeoutMillis
                    instanceFollowRedirects = false
                    useCaches = false
                    for ((name, value) in request.headers) setRequestProperty(name, value)
                    request.body?.let { payload ->
                        doOutput = true
                        setFixedLengthStreamingMode(payload.size)
                        outputStream.use { it.write(payload) }
                    }
                }
            } catch (t: Throwable) {
                throw HaviTransportException("HAVI request to ${request.url} failed: ${t.message}", t)
            }

        return try {
            val status = connection.responseCode
            val stream = if (status in 200..399) connection.inputStream else connection.errorStream
            val body = stream?.use { it.readBytesCompat() } ?: ByteArray(0)
            HaviHttpResponse(statusCode = status, body = body)
        } catch (t: Throwable) {
            throw HaviTransportException("HAVI request to ${request.url} failed: ${t.message}", t)
        } finally {
            connection.disconnect()
        }
    }

    private fun java.io.InputStream.readBytesCompat(): ByteArray {
        val out = ByteArrayOutputStream()
        val buffer = ByteArray(8 * 1024)
        while (true) {
            val read = read(buffer)
            if (read < 0) break
            out.write(buffer, 0, read)
        }
        return out.toByteArray()
    }
}
