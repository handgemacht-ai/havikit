package ai.handgemacht.havikit

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** Secret KEY-name scrub (wire spec §6.6): the denylist and deep, empty-pruning recursion. */
class HaviRedactionTest {
    @Test
    fun denylistMatchesAreSubstringAndCaseInsensitive() {
        assertTrue(HaviRedaction.isSecretKey("cookies")) // substring of "cookie"
        assertTrue(HaviRedaction.isSecretKey("authToken"))
        assertTrue(HaviRedaction.isSecretKey("secretKey"))
        assertTrue(HaviRedaction.isSecretKey("api_key"))
        assertTrue(HaviRedaction.isSecretKey("api-key"))
        assertTrue(HaviRedaction.isSecretKey("apikey"))
        assertTrue(HaviRedaction.isSecretKey("AUTHORIZATION"))
        assertTrue(HaviRedaction.isSecretKey("password"))
        assertFalse(HaviRedaction.isSecretKey("userId"))
        assertFalse(HaviRedaction.isSecretKey("note"))
    }

    @Test
    fun scrubDropsSecretKeysAtAnyDepth() {
        val input =
            mapOf(
                "session" to mapOf("userId" to "u-42", "authToken" to "x", "note" to "n"),
                "cookies" to mapOf("sid" to "abc"),
            )
        val scrubbed = HaviRedaction.scrub(input)
        assertEquals(
            mapOf("session" to mapOf("userId" to "u-42", "note" to "n")),
            scrubbed,
        )
    }

    @Test
    fun scrubRecursesArraysAndPassesScalars() {
        val input = mapOf("list" to listOf(mapOf("token" to "t", "keep" to "k"), "scalar"))
        assertEquals(mapOf("list" to listOf(mapOf("keep" to "k"), "scalar")), HaviRedaction.scrub(input))
    }
}
