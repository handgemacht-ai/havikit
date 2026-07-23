package ai.handgemacht.havikit

import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/**
 * Normalized (0…1) floating-point point in image space. The pure stand-in for
 * `CGPoint` so the markup + crop geometry runs on the JVM (no Android graphics).
 */
public data class HaviPointF(
    val x: Double,
    val y: Double,
)

/**
 * Normalized (0…1) floating-point rectangle in image space — the pure stand-in for
 * `CGRect`. Draw direction may leave width/height negative; [standardized]
 * normalizes it.
 */
public data class HaviRectF(
    val x: Double,
    val y: Double,
    val width: Double,
    val height: Double,
) {
    public val minX: Double get() = x
    public val minY: Double get() = y
    public val maxX: Double get() = x + width
    public val maxY: Double get() = y + height
    public val midX: Double get() = x + width / 2
    public val midY: Double get() = y + height / 2

    public fun standardized(): HaviRectF {
        val sx = if (width < 0) x + width else x
        val sy = if (height < 0) y + height else y
        return HaviRectF(sx, sy, abs(width), abs(height))
    }

    public fun union(other: HaviRectF): HaviRectF {
        val a = standardized()
        val b = other.standardized()
        val minX = min(a.minX, b.minX)
        val minY = min(a.minY, b.minY)
        val maxX = max(a.maxX, b.maxX)
        val maxY = max(a.maxY, b.maxY)
        return HaviRectF(minX, minY, maxX - minX, maxY - minY)
    }

    public fun insetBy(
        dx: Double,
        dy: Double,
    ): HaviRectF = HaviRectF(x + dx, y + dy, width - 2 * dx, height - 2 * dy)

    public fun offsetBy(
        dx: Double,
        dy: Double,
    ): HaviRectF = HaviRectF(x + dx, y + dy, width, height)

    public fun contains(point: HaviPointF): Boolean {
        val r = standardized()
        return point.x >= r.minX && point.x <= r.maxX && point.y >= r.minY && point.y <= r.maxY
    }

    public fun intersects(other: HaviRectF): Boolean {
        val a = standardized()
        val b = other.standardized()
        return a.minX < b.maxX && a.maxX > b.minX && a.minY < b.maxY && a.maxY > b.minY
    }

    public companion object {
        public fun boundsOf(points: List<HaviPointF>): HaviRectF {
            val first = points.firstOrNull() ?: return HaviRectF(0.0, 0.0, 0.0, 0.0)
            var minX = first.x
            var minY = first.y
            var maxX = first.x
            var maxY = first.y
            for (p in points.drop(1)) {
                minX = min(minX, p.x)
                minY = min(minY, p.y)
                maxX = max(maxX, p.x)
                maxY = max(maxY, p.y)
            }
            return HaviRectF(minX, minY, maxX - minX, maxY - minY)
        }
    }
}
