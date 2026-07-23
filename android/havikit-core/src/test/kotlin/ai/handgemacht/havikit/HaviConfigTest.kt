package ai.handgemacht.havikit

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.net.URI

/** Config resolution (wire spec §14): inert when unconfigured, fail-fast, omit-never-empty. */
class HaviConfigTest {
    @Test
    fun unsetEnabledIsInert() {
        assertEquals(HaviConfig.Inert, HaviConfig.fromMetaData(emptyMap()))
        assertFalse(HaviConfig.fromMetaData(mapOf("HAVI_ENABLED" to "no")).isEnabled)
    }

    @Test
    fun enabledAcceptsYesOrTrueCaseInsensitively() {
        val yes = HaviConfig.fromMetaData(mapOf("HAVI_ENABLED" to "yes", "HAVI_BASE_URL" to "https://havi.test"))
        assertTrue(yes.isEnabled)
        val truthy = HaviConfig.fromMetaData(mapOf("HAVI_ENABLED" to "TRUE", "HAVI_BASE_URL" to "https://havi.test"))
        assertTrue(truthy.isEnabled)
    }

    @Test
    fun enabledButMissingOrInvalidBaseUrlFailsFast() {
        assertThrows(IllegalStateException::class.java) {
            HaviConfig.fromMetaData(mapOf("HAVI_ENABLED" to "YES"))
        }
        assertThrows(IllegalStateException::class.java) {
            HaviConfig.fromMetaData(mapOf("HAVI_ENABLED" to "YES", "HAVI_BASE_URL" to "not a url"))
        }
        // empty string is treated as absent -> still fails fast
        assertThrows(IllegalStateException::class.java) {
            HaviConfig.fromMetaData(mapOf("HAVI_ENABLED" to "YES", "HAVI_BASE_URL" to ""))
        }
    }

    @Test
    fun readsEveryKeyWithOmitNeverEmptyDiscipline() {
        val config =
            HaviConfig.fromMetaData(
                mapOf(
                    "HAVI_ENABLED" to "YES",
                    "HAVI_BASE_URL" to "https://havi.handgemacht.ai",
                    "HAVI_WORKSPACE_ID" to "ws-9",
                    "HAVI_PROJECT" to "lesewerkstatt",
                    "HAVI_WORKTREE" to "",
                    "HAVI_BRANCH" to "main",
                    "HAVI_COMMIT" to "a1b2c3d",
                    "HAVI_DEV_TOKEN" to "tok",
                    "HAVI_IMAGE_FORMAT" to "jpeg",
                ),
            )
        assertTrue(config.isEnabled)
        assertEquals(URI("https://havi.handgemacht.ai"), config.baseUrl)
        assertEquals("ws-9", config.workspaceId)
        assertEquals("lesewerkstatt", config.project)
        assertNull(config.worktree) // empty string -> absent
        assertEquals("main", config.branch)
        assertEquals("a1b2c3d", config.commit)
        assertEquals("tok", config.devToken)
        assertEquals(HaviImageFormat.JPEG, config.imageFormat)
    }

    @Test
    fun imageFormatDefaultsToPngWhenAbsentOrUnknown() {
        val base = mapOf("HAVI_ENABLED" to "YES", "HAVI_BASE_URL" to "https://havi.test")
        assertEquals(HaviImageFormat.PNG, HaviConfig.fromMetaData(base).imageFormat)
        assertEquals(HaviImageFormat.PNG, HaviConfig.fromMetaData(base + ("HAVI_IMAGE_FORMAT" to "webp")).imageFormat)
    }
}
