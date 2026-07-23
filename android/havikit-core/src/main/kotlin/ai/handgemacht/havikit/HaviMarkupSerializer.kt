package ai.handgemacht.havikit

import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sqrt

/**
 * Serializes the v2 markup marks into the envelope's geometry (wire spec §6.5):
 * one `SvgSelector` `<svg>` holding every non-blur mark in image-pixel space, and
 * the `FragmentSelector`'s bounding-box union of those same marks. `Blur` marks are
 * excluded from both — redaction, burned into the pixels before send. Byte-for-byte
 * reproducible against the golden fixture's `markupSvg` / `fragment` values.
 */
public object HaviMarkupSerializer {
    // Stroke widths in image-pixel space (one default per tool; no width picker).
    public const val PEN_WIDTH: Int = 6
    public const val HIGHLIGHTER_WIDTH: Int = 24
    public const val ARROW_WIDTH: Int = 6
    public const val RECTANGLE_WIDTH: Int = 6

    public const val ARROW_HEAD_LENGTH: Double = 34.0
    public const val ARROW_HEAD_WIDTH: Double = 26.0

    public const val HIGHLIGHTER_STROKE_OPACITY: String = "0.35"

    /** The `SvgSelector` value for all non-blur marks, or null when there are none. */
    public fun svg(
        marks: List<HaviMark>,
        imageSize: HaviSize,
    ): String? {
        val drawable = marks.filterNot { it.isBlur }
        if (drawable.isEmpty()) return null
        val body = drawable.joinToString("") { element(it, imageSize) }
        return "<svg xmlns=\"http://www.w3.org/2000/svg\">$body</svg>"
    }

    /** The `FragmentSelector` region: image-pixel bounding-box union of non-blur marks, or null. */
    public fun boundingBox(
        marks: List<HaviMark>,
        imageSize: HaviSize,
    ): HaviRect? {
        val union = normalizedBoundingBox(marks) ?: return null
        return HaviCaptureGeometry.imagePixelRect(union, imageSize)
    }

    /** Normalized (0…1) bounding-box union of non-blur marks. */
    public fun normalizedBoundingBox(marks: List<HaviMark>): HaviRectF? {
        val drawable = marks.filterNot { it.isBlur }
        if (drawable.isEmpty()) return null
        return drawable.drop(1).fold(drawable.first().normalizedBounds) { acc, mark ->
            acc.union(mark.normalizedBounds)
        }
    }

    /** Normalized redaction rects to burn into the pixels before send. */
    public fun blurRects(marks: List<HaviMark>): List<HaviRectF> =
        marks.mapNotNull { (it.shape as? HaviMark.Shape.Blur)?.rect?.standardized() }

    /**
     * The filled arrowhead triangle for a shaft [tail]→[tip]: the tip plus the two
     * base barbs, offset back along the shaft by [length] and out by [width]/2.
     */
    public fun arrowHead(
        tip: HaviPointF,
        tail: HaviPointF,
        length: Double,
        width: Double,
    ): List<HaviPointF> {
        val dx = tip.x - tail.x
        val dy = tip.y - tail.y
        val shaft = sqrt(dx * dx + dy * dy)
        if (shaft <= 0) return listOf(tip, tip, tip)
        val ux = dx / shaft
        val uy = dy / shaft
        val px = -uy
        val py = ux
        val base = HaviPointF(tip.x - ux * length, tip.y - uy * length)
        val left = HaviPointF(base.x + px * width / 2, base.y + py * width / 2)
        val right = HaviPointF(base.x - px * width / 2, base.y - py * width / 2)
        return listOf(tip, left, right)
    }

    private fun element(
        mark: HaviMark,
        imageSize: HaviSize,
    ): String {
        val hex = mark.color.hex
        return when (val s = mark.shape) {
            is HaviMark.Shape.Pen -> path(s.points, imageSize, hex, PEN_WIDTH, null)
            is HaviMark.Shape.Highlighter -> path(s.points, imageSize, hex, HIGHLIGHTER_WIDTH, HIGHLIGHTER_STROKE_OPACITY)
            is HaviMark.Shape.Arrow -> arrow(s.from, s.to, imageSize, hex)
            is HaviMark.Shape.Rectangle -> rectElement(s.rect, imageSize, hex, RECTANGLE_WIDTH)
            is HaviMark.Shape.Blur -> ""
        }
    }

    private fun rectElement(
        rect: HaviRectF,
        imageSize: HaviSize,
        stroke: String,
        width: Int,
    ): String {
        val pixels = HaviCaptureGeometry.imagePixelRect(rect.standardized(), imageSize)
        return "<rect x=\"${pixels.x}\" y=\"${pixels.y}\" width=\"${pixels.width}\" height=\"${pixels.height}\" " +
            "fill=\"none\" stroke=\"$stroke\" stroke-width=\"$width\"/>"
    }

    private fun path(
        points: List<HaviPointF>,
        imageSize: HaviSize,
        stroke: String,
        width: Int,
        opacity: String?,
    ): String {
        val first = points.firstOrNull() ?: return ""
        val d = StringBuilder("M ${pixelX(first, imageSize)} ${pixelY(first, imageSize)}")
        for (point in points.drop(1)) {
            d.append(" L ${pixelX(point, imageSize)} ${pixelY(point, imageSize)}")
        }
        val opacityAttr = opacity?.let { " stroke-opacity=\"$it\"" } ?: ""
        return "<path d=\"$d\" fill=\"none\" stroke=\"$stroke\" stroke-width=\"$width\" " +
            "stroke-linecap=\"round\" stroke-linejoin=\"round\"$opacityAttr/>"
    }

    private fun arrow(
        from: HaviPointF,
        to: HaviPointF,
        imageSize: HaviSize,
        stroke: String,
    ): String {
        val tip = HaviPointF(pixelX(to, imageSize).toDouble(), pixelY(to, imageSize).toDouble())
        val tail = HaviPointF(pixelX(from, imageSize).toDouble(), pixelY(from, imageSize).toDouble())
        val head = arrowHead(tip, tail, ARROW_HEAD_LENGTH, ARROW_HEAD_WIDTH)
        val points = head.joinToString(" ") { "${it.x.roundToInt()},${it.y.roundToInt()}" }
        return "<line x1=\"${tail.x.roundToInt()}\" y1=\"${tail.y.roundToInt()}\" " +
            "x2=\"${tip.x.roundToInt()}\" y2=\"${tip.y.roundToInt()}\" " +
            "stroke=\"$stroke\" stroke-width=\"$ARROW_WIDTH\" stroke-linecap=\"round\"/>" +
            "<polygon points=\"$points\" fill=\"$stroke\"/>"
    }

    private fun pixelX(
        point: HaviPointF,
        size: HaviSize,
    ): Int = clamp((clampUnit(point.x) * size.width).roundToInt(), size.width)

    private fun pixelY(
        point: HaviPointF,
        size: HaviSize,
    ): Int = clamp((clampUnit(point.y) * size.height).roundToInt(), size.height)

    private fun clampUnit(value: Double): Double = min(max(0.0, value), 1.0)

    private fun clamp(
        value: Int,
        upper: Int,
    ): Int = min(max(0, value), upper)
}
