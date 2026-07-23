package ai.handgemacht.havikit

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull

/**
 * The label kinds the SDK renders (wire spec §10): a `choice` drawn from
 * `allowed_values`, a free-form `value`, or a boolean `flag`. An unrecognized
 * `kind` is dropped at parse time rather than guessed at.
 */
public enum class HaviLabelKind(public val wireValue: String) {
    CHOICE("choice"),
    VALUE("value"),
    FLAG("flag"),
    ;

    public companion object {
        public fun fromWire(raw: String?): HaviLabelKind? = entries.firstOrNull { it.wireValue == raw }
    }
}

/**
 * One workspace label definition from `GET /api/label-definitions` (wire spec
 * §10). The capture sheet renders a control per definition, ordered by
 * [position]; the built-in `priority` definition (`key == "priority"`) maps to the
 * existing segmented control.
 */
public data class HaviLabelDefinition(
    val id: String,
    val key: String,
    val name: String,
    val kind: HaviLabelKind,
    val allowedValues: List<String> = emptyList(),
    val color: String? = null,
    val description: String? = null,
    val position: Int = 0,
) {
    public companion object {
        /**
         * Parses the `{ "data": [ … ] }` envelope into definitions ordered by
         * `position`. Archived entries and any with an unknown `kind`, a missing
         * `key`/`id`, or (for `choice`) no allowed values are dropped so only
         * renderable definitions survive. Returns null when the bytes are not the
         * expected envelope shape at all (wire spec §10.1).
         */
        public fun parseList(json: ByteArray): List<HaviLabelDefinition>? = parseList(json.toString(Charsets.UTF_8))

        public fun parseList(json: String): List<HaviLabelDefinition>? {
            val root = runCatching { Json.parseToJsonElement(json) }.getOrNull() as? JsonObject ?: return null
            val rawList = root["data"] as? JsonArray ?: return null
            return rawList
                .mapNotNull { (it as? JsonObject)?.let(::fromResource) }
                .sortedBy { it.position }
        }

        private fun fromResource(raw: JsonObject): HaviLabelDefinition? {
            val id = raw.string("id")?.takeIf { it.isNotEmpty() } ?: return null
            val key = raw.string("key")?.takeIf { it.isNotEmpty() } ?: return null
            val kind = HaviLabelKind.fromWire(raw.string("kind")) ?: return null

            if ((raw["archived"] as? JsonPrimitive)?.booleanOrNull == true) return null

            val allowedValues =
                (raw["allowed_values"] as? JsonArray)
                    ?.mapNotNull { (it as? JsonPrimitive)?.takeIf { p -> p.isString }?.content }
                    ?: emptyList()
            if (kind == HaviLabelKind.CHOICE && allowedValues.isEmpty()) return null

            return HaviLabelDefinition(
                id = id,
                key = key,
                name = raw.string("name") ?: key,
                kind = kind,
                allowedValues = allowedValues,
                color = raw.string("color"),
                description = raw.string("description"),
                position = (raw["position"] as? JsonPrimitive)?.let { it.intOrNull ?: it.doubleOrNull?.toInt() } ?: 0,
            )
        }

        private fun JsonObject.string(key: String): String? =
            (this[key] as? JsonPrimitive)?.takeIf { it.isString }?.content
    }
}
