package ai.handgemacht.havikit

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * Breadcrumb ring bounds (wire spec §6, A6): capacity by count, plus the two byte
 * caps that keep a runaway `Havi.log` from ballooning memory and the next upload —
 * per-message truncation and the whole-ring budget. Constants mirror iOS.
 */
class HaviLogBufferTest {
    private fun entry(message: String) = HaviLogEntry(HaviLogLevel.INFO, "app", message)

    private fun utf8(message: String) = message.toByteArray(Charsets.UTF_8).size

    @Test
    fun keepsTheNewestEntriesUpToCapacity() {
        val buffer = HaviLogBuffer(capacity = 3)
        repeat(5) { buffer.append(entry("m$it")) }
        assertEquals(listOf("m2", "m3", "m4"), buffer.snapshot().map { it.message })
    }

    @Test
    fun shortMessagesAreUntouched() {
        val buffer = HaviLogBuffer()
        buffer.append(entry("card start ref=Haus"))
        assertEquals("card start ref=Haus", buffer.snapshot().single().message)
    }

    @Test
    fun oversizedMessageIsTruncatedWithAMarkerAndFitsTheEntryCap() {
        val buffer = HaviLogBuffer()
        buffer.append(entry("x".repeat(HaviLogBuffer.MAX_ENTRY_BYTES * 3)))

        val stored = buffer.snapshot().single().message
        assertTrue(stored.endsWith(HaviLogBuffer.TRUNCATION_MARKER))
        assertEquals(HaviLogBuffer.MAX_ENTRY_BYTES, utf8(stored))
        assertTrue(stored.startsWith("xxx"))
    }

    /** The cut lands on a character boundary, never inside a multi-byte scalar. */
    @Test
    fun truncationNeverSplitsAMultiByteCharacter() {
        val message = "ä".repeat(HaviLogBuffer.MAX_ENTRY_BYTES) // 2 bytes each

        val truncated = HaviLogBuffer.truncate(message)

        assertTrue(utf8(truncated) <= HaviLogBuffer.MAX_ENTRY_BYTES)
        assertTrue(truncated.endsWith(HaviLogBuffer.TRUNCATION_MARKER))
        val body = truncated.removeSuffix(HaviLogBuffer.TRUNCATION_MARKER)
        assertEquals(body.length, body.count { it == 'ä' }, "no replacement character from a split scalar")
        // Round-tripping through UTF-8 is lossless, which a split scalar would break.
        assertEquals(truncated, String(truncated.toByteArray(Charsets.UTF_8), Charsets.UTF_8))
    }

    @Test
    fun emojiAtTheCutSurviveIntact() {
        val truncated = HaviLogBuffer.truncate("🙂".repeat(HaviLogBuffer.MAX_ENTRY_BYTES))
        val body = truncated.removeSuffix(HaviLogBuffer.TRUNCATION_MARKER)

        assertTrue(utf8(truncated) <= HaviLogBuffer.MAX_ENTRY_BYTES)
        assertEquals(0, utf8(body) % 4, "the cut fell on a whole 4-byte scalar")
        assertTrue(!body.contains('�'), "no replacement character from a split scalar")
    }

    /** Well under the count cap, the byte budget is what evicts. */
    @Test
    fun totalByteBudgetEvictsOldestFirst() {
        val buffer = HaviLogBuffer()
        val chunk = "y".repeat(HaviLogBuffer.MAX_ENTRY_BYTES)
        val fitting = HaviLogBuffer.MAX_TOTAL_BYTES / HaviLogBuffer.MAX_ENTRY_BYTES

        repeat(fitting) { buffer.append(entry(chunk)) }
        assertEquals(fitting, buffer.snapshot().size)

        buffer.append(entry("newest"))
        val retained = buffer.snapshot()

        assertEquals(fitting, retained.size, "the oldest chunk made room for the newest entry")
        assertEquals("newest", retained.last().message)
        assertTrue(retained.sumOf { utf8(it.message) } <= HaviLogBuffer.MAX_TOTAL_BYTES)
    }

    @Test
    fun clearResetsTheByteBudgetToo() {
        val buffer = HaviLogBuffer()
        repeat(40) { buffer.append(entry("z".repeat(HaviLogBuffer.MAX_ENTRY_BYTES))) }
        buffer.clear()

        repeat(3) { buffer.append(entry("after")) }
        assertEquals(3, buffer.snapshot().size)
    }

    @Test
    fun bytesCapsMatchTheDocumentedConstants() {
        assertEquals(4 * 1024, HaviLogBuffer.MAX_ENTRY_BYTES)
        assertEquals(256 * 1024, HaviLogBuffer.MAX_TOTAL_BYTES)
        assertEquals(200, HaviLogBuffer.DEFAULT_CAPACITY)
    }
}
