#if canImport(UIKit)
import SwiftUI
import UIKit

/// The v2 markup surface (bead havi-6953): the frozen screenshot with a live
/// SwiftUI `Canvas` overlay that renders the editor's typed vector marks — pen,
/// highlighter, arrow, rectangle, and blur/redact regions — plus the in-progress
/// stroke and the current selection. Drawing happens over the still (never live
/// UI) so mark coordinates stay aligned with the screenshot. All geometry is kept
/// normalized (0…1) in `HaviMarkupModel`; this view only converts display points
/// to and from that space.
struct HaviMarkupCanvas: View {
    let image: UIImage
    @Bindable var model: HaviMarkupModel

    @State private var strokeActive = false

    var body: some View {
        GeometryReader { proxy in
            let fitted = fittedRect(in: proxy.size)
            ZStack(alignment: .topLeading) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()

                Canvas { context, size in
                    for mark in model.marks {
                        draw(mark, in: context, size: size, selected: mark.id == model.selectedMarkID)
                    }
                    if let inProgress = model.inProgress {
                        draw(inProgress, in: context, size: size, selected: false)
                    }
                }
                .frame(width: fitted.width, height: fitted.height)
                .offset(x: fitted.minX, y: fitted.minY)
                .contentShape(Rectangle())
                .highPriorityGesture(drawGesture(canvasSize: fitted.size))
                .accessibilityIdentifier("havi-markup-canvas")
            }
        }
        .aspectRatio(imageAspect, contentMode: .fit)
    }

    // MARK: - Gesture

    private func drawGesture(canvasSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                let point = normalized(value.location, in: canvasSize)
                if strokeActive {
                    model.extend(to: point)
                } else {
                    strokeActive = true
                    model.begin(at: point)
                }
            }
            .onEnded { _ in
                strokeActive = false
                model.end()
            }
    }

    private func normalized(_ point: CGPoint, in size: CGSize) -> CGPoint {
        guard size.width > 0, size.height > 0 else { return .zero }
        return CGPoint(
            x: min(max(0, point.x / size.width), 1),
            y: min(max(0, point.y / size.height), 1)
        )
    }

    // MARK: - Rendering

    private func draw(_ mark: HaviMark, in context: GraphicsContext, size: CGSize, selected: Bool) {
        let color = mark.color.swiftUIColor
        switch mark.shape {
        case .pen(let points):
            context.stroke(strokePath(points, size: size), with: .color(color), style: roundStyle(lineWidth: 4))
        case .highlighter(let points):
            context.stroke(strokePath(points, size: size), with: .color(color.opacity(0.35)), style: roundStyle(lineWidth: 16))
        case .arrow(let from, let to):
            drawArrow(from: from, to: to, color: color, in: context, size: size)
        case .rectangle(let rect):
            context.stroke(Path(displayRect(rect, size: size)), with: .color(color), style: StrokeStyle(lineWidth: 4))
        case .blur(let rect):
            drawBlurPlaceholder(displayRect(rect, size: size), in: context)
        }
        if selected {
            drawSelection(mark.normalizedBounds, size: size, in: context)
        }
    }

    private func drawArrow(from: CGPoint, to: CGPoint, color: Color, in context: GraphicsContext, size: CGSize) {
        let tail = display(from, size: size)
        let tip = display(to, size: size)
        var shaft = Path()
        shaft.move(to: tail)
        shaft.addLine(to: tip)
        context.stroke(shaft, with: .color(color), style: roundStyle(lineWidth: 4))

        let head = HaviMarkupSerializer.arrowHead(tip: tip, tail: tail, length: 20, width: 16)
        var headPath = Path()
        if let first = head.first {
            headPath.move(to: first)
            for point in head.dropFirst() { headPath.addLine(to: point) }
            headPath.closeSubpath()
        }
        context.fill(headPath, with: .color(color))
    }

    private func drawBlurPlaceholder(_ rect: CGRect, in context: GraphicsContext) {
        let path = Path(roundedRect: rect, cornerRadius: 4)
        context.fill(path, with: .color(Color(white: 0.22).opacity(0.94)))
        context.stroke(path, with: .color(.white.opacity(0.65)), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
    }

    private func drawSelection(_ bounds: CGRect, size: CGSize, in context: GraphicsContext) {
        let rect = displayRect(bounds, size: size).insetBy(dx: -6, dy: -6)
        context.stroke(
            Path(roundedRect: rect, cornerRadius: 6),
            with: .color(Self.accent),
            style: StrokeStyle(lineWidth: 1.5, dash: [5, 3])
        )
    }

    private func strokePath(_ points: [CGPoint], size: CGSize) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: display(first, size: size))
        for point in points.dropFirst() { path.addLine(to: display(point, size: size)) }
        return path
    }

    private func roundStyle(lineWidth: CGFloat) -> StrokeStyle {
        StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
    }

    private func display(_ point: CGPoint, size: CGSize) -> CGPoint {
        CGPoint(x: point.x * size.width, y: point.y * size.height)
    }

    private func displayRect(_ rect: CGRect, size: CGSize) -> CGRect {
        let standardized = rect.standardized
        return CGRect(
            x: standardized.minX * size.width,
            y: standardized.minY * size.height,
            width: standardized.width * size.width,
            height: standardized.height * size.height
        )
    }

    // MARK: - Layout

    private var imageAspect: CGFloat {
        image.size.height > 0 ? image.size.width / image.size.height : 1
    }

    private func fittedRect(in size: CGSize) -> CGRect {
        guard image.size.width > 0, image.size.height > 0 else {
            return CGRect(origin: .zero, size: size)
        }
        let scale = min(size.width / image.size.width, size.height / image.size.height)
        let width = image.size.width * scale
        let height = image.size.height * scale
        return CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2, width: width, height: height)
    }

    /// Brand accent (HAVI red #E8542F), shared by the submit button, priority
    /// segments, and the floating capture button.
    static let accent = Color(red: 0.909, green: 0.329, blue: 0.184)
}

extension HaviMarkColor {
    var swiftUIColor: Color { Color(red: red, green: green, blue: blue) }
}
#endif
