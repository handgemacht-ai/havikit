package ai.handgemacht.havikit

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** Multipart body layout (wire spec §5.1): strict field order, CRLF, image last, commit never a sibling. */
class HaviMultipartTest {
    @Test
    fun boundaryHasHaviPrefix() {
        assertTrue(HaviMultipart.boundary().startsWith("havi.boundary."))
    }

    @Test
    fun bodyOrdersAnnotationSiblingsThenImage() {
        val body =
            HaviMultipart.body(
                boundary = "B",
                annotationJson = """{"type":"Annotation"}""",
                imageData = byteArrayOf(0xAB.toByte(), 0xCD.toByte()),
                imageFilename = "screenshot.png",
                imageContentType = "image/png",
                siblings = mapOf("branch" to "b", "project" to "p", "worktree" to "w", "commit" to "c"),
            ).toString(Charsets.UTF_8)

        val expectedHead =
            "--B\r\n" +
                "Content-Disposition: form-data; name=\"annotation\"\r\n\r\n" +
                "{\"type\":\"Annotation\"}\r\n" +
                "--B\r\n" +
                "Content-Disposition: form-data; name=\"project\"\r\n\r\np\r\n" +
                "--B\r\n" +
                "Content-Disposition: form-data; name=\"worktree\"\r\n\r\nw\r\n" +
                "--B\r\n" +
                "Content-Disposition: form-data; name=\"branch\"\r\n\r\nb\r\n" +
                "--B\r\n" +
                "Content-Disposition: form-data; name=\"image\"; filename=\"screenshot.png\"\r\n" +
                "Content-Type: image/png\r\n\r\n"

        assertTrue(body.startsWith(expectedHead), "unexpected head:\n$body")
        assertTrue(body.endsWith("\r\n--B--\r\n"))
        // commit is never a sibling.
        assertFalse(body.contains("name=\"commit\""))
        // project precedes worktree precedes branch.
        assertTrue(body.indexOf("name=\"project\"") < body.indexOf("name=\"worktree\""))
        assertTrue(body.indexOf("name=\"worktree\"") < body.indexOf("name=\"branch\""))
    }

    @Test
    fun bodyOmitsImageWhenNull() {
        val body =
            HaviMultipart.body(
                boundary = "B",
                annotationJson = "{}",
                imageData = null,
                imageFilename = "screenshot.png",
                imageContentType = "image/png",
                siblings = emptyMap(),
            ).toString(Charsets.UTF_8)
        assertFalse(body.contains("name=\"image\""))
        assertEquals("--B\r\nContent-Disposition: form-data; name=\"annotation\"\r\n\r\n{}\r\n--B--\r\n", body)
    }
}
