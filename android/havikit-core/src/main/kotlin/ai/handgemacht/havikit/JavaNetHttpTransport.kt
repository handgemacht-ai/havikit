package ai.handgemacht.havikit

import java.net.http.HttpClient
import java.net.http.HttpRequest
import java.net.http.HttpResponse
import java.time.Duration

/**
 * Default [HaviHttpTransport] over the JDK's `java.net.http.HttpClient`. Ephemeral
 * by construction (no shared cookie/cache state for API calls, wire spec §1). The
 * uploader/connect service use a 30 s request timeout; the label service a 15 s
 * one (wire spec §1). Works unchanged on Android (API 26+ ships java.net.http via
 * desugaring or platform), but the Android module may swap in its own client.
 */
public class JavaNetHttpTransport(
    private val requestTimeout: Duration = Duration.ofSeconds(30),
    private val client: HttpClient =
        HttpClient.newBuilder()
            .connectTimeout(Duration.ofSeconds(30))
            .followRedirects(HttpClient.Redirect.NEVER)
            .build(),
) : HaviHttpTransport {
    override fun execute(request: HaviHttpRequest): HaviHttpResponse {
        val bodyPublisher =
            request.body
                ?.let { HttpRequest.BodyPublishers.ofByteArray(it) }
                ?: HttpRequest.BodyPublishers.noBody()

        val builder =
            HttpRequest.newBuilder()
                .uri(request.url)
                .timeout(requestTimeout)
                .method(request.method, bodyPublisher)

        for ((name, value) in request.headers) {
            builder.header(name, value)
        }

        return try {
            val response = client.send(builder.build(), HttpResponse.BodyHandlers.ofByteArray())
            HaviHttpResponse(statusCode = response.statusCode(), body = response.body())
        } catch (e: Exception) {
            throw HaviTransportException("HAVI request to ${request.url} failed: ${e.message}", e)
        }
    }
}
