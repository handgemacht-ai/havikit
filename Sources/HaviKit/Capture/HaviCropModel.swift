#if canImport(UIKit)
import CoreGraphics
import Observation

/// The crop tool's editor state (bead havi-od6t): the normalized crop rect,
/// defaulting to the full frame, moved by dragging one of the eight
/// `HaviCropGeometry.Handle`s. Crop is now a **confirmed step** — selecting the
/// crop tool opens crop mode (`isEditing`), where `rect` tracks the live draft;
/// `confirm()` keeps it and zooms the canvas into it, `cancel()` reverts to the
/// last confirmed crop. Kept separate from `HaviMarkupModel`'s mark/undo stack —
/// a mis-dragged crop is recovered with `reset()` / `cancel()`, not object undo,
/// since it is one rect rather than a history of discrete marks.
@MainActor
@Observable
final class HaviCropModel {
    /// The confirmed crop AND the live draft while editing — one rect so the
    /// submit pipeline keeps reading `crop.rect` unchanged and the overlay shows
    /// a WYSIWYG box. `confirmedRect` snapshots the value `cancel()` restores.
    private(set) var rect: CGRect = HaviCropGeometry.fullFrame
    private(set) var isEditing = false
    private var confirmedRect: CGRect = HaviCropGeometry.fullFrame

    var isCropped: Bool { rect != HaviCropGeometry.fullFrame }

    /// Enters crop mode from the current confirmed crop, so a re-crop can widen
    /// (not only narrow) the existing region.
    func beginEditing() {
        confirmedRect = rect
        isEditing = true
    }

    /// Applies one handle-drag update to the live draft: `point` is the drag
    /// location normalized (0…1) to the full still.
    func updateResize(handle: HaviCropGeometry.Handle, to point: CGPoint) {
        rect = HaviCropGeometry.resize(rect, handle: handle, to: point)
    }

    /// Keeps the draft as the confirmed crop and leaves crop mode.
    func confirm() {
        rect = HaviCropGeometry.clamped(rect)
        isEditing = false
    }

    /// Discards the draft, restoring the last confirmed crop, and leaves crop mode.
    func cancel() {
        rect = confirmedRect
        isEditing = false
    }

    /// Widens the draft back to the full frame while staying in crop mode — the
    /// recovery affordance for a mis-dragged crop (design: "recoverable").
    func reset() {
        rect = HaviCropGeometry.fullFrame
    }
}
#endif
