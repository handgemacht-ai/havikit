package ai.handgemacht.havikit

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * The one-way move from the pre-encryption plaintext file into the
 * `EncryptedSharedPreferences` file. Getting this wrong is either a silent
 * re-pair (entries dropped), a resurrected stale token (entries overwriting newer
 * encrypted ones), or a cleartext token left on disk (deleted before the write
 * committed) — so each of those is pinned here.
 */
class HaviCredentialMigrationTest {
    private val accessToken = "havi.access_token"
    private val workspaceId = "havi.workspace_id"

    @Test
    fun `moves every plaintext credential into the encrypted store`() {
        val plaintext = FakeSharedPreferences(mapOf(accessToken to "token-1", workspaceId to "ws-1"))
        val secure = FakeSharedPreferences()

        assertTrue(HaviCredentialMigration.move(plaintext, secure))

        assertEquals("token-1", secure.getString(accessToken, null))
        assertEquals("ws-1", secure.getString(workspaceId, null))
    }

    @Test
    fun `never overwrites a credential the encrypted store already holds`() {
        val plaintext = FakeSharedPreferences(mapOf(accessToken to "stale", workspaceId to "ws-1"))
        val secure = FakeSharedPreferences(mapOf(accessToken to "fresh"))

        assertTrue(HaviCredentialMigration.move(plaintext, secure))

        assertEquals("fresh", secure.getString(accessToken, null))
        assertEquals("ws-1", secure.getString(workspaceId, null))
    }

    @Test
    fun `an empty plaintext file is not a migration`() {
        val plaintext = FakeSharedPreferences()
        val secure = FakeSharedPreferences()

        assertFalse(HaviCredentialMigration.move(plaintext, secure))
        assertEquals(0, secure.commits)
    }

    @Test
    fun `a fresh install with only encrypted credentials is not a migration`() {
        val plaintext = FakeSharedPreferences()
        val secure = FakeSharedPreferences(mapOf(accessToken to "token-1"))

        assertFalse(HaviCredentialMigration.move(plaintext, secure))
        assertEquals("token-1", secure.getString(accessToken, null))
    }

    @Test
    fun `a failed encrypted write keeps the plaintext file for the next attempt`() {
        val plaintext = FakeSharedPreferences(mapOf(accessToken to "token-1"))
        val secure = FakeSharedPreferences().apply { commitSucceeds = false }

        assertFalse(HaviCredentialMigration.move(plaintext, secure))

        assertNull(secure.getString(accessToken, null))
        assertEquals("token-1", plaintext.getString(accessToken, null))
    }

    @Test
    fun `entries that are not credentials are left behind`() {
        val plaintext = FakeSharedPreferences(mapOf("havi.some_flag" to 1))
        val secure = FakeSharedPreferences()

        assertFalse(HaviCredentialMigration.move(plaintext, secure))
        assertEquals(0, secure.commits)
    }
}
