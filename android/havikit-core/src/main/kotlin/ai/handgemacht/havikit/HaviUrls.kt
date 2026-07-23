package ai.handgemacht.havikit

import java.net.URI

/**
 * Endpoint-URL construction, mirroring iOS `URL.appendingPathComponent` (wire spec
 * §1): a relative API path is appended to the base with exactly one separating
 * slash, so a base with or without a trailing slash resolves the same result.
 */
public object HaviUrls {
    public fun endpoint(
        base: URI,
        relativePath: String,
    ): URI {
        val basePath = (base.path ?: "").trimEnd('/')
        val rel = relativePath.trimStart('/')
        val newPath = "$basePath/$rel"
        return URI(base.scheme, base.userInfo, base.host, base.port, newPath, null, null)
    }
}
