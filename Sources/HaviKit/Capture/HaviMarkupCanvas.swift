#if canImport(UIKit)
import SwiftUI
import UIKit

/// The frozen still with single-rectangle markup (design §2, v1 = one gesture).
/// The developer drags to draw one rectangle to "point at the bug"; the rect is
/// reported as a **normalized** fraction of the image (0…1) so the model can
/// project it into image-pixel space at submit time regardless of display size.
/// Drawing over the still — never live UI — keeps markup coordinates aligned with
/// the screenshot.
struct HaviMarkupCanvas: View {
    let image: UIImage
    @Binding var markupFraction: CGRect?

    @State private var dragStart: CGPoint?
    @State private var dragCurrent: CGPoint?

    var body: some View {
        GeometryReader { proxy in
            let displayed = fittedRect(in: proxy.size)
            ZStack {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()

                if let rect = currentDisplayRect(in: displayed) {
                    Rectangle()
                        .stroke(Self.accent, lineWidth: 3)
                        .background(Rectangle().fill(Self.accent.opacity(0.12)))
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { value in
                        if dragStart == nil { dragStart = value.startLocation }
                        dragCurrent = value.location
                        markupFraction = normalizedRect(in: displayed)
                    }
                    .onEnded { _ in
                        markupFraction = normalizedRect(in: displayed)
                        dragStart = nil
                        dragCurrent = nil
                    }
            )
        }
        .aspectRatio(imageAspect, contentMode: .fit)
    }

    private var imageAspect: CGFloat {
        image.size.height > 0 ? image.size.width / image.size.height : 1
    }

    /// The letterboxed rect the `scaledToFit` image occupies inside `size`.
    private func fittedRect(in size: CGSize) -> CGRect {
        guard image.size.width > 0, image.size.height > 0 else {
            return CGRect(origin: .zero, size: size)
        }
        let scale = min(size.width / image.size.width, size.height / image.size.height)
        let width = image.size.width * scale
        let height = image.size.height * scale
        return CGRect(
            x: (size.width - width) / 2,
            y: (size.height - height) / 2,
            width: width,
            height: height
        )
    }

    private func currentDisplayRect(in displayed: CGRect) -> CGRect? {
        if let start = dragStart, let current = dragCurrent {
            return rect(from: start, to: current).intersection(displayed)
        }
        guard let fraction = markupFraction else { return nil }
        return CGRect(
            x: displayed.minX + fraction.minX * displayed.width,
            y: displayed.minY + fraction.minY * displayed.height,
            width: fraction.width * displayed.width,
            height: fraction.height * displayed.height
        )
    }

    private func normalizedRect(in displayed: CGRect) -> CGRect? {
        guard let start = dragStart, let current = dragCurrent, displayed.width > 0, displayed.height > 0 else {
            return markupFraction
        }
        let drawn = rect(from: start, to: current).intersection(displayed)
        guard drawn.width > 0, drawn.height > 0 else { return nil }
        return CGRect(
            x: (drawn.minX - displayed.minX) / displayed.width,
            y: (drawn.minY - displayed.minY) / displayed.height,
            width: drawn.width / displayed.width,
            height: drawn.height / displayed.height
        )
    }

    private func rect(from a: CGPoint, to b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    static let accent = Color(red: 0.91, green: 0.33, blue: 0.18)
}
#endif
