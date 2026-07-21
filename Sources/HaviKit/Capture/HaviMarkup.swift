import CoreGraphics
import Foundation

/// The markup toolset v2 (bead havi-6953). Each tool produces a typed vector mark
/// stored in **normalized** image coordinates (0…1) — resolution-independent like
/// the v1 `markupFraction` — projected into image-pixel space at submit time by
/// `HaviMarkupSerializer`. Kept UIKit-free so the model + serialization run under
/// `swift test` on the Mac host without a Simulator.
public enum HaviMarkTool: String, CaseIterable, Sendable {
    case pen
    case highlighter
    case arrow
    case rectangle
    case blur
    case select

    /// Leaf accessibility identifier for the tool's toolbar button.
    public var accessibilityIdentifier: String { "havi-tool-\(rawValue)" }

    /// SF Symbol shown on the toolbar button.
    public var systemImage: String {
        switch self {
        case .pen: return "scribble.variable"
        case .highlighter: return "highlighter"
        case .arrow: return "arrow.up.right"
        case .rectangle: return "rectangle"
        case .blur: return "eye.slash"
        case .select: return "hand.point.up.left"
        }
    }

    public var title: String {
        switch self {
        case .pen: return "Pen"
        case .highlighter: return "Highlighter"
        case .arrow: return "Arrow"
        case .rectangle: return "Rectangle"
        case .blur: return "Redact"
        case .select: return "Select"
        }
    }

    /// Whether the tool draws a new mark (vs. `select`, which edits existing).
    public var isDrawing: Bool { self != .select }
}

/// A markup color preset. Stores the RGB components (for the SwiftUI swatch) and
/// the `#RRGGBB` hex used verbatim in the SVG `stroke` / `fill` (design §3). Brand
/// red (`#E8542F`) is the default, preserved from v1's hardcoded stroke color.
public struct HaviMarkColor: Equatable, Sendable {
    public let name: String
    public let hex: String
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(name: String, hex: String, red: Double, green: Double, blue: Double) {
        self.name = name
        self.hex = hex
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// Leaf accessibility identifier for the swatch button.
    public var accessibilityIdentifier: String { "havi-color-\(name)" }

    public static let red = HaviMarkColor(name: "red", hex: "#E8542F", red: 0.909, green: 0.329, blue: 0.184)
    public static let yellow = HaviMarkColor(name: "yellow", hex: "#F5C518", red: 0.961, green: 0.773, blue: 0.094)
    public static let green = HaviMarkColor(name: "green", hex: "#34C759", red: 0.204, green: 0.780, blue: 0.349)
    public static let blue = HaviMarkColor(name: "blue", hex: "#0A84FF", red: 0.039, green: 0.518, blue: 1.0)
    public static let black = HaviMarkColor(name: "black", hex: "#000000", red: 0.0, green: 0.0, blue: 0.0)
    public static let white = HaviMarkColor(name: "white", hex: "#FFFFFF", red: 1.0, green: 1.0, blue: 1.0)

    /// Swatch row, red first (design: 6 presets, red default).
    public static let presets: [HaviMarkColor] = [.red, .yellow, .green, .blue, .black, .white]
}

/// One typed vector mark in normalized image space. `blur` marks are **redaction**
/// regions: they are burned into the screenshot pixels before send and are never
/// serialized into the envelope's SVG or selectors (design: pre-byte redaction).
public struct HaviMark: Identifiable, Equatable, Sendable {
    public enum Shape: Equatable, Sendable {
        case pen(points: [CGPoint])
        case highlighter(points: [CGPoint])
        case arrow(from: CGPoint, to: CGPoint)
        case rectangle(CGRect)
        case blur(CGRect)
    }

    public let id: UUID
    public var shape: Shape
    public var color: HaviMarkColor

    public init(id: UUID = UUID(), shape: Shape, color: HaviMarkColor) {
        self.id = id
        self.shape = shape
        self.color = color
    }

    public var isBlur: Bool {
        if case .blur = shape { return true }
        return false
    }

    /// Normalized bounding box (0…1) of the mark's geometry, standardized so
    /// width/height are non-negative regardless of draw direction.
    public var normalizedBounds: CGRect {
        switch shape {
        case .pen(let points), .highlighter(let points):
            return HaviMark.bounds(of: points)
        case .arrow(let from, let to):
            return HaviMark.bounds(of: [from, to])
        case .rectangle(let rect), .blur(let rect):
            return rect.standardized
        }
    }

    /// Shift the mark's geometry by a normalized offset (select → drag to move).
    public mutating func translate(by offset: CGVector) {
        switch shape {
        case .pen(let points):
            shape = .pen(points: points.map { $0.applying(.init(translationX: offset.dx, y: offset.dy)) })
        case .highlighter(let points):
            shape = .highlighter(points: points.map { $0.applying(.init(translationX: offset.dx, y: offset.dy)) })
        case .arrow(let from, let to):
            shape = .arrow(
                from: from.applying(.init(translationX: offset.dx, y: offset.dy)),
                to: to.applying(.init(translationX: offset.dx, y: offset.dy))
            )
        case .rectangle(let rect):
            shape = .rectangle(rect.offsetBy(dx: offset.dx, dy: offset.dy))
        case .blur(let rect):
            shape = .blur(rect.offsetBy(dx: offset.dx, dy: offset.dy))
        }
    }

    /// Hit test for the select tool: the mark's bounds expanded by `tolerance`
    /// contains `point`. Coarse on purpose — thumb-sized targets over thin strokes.
    public func hitTest(_ point: CGPoint, tolerance: CGFloat) -> Bool {
        normalizedBounds.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
    }

    static func bounds(of points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return .zero }
        var minX = first.x, minY = first.y, maxX = first.x, maxY = first.y
        for point in points.dropFirst() {
            minX = Swift.min(minX, point.x)
            minY = Swift.min(minY, point.y)
            maxX = Swift.max(maxX, point.x)
            maxY = Swift.max(maxY, point.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
