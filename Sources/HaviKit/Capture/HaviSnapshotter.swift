#if canImport(UIKit)
import UIKit

/// The frozen key-window capture for one shake→sheet cycle (design §2). Carries
/// the redacted still, the logical viewport (points), the a11y-id frames used to
/// derive the display-only `CssSelector`, and the interface orientation for the
/// `device-info` body.
struct HaviSnapshot {
    let image: UIImage
    let viewport: HaviSize
    let a11yFrames: [HaviA11yFrame]
    let orientation: String
}

/// An accessibility identifier and its frame in window points, captured at
/// freeze time so the sheet can name the nearest control under the markup
/// rectangle without retaining live view references.
struct HaviA11yFrame {
    let identifier: String
    let frame: CGRect
}

/// Grabs the key window synchronously and paints the redaction rects **before**
/// the bytes exist (design §2): masked-by-default text inputs (policy) plus every
/// `.haviRedacted()` frame, minus any `.haviReveal()` area. The still guarantees
/// the markup coordinates match the screenshot exactly (top-window point space).
@MainActor
enum HaviSnapshotter {
    static func capture(policy: HaviRedactionPolicy) -> HaviSnapshot? {
        guard let window = keyWindow() else { return nil }

        let bounds = window.bounds
        guard bounds.width > 0, bounds.height > 0 else { return nil }

        let revealFrames = HaviRedactionRelay.shared.revealFrames()
        var maskFrames = HaviRedactionRelay.shared.maskFrames()
        if policy.maskTextFieldsByDefault {
            maskFrames.append(contentsOf: textInputFrames(in: window, excluding: revealFrames))
        }

        let a11yFrames = accessibilityFrames(in: window)

        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(bounds: bounds, format: format)
        let image = renderer.image { context in
            // `afterScreenUpdates: false` freezes the live pixels as-drawn; a
            // pending layout pass must not be able to reveal masked content.
            window.drawHierarchy(in: bounds, afterScreenUpdates: false)
            UIColor.black.setFill()
            for frame in maskFrames {
                context.fill(frame.intersection(bounds))
            }
        }

        return HaviSnapshot(
            image: image,
            viewport: HaviSize(width: Int(bounds.width.rounded()), height: Int(bounds.height.rounded())),
            a11yFrames: a11yFrames,
            orientation: orientationName(for: window)
        )
    }

    /// The smallest a11y-id frame that contains `point` (window points), or nil —
    /// the nearest labelled control under the markup, for the `CssSelector` hint.
    static func nearestIdentifier(at point: CGPoint, in frames: [HaviA11yFrame]) -> String? {
        frames
            .filter { $0.frame.contains(point) }
            .min(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height })?
            .identifier
    }

    // MARK: - Window

    private static func keyWindow() -> UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let foreground = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
        return foreground?.windows.first(where: \.isKeyWindow) ?? foreground?.windows.first
    }

    private static func orientationName(for window: UIWindow) -> String {
        switch window.windowScene?.interfaceOrientation {
        case .portrait: return "portrait"
        case .portraitUpsideDown: return "portraitUpsideDown"
        case .landscapeLeft: return "landscapeLeft"
        case .landscapeRight: return "landscapeRight"
        default: return "unknown"
        }
    }

    // MARK: - Hierarchy walks

    /// Text-input views (SwiftUI `TextField` / `SecureField` are backed by
    /// `UITextField`; `TextEditor` by `UITextView`), in window points, dropping
    /// any whose frame sits inside an explicit `.haviReveal()` region.
    private static func textInputFrames(in window: UIWindow, excluding revealFrames: [CGRect]) -> [CGRect] {
        var frames: [CGRect] = []
        walk(window) { view in
            guard view is UITextField || view is UITextView, !view.isHidden, view.alpha > 0.01 else { return }
            let frame = view.convert(view.bounds, to: window)
            guard frame.width > 0, frame.height > 0 else { return }
            if revealFrames.contains(where: { $0.contains(frame.center) }) { return }
            frames.append(frame)
        }
        return frames
    }

    private static func accessibilityFrames(in window: UIWindow) -> [HaviA11yFrame] {
        var out: [HaviA11yFrame] = []
        walk(window) { view in
            guard let identifier = view.accessibilityIdentifier, !identifier.isEmpty else { return }
            let frame = view.convert(view.bounds, to: window)
            guard frame.width > 0, frame.height > 0 else { return }
            out.append(HaviA11yFrame(identifier: identifier, frame: frame))
        }
        return out
    }

    private static func walk(_ view: UIView, _ visit: (UIView) -> Void) {
        visit(view)
        for subview in view.subviews {
            walk(subview, visit)
        }
    }
}

private extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}
#endif
