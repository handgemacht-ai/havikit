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
///
/// The crop tool (bead havi-oukr) layers on top: a persistent dimmed-outside /
/// bright-inside preview of `HaviCropModel`'s rect, plus eight discrete
/// draggable handle views (Apple screenshot-editor pattern) shown while `.crop`
/// is the active tool. The crop rect lives in the same full-image normalized
/// space as the marks; nothing here projects it — that happens once, at
/// envelope-build time, via `HaviCropGeometry`.
struct HaviMarkupCanvas: View {
    let image: UIImage
    @Bindable var model: HaviMarkupModel
    @Bindable var crop: HaviCropModel

    @State private var strokeActive = false
    @State private var cropGrabOffset: CGSize?

    private static let cropCoordinateSpace = "haviCropSurface"

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

                if crop.isCropped {
                    cropDimOverlay(size: fitted.size)
                        .frame(width: fitted.width, height: fitted.height)
                        .offset(x: fitted.minX, y: fitted.minY)
                        .allowsHitTesting(false)
                }

                if model.tool == .crop {
                    cropInteractionOverlay(size: fitted.size)
                        .offset(x: fitted.minX, y: fitted.minY)
                }
            }
        }
        .aspectRatio(imageAspect, contentMode: .fit)
    }

    // MARK: - Crop overlay (design: dimmed outside, bright inside, draggable handles)

    /// The persistent "this is what will actually be uploaded" preview: a
    /// dark scrim over everything outside the crop rect, shown regardless of
    /// which tool is active so a crop never surprises the user at submit time.
    private func cropDimOverlay(size: CGSize) -> some View {
        let cropRect = displayRect(crop.rect, size: size)
        return Path { path in
            path.addRect(CGRect(origin: .zero, size: size))
            path.addRect(cropRect)
        }
        .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
    }

    /// The crop tool's live border + eight draggable handles, mounted only
    /// while `.crop` is the active tool.
    private func cropInteractionOverlay(size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            cropBorder(size: size)
                .allowsHitTesting(false)
            ForEach(HaviCropGeometry.Handle.allCases, id: \.self) { handle in
                cropHandle(handle, size: size)
            }
        }
        .frame(width: size.width, height: size.height)
        .coordinateSpace(name: Self.cropCoordinateSpace)
    }

    private func cropBorder(size: CGSize) -> some View {
        Path(displayRect(crop.rect, size: size))
            .stroke(Color.white, style: StrokeStyle(lineWidth: 2))
    }

    private func cropHandle(_ handle: HaviCropGeometry.Handle, size: CGSize) -> some View {
        let point = display(HaviCropGeometry.anchor(of: handle, in: crop.rect), size: size)
        return Circle()
            .fill(Color.white)
            .frame(width: 14, height: 14)
            .overlay(Circle().strokeBorder(Self.accent, lineWidth: 2))
            .shadow(color: Color.black.opacity(0.3), radius: 2, y: 1)
            .frame(width: 44, height: 44)
            .contentShape(Circle())
            .position(point)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.cropCoordinateSpace))
                    .onChanged { value in
                        let offset = cropGrabOffset ?? {
                            let captured = CGSize(
                                width: point.x - value.startLocation.x,
                                height: point.y - value.startLocation.y
                            )
                            cropGrabOffset = captured
                            return captured
                        }()
                        let normalized = CGPoint(
                            x: (value.location.x + offset.width) / size.width,
                            y: (value.location.y + offset.height) / size.height
                        )
                        crop.updateResize(handle: handle, to: normalized)
                    }
                    .onEnded { _ in
                        cropGrabOffset = nil
                    }
            )
            .accessibilityLabel(handle.accessibilityLabel)
            .accessibilityIdentifier(handle.accessibilityIdentifier)
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
        let path = Path(roundedRect: rect, cornerRadius: 6)
        context.fill(path, with: .color(.black))
        context.stroke(path, with: .color(.white.opacity(0.6)), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
    }

    private func drawSelection(_ bounds: CGRect, size: CGSize, in context: GraphicsContext) {
        let rect = displayRect(bounds, size: size).insetBy(dx: -6, dy: -6)
        context.stroke(
            Path(roundedRect: rect, cornerRadius: 6),
            with: .color(Self.accent),
            style: StrokeStyle(lineWidth: 1.5, dash: [5, 3])
        )
        for corner in [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.maxY),
            CGPoint(x: rect.maxX, y: rect.maxY)
        ] {
            let handle = Path(ellipseIn: CGRect(x: corner.x - 3.5, y: corner.y - 3.5, width: 7, height: 7))
            context.fill(handle, with: .color(.white))
            context.stroke(handle, with: .color(Self.accent), style: StrokeStyle(lineWidth: 1.5))
        }
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
