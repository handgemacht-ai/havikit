package ai.handgemacht.havikit

import java.time.Instant
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock

/**
 * The connected HAVI identity resolved by the device-code flow (wire spec §4.3,
 * §11): the bearer credential plus the display names the connect sheet shows.
 * `refreshToken` is always null in practice — the exchange parser hard-codes null
 * and there is no refresh flow anywhere in the SDK.
 */
public data class HaviConnectedSession(
    val accessToken: String,
    val workspaceId: String,
    val refreshToken: String? = null,
    val expiresAt: Instant? = null,
    val userName: String? = null,
    val workspaceName: String? = null,
)

/**
 * Backing for the token store's string items. Production (Android) resolves an
 * EncryptedSharedPreferences / Keystore backing under a distinct namespace,
 * analogous to iOS's dedicated `ai.handgemacht.havikit` Keychain service; the core
 * ships an in-memory backing so the credential lifecycle is unit-tested without a
 * device.
 */
public interface HaviCredentialBacking {
    public fun read(account: String): String?

    public fun write(
        account: String,
        value: String,
    )

    public fun delete(account: String)
}

/**
 * HaviKit's own credential store, kept separate from the host app's store so the
 * dogfood identity never mixes with the child's account (wire spec §11). The
 * stamped `devToken` is a fallback source only and is never written here.
 * Manual-paste and device-code credentials, when present, override the stamped
 * token. `hasCredential` = access token AND workspace id both present.
 */
public class HaviTokenStore(
    private val backing: HaviCredentialBacking = InMemoryCredentialBacking(),
) {
    private object Key {
        const val ACCESS_TOKEN = "havi.access_token"
        const val WORKSPACE_ID = "havi.workspace_id"
        const val REFRESH_TOKEN = "havi.refresh_token"
        const val EXPIRES_AT = "havi.expires_at"
        const val USER_NAME = "havi.user_name"
        const val WORKSPACE_NAME = "havi.workspace_name"
    }

    public val accessToken: String? get() = backing.read(Key.ACCESS_TOKEN)
    public val workspaceId: String? get() = backing.read(Key.WORKSPACE_ID)
    public val refreshToken: String? get() = backing.read(Key.REFRESH_TOKEN)
    public val userName: String? get() = backing.read(Key.USER_NAME)
    public val workspaceName: String? get() = backing.read(Key.WORKSPACE_NAME)

    /** Stored as unix epoch seconds (wire spec §11); informational only. */
    public val expiresAt: Instant?
        get() = backing.read(Key.EXPIRES_AT)?.toDoubleOrNull()?.let { Instant.ofEpochMilli((it * 1000).toLong()) }

    public val hasCredential: Boolean get() = accessToken != null && workspaceId != null

    /** The stored identity reassembled for the connect sheet's "Connected as …" row. */
    public val connectedSession: HaviConnectedSession?
        get() {
            val token = accessToken ?: return null
            val workspace = workspaceId ?: return null
            return HaviConnectedSession(
                accessToken = token,
                workspaceId = workspace,
                refreshToken = refreshToken,
                expiresAt = expiresAt,
                userName = userName,
                workspaceName = workspaceName,
            )
        }

    /** Manual-paste dev fallback: a bearer token + workspace id, clearing the rest. */
    public fun signIn(
        token: String,
        workspaceId: String,
    ) {
        backing.write(Key.ACCESS_TOKEN, token)
        backing.write(Key.WORKSPACE_ID, workspaceId)
        backing.delete(Key.REFRESH_TOKEN)
        backing.delete(Key.EXPIRES_AT)
        backing.delete(Key.USER_NAME)
        backing.delete(Key.WORKSPACE_NAME)
    }

    /** Device-code result: the full session, writing present fields and deleting absent ones. */
    public fun store(session: HaviConnectedSession) {
        backing.write(Key.ACCESS_TOKEN, session.accessToken)
        backing.write(Key.WORKSPACE_ID, session.workspaceId)
        writeOrDelete(Key.REFRESH_TOKEN, session.refreshToken)
        writeOrDelete(Key.EXPIRES_AT, session.expiresAt?.let { epochSecondsString(it) })
        writeOrDelete(Key.USER_NAME, session.userName)
        writeOrDelete(Key.WORKSPACE_NAME, session.workspaceName)
    }

    public fun clear() {
        backing.delete(Key.ACCESS_TOKEN)
        backing.delete(Key.WORKSPACE_ID)
        backing.delete(Key.REFRESH_TOKEN)
        backing.delete(Key.EXPIRES_AT)
        backing.delete(Key.USER_NAME)
        backing.delete(Key.WORKSPACE_NAME)
    }

    private fun writeOrDelete(
        account: String,
        value: String?,
    ) {
        if (value != null) backing.write(account, value) else backing.delete(account)
    }

    private fun epochSecondsString(instant: Instant): String {
        val seconds = instant.toEpochMilli() / 1000.0
        return if (seconds == seconds.toLong().toDouble()) seconds.toLong().toString() else seconds.toString()
    }
}

/** Lock-guarded in-memory backing (the core default and the tests' backing). */
public class InMemoryCredentialBacking : HaviCredentialBacking {
    private val lock = ReentrantLock()
    private val storage = HashMap<String, String>()

    override fun read(account: String): String? = lock.withLock { storage[account] }

    override fun write(
        account: String,
        value: String,
    ): Unit = lock.withLock { storage[account] = value }

    override fun delete(account: String): Unit = lock.withLock { storage.remove(account) }
}
