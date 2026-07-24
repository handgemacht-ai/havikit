package ai.handgemacht.havikit

import android.content.SharedPreferences

/**
 * A real in-memory [SharedPreferences] for the plain-JVM unit test path. The mockable
 * `android.jar` only supplies the interface (every method returns a default), so the
 * migration is exercised against this implementation instead of a device: it records
 * commits and can be told to fail one, which is the branch that decides whether the
 * plaintext file may be deleted.
 */
internal class FakeSharedPreferences(
    seed: Map<String, Any> = emptyMap(),
) : SharedPreferences {
    val values = LinkedHashMap<String, Any?>(seed)

    var commitSucceeds = true
    var commits = 0
        private set

    override fun getAll(): MutableMap<String, *> = values

    override fun getString(
        key: String?,
        defValue: String?,
    ): String? = values[key] as? String ?: defValue

    override fun getStringSet(
        key: String?,
        defValues: MutableSet<String>?,
    ): MutableSet<String>? = defValues

    override fun getInt(
        key: String?,
        defValue: Int,
    ): Int = defValue

    override fun getLong(
        key: String?,
        defValue: Long,
    ): Long = defValue

    override fun getFloat(
        key: String?,
        defValue: Float,
    ): Float = defValue

    override fun getBoolean(
        key: String?,
        defValue: Boolean,
    ): Boolean = defValue

    override fun contains(key: String?): Boolean = values.containsKey(key)

    override fun edit(): SharedPreferences.Editor = Editor(this)

    override fun registerOnSharedPreferenceChangeListener(listener: SharedPreferences.OnSharedPreferenceChangeListener?) = Unit

    override fun unregisterOnSharedPreferenceChangeListener(listener: SharedPreferences.OnSharedPreferenceChangeListener?) = Unit

    private class Editor(
        private val prefs: FakeSharedPreferences,
    ) : SharedPreferences.Editor {
        private val pending = LinkedHashMap<String, Any?>()
        private val removed = LinkedHashSet<String>()
        private var cleared = false

        override fun putString(
            key: String,
            value: String?,
        ): SharedPreferences.Editor = put(key, value)

        override fun putStringSet(
            key: String,
            values: MutableSet<String>?,
        ): SharedPreferences.Editor = put(key, values)

        override fun putInt(
            key: String,
            value: Int,
        ): SharedPreferences.Editor = put(key, value)

        override fun putLong(
            key: String,
            value: Long,
        ): SharedPreferences.Editor = put(key, value)

        override fun putFloat(
            key: String,
            value: Float,
        ): SharedPreferences.Editor = put(key, value)

        override fun putBoolean(
            key: String,
            value: Boolean,
        ): SharedPreferences.Editor = put(key, value)

        override fun remove(key: String): SharedPreferences.Editor {
            removed += key
            return this
        }

        override fun clear(): SharedPreferences.Editor {
            cleared = true
            return this
        }

        override fun commit(): Boolean {
            prefs.commits++
            if (!prefs.commitSucceeds) return false
            if (cleared) prefs.values.clear()
            for (key in removed) prefs.values.remove(key)
            prefs.values.putAll(pending)
            return true
        }

        override fun apply() {
            commit()
        }

        private fun put(
            key: String,
            value: Any?,
        ): SharedPreferences.Editor {
            pending[key] = value
            return this
        }
    }
}
