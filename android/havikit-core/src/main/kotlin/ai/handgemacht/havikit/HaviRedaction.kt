package ai.handgemacht.havikit

/**
 * Redaction policy (wire spec §1). Privacy-first / default-mask: every text input
 * is blacked out in the frozen snapshot unless explicitly revealed. The Android
 * capture layer (later stage) consumes [maskTextFieldsByDefault]; Stage 1 carries
 * it so `HaviConfig` matches the iOS shape.
 */
public data class HaviRedactionPolicy(
    val maskTextFieldsByDefault: Boolean = true,
)

/**
 * The KEY-name secret scrub, byte-identical to the web `enrichment.js`
 * `SECRET_KEY_RE` and the iOS `HaviRedaction` (wire spec §6.6). A key-name
 * denylist — not a value scanner: any object key whose name matches the regex
 * (case-insensitive, unanchored substring) is dropped at any nesting depth.
 * Arrays recurse; scalars pass through. Applied to `x:havi.contexts` and
 * `x:havi.tags` before send.
 */
public object HaviRedaction {
    /** `token|secret|password|api[_-]?key|authorization|cookie`, case-insensitive. */
    public const val SECRET_KEY_PATTERN: String = "token|secret|password|api[_-]?key|authorization|cookie"

    private val secretKeyRegex = Regex(SECRET_KEY_PATTERN, RegexOption.IGNORE_CASE)

    public fun isSecretKey(key: String): Boolean = secretKeyRegex.containsMatchIn(key)

    /**
     * Deep, non-mutating copy with every secret-shaped key dropped at any depth.
     * Objects and arrays recurse; scalars pass through unchanged.
     */
    public fun scrub(value: Any?): Any? =
        when (value) {
            is Map<*, *> -> {
                val out = LinkedHashMap<String, Any?>()
                for ((rawKey, nested) in value) {
                    val key = rawKey as? String ?: continue
                    if (isSecretKey(key)) continue
                    out[key] = scrub(nested)
                }
                out
            }

            is List<*> -> value.map { scrub(it) }

            else -> value
        }
}
