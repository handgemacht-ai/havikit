package ai.handgemacht.havikit

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlin.math.abs
import kotlin.math.min

/**
 * The Compose-observable markup editor (Part B4), mirroring iOS `HaviMarkupModel`.
 * The reversible history lives in the pure [HaviMarkupState] (`:havikit-core`),
 * held in a `mutableStateOf` so every transition recomposes the canvas; the
 * transient in-progress stroke and drag-to-move tracking live here. The canvas
 * only converts display points to normalized (0..1) image coordinates and calls
 * these begin/extend/end methods, so the view stays thin.
 */
internal class HaviMarkupEditor {
    var state by mutableStateOf(HaviMarkupState())
        private set

    var inProgress by mutableStateOf<HaviMark?>(null)
        private set

    private var anchor: HaviPointF? = null
    private var moveSnapshot: List<HaviMark>? = null
    private var moveLast: HaviPointF? = null

    /** Notified before a tool change so the owner (the capture model) can open/close crop mode. */
    var onToolChange: ((old: HaviMarkTool, new: HaviMarkTool) -> Unit)? = null

    val tool: HaviMarkTool get() = state.tool
    val color: HaviMarkColor get() = state.color
    val marks: List<HaviMark> get() = state.marks
    val selectedMarkId get() = state.selectedMarkId
    val selectedMark: HaviMark? get() = state.selectedMark
    val canUndo: Boolean get() = state.canUndo
    val canRedo: Boolean get() = state.canRedo

    fun selectTool(newTool: HaviMarkTool) {
        val old = state.tool
        if (old != newTool) onToolChange?.invoke(old, newTool)
        state = state.withTool(newTool)
    }

    fun setColor(newColor: HaviMarkColor) {
        state = state.withColor(newColor)
    }

    fun undo() {
        state = state.undoing()
    }

    fun redo() {
        state = state.redoing()
    }

    fun deleteSelected() {
        state = state.deletingSelected()
    }

    // Gestures — points already normalized (0..1) full-image space by the canvas.

    fun begin(
        point: HaviPointF,
        region: HaviRectF = HaviCropGeometry.fullFrame,
    ) {
        when (state.tool) {
            HaviMarkTool.PEN -> inProgress = HaviMark(HaviMark.Shape.Pen(listOf(point)), state.color)
            HaviMarkTool.HIGHLIGHTER -> inProgress = HaviMark(HaviMark.Shape.Highlighter(listOf(point)), state.color)
            HaviMarkTool.ARROW -> inProgress = HaviMark(HaviMark.Shape.Arrow(point, point), state.color)
            HaviMarkTool.RECTANGLE -> {
                anchor = point
                inProgress = HaviMark(HaviMark.Shape.Rectangle(HaviRectF(point.x, point.y, 0.0, 0.0)), state.color)
            }
            HaviMarkTool.BLUR -> {
                anchor = point
                inProgress = HaviMark(HaviMark.Shape.Blur(HaviRectF(point.x, point.y, 0.0, 0.0)), state.color)
            }
            HaviMarkTool.SELECT -> beginSelectOrMove(point, region)
            HaviMarkTool.CROP -> Unit
        }
    }

    fun extend(point: HaviPointF) {
        if (!state.tool.isDrawing) {
            updateMove(point)
            return
        }
        val mark = inProgress ?: return
        val updated =
            when (val s = mark.shape) {
                is HaviMark.Shape.Pen -> mark.copy(shape = HaviMark.Shape.Pen(s.points + point))
                is HaviMark.Shape.Highlighter -> mark.copy(shape = HaviMark.Shape.Highlighter(s.points + point))
                is HaviMark.Shape.Arrow -> mark.copy(shape = HaviMark.Shape.Arrow(s.from, point))
                is HaviMark.Shape.Rectangle -> mark.copy(shape = HaviMark.Shape.Rectangle(rect(anchor ?: point, point)))
                is HaviMark.Shape.Blur -> mark.copy(shape = HaviMark.Shape.Blur(rect(anchor ?: point, point)))
            }
        inProgress = updated
    }

    fun end(region: HaviRectF = HaviCropGeometry.fullFrame) {
        if (!state.tool.isDrawing) {
            endMove()
            return
        }
        val mark = inProgress
        inProgress = null
        anchor = null
        if (mark == null || !HaviCropGeometry.isMeaningfulMark(mark, region)) return
        state = state.addingMark(mark)
    }

    private fun beginSelectOrMove(
        point: HaviPointF,
        region: HaviRectF,
    ) {
        val hit =
            marks.lastOrNull {
                HaviCropGeometry.markHitTest(it, point, SELECT_HIT_TOLERANCE, region)
            }
        if (hit != null) {
            state = state.selecting(hit.id)
            moveSnapshot = marks
            moveLast = point
        } else {
            state = state.selecting(null)
            moveSnapshot = null
            moveLast = null
        }
    }

    private fun updateMove(point: HaviPointF) {
        val id = selectedMarkId ?: return
        val last = moveLast ?: return
        val current = marks.firstOrNull { it.id == id } ?: return
        state = state.replacingMark(current.translated(point.x - last.x, point.y - last.y))
        moveLast = point
    }

    private fun endMove() {
        val snapshot = moveSnapshot
        moveSnapshot = null
        moveLast = null
        if (snapshot != null) state = state.committingMove(snapshot)
    }

    private fun rect(
        a: HaviPointF,
        b: HaviPointF,
    ): HaviRectF = HaviRectF(min(a.x, b.x), min(a.y, b.y), abs(a.x - b.x), abs(a.y - b.y))

    companion object {
        /** Select-tool hit-test slop, a fraction of the visible region (parity with iOS 0.03). */
        const val SELECT_HIT_TOLERANCE: Double = 0.03
    }
}
