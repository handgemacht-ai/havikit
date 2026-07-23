package ai.handgemacht.havikit

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * Markup v2 serialization (wire spec §6.5), mirroring the iOS
 * `HaviMarkupSerializerTests`: normalized vector marks project into one
 * image-pixel `<svg>`, the FragmentSelector is the bounding-box union of non-blur
 * marks, blur/redact marks are excluded from both, and the arrowhead geometry is
 * deterministic. The single-rectangle case reproduces the golden `full-context`
 * SVG bytes; the multi-mark case is the golden `markup-multi` anchor.
 */
class HaviMarkupSerializerTest {
    private val imageSize = HaviSize(1000, 2000)

    @Test
    fun singleRectangleReproducesV1Svg() {
        val mark = HaviMark(HaviMark.Shape.Rectangle(HaviRectF(0.306, 0.245, 0.235, 0.0475)), HaviMarkColor.Red)
        assertEquals(
            "<svg xmlns=\"http://www.w3.org/2000/svg\"><rect x=\"612\" y=\"980\" width=\"470\" height=\"190\" " +
                "fill=\"none\" stroke=\"#E8542F\" stroke-width=\"6\"/></svg>",
            HaviMarkupSerializer.svg(listOf(mark), HaviSize(2000, 4000)),
        )
    }

    @Test
    fun multiMarkSvgAndBoundingBoxMatchGolden() {
        val pen =
            HaviMark(
                HaviMark.Shape.Pen(listOf(HaviPointF(0.1, 0.1), HaviPointF(0.15, 0.13), HaviPointF(0.22, 0.12))),
                HaviMarkColor.Red,
            )
        val rect = HaviMark(HaviMark.Shape.Rectangle(HaviRectF(0.4, 0.45, 0.2, 0.075)), HaviMarkColor.Blue)
        val blur = HaviMark(HaviMark.Shape.Blur(HaviRectF(0.05, 0.8, 0.3, 0.1)), HaviMarkColor.Black)

        assertEquals(
            "<svg xmlns=\"http://www.w3.org/2000/svg\"><path d=\"M 100 200 L 150 260 L 220 240\" fill=\"none\" " +
                "stroke=\"#E8542F\" stroke-width=\"6\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/>" +
                "<rect x=\"400\" y=\"900\" width=\"200\" height=\"150\" fill=\"none\" stroke=\"#0A84FF\" " +
                "stroke-width=\"6\"/></svg>",
            HaviMarkupSerializer.svg(listOf(pen, rect, blur), imageSize),
        )
        assertEquals(
            HaviRect(100, 200, 500, 850),
            HaviMarkupSerializer.boundingBox(listOf(pen, rect, blur), imageSize),
        )
    }

    @Test
    fun highlighterIsSemiTransparentWiderStroke() {
        val mark =
            HaviMark(HaviMark.Shape.Highlighter(listOf(HaviPointF(0.1, 0.1), HaviPointF(0.2, 0.1))), HaviMarkColor.Yellow)
        assertEquals(
            "<svg xmlns=\"http://www.w3.org/2000/svg\"><path d=\"M 100 200 L 200 200\" fill=\"none\" " +
                "stroke=\"#F5C518\" stroke-width=\"24\" stroke-linecap=\"round\" stroke-linejoin=\"round\" " +
                "stroke-opacity=\"0.35\"/></svg>",
            HaviMarkupSerializer.svg(listOf(mark), imageSize),
        )
    }

    @Test
    fun arrowSerializesLinePlusPolygonHead() {
        val arrow = HaviMark(HaviMark.Shape.Arrow(HaviPointF(0.1, 0.5), HaviPointF(0.9, 0.5)), HaviMarkColor.Red)
        assertEquals(
            "<svg xmlns=\"http://www.w3.org/2000/svg\"><line x1=\"100\" y1=\"1000\" x2=\"900\" y2=\"1000\" " +
                "stroke=\"#E8542F\" stroke-width=\"6\" stroke-linecap=\"round\"/><polygon points=\"900,1000 " +
                "866,1013 866,987\" fill=\"#E8542F\"/></svg>",
            HaviMarkupSerializer.svg(listOf(arrow), imageSize),
        )
    }

    @Test
    fun arrowHeadGeometryIsDeterministic() {
        val head = HaviMarkupSerializer.arrowHead(HaviPointF(100.0, 0.0), HaviPointF(0.0, 0.0), 20.0, 20.0)
        assertEquals(listOf(HaviPointF(100.0, 0.0), HaviPointF(80.0, 10.0), HaviPointF(80.0, -10.0)), head)
    }

    @Test
    fun blurMarksAreExcludedFromEnvelopeGeometry() {
        val blur = HaviMark(HaviMark.Shape.Blur(HaviRectF(0.1, 0.1, 0.3, 0.3)), HaviMarkColor.Black)
        assertNull(HaviMarkupSerializer.svg(listOf(blur), imageSize))
        assertNull(HaviMarkupSerializer.boundingBox(listOf(blur), imageSize))
        assertEquals(listOf(HaviRectF(0.1, 0.1, 0.3, 0.3)), HaviMarkupSerializer.blurRects(listOf(blur)))
    }

    @Test
    fun noMarksProducesNoSvgOrBox() {
        assertNull(HaviMarkupSerializer.svg(emptyList(), imageSize))
        assertNull(HaviMarkupSerializer.boundingBox(emptyList(), imageSize))
        assertTrue(HaviMarkupSerializer.blurRects(emptyList()).isEmpty())
    }

    @Test
    fun boundingBoxUnionSpansAllNonBlurMarks() {
        val a = HaviMark(HaviMark.Shape.Rectangle(HaviRectF(0.1, 0.1, 0.1, 0.1)), HaviMarkColor.Red)
        val b = HaviMark(HaviMark.Shape.Rectangle(HaviRectF(0.6, 0.7, 0.2, 0.2)), HaviMarkColor.Blue)
        assertEquals(HaviRect(100, 200, 700, 1600), HaviMarkupSerializer.boundingBox(listOf(a, b), imageSize))
    }
}
