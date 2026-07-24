// `androidx.security:security-crypto` deprecated EncryptedSharedPreferences and
// MasterKey in 1.1.0 without shipping a replacement: the Jetpack guidance is now
// "use the Android Keystore directly". It is still the only first-party, maintained
// implementation of an encrypted SharedPreferences file, it still receives Tink
// updates, and it stays functional — so HaviKit uses it deliberately and confines
// every deprecated call to this file, which is also the seam a hand-rolled Keystore
// backing would replace.
@file:Suppress("DEPRECATION")

package ai.handgemacht.havikit

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey

/**
 * The Android [HaviCredentialBacking], persisting HaviKit's own credential in a
 * dedicated `EncryptedSharedPreferences` file (keys AES256-SIV, values AES256-GCM
 * under an Android Keystore master key), kept separate from the host app's own
 * storage (wire spec §11) and named after the iOS Keychain service
 * (`ai.handgemacht.havikit`).
 *
 * Two properties matter beyond the encryption itself:
 *
 *  * **Migration.** Builds before this one wrote the same account keys into a
 *    plaintext `MODE_PRIVATE` file. The first access moves those entries into the
 *    encrypted file (never overwriting a newer encrypted value) and deletes the
 *    plaintext file, so an already-connected device stays connected without a
 *    re-pair and leaves no cleartext token behind.
 *  * **Degradation.** A Keystore that cannot produce a master key (wiped/rotated
 *    keys, a corrupt keyset, vendor Keystore bugs) must never take the host app
 *    down for a feedback SDK. The store falls back to the plaintext file and notes
 *    it in the diagnostics buffer, and every individual read/write is guarded the
 *    same way — a failing credential store degrades to "not connected", never to a
 *    crash.
 */
internal class HaviPrefsCredentialBacking(
    context: Context,
) : HaviCredentialBacking {
    private val appContext = context.applicationContext

    private val prefs: SharedPreferences by lazy { openStore() }

    override fun read(account: String): String? = attempt { prefs.getString(account, null) }

    override fun write(
        account: String,
        value: String,
    ) {
        attempt { prefs.edit().putString(account, value).apply() }
    }

    override fun delete(account: String) {
        attempt { prefs.edit().remove(account).apply() }
    }

    private fun openStore(): SharedPreferences {
        val secure = openEncrypted()
        if (secure == null) {
            Havi.log(FALLBACK_MESSAGE, HaviLogLevel.WARNING, "app")
            return plaintextPrefs()
        }
        attempt { migrate(secure) }
        return secure
    }

    private fun openEncrypted(): SharedPreferences? =
        attempt {
            val masterKey =
                MasterKey
                    .Builder(appContext)
                    .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
                    .build()
            EncryptedSharedPreferences.create(
                appContext,
                ENCRYPTED_STORE_NAME,
                masterKey,
                EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
                EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
            )
        }

    private fun migrate(secure: SharedPreferences) {
        val plaintext = plaintextPrefs()
        if (HaviCredentialMigration.move(plaintext, secure)) {
            appContext.deleteSharedPreferences(PLAINTEXT_STORE_NAME)
        }
    }

    private fun plaintextPrefs(): SharedPreferences =
        appContext.getSharedPreferences(PLAINTEXT_STORE_NAME, Context.MODE_PRIVATE)

    private fun <T> attempt(block: () -> T): T? =
        try {
            block()
        } catch (failure: Throwable) {
            null
        }

    private companion object {
        const val PLAINTEXT_STORE_NAME = "ai.handgemacht.havikit"
        const val ENCRYPTED_STORE_NAME = "ai.handgemacht.havikit.secure"

        const val FALLBACK_MESSAGE =
            "HaviKit could not open its encrypted credential store (Android Keystore unavailable) " +
                "and fell back to app-private plaintext storage."
    }
}

/**
 * Moves the plaintext credential entries into the encrypted store. An account that
 * already carries an encrypted value is left alone: after a migration that copied
 * but failed to delete, the encrypted side is the newer one (a reconnect writes
 * there), so re-running must never resurrect a stale token.
 *
 * Returns true only when entries were moved **and** the encrypted write committed —
 * the caller deletes the plaintext file on that signal alone, so a failed commit
 * simply retries on the next launch.
 */
internal object HaviCredentialMigration {
    fun move(
        plaintext: SharedPreferences,
        secure: SharedPreferences,
    ): Boolean {
        val entries = plaintext.all?.filterValues { it is String } ?: return false
        if (entries.isEmpty()) return false

        val editor = secure.edit()
        for ((account, value) in entries) {
            if (secure.getString(account, null) != null) continue
            editor.putString(account, value as String)
        }
        return editor.commit()
    }
}
