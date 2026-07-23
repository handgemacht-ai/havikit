package ai.handgemacht.havikit

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.time.Instant

/** Credential store lifecycle (wire spec §11): two write paths, hasCredential, clear. */
class HaviTokenStoreTest {
    @Test
    fun storeWritesPresentFieldsAndDeletesAbsentOnes() {
        val store = HaviTokenStore()
        store.store(
            HaviConnectedSession(
                accessToken = "tok",
                workspaceId = "ws",
                refreshToken = null,
                expiresAt = Instant.ofEpochSecond(1_700_000_000),
                userName = "marco@alimax.at",
                workspaceName = "Team HAVI",
            ),
        )
        assertEquals("tok", store.accessToken)
        assertEquals("ws", store.workspaceId)
        assertNull(store.refreshToken)
        assertEquals(Instant.ofEpochSecond(1_700_000_000), store.expiresAt)
        assertEquals("marco@alimax.at", store.userName)
        assertEquals("Team HAVI", store.workspaceName)
        assertTrue(store.hasCredential)
        assertEquals("tok", store.connectedSession?.accessToken)
    }

    @Test
    fun signInClearsRefreshExpiryAndNames() {
        val store = HaviTokenStore()
        store.store(
            HaviConnectedSession("old", "wsOld", refreshToken = "r", userName = "u", workspaceName = "n"),
        )
        store.signIn(token = "pasted", workspaceId = "wsNew")
        assertEquals("pasted", store.accessToken)
        assertEquals("wsNew", store.workspaceId)
        assertNull(store.refreshToken)
        assertNull(store.expiresAt)
        assertNull(store.userName)
        assertNull(store.workspaceName)
    }

    @Test
    fun clearWipesEverything() {
        val store = HaviTokenStore()
        store.signIn("t", "w")
        assertTrue(store.hasCredential)
        store.clear()
        assertFalse(store.hasCredential)
        assertNull(store.accessToken)
        assertNull(store.connectedSession)
    }

    @Test
    fun hasCredentialRequiresBothTokenAndWorkspace() {
        val store = HaviTokenStore()
        assertFalse(store.hasCredential)
    }
}
