package ai.handgemacht.havikit

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/**
 * Loads the committed cross-language golden table (`havi-envelope-golden.json`,
 * byte-identical to the iOS repo's fixture, vendored into this module's test
 * resources). This is the same acceptance contract the Swift `HaviKitEnvelopeTests`
 * assert against and the havi backend replays through `AnnotationController.create`.
 */
object GoldenFixture {
    data class Case(
        val id: String,
        val envelope: JsonObject,
        val siblings: Map<String, String>,
    )

    fun load(): List<Case> {
        val stream =
            GoldenFixture::class.java.classLoader.getResourceAsStream("havi-envelope-golden.json")
                ?: error("could not locate havi-envelope-golden.json in test resources")
        val root = Json.parseToJsonElement(stream.readBytes().toString(Charsets.UTF_8)) as JsonObject
        val cases = root["cases"] as JsonArray
        return cases.map { element ->
            val obj = element as JsonObject
            val siblings =
                (obj["siblings"] as? JsonObject).orEmpty()
                    .mapValues { (it.value as JsonPrimitive).content }
            Case(
                id = (obj["id"] as JsonPrimitive).content,
                envelope = obj["envelope"] as JsonObject,
                siblings = siblings,
            )
        }
    }

    fun case(id: String): Case = load().firstOrNull { it.id == id } ?: error("no golden case with id $id")

    private fun JsonObject?.orEmpty(): Map<String, kotlinx.serialization.json.JsonElement> = this ?: emptyMap()
}
