import CoreGraphics
import Foundation

/// Pure coordinate math for the capture sheet (design §2, §3). The markup
/// rectangle is tracked in the sheet as a **normalized** rect (fractions of the
/// frozen image, 0…1) so it is resolution-independent; at submit time it is
/// projected into the **downscaled image-pixel** space of the encoded screenshot,
/// which is the space the `FragmentSelector` / `SvgSelector` coordinates live in.
/// Kept UIKit-free so the projection is unit-testable without a Simulator.
enum HaviCaptureGeometry {
    /// Projects a normalized rect (0…1 in image space) onto integer image pixels,
    /// clamped to the image bounds. A zero-area or nil result is treated by the
    /// caller as "no markup".
    static func imagePixelRect(fraction: CGRect, imageSize: HaviSize) -> HaviRect {
        let clamped = clampUnit(fraction)
        let x = Int((clamped.minX * CGFloat(imageSize.width)).rounded())
        let y = Int((clamped.minY * CGFloat(imageSize.height)).rounded())
        let w = Int((clamped.width * CGFloat(imageSize.width)).rounded())
        let h = Int((clamped.height * CGFloat(imageSize.height)).rounded())
        return HaviRect(
            x: min(max(0, x), imageSize.width),
            y: min(max(0, y), imageSize.height),
            width: max(0, min(w, imageSize.width - min(max(0, x), imageSize.width))),
            height: max(0, min(h, imageSize.height - min(max(0, y), imageSize.height)))
        )
    }

    /// The full-frame region used for the `FragmentSelector` when there is no
    /// drawn markup (design §3).
    static func fullFrameRect(imageSize: HaviSize) -> HaviRect {
        HaviRect(x: 0, y: 0, width: imageSize.width, height: imageSize.height)
    }

    /// A drawn rectangle is meaningful only when it covers a non-trivial area;
    /// an accidental tap (near-zero drag) is treated as no markup.
    static func isMeaningful(fraction: CGRect) -> Bool {
        let clamped = clampUnit(fraction)
        return clamped.width >= minMarkupFraction && clamped.height >= minMarkupFraction
    }

    /// The display-only `CssSelector` value (design §3): `"<screen>"` alone, or
    /// `"<screen> > <a11y-id>"` when a nearest accessibility identifier resolved
    /// under the markup rectangle. Never browser-resolvable — grouping/display
    /// only, the same role the web `CssSelector` fallback plays.
    static func cssPath(screen: String, hint: String?) -> String {
        guard let hint, !hint.isEmpty else { return screen }
        return "\(screen) > \(hint)"
    }

    static let minMarkupFraction: CGFloat = 0.01

    private static func clampUnit(_ rect: CGRect) -> CGRect {
        let x = min(max(0, rect.minX), 1)
        let y = min(max(0, rect.minY), 1)
        let maxX = min(max(0, rect.maxX), 1)
        let maxY = min(max(0, rect.maxY), 1)
        return CGRect(x: x, y: y, width: max(0, maxX - x), height: max(0, maxY - y))
    }
}
