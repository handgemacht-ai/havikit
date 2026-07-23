package ai.handgemacht.havikit

import androidx.compose.ui.graphics.Color

/**
 * Shared HaviKit brand colors for the capture + connect UI (parity with iOS
 * `HaviMarkupCanvas.accent` / `.success`). The accent is HAVI red `#E8542F`, used
 * for the submit button, priority segments, and the sign-in call to action;
 * success green never reads through the red-orange accent (which looks like an
 * error).
 */
internal object HaviBrand {
    val Accent = Color(0xFFE8542F)
    val Success = Color(0xFF34C759)
}

/** The packed-ARGB preset color as a Compose [Color] for the swatch + canvas strokes. */
internal fun HaviMarkColor.toColor(): Color = Color(argb)

/** Short toolbar label for a tool (the tray is text-labelled to avoid an icon dependency). */
internal val HaviMarkTool.shortTitle: String
    get() =
        when (this) {
            HaviMarkTool.PEN -> "Pen"
            HaviMarkTool.HIGHLIGHTER -> "Mark"
            HaviMarkTool.ARROW -> "Arrow"
            HaviMarkTool.RECTANGLE -> "Rect"
            HaviMarkTool.BLUR -> "Redact"
            HaviMarkTool.SELECT -> "Select"
            HaviMarkTool.CROP -> "Crop"
        }

/** The one-line hint shown under the canvas for the active tool (parity with iOS `markupHint`). */
internal val HaviMarkTool.hint: String
    get() =
        when (this) {
            HaviMarkTool.SELECT -> "Tap a mark to select it, then drag to move or delete it."
            HaviMarkTool.BLUR -> "Drag over anything private — it's blacked out before it's sent."
            HaviMarkTool.HIGHLIGHTER -> "Drag to highlight the area of the bug."
            HaviMarkTool.CROP -> "Drag a corner or edge, then Crop to zoom in and keep annotating."
            else -> "Draw on the screenshot to point at the bug."
        }
