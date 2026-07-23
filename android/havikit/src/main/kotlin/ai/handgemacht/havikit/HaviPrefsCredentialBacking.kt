package ai.handgemacht.havikit

import android.content.Context

/**
 * The Android [HaviCredentialBacking], persisting HaviKit's own credential in a
 * dedicated `SharedPreferences` file named after the iOS Keychain service
 * (`ai.handgemacht.havikit`), kept separate from the host app's own storage (wire
 * spec §11). This is a dogfood/dev credential; a production hardening step is to
 * swap the file for an `EncryptedSharedPreferences` backing with the same account
 * keys — nothing else changes, because the store is written through this seam.
 */
internal class HaviPrefsCredentialBacking(
    context: Context,
) : HaviCredentialBacking {
    private val prefs = context.applicationContext.getSharedPreferences(STORE_NAME, Context.MODE_PRIVATE)

    override fun read(account: String): String? = prefs.getString(account, null)

    override fun write(
        account: String,
        value: String,
    ) {
        prefs.edit().putString(account, value).apply()
    }

    override fun delete(account: String) {
        prefs.edit().remove(account).apply()
    }

    private companion object {
        const val STORE_NAME = "ai.handgemacht.havikit"
    }
}
