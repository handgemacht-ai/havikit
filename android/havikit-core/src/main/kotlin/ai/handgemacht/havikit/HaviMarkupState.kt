package ai.handgemacht.havikit

import java.util.UUID

/**
 * The pure, immutable core of the multi-mark markup editor (wire spec §A4),
 * mirroring the object-level history of iOS `HaviMarkupModel`. Holds the current
 * tool + color, the committed vector marks (normalized image space), the
 * selection, and whole-array undo AND redo stacks — so an add, a move, and a
 * delete are each one reversible step. Every transition returns a new value
 * (copy-on-transition, like [HaviConnectBrowserState]) so it drops straight into
 * a Compose `mutableStateOf`; the transient in-progress stroke and drag-to-move
 * tracking live in the Android editor around it. Kept free of any Android graphics
 * so the history logic unit-tests on the JVM.
 */
public data class HaviMarkupState(
    val tool: HaviMarkTool = HaviMarkTool.PEN,
    val color: HaviMarkColor = HaviMarkColor.Red,
    val marks: List<HaviMark> = emptyList(),
    val selectedMarkId: UUID? = null,
    val undoStack: List<List<HaviMark>> = emptyList(),
    val redoStack: List<List<HaviMark>> = emptyList(),
) {
    public val canUndo: Boolean get() = undoStack.isNotEmpty()
    public val canRedo: Boolean get() = redoStack.isNotEmpty()

    public val selectedMark: HaviMark?
        get() = selectedMarkId?.let { id -> marks.firstOrNull { it.id == id } }

    /** Selecting a non-`select` tool drops any current selection (parity with iOS `selectTool`). */
    public fun withTool(newTool: HaviMarkTool): HaviMarkupState =
        copy(tool = newTool, selectedMarkId = if (newTool == HaviMarkTool.SELECT) selectedMarkId else null)

    public fun withColor(newColor: HaviMarkColor): HaviMarkupState = copy(color = newColor)

    public fun selecting(id: UUID?): HaviMarkupState = copy(selectedMarkId = id)

    /** Commits [newMarks] as one reversible step: pushes the current marks to undo and clears redo. */
    public fun committing(newMarks: List<HaviMark>): HaviMarkupState =
        copy(marks = newMarks, undoStack = undoStack + listOf(marks), redoStack = emptyList())

    /** Adds one drawn mark as a reversible step, clearing the selection. */
    public fun addingMark(mark: HaviMark): HaviMarkupState =
        committing(marks + mark).copy(selectedMarkId = null)

    /** Deletes the selected mark as a reversible step. A no-op when nothing is selected. */
    public fun deletingSelected(): HaviMarkupState {
        val id = selectedMarkId ?: return this
        return committing(marks.filterNot { it.id == id }).copy(selectedMarkId = null)
    }

    public fun undoing(): HaviMarkupState {
        val previous = undoStack.lastOrNull() ?: return this
        return copy(
            marks = previous,
            undoStack = undoStack.dropLast(1),
            redoStack = redoStack + listOf(marks),
            selectedMarkId = null,
        )
    }

    public fun redoing(): HaviMarkupState {
        val next = redoStack.lastOrNull() ?: return this
        return copy(
            marks = next,
            redoStack = redoStack.dropLast(1),
            undoStack = undoStack + listOf(marks),
            selectedMarkId = null,
        )
    }

    /**
     * Replaces the mark with [mark]'s id in place, without touching history — the
     * live drag-to-move update. History for a completed move is recorded once via
     * [committingMove] on drag end.
     */
    public fun replacingMark(mark: HaviMark): HaviMarkupState =
        copy(marks = marks.map { if (it.id == mark.id) mark else it })

    /**
     * Records a completed move: if the marks changed from [snapshot], pushes the
     * pre-move [snapshot] onto undo and clears redo. A no-op when nothing moved
     * (parity with iOS `endMove`).
     */
    public fun committingMove(snapshot: List<HaviMark>): HaviMarkupState =
        if (snapshot == marks) this else copy(undoStack = undoStack + listOf(snapshot), redoStack = emptyList())
}
