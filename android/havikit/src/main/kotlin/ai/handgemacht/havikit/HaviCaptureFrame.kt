package ai.handgemacht.havikit

import android.graphics.Bitmap

internal enum class HaviCaptureOrientation { PORTRAIT, LANDSCAPE }

/**
 * The frozen, already-redacted capture handed to the capture sheet (a later stage).
 * Everything the envelope needs is snapshotted here at freeze time so a later
 * context/log mutation cannot race the in-flight capture:
 *  - [bitmap]: the redacted screenshot at full capture-pixel resolution (pre-crop,
 *    pre-downscale). The submit pipeline crops, re-projects marks, and encodes it.
 *  - [viewportPoints]: the still's size in density-independent points → `target.state`.
 *  - [imagePixelSize]: the bitmap's pixel size before the encode downscale ladder.
 *  - [accessibility]: id frames for the `CssSelector` hint.
 *  - [logEntries] / [contexts] / [tags]: diagnostics + scoped context snapshots.
 */
internal class HaviCaptureFrame(
    val bitmap: Bitmap,
    val bundleId: String,
    val screen: String,
    val viewportPoints: HaviSize,
    val imagePixelSize: HaviSize,
    val orientation: HaviCaptureOrientation,
    val accessibility: List<HaviAccessibilityFrame>,
    val logEntries: List<HaviLogEntry>,
    val contexts: Map<String, Map<String, String>>,
    val tags: Map<String, String>,
)
