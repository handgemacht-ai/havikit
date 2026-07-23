package ai.handgemacht.havikit

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * Builds an envelope from each golden input and asserts it byte-for-byte against
 * the committed golden JSON (wire spec §8, §13). Both sides pass through
 * [HaviCanonicalJson] (sorted keys, minimal whitespace), so the comparison is
 * order-independent and truly byte-exact on the canonical form — the same contract
 * the iOS `HaviKitEnvelopeTests` enforce. Passing all six cases is the definition
 * of a correct envelope builder.
 */
class HaviEnvelopeTest {
    private fun assertMatchesGolden(
        id: String,
        input: HaviEnvelopeInput,
    ) {
        val built = HaviCanonicalJson.encode(HaviEnvelopeBuilder.build(input))
        val golden = HaviCanonicalJson.encode(GoldenFixture.case(id).envelope)
        assertEquals(golden, built, "envelope for $id diverged from golden")
    }

    private fun assertSiblings(
        id: String,
        input: HaviEnvelopeInput,
    ) = assertEquals(GoldenFixture.case(id).siblings, HaviEnvelopeBuilder.siblings(input))

    @Test
    fun minimalMatchesGolden() {
        assertMatchesGolden("minimal", minimalInput)
        assertSiblings("minimal", minimalInput)
    }

    @Test
    fun fullContextMatchesGolden() {
        assertMatchesGolden("full-context", fullContextInput)
        assertSiblings("full-context", fullContextInput)
    }

    @Test
    fun redactedMatchesGolden() {
        assertMatchesGolden("redacted", redactedInput)
        assertSiblings("redacted", redactedInput)
    }

    @Test
    fun diagnosticsMatchesGolden() {
        assertMatchesGolden("diagnostics", diagnosticsInput)
        assertSiblings("diagnostics", diagnosticsInput)
    }

    @Test
    fun markupMultiMatchesGolden() {
        assertMatchesGolden("markup-multi", markupMultiInput)
        assertSiblings("markup-multi", markupMultiInput)
    }

    @Test
    fun croppedMatchesGolden() {
        assertMatchesGolden("cropped", croppedInput)
        assertSiblings("cropped", croppedInput)
    }

    /**
     * Proves `croppedInput`'s fragment/viewport/svg are exactly what the crop
     * pipeline produces from the marks + crop rect it describes — the numbers are
     * pipeline-derived, not hand-fitted (mirrors iOS
     * `testCroppedInputMatchesCropPipelineProjection`). A second mark fully outside
     * the crop is dropped and has no envelope side effect.
     */
    @Test
    fun croppedInputMatchesCropPipelineProjection() {
        val crop = HaviRectF(0.25, 0.25, 0.5, 0.5)
        val originalViewport = HaviSize(400, 800)
        val originalImageSize = HaviSize(800, 1600)
        val inside = HaviMark(HaviMark.Shape.Rectangle(HaviRectF(0.4, 0.4, 0.2, 0.1)), HaviMarkColor.Red)
        val outside = HaviMark(HaviMark.Shape.Rectangle(HaviRectF(0.85, 0.85, 0.1, 0.1)), HaviMarkColor.Blue)

        val projected = HaviCropGeometry.projectMarks(listOf(inside, outside), crop)
        assertEquals(1, projected.size, "the fully-outside mark is dropped")

        val croppedImageSize = HaviCropGeometry.projectedImageSize(originalImageSize, crop)
        val croppedViewport = HaviCropGeometry.projectedViewport(originalViewport, crop)
        assertEquals(HaviSize(400, 800), croppedImageSize)
        assertEquals(croppedInput.viewport, croppedViewport)
        assertEquals(croppedInput.fragment, HaviMarkupSerializer.boundingBox(projected, croppedImageSize))
        assertEquals(croppedInput.markupSvg, HaviMarkupSerializer.svg(projected, croppedImageSize))
    }

    @Test
    fun commitRidesInDevButNotSiblings() {
        val siblings = HaviEnvelopeBuilder.siblings(fullContextInput)
        assertNull(siblings["commit"])
        val dev = xHaviDev(fullContextInput)
        assertEquals("a1b2c3d", dev["commit"])
    }

    @Test
    fun emptyStringDevFieldsAreTreatedAsAbsent() {
        val input = minimalInput.copy(dev = HaviDev(project = "lesewerkstatt", worktree = "", branch = ""))
        assertEquals(mapOf("project" to "lesewerkstatt"), HaviEnvelopeBuilder.siblings(input))
        val dev = xHaviDev(input)
        assertEquals("lesewerkstatt", dev["project"])
        assertNull(dev["worktree"])
        assertNull(dev["branch"])
    }

    @Test
    fun emptyCommentIsOmitted() {
        val input = minimalInput.copy(comment = "   ")
        val body = bodyList(input)
        assertEquals(1, body.size)
        assertEquals("Image", body.first()["type"])
    }

    @Test
    fun noMarkupOmitsSvgSelector() {
        assertEquals(listOf("FragmentSelector", "CssSelector"), selectorTypes(minimalInput))
    }

    @Test
    fun markupEmitsSvgSelector() {
        assertEquals(listOf("FragmentSelector", "CssSelector", "SvgSelector"), selectorTypes(fullContextInput))
    }

    @Test
    fun diagnosticsBodiesOrderAndRoles() {
        val roles = bodyList(diagnosticsInput).mapNotNull { it["x:role"] }
        assertEquals(listOf("device-info", "console-errors", "network-errors", "app-logs"), roles)
    }

    @Test
    fun consoleAndNetworkBodiesOmittedWhenNull() {
        val input = diagnosticsInput.copy(consoleErrors = null, networkErrors = null)
        val roles = bodyList(input).mapNotNull { it["x:role"] }
        assertEquals(listOf("device-info", "app-logs"), roles)
    }

    @Test
    fun excludedNetworkGroupDropsOnlyThatBody() {
        val input = diagnosticsInput.copy(networkErrors = null)
        val roles = bodyList(input).mapNotNull { it["x:role"] }
        assertEquals(listOf("device-info", "console-errors", "app-logs"), roles)
    }

    @Test
    fun appliedLabelsEmitTaggingBodiesAfterPriority() {
        val input =
            minimalInput.copy(
                comment = "Overlaps the mic button",
                priority = "high",
                labels =
                    listOf(
                        HaviLabel("area", "reader"),
                        HaviLabel("component", "WordCard"),
                        HaviLabel("blocker"),
                    ),
            )
        val tagging = taggingBodies(input)
        assertEquals(listOf("priority", "area", "component", "blocker"), tagging.map { it["x:labelKey"] })
        assertEquals("high", taggingValue(tagging, "priority"))
        assertEquals("reader", taggingValue(tagging, "area"))
        assertEquals("WordCard", taggingValue(tagging, "component"))
        assertTrue(tagging.all { it["purpose"] == "tagging" && it["type"] == "TextualBody" })
    }

    @Test
    fun flagLabelOmitsValueField() {
        val input = minimalInput.copy(labels = listOf(HaviLabel("regression")))
        val flag = taggingBodies(input).first { it["x:labelKey"] == "regression" }
        assertNull(flag["value"])
        assertEquals("tagging", flag["purpose"])
    }

    @Test
    fun labelsApplyWithoutPriority() {
        val input = minimalInput.copy(priority = null, labels = listOf(HaviLabel("area", "reader")))
        assertEquals(listOf("area"), taggingBodies(input).map { it["x:labelKey"] })
    }

    @Test
    fun priorityKeyInLabelsIsNotDuplicated() {
        val input =
            minimalInput.copy(
                priority = "high",
                labels = listOf(HaviLabel("priority", "low"), HaviLabel("area", "reader")),
            )
        val priorityBodies = taggingBodies(input).filter { it["x:labelKey"] == "priority" }
        assertEquals(1, priorityBodies.size)
        assertEquals("high", priorityBodies.first()["value"])
        assertEquals(listOf("priority", "area"), taggingBodies(input).map { it["x:labelKey"] })
    }

    @Test
    fun noLabelsEmitsNoTaggingBodies() {
        assertTrue(taggingBodies(minimalInput).isEmpty())
    }

    @Test
    fun customPriorityValueEmitsVerbatim() {
        val input = minimalInput.copy(priority = "P1")
        val tagging = taggingBodies(input)
        assertEquals(listOf("priority"), tagging.map { it["x:labelKey"] })
        assertEquals("P1", taggingValue(tagging, "priority"))
    }

    @Test
    fun nilOrEmptyPriorityEmitsNoPriorityBody() {
        assertTrue(taggingBodies(minimalInput.copy(priority = null)).isEmpty())
        assertTrue(taggingBodies(minimalInput.copy(priority = "   ")).isEmpty())
    }

    // MARK: - tree helpers over the builder's Map output

    @Suppress("UNCHECKED_CAST")
    private fun bodyList(input: HaviEnvelopeInput): List<Map<String, Any?>> =
        HaviEnvelopeBuilder.build(input)["body"] as List<Map<String, Any?>>

    private fun taggingBodies(input: HaviEnvelopeInput): List<Map<String, Any?>> =
        bodyList(input).filter { it["purpose"] == "tagging" }

    private fun taggingValue(
        bodies: List<Map<String, Any?>>,
        key: String,
    ): String? = bodies.firstOrNull { it["x:labelKey"] == key }?.get("value") as? String

    @Suppress("UNCHECKED_CAST")
    private fun selectorTypes(input: HaviEnvelopeInput): List<String> {
        val target = HaviEnvelopeBuilder.build(input)["target"] as Map<String, Any?>
        val selector = target["selector"] as List<Map<String, Any?>>
        return selector.map { it["type"] as String }
    }

    @Suppress("UNCHECKED_CAST")
    private fun xHaviDev(input: HaviEnvelopeInput): Map<String, Any?> {
        val xHavi = HaviEnvelopeBuilder.build(input)["x:havi"] as Map<String, Any?>
        return xHavi["dev"] as Map<String, Any?>
    }

    private companion object {
        val minimalInput =
            HaviEnvelopeInput(
                bundleId = "ai.handgemacht.lesewerkstatt.dev",
                screen = "HomeScreen",
                viewport = HaviSize(393, 852),
                fragment = HaviRect(0, 0, 786, 1704),
                markupSvg = null,
                cssPath = "HomeScreen",
                dev = HaviDev(project = "lesewerkstatt", worktree = "home-fix", branch = "home-fix"),
            )

        val fullContextInput =
            HaviEnvelopeInput(
                bundleId = "ai.handgemacht.lesewerkstatt.dev",
                screen = "ReaderScreen",
                viewport = HaviSize(844, 390),
                fragment = HaviRect(612, 980, 470, 190),
                markupSvg =
                    "<svg xmlns=\"http://www.w3.org/2000/svg\"><rect x=\"612\" y=\"980\" width=\"470\" " +
                        "height=\"190\" fill=\"none\" stroke=\"#E8542F\" stroke-width=\"6\"/></svg>",
                cssPath = "ReaderScreen > wordCard.Haus",
                comment = "Word card overlaps the mic button in landscape",
                priority = "high",
                deviceInfo = "iPhone15,3 · iOS 17.5.1 · Lesewerkstatt Dev 1.4.0+812 · de_DE · landscapeLeft",
                appLogs = "[info] card start ref=Haus\n[warning] settle timeout phase=listen\n[error] RPC readAloudScore 503",
                dev =
                    HaviDev(
                        project = "lesewerkstatt",
                        worktree = "reader-landscape-fix",
                        branch = "reader-landscape-fix",
                        commit = "a1b2c3d",
                    ),
                contexts = mapOf("reader" to mapOf("cardType" to "known-word", "phase" to "listen")),
                tags = mapOf("buildConfig" to "DevRelease"),
            )

        val redactedInput =
            HaviEnvelopeInput(
                bundleId = "ai.handgemacht.lesewerkstatt.dev",
                screen = "SettingsScreen",
                viewport = HaviSize(393, 852),
                fragment = HaviRect(0, 0, 786, 1704),
                markupSvg = null,
                cssPath = "SettingsScreen",
                comment = "Secret-shaped context keys must be scrubbed before send",
                priority = "medium",
                dev = HaviDev(project = "lesewerkstatt", worktree = "redaction-audit", branch = "redaction-audit"),
                contexts =
                    mapOf(
                        "session" to mapOf("userId" to "u-42", "authToken" to "eyJhbGciOi", "note" to "landscape"),
                        "cookies" to mapOf("sid" to "abc123"),
                        "vault" to mapOf("password" to "hunter2", "secretKey" to "k-01"),
                    ),
                tags = mapOf("authorization" to "Bearer zzz", "buildConfig" to "Debug"),
            )

        val diagnosticsInput =
            HaviEnvelopeInput(
                bundleId = "ai.handgemacht.lesewerkstatt.dev",
                screen = "ReaderScreen",
                viewport = HaviSize(393, 852),
                fragment = HaviRect(0, 0, 786, 1704),
                markupSvg = null,
                cssPath = "ReaderScreen",
                comment = "Scores never came back after the last card",
                priority = "high",
                deviceInfo = "iPhone15,3 · iOS 17.5.1 · Lesewerkstatt Dev 1.4.0+812 · de_DE · portrait",
                consoleErrors = "[error] Read-aloud scorer returned nil\n[error] Missing card asset: Haus",
                networkErrors =
                    "POST https://havi.example/api/rpc/run 503 action=readAloudScore\n" +
                        "POST https://havi.example/api/rpc/run 401 action=loadPlan",
                appLogs = "[info] card start ref=Haus\n[warning] settle timeout phase=listen",
                dev = HaviDev(project = "lesewerkstatt", worktree = "diagnostics-badges", branch = "diagnostics-badges"),
            )

        val markupMultiInput =
            HaviEnvelopeInput(
                bundleId = "ai.handgemacht.lesewerkstatt.dev",
                screen = "ReaderScreen",
                viewport = HaviSize(500, 1000),
                fragment = HaviRect(100, 200, 500, 850),
                markupSvg =
                    "<svg xmlns=\"http://www.w3.org/2000/svg\"><path d=\"M 100 200 L 150 260 L 220 240\" " +
                        "fill=\"none\" stroke=\"#E8542F\" stroke-width=\"6\" stroke-linecap=\"round\" " +
                        "stroke-linejoin=\"round\"/><rect x=\"400\" y=\"900\" width=\"200\" height=\"150\" " +
                        "fill=\"none\" stroke=\"#0A84FF\" stroke-width=\"6\"/></svg>",
                cssPath = "ReaderScreen",
                comment = "Circled the glitchy card and boxed the button",
                priority = "medium",
                dev = HaviDev(project = "lesewerkstatt", worktree = "markup-multi", branch = "markup-multi"),
            )

        val croppedInput =
            HaviEnvelopeInput(
                bundleId = "ai.handgemacht.lesewerkstatt.dev",
                screen = "ReaderScreen",
                viewport = HaviSize(200, 400),
                fragment = HaviRect(120, 240, 160, 160),
                markupSvg =
                    "<svg xmlns=\"http://www.w3.org/2000/svg\"><rect x=\"120\" y=\"240\" width=\"160\" " +
                        "height=\"160\" fill=\"none\" stroke=\"#E8542F\" stroke-width=\"6\"/></svg>",
                cssPath = "ReaderScreen",
                comment = "Cropped to the card before flagging the glitch",
                priority = "medium",
                dev =
                    HaviDev(
                        project = "lesewerkstatt",
                        worktree = "capture-two-screen",
                        branch = "capture-two-screen",
                    ),
            )
    }
}
