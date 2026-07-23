package ai.handgemacht.havikit

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue

/**
 * The Compose-observable crop editor (Part B4), mirroring iOS `HaviCropModel`. The
 * crop rect lives in the same normalized (0..1) full-image space as the marks;
 * crop is a confirmed step — [beginEditing] opens crop mode, [updateResize] tracks
 * the live draft as a handle drags, [confirm] keeps it (the canvas then zooms into
 * it), [cancel] reverts to the last confirmed crop, and [reset] widens the draft
 * back to the full frame. The pure math is delegated to `HaviCropGeometry`.
 */
internal class HaviCropEditor {
    var rect by mutableStateOf(HaviCropGeometry.fullFrame)
        private set

    var isEditing by mutableStateOf(false)
        private set

    private var confirmedRect: HaviRectF = HaviCropGeometry.fullFrame

    val isCropped: Boolean get() = rect != HaviCropGeometry.fullFrame

    fun beginEditing() {
        confirmedRect = rect
        isEditing = true
    }

    fun updateResize(
        handle: HaviCropGeometry.Handle,
        point: HaviPointF,
    ) {
        rect = HaviCropGeometry.resize(rect, handle, point)
    }

    fun confirm() {
        rect = HaviCropGeometry.clamped(rect)
        isEditing = false
    }

    fun cancel() {
        rect = confirmedRect
        isEditing = false
    }

    fun reset() {
        rect = HaviCropGeometry.fullFrame
    }
}
