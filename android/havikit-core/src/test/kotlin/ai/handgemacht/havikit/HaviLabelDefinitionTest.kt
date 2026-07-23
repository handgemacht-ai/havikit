package ai.handgemacht.havikit

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test

/** Label vocabulary parsing (wire spec §10.1): drop rules, defaults, position sort. */
class HaviLabelDefinitionTest {
    @Test
    fun parsesSortsAndAppliesDefaults() {
        val json =
            """
            {"data":[
              {"id":"2","key":"area","kind":"choice","allowed_values":["reader","home"],"position":2},
              {"id":"1","key":"priority","kind":"choice","name":"Priority","allowed_values":["high","low"],"position":1},
              {"id":"3","key":"blocker","kind":"flag","position":3}
            ]}
            """.trimIndent()
        val list = HaviLabelDefinition.parseList(json)!!
        assertEquals(listOf("priority", "area", "blocker"), list.map { it.key })
        assertEquals("Priority", list[0].name)
        assertEquals("area", list[1].name) // name defaults to key
        assertEquals(HaviLabelKind.FLAG, list[2].kind)
    }

    @Test
    fun dropsArchivedUnknownKindMissingIdOrKeyAndEmptyChoice() {
        val json =
            """
            {"data":[
              {"id":"1","key":"a","kind":"flag","archived":true},
              {"id":"2","key":"b","kind":"mystery"},
              {"key":"c","kind":"flag"},
              {"id":"4","kind":"flag"},
              {"id":"5","key":"e","kind":"choice"},
              {"id":"6","key":"ok","kind":"value"}
            ]}
            """.trimIndent()
        val list = HaviLabelDefinition.parseList(json)!!
        assertEquals(listOf("ok"), list.map { it.key })
    }

    @Test
    fun returnsNullWhenNotTheEnvelopeShape() {
        assertNull(HaviLabelDefinition.parseList("""{"nope":true}"""))
        assertNull(HaviLabelDefinition.parseList("not json"))
    }
}
