package ai.handgemacht.havikit

import java.io.ByteArrayOutputStream
import java.util.UUID

/**
 * Assembles the `multipart/form-data` body for `POST /api/annotations` (wire spec
 * §5.1), matching the controller exactly: the `annotation` JSON field, then the
 * load-bearing siblings `project` / `worktree` / `branch` (only those the
 * controller reads, only when present), then the `image` file part last. `commit`
 * is deliberately not a sibling — it rides in `x:havi.dev` only. CRLF line endings
 * throughout, UTF-8 text.
 */
public object HaviMultipart {
    public val siblingOrder: List<String> = listOf("project", "worktree", "branch")

    /** `havi.boundary.` + a random UUID string. */
    public fun boundary(): String = "havi.boundary.${UUID.randomUUID()}"

    public fun body(
        boundary: String,
        annotationJson: String,
        imageData: ByteArray?,
        imageFilename: String,
        imageContentType: String,
        siblings: Map<String, String>,
    ): ByteArray {
        val out = ByteArrayOutputStream()

        out.appendField(boundary, "annotation", annotationJson)

        for (key in siblingOrder) {
            siblings[key]?.let { out.appendField(boundary, key, it) }
        }

        if (imageData != null) {
            out.appendString("--$boundary\r\n")
            out.appendString("Content-Disposition: form-data; name=\"image\"; filename=\"$imageFilename\"\r\n")
            out.appendString("Content-Type: $imageContentType\r\n\r\n")
            out.write(imageData)
            out.appendString("\r\n")
        }

        out.appendString("--$boundary--\r\n")
        return out.toByteArray()
    }

    private fun ByteArrayOutputStream.appendString(value: String) = write(value.toByteArray(Charsets.UTF_8))

    private fun ByteArrayOutputStream.appendField(
        boundary: String,
        name: String,
        value: String,
    ) {
        appendString("--$boundary\r\n")
        appendString("Content-Disposition: form-data; name=\"$name\"\r\n\r\n")
        appendString(value)
        appendString("\r\n")
    }
}
