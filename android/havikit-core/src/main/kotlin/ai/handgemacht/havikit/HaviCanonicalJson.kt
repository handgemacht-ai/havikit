package ai.handgemacht.havikit

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonPrimitive

/**
 * Deterministic JSON serialization used for both the wire body and the byte-exact
 * golden comparison (wire spec §8). Reproduces Foundation
 * `JSONSerialization.data(_:, options: [.sortedKeys])`:
 *  - object keys sorted lexicographically (recursively),
 *  - no pretty-printing / no inserted whitespace,
 *  - standard JSON string escaping (`"` and `\` and control chars only — forward
 *    slashes are NOT escaped and non-ASCII is emitted as literal UTF-8),
 *  - UTF-8 output.
 *
 * The envelope carries no numeric JSON values (coordinates/viewport ride as
 * strings), so there is no float-formatting ambiguity to reconcile.
 *
 * [encode] accepts the builder's own `Map`/`List`/`String` tree as well as a
 * kotlinx [JsonElement], so a hand-authored golden fixture and the builder's
 * output compare byte-for-byte after both pass through here.
 */
public object HaviCanonicalJson {
    /** Canonical UTF-8 string for a builder tree (`Map`/`List`/`String`/…) or a [JsonElement]. */
    public fun encode(value: Any?): String {
        val sb = StringBuilder()
        write(value, sb)
        return sb.toString()
    }

    /** Canonical UTF-8 bytes — the exact `annotation` multipart field payload. */
    public fun encodeToBytes(value: Any?): ByteArray = encode(value).toByteArray(Charsets.UTF_8)

    /** Parse arbitrary JSON text and re-emit it canonically (used to canonicalize fixtures). */
    public fun canonicalize(json: String): String = encode(Json.parseToJsonElement(json))

    private fun write(
        value: Any?,
        sb: StringBuilder,
    ) {
        when (value) {
            null, JsonNull -> sb.append("null")

            is Map<*, *> -> {
                sb.append('{')
                var first = true
                value.entries
                    .map { (it.key as String) to it.value }
                    .sortedBy { it.first }
                    .forEach { (key, nested) ->
                        if (!first) sb.append(',')
                        first = false
                        writeString(key, sb)
                        sb.append(':')
                        write(nested, sb)
                    }
                sb.append('}')
            }

            is List<*> -> {
                sb.append('[')
                value.forEachIndexed { index, element ->
                    if (index > 0) sb.append(',')
                    write(element, sb)
                }
                sb.append(']')
            }

            is JsonPrimitive ->
                if (value.isString) {
                    writeString(value.content, sb)
                } else {
                    sb.append(value.content)
                }

            is String -> writeString(value, sb)
            is Boolean -> sb.append(if (value) "true" else "false")
            is Number -> sb.append(value.toString())

            else -> error("HaviCanonicalJson cannot encode value of type ${value::class}")
        }
    }

    private fun writeString(
        value: String,
        sb: StringBuilder,
    ) {
        sb.append('"')
        for (ch in value) {
            when (ch) {
                '\\' -> sb.append("\\\\")
                '"' -> sb.append("\\\"")
                '\b' -> sb.append("\\b")
                '\u000C' -> sb.append("\\f")
                '\n' -> sb.append("\\n")
                '\r' -> sb.append("\\r")
                '\t' -> sb.append("\\t")
                else ->
                    if (ch < ' ') {
                        sb.append("\\u")
                        sb.append(ch.code.toString(16).padStart(4, '0'))
                    } else {
                        sb.append(ch)
                    }
            }
        }
        sb.append('"')
    }
}
