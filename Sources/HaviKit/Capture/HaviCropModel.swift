#if canImport(UIKit)
import CoreGraphics
import Observation

/// The crop tool's editor state (bead havi-oukr): the normalized crop rect,
/// defaulting to the full frame, moved by dragging one of the eight
/// `HaviCropGeometry.Handle`s. Kept separate from `HaviMarkupModel`'s
/// mark/undo stack — a mis-dragged crop is recovered with `reset()`, not object
/// undo, since it is one rect rather than a history of discrete marks.
@MainActor
@Observable
final class HaviCropModel {
    private(set) var rect: CGRect = HaviCropGeometry.fullFrame

    var isCropped: Bool { rect != HaviCropGeometry.fullFrame }

    /// Applies one handle-drag update: `point` is the drag location normalized
    /// (0…1) to the canvas the handle is drawn in.
    func updateResize(handle: HaviCropGeometry.Handle, to point: CGPoint) {
        rect = HaviCropGeometry.resize(rect, handle: handle, to: point)
    }

    /// The recovery affordance for a mis-dragged crop (design: "recoverable").
    func reset() {
        rect = HaviCropGeometry.fullFrame
    }
}
#endif
