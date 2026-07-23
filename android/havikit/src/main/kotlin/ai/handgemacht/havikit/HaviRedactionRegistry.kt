package ai.handgemacht.havikit

import androidx.compose.ui.geometry.Rect
import java.util.concurrent.atomic.AtomicLong
import kotlin.math.roundToInt

/** An integer rectangle in window-pixel space — the coordinate space of a PixelCopy window capture. */
internal data class HaviWindowRect(
    val left: Int,
    val top: Int,
    val right: Int,
    val bottom: Int,
) {
    val width: Int get() = right - left
    val height: Int get() = bottom - top
    private val centerX: Float get() = (left + right) / 2f
    private val centerY: Float get() = (top + bottom) / 2f

    fun isDegenerate(): Boolean = width <= 0 || height <= 0

    fun translate(
        dx: Int,
        dy: Int,
    ): HaviWindowRect = HaviWindowRect(left + dx, top + dy, right + dx, bottom + dy)

    /** True when [other]'s center point lies inside this rect — used to match a text field to a reveal region. */
    fun containsCenterOf(other: HaviWindowRect): Boolean =
        other.centerX >= left && other.centerX <= right &&
            other.centerY >= top && other.centerY <= bottom
}

internal data class HaviRedactionSnapshot(
    val redacted: List<HaviWindowRect>,
    val revealed: List<HaviWindowRect>,
)

/**
 * The process-wide redaction relay backing `Modifier.haviRedacted()` /
 * `Modifier.haviReveal()` (Part B3). Each modifier instance owns a stable id and
 * publishes its window-space bounds on layout, removing them on dispose. At capture
 * time the controller reads a [snapshot]: explicit redacted regions are always masked,
 * and `haviReveal` regions cancel the default masking of the text fields they contain.
 * Global (not runtime-scoped) so the modifiers work regardless of start ordering.
 */
internal object HaviRedactionRegistry {
    private val lock = Any()
    private val redacted = LinkedHashMap<Long, HaviWindowRect>()
    private val revealed = LinkedHashMap<Long, HaviWindowRect>()
    private val ids = AtomicLong(0L)

    fun nextId(): Long = ids.incrementAndGet()

    fun setRedacted(
        id: Long,
        bounds: Rect,
    ): Unit = update(redacted, id, bounds)

    fun setRevealed(
        id: Long,
        bounds: Rect,
    ): Unit = update(revealed, id, bounds)

    fun remove(id: Long) {
        synchronized(lock) {
            redacted.remove(id)
            revealed.remove(id)
        }
    }

    fun snapshot(): HaviRedactionSnapshot =
        synchronized(lock) {
            HaviRedactionSnapshot(redacted.values.toList(), revealed.values.toList())
        }

    private fun update(
        target: MutableMap<Long, HaviWindowRect>,
        id: Long,
        bounds: Rect,
    ) {
        val rect = bounds.toWindowRect()
        synchronized(lock) {
            if (rect.isDegenerate()) target.remove(id) else target[id] = rect
        }
    }

    private fun Rect.toWindowRect(): HaviWindowRect =
        HaviWindowRect(
            left = left.roundToInt(),
            top = top.roundToInt(),
            right = right.roundToInt(),
            bottom = bottom.roundToInt(),
        )
}
