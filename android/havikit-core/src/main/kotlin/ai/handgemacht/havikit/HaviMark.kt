package ai.handgemacht.havikit

import java.util.UUID

/**
 * The markup toolset v2 (wire spec §A4). Each tool produces a typed vector mark
 * stored in normalized image coordinates (0…1), projected into image-pixel space
 * at submit time by [HaviMarkupSerializer]. Kept free of any Android graphics so
 * the model + serialization run on the JVM.
 */
public enum class HaviMarkTool(public val id: String) {
    PEN("pen"),
    HIGHLIGHTER("highlighter"),
    ARROW("arrow"),
    RECTANGLE("rectangle"),
    BLUR("blur"),
    SELECT("select"),
    CROP("crop"),
    ;

    public val accessibilityId: String get() = "havi-tool-$id"

    /** Whether the tool draws a new mark (vs. `select`/`crop`, which edit existing state). */
    public val isDrawing: Boolean get() = this != SELECT && this != CROP
}

/**
 * A markup color preset. Stores the `#RRGGBB` hex used verbatim in the SVG
 * `stroke` / `fill` (wire spec §6.5) plus the packed ARGB the Android canvas
 * renders with. Brand red (`#E8542F`) is the default.
 */
public data class HaviMarkColor(
    val name: String,
    val hex: String,
    val argb: Int,
) {
    public val accessibilityId: String get() = "havi-color-$name"

    public companion object {
        public val Red: HaviMarkColor = HaviMarkColor("red", "#E8542F", 0xFFE8542F.toInt())
        public val Yellow: HaviMarkColor = HaviMarkColor("yellow", "#F5C518", 0xFFF5C518.toInt())
        public val Green: HaviMarkColor = HaviMarkColor("green", "#34C759", 0xFF34C759.toInt())
        public val Blue: HaviMarkColor = HaviMarkColor("blue", "#0A84FF", 0xFF0A84FF.toInt())
        public val Black: HaviMarkColor = HaviMarkColor("black", "#000000", 0xFF000000.toInt())
        public val White: HaviMarkColor = HaviMarkColor("white", "#FFFFFF", 0xFFFFFFFF.toInt())

        /** Swatch row, red first (wire spec §A4: 6 presets, red default). */
        public val Presets: List<HaviMarkColor> = listOf(Red, Yellow, Green, Blue, Black, White)
    }
}

/**
 * One typed vector mark in normalized image space. `Blur` marks are redaction
 * regions: burned into the screenshot pixels before send and never serialized into
 * the envelope's SVG or selectors (wire spec §6.5).
 */
public data class HaviMark(
    val shape: Shape,
    val color: HaviMarkColor,
    val id: UUID = UUID.randomUUID(),
) {
    public sealed interface Shape {
        public data class Pen(val points: List<HaviPointF>) : Shape

        public data class Highlighter(val points: List<HaviPointF>) : Shape

        public data class Arrow(val from: HaviPointF, val to: HaviPointF) : Shape

        public data class Rectangle(val rect: HaviRectF) : Shape

        public data class Blur(val rect: HaviRectF) : Shape
    }

    public val isBlur: Boolean get() = shape is Shape.Blur

    /** Normalized (0…1) bounding box of the mark's geometry, standardized. */
    public val normalizedBounds: HaviRectF
        get() =
            when (val s = shape) {
                is Shape.Pen -> HaviRectF.boundsOf(s.points)
                is Shape.Highlighter -> HaviRectF.boundsOf(s.points)
                is Shape.Arrow -> HaviRectF.boundsOf(listOf(s.from, s.to))
                is Shape.Rectangle -> s.rect.standardized()
                is Shape.Blur -> s.rect.standardized()
            }

    /** Shift the mark's geometry by a normalized offset (select → drag to move). */
    public fun translated(
        dx: Double,
        dy: Double,
    ): HaviMark {
        fun HaviPointF.moved() = HaviPointF(x + dx, y + dy)
        val moved =
            when (val s = shape) {
                is Shape.Pen -> Shape.Pen(s.points.map { it.moved() })
                is Shape.Highlighter -> Shape.Highlighter(s.points.map { it.moved() })
                is Shape.Arrow -> Shape.Arrow(s.from.moved(), s.to.moved())
                is Shape.Rectangle -> Shape.Rectangle(s.rect.offsetBy(dx, dy))
                is Shape.Blur -> Shape.Blur(s.rect.offsetBy(dx, dy))
            }
        return copy(shape = moved)
    }

    /** Coarse hit test for the select tool: bounds expanded by [tolerance] contains [point]. */
    public fun hitTest(
        point: HaviPointF,
        tolerance: Double,
    ): Boolean = normalizedBounds.insetBy(-tolerance, -tolerance).contains(point)
}
