package ai.handgemacht.havikit

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** Object-level undo/redo + selection history of the markup editor core (wire spec §A4). */
class HaviMarkupStateTest {
    private fun rect(x: Double) = HaviMark(HaviMark.Shape.Rectangle(HaviRectF(x, 0.1, 0.2, 0.2)), HaviMarkColor.Red)

    @Test
    fun addUndoRedoAreEachOneStep() {
        val a = rect(0.1)
        val b = rect(0.5)
        var state = HaviMarkupState().addingMark(a).addingMark(b)
        assertEquals(listOf(a, b), state.marks)
        assertTrue(state.canUndo)
        assertFalse(state.canRedo)

        state = state.undoing()
        assertEquals(listOf(a), state.marks)
        assertTrue(state.canRedo)

        state = state.undoing()
        assertEquals(emptyList<HaviMark>(), state.marks)
        assertFalse(state.canUndo)

        state = state.redoing().redoing()
        assertEquals(listOf(a, b), state.marks)
        assertFalse(state.canRedo)
    }

    @Test
    fun addingAfterUndoClearsRedo() {
        val a = rect(0.1)
        val b = rect(0.5)
        val c = rect(0.8)
        var state = HaviMarkupState().addingMark(a).addingMark(b).undoing()
        assertTrue(state.canRedo)
        state = state.addingMark(c)
        assertFalse(state.canRedo)
        assertEquals(listOf(a, c), state.marks)
    }

    @Test
    fun deleteSelectedIsReversible() {
        val a = rect(0.1)
        val b = rect(0.5)
        var state = HaviMarkupState().addingMark(a).addingMark(b).selecting(b.id)
        state = state.deletingSelected()
        assertEquals(listOf(a), state.marks)
        assertNull(state.selectedMarkId)
        state = state.undoing()
        assertEquals(listOf(a, b), state.marks)
    }

    @Test
    fun toolChangeClearsSelectionUnlessSelectTool() {
        val a = rect(0.1)
        var state = HaviMarkupState().addingMark(a).withTool(HaviMarkTool.SELECT).selecting(a.id)
        assertEquals(a.id, state.selectedMarkId)
        // Staying on select keeps the selection.
        state = state.withTool(HaviMarkTool.SELECT)
        assertEquals(a.id, state.selectedMarkId)
        // Switching to a drawing tool clears it.
        state = state.withTool(HaviMarkTool.PEN)
        assertNull(state.selectedMarkId)
    }

    @Test
    fun moveRecordsOneUndoStepOnlyWhenChanged() {
        val a = rect(0.1)
        val start = HaviMarkupState().addingMark(a)
        val snapshot = start.marks
        val moved = start.replacingMark(a.translated(0.2, 0.0))
        // A live move mutation does not itself add history...
        assertEquals(start.undoStack.size, moved.undoStack.size)
        val committed = moved.committingMove(snapshot)
        assertTrue(committed.canUndo)
        // Undo restores the pre-move geometry.
        assertEquals(snapshot, committed.undoing().marks)

        // No net change => no history entry.
        val unchanged = start.committingMove(start.marks)
        assertEquals(start.undoStack.size, unchanged.undoStack.size)
    }
}
