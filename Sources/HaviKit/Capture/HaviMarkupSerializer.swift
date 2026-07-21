import CoreGraphics
import Foundation

/// Serializes the v2 markup marks into the envelope's geometry (design §3): one
/// `SvgSelector` `<svg>` holding every non-blur mark in image-pixel space, and the
/// `FragmentSelector`'s bounding-box union of those same marks. `blur` marks are
/// **excluded** from both — they are redaction, burned into the screenshot pixels
/// (`HaviImageRedactor`) before any bytes leave the device, never described in the
/// envelope. Pure (CoreGraphics only) so it runs under `swift test` without UIKit.
enum HaviMarkupSerializer {
    /// Stroke widths in image-pixel space (design: one sensible default per tool,
    /// no width picker in v2). `rectangle` stays 6 to preserve the v1 SVG bytes.
    static let penWidth = 6
    static let highlighterWidth = 24
    static let arrowWidth = 6
    static let rectangleWidth = 6

    /// Arrowhead geometry in image-pixel space.
    static let arrowHeadLength: CGFloat = 34
    static let arrowHeadWidth: CGFloat = 26

    /// Highlighter is the pen at reduced opacity (design: same as pen, semi-transparent).
    static let highlighterStrokeOpacity = "0.35"

    /// The `SvgSelector` value for all non-blur marks, or nil when there are none
    /// (design §3: omit the `SvgSelector` when there is no markup).
    static func svg(for marks: [HaviMark], imageSize: HaviSize) -> String? {
        let drawable = marks.filter { !$0.isBlur }
        guard !drawable.isEmpty else { return nil }
        let body = drawable.map { element(for: $0, imageSize: imageSize) }.joined()
        return "<svg xmlns=\"http://www.w3.org/2000/svg\">\(body)</svg>"
    }

    /// The `FragmentSelector` region: image-pixel bounding-box union of every
    /// non-blur mark, or nil when there are none (the caller then uses the full
    /// frame, design §3).
    static func boundingBox(of marks: [HaviMark], imageSize: HaviSize) -> HaviRect? {
        guard let union = normalizedBoundingBox(of: marks) else { return nil }
        return HaviCaptureGeometry.imagePixelRect(fraction: union, imageSize: imageSize)
    }

    /// Normalized (0…1) bounding-box union of non-blur marks — used to place the
    /// `CssSelector` hint's centre before projection.
    static func normalizedBoundingBox(of marks: [HaviMark]) -> CGRect? {
        let drawable = marks.filter { !$0.isBlur }
        guard !drawable.isEmpty else { return nil }
        return drawable.dropFirst().reduce(drawable[0].normalizedBounds) { $0.union($1.normalizedBounds) }
    }

    /// Normalized redaction rects to burn into the pixels before send.
    static func blurRects(of marks: [HaviMark]) -> [CGRect] {
        marks.compactMap {
            if case .blur(let rect) = $0.shape { return rect.standardized }
            return nil
        }
    }

    /// The filled arrowhead triangle for a shaft `tail`→`tip`: the tip plus the two
    /// base barbs, offset back along the shaft by `length` and out by `width/2`.
    /// Pure and deterministic so arrow geometry is unit-testable.
    static func arrowHead(tip: CGPoint, tail: CGPoint, length: CGFloat, width: CGFloat) -> [CGPoint] {
        let dx = tip.x - tail.x
        let dy = tip.y - tail.y
        let shaft = (dx * dx + dy * dy).squareRoot()
        guard shaft > 0 else { return [tip, tip, tip] }
        let ux = dx / shaft
        let uy = dy / shaft
        let px = -uy
        let py = ux
        let base = CGPoint(x: tip.x - ux * length, y: tip.y - uy * length)
        let left = CGPoint(x: base.x + px * width / 2, y: base.y + py * width / 2)
        let right = CGPoint(x: base.x - px * width / 2, y: base.y - py * width / 2)
        return [tip, left, right]
    }

    // MARK: - SVG elements

    private static func element(for mark: HaviMark, imageSize: HaviSize) -> String {
        let hex = mark.color.hex
        switch mark.shape {
        case .pen(let points):
            return path(points, imageSize: imageSize, stroke: hex, width: penWidth, opacity: nil)
        case .highlighter(let points):
            return path(points, imageSize: imageSize, stroke: hex, width: highlighterWidth, opacity: highlighterStrokeOpacity)
        case .arrow(let from, let to):
            return arrow(from: from, to: to, imageSize: imageSize, stroke: hex)
        case .rectangle(let rect):
            return rectElement(rect, imageSize: imageSize, stroke: hex, width: rectangleWidth)
        case .blur:
            return ""
        }
    }

    private static func rectElement(_ rect: CGRect, imageSize: HaviSize, stroke: String, width: Int) -> String {
        let pixels = HaviCaptureGeometry.imagePixelRect(fraction: rect.standardized, imageSize: imageSize)
        return "<rect x=\"\(pixels.x)\" y=\"\(pixels.y)\" width=\"\(pixels.width)\" height=\"\(pixels.height)\" "
            + "fill=\"none\" stroke=\"\(stroke)\" stroke-width=\"\(width)\"/>"
    }

    private static func path(_ points: [CGPoint], imageSize: HaviSize, stroke: String, width: Int, opacity: String?) -> String {
        guard let first = points.first else { return "" }
        var d = "M \(pixelX(first, imageSize)) \(pixelY(first, imageSize))"
        for point in points.dropFirst() {
            d += " L \(pixelX(point, imageSize)) \(pixelY(point, imageSize))"
        }
        let opacityAttr = opacity.map { " stroke-opacity=\"\($0)\"" } ?? ""
        return "<path d=\"\(d)\" fill=\"none\" stroke=\"\(stroke)\" stroke-width=\"\(width)\" "
            + "stroke-linecap=\"round\" stroke-linejoin=\"round\"\(opacityAttr)/>"
    }

    private static func arrow(from: CGPoint, to: CGPoint, imageSize: HaviSize, stroke: String) -> String {
        let tip = CGPoint(x: CGFloat(pixelX(to, imageSize)), y: CGFloat(pixelY(to, imageSize)))
        let tail = CGPoint(x: CGFloat(pixelX(from, imageSize)), y: CGFloat(pixelY(from, imageSize)))
        let head = arrowHead(tip: tip, tail: tail, length: arrowHeadLength, width: arrowHeadWidth)
        let points = head.map { "\(Int($0.x.rounded())),\(Int($0.y.rounded()))" }.joined(separator: " ")
        return "<line x1=\"\(Int(tail.x.rounded()))\" y1=\"\(Int(tail.y.rounded()))\" "
            + "x2=\"\(Int(tip.x.rounded()))\" y2=\"\(Int(tip.y.rounded()))\" "
            + "stroke=\"\(stroke)\" stroke-width=\"\(arrowWidth)\" stroke-linecap=\"round\"/>"
            + "<polygon points=\"\(points)\" fill=\"\(stroke)\"/>"
    }

    private static func pixelX(_ point: CGPoint, _ size: HaviSize) -> Int {
        clamp(Int((clampUnit(point.x) * CGFloat(size.width)).rounded()), size.width)
    }

    private static func pixelY(_ point: CGPoint, _ size: HaviSize) -> Int {
        clamp(Int((clampUnit(point.y) * CGFloat(size.height)).rounded()), size.height)
    }

    private static func clampUnit(_ value: CGFloat) -> CGFloat { min(max(0, value), 1) }

    private static func clamp(_ value: Int, _ upper: Int) -> Int { min(max(0, value), upper) }
}
