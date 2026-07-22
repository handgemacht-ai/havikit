import CoreGraphics
import Foundation

/// Pure crop math for the capture sheet's crop tool (bead havi-oukr): the
/// corner/edge handle drag → new normalized crop rect, and the full-image
/// normalized → crop-relative normalized projection used to re-express marks
/// (and the reported viewport) once a crop is applied. Kept UIKit-free, like
/// `HaviCaptureGeometry`, so it runs under `swift test` without a Simulator.
///
/// The crop rect lives in the SAME normalized (0…1) space as the frozen still
/// and the markup marks — fractions of the FULL, uncropped image, never of the
/// image that will eventually be uploaded. Marks stay in that full-image space
/// while editing (so toggling crop never corrupts them); only at envelope-build
/// time are they projected into the cropped image's own 0…1 space via
/// `projectMarks`, after the real byte crop has already produced that image.
enum HaviCropGeometry {
    static let fullFrame = CGRect(x: 0, y: 0, width: 1, height: 1)

    /// Below this fraction on either axis, a crop stops shrinking further — a
    /// handle dragged past its opposite edge cannot collapse the rect to zero.
    static let minCropFraction: CGFloat = 0.1

    /// The eight discrete handles on the crop rect (Apple screenshot-editor
    /// pattern): four corners plus four edge midpoints.
    enum Handle: String, CaseIterable, Sendable {
        case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

        /// Leaf accessibility identifier for the handle's draggable control.
        var accessibilityIdentifier: String { "havi-crop-handle-\(rawValue)" }

        var accessibilityLabel: String {
            switch self {
            case .topLeft: return "Crop top-left handle"
            case .top: return "Crop top handle"
            case .topRight: return "Crop top-right handle"
            case .right: return "Crop right handle"
            case .bottomRight: return "Crop bottom-right handle"
            case .bottom: return "Crop bottom handle"
            case .bottomLeft: return "Crop bottom-left handle"
            case .left: return "Crop left handle"
            }
        }

        var movesLeftEdge: Bool { self == .topLeft || self == .left || self == .bottomLeft }
        var movesRightEdge: Bool { self == .topRight || self == .right || self == .bottomRight }
        var movesTopEdge: Bool { self == .topLeft || self == .top || self == .topRight }
        var movesBottomEdge: Bool { self == .bottomLeft || self == .bottom || self == .bottomRight }
    }

    // MARK: - Handle drag

    /// The point `handle` sits at on `rect` — used to position its draggable view.
    static func anchor(of handle: Handle, in rect: CGRect) -> CGPoint {
        switch handle {
        case .topLeft: return CGPoint(x: rect.minX, y: rect.minY)
        case .top: return CGPoint(x: rect.midX, y: rect.minY)
        case .topRight: return CGPoint(x: rect.maxX, y: rect.minY)
        case .right: return CGPoint(x: rect.maxX, y: rect.midY)
        case .bottomRight: return CGPoint(x: rect.maxX, y: rect.maxY)
        case .bottom: return CGPoint(x: rect.midX, y: rect.maxY)
        case .bottomLeft: return CGPoint(x: rect.minX, y: rect.maxY)
        case .left: return CGPoint(x: rect.minX, y: rect.midY)
        }
    }

    /// `rect` with `handle`'s edge(s) dragged to normalized `point` (0…1,
    /// full-image space), clamped to the image bounds and never smaller than
    /// `minCropFraction` on either axis — the opposite edge stays fixed.
    static func resize(_ rect: CGRect, handle: Handle, to point: CGPoint) -> CGRect {
        let x = min(max(0, point.x), 1)
        let y = min(max(0, point.y), 1)

        var minX = rect.minX, minY = rect.minY, maxX = rect.maxX, maxY = rect.maxY
        if handle.movesLeftEdge { minX = x }
        if handle.movesRightEdge { maxX = x }
        if handle.movesTopEdge { minY = y }
        if handle.movesBottomEdge { maxY = y }

        if maxX - minX < minCropFraction {
            if handle.movesLeftEdge { minX = maxX - minCropFraction }
            if handle.movesRightEdge { maxX = minX + minCropFraction }
        }
        if maxY - minY < minCropFraction {
            if handle.movesTopEdge { minY = maxY - minCropFraction }
            if handle.movesBottomEdge { maxY = minY + minCropFraction }
        }

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Defensive clamp of a crop rect into the full-image unit square.
    static func clamped(_ rect: CGRect) -> CGRect {
        let standardized = rect.standardized
        let minX = min(max(0, standardized.minX), 1)
        let minY = min(max(0, standardized.minY), 1)
        let maxX = min(max(minX, standardized.maxX), 1)
        let maxY = min(max(minY, standardized.maxY), 1)
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    // MARK: - Mark projection (full-image normalized → crop-relative normalized)

    /// A full-image-normalized point projected into the crop's own 0…1 space.
    /// Values land outside 0…1 for a point outside the crop — left for the
    /// existing per-point / per-rect pixel clamping (`HaviMarkupSerializer`,
    /// `HaviCaptureGeometry`) to clip once the mark reaches pixel space.
    static func project(_ point: CGPoint, into crop: CGRect) -> CGPoint {
        guard crop.width > 0, crop.height > 0 else { return point }
        return CGPoint(x: (point.x - crop.minX) / crop.width, y: (point.y - crop.minY) / crop.height)
    }

    /// Inverse of `project`: a crop-relative-normalized point back into the
    /// full-image 0…1 space.
    static func unproject(_ point: CGPoint, from crop: CGRect) -> CGPoint {
        CGPoint(x: crop.minX + point.x * crop.width, y: crop.minY + point.y * crop.height)
    }

    private static func project(_ rect: CGRect, into crop: CGRect) -> CGRect {
        let standardized = rect.standardized
        let origin = project(CGPoint(x: standardized.minX, y: standardized.minY), into: crop)
        let far = project(CGPoint(x: standardized.maxX, y: standardized.maxY), into: crop)
        return CGRect(x: origin.x, y: origin.y, width: far.x - origin.x, height: far.y - origin.y)
    }

    /// `mark`'s geometry re-expressed in crop-relative normalized space.
    static func project(_ mark: HaviMark, into crop: CGRect) -> HaviMark {
        var projected = mark
        switch mark.shape {
        case .pen(let points):
            projected.shape = .pen(points: points.map { project($0, into: crop) })
        case .highlighter(let points):
            projected.shape = .highlighter(points: points.map { project($0, into: crop) })
        case .arrow(let from, let to):
            projected.shape = .arrow(from: project(from, into: crop), to: project(to, into: crop))
        case .rectangle(let rect):
            projected.shape = .rectangle(project(rect, into: crop))
        case .blur(let rect):
            projected.shape = .blur(project(rect, into: crop))
        }
        return projected
    }

    /// True once `mark`'s (already crop-projected) bounds share no area with
    /// the crop's own unit square — dropped from the envelope entirely rather
    /// than clamped to a zero-width sliver at the edge.
    static func isFullyOutsideCrop(_ projectedMark: HaviMark) -> Bool {
        !fullFrame.intersects(projectedMark.normalizedBounds)
    }

    /// Projects every mark from full-image normalized space into the crop's
    /// own normalized space, dropping any that land fully outside it. A no-op
    /// (returns `marks` unchanged) when there is no crop, so the untouched path
    /// has zero behavior change.
    static func projectMarks(_ marks: [HaviMark], into crop: CGRect) -> [HaviMark] {
        let clampedCrop = clamped(crop)
        guard clampedCrop != fullFrame else { return marks }
        return marks
            .map { project($0, into: clampedCrop) }
            .filter { !isFullyOutsideCrop($0) }
    }

    /// The `state`'s `viewport=WxH` value (points) for the cropped image,
    /// proportional to the original session viewport so it stays consistent
    /// with the uploaded (cropped) image's aspect ratio.
    static func projectedViewport(_ viewport: HaviSize, crop: CGRect) -> HaviSize {
        let clampedCrop = clamped(crop)
        guard clampedCrop != fullFrame else { return viewport }
        return HaviSize(
            width: max(1, Int((CGFloat(viewport.width) * clampedCrop.width).rounded())),
            height: max(1, Int((CGFloat(viewport.height) * clampedCrop.height).rounded()))
        )
    }

    /// The pixel size of `imageSize` after cropping to `crop` — used by tests to
    /// predict the real byte-crop's output size without a `UIImage`.
    static func projectedImageSize(_ imageSize: HaviSize, crop: CGRect) -> HaviSize {
        let clampedCrop = clamped(crop)
        guard clampedCrop != fullFrame else { return imageSize }
        return HaviSize(
            width: max(1, Int((CGFloat(imageSize.width) * clampedCrop.width).rounded())),
            height: max(1, Int((CGFloat(imageSize.height) * clampedCrop.height).rounded()))
        )
    }

    // MARK: - Display transform (canvas point ↔ full-image normalized)

    /// The display transform that lets the canvas show ONLY a `visibleRegion` of
    /// the full still, scaled up to fill a content rect of `contentSize` points.
    /// Marks and gestures always speak full-image normalized space (0…1 over the
    /// whole still); these two functions are the only bridge to canvas points,
    /// so the stored geometry — and the submit pipeline that reads it — is
    /// untouched by the zoom. When `visibleRegion` is the full frame both reduce
    /// to the plain point ÷ size mapping the canvas used before the zoom existed.

    /// A content-local canvas point (0…`contentSize`) → full-image normalized
    /// point, clamped to `visibleRegion` so a mark drawn in the zoomed view can
    /// never land outside what is shown.
    static func normalizedFromCanvas(_ point: CGPoint, contentSize: CGSize, visibleRegion: CGRect) -> CGPoint {
        guard contentSize.width > 0, contentSize.height > 0 else { return visibleRegion.origin }
        let relative = CGPoint(
            x: min(max(0, point.x / contentSize.width), 1),
            y: min(max(0, point.y / contentSize.height), 1)
        )
        return unproject(relative, from: visibleRegion)
    }

    /// A full-image normalized point → content-local canvas point within the
    /// zoomed `visibleRegion`. Points outside the region land outside
    /// `0…contentSize` and are clipped by the content view's bounds.
    static func canvasFromNormalized(_ point: CGPoint, contentSize: CGSize, visibleRegion: CGRect) -> CGPoint {
        let relative = project(point, into: visibleRegion)
        return CGPoint(x: relative.x * contentSize.width, y: relative.y * contentSize.height)
    }
}
