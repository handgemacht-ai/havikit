package ai.handgemacht.havikit

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

/** Canonical JSON (wire spec §8): recursive key sort, minimal whitespace, standard escaping. */
class HaviCanonicalJsonTest {
    @Test
    fun sortsKeysRecursivelyWithNoWhitespace() {
        val tree = mapOf("b" to "2", "a" to mapOf("y" to "1", "x" to "0"))
        assertEquals("""{"a":{"x":"0","y":"1"},"b":"2"}""", HaviCanonicalJson.encode(tree))
    }

    @Test
    fun escapesQuotesBackslashesAndControlCharsButNotSlashOrUnicode() {
        val tree = mapOf("svg" to "<a href=\"x\"/>", "url" to "http://x/y", "log" to "line1\nline2", "dot" to "a · b")
        // forward slashes stay literal; the middle dot stays literal UTF-8; " and \n are escaped.
        assertEquals(
            """{"dot":"a · b","log":"line1\nline2","svg":"<a href=\"x\"/>","url":"http://x/y"}""",
            HaviCanonicalJson.encode(tree),
        )
    }

    @Test
    fun canonicalizeReparsesAndReemits() {
        val messy = """{ "z" : "1" ,  "a": "2" }"""
        assertEquals("""{"a":"2","z":"1"}""", HaviCanonicalJson.canonicalize(messy))
    }

    @Test
    fun builderTreeAndParsedFixtureCanonicalizeIdentically() {
        val built = HaviCanonicalJson.encode(mapOf("type" to "Annotation", "@context" to "x"))
        val parsed = HaviCanonicalJson.canonicalize("""{"@context":"x","type":"Annotation"}""")
        assertEquals(parsed, built)
    }
}
