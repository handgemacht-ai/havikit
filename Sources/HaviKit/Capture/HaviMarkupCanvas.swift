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
/// Crop is a confirmed step (bead havi-od6t). Selecting the crop tool opens crop
/// mode: the whole still is shown with `HaviCropModel`'s draft rect dimmed-outside
/// and eight draggable handles. Once confirmed, the canvas DISPLAYS ONLY the
/// cropped region, scaled up to fill the frame, and every markup tool then draws
/// on that zoomed view. The zoom is display-only: `HaviCropGeometry`'s display
/// transform maps canvas points ↔ the full-still normalized space marks live in,
/// so the crop rect the submit pipeline reads is never touched here.
struct HaviMarkupCanvas: View {
    let image: UIImage
    @Bindable var model: HaviMarkupModel
    @Bindable var crop: HaviCropModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var strokeActive = false
    @State private var cropGrabOffset: CGSize?

    private static let cropCoordinateSpace = "haviCropSurface"

    /// In crop mode the whole still is shown (so a crop can be widened); once
    /// confirmed the canvas zooms into the confirmed crop.
    private var editingCrop: Bool { model.tool == .crop }

    /// The slice of the full still the canvas currently renders, in full-image
    /// normalized space — the full frame while cropping, the confirmed crop after.
    private var visibleRegion: CGRect {
        editingCrop ? HaviCropGeometry.fullFrame : crop.rect
    }

    var body: some View {
        GeometryReader { proxy in
            let region = visibleRegion
            let content = contentRect(region: region, in: proxy.size)
            ZStack(alignment: .topLeading) {
                contentLayer(region: region, size: content.size)
                    .frame(width: content.width, height: content.height, alignment: .topLeading)
                    .clipped()
                    .offset(x: content.minX, y: content.minY)

                if editingCrop {
                    cropInteractionOverlay(size: content.size)
                        .offset(x: content.minX, y: content.minY)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .aspectRatio(visibleAspect, contentMode: .fit)
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: visibleRegion)
    }

    // MARK: - Content (image + marks, zoomed into the visible region)

    private func contentLayer(region: CGRect, size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            scaledImage(region: region, size: size)

            Canvas { context, canvasSize in
                for mark in model.marks {
                    draw(mark, in: context, size: canvasSize, region: region, selected: mark.id == model.selectedMarkID)
                }
                if let inProgress = model.inProgress {
                    draw(inProgress, in: context, size: canvasSize, region: region, selected: false)
                }
            }
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
            .highPriorityGesture(drawGesture(canvasSize: size, region: region))
            .accessibilityIdentifier("havi-markup-canvas")

            if editingCrop {
                cropDimOverlay(size: size)
                    .allowsHitTesting(false)
            }
        }
    }

    /// The full still, scaled so `region` exactly fills the content bounds — the
    /// zoom is nothing more than a larger image offset up-and-left and clipped.
    private func scaledImage(region: CGRect, size: CGSize) -> some View {
        let fullWidth = region.width > 0 ? size.width / region.width : size.width
        let fullHeight = region.height > 0 ? size.height / region.height : size.height
        return Image(uiImage: image)
            .resizable()
            .frame(width: fullWidth, height: fullHeight)
            .offset(x: -region.minX * fullWidth, y: -region.minY * fullHeight)
    }

    // MARK: - Crop overlay (design: dimmed outside, bright inside, draggable handles)

    /// The dark scrim over everything outside the draft crop, shown only while
    /// crop mode is open (the confirmed crop is expressed as the canvas zoom, not
    /// a scrim). `region` is the full frame here, so crop-rect points map straight
    /// to canvas points.
    private func cropDimOverlay(size: CGSize) -> some View {
        let cropRect = displayRect(crop.rect, size: size, region: HaviCropGeometry.fullFrame)
        return Path { path in
            path.addRect(CGRect(origin: .zero, size: size))
            path.addRect(cropRect)
        }
        .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
    }

    /// The crop tool's live border + eight draggable handles, mounted only while
    /// crop mode is open.
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
        Path(displayRect(crop.rect, size: size, region: HaviCropGeometry.fullFrame))
            .stroke(Color.white, style: StrokeStyle(lineWidth: 2))
    }

    private func cropHandle(_ handle: HaviCropGeometry.Handle, size: CGSize) -> some View {
        let point = display(HaviCropGeometry.anchor(of: handle, in: crop.rect), size: size, region: HaviCropGeometry.fullFrame)
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

    private func drawGesture(canvasSize: CGSize, region: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                let point = HaviCropGeometry.normalizedFromCanvas(value.location, contentSize: canvasSize, visibleRegion: region)
                if strokeActive {
                    model.extend(to: point)
                } else {
                    strokeActive = true
                    model.begin(at: point, region: region)
                }
            }
            .onEnded { _ in
                strokeActive = false
                model.end(region: region)
            }
    }

    // MARK: - Rendering

    private func draw(_ mark: HaviMark, in context: GraphicsContext, size: CGSize, region: CGRect, selected: Bool) {
        let color = mark.color.swiftUIColor
        switch mark.shape {
        case .pen(let points):
            context.stroke(strokePath(points, size: size, region: region), with: .color(color), style: roundStyle(lineWidth: 4))
        case .highlighter(let points):
            context.stroke(strokePath(points, size: size, region: region), with: .color(color.opacity(0.35)), style: roundStyle(lineWidth: 16))
        case .arrow(let from, let to):
            drawArrow(from: from, to: to, color: color, in: context, size: size, region: region)
        case .rectangle(let rect):
            context.stroke(Path(displayRect(rect, size: size, region: region)), with: .color(color), style: StrokeStyle(lineWidth: 4))
        case .blur(let rect):
            drawBlurPlaceholder(displayRect(rect, size: size, region: region), in: context)
        }
        if selected {
            drawSelection(mark.normalizedBounds, size: size, region: region, in: context)
        }
    }

    private func drawArrow(from: CGPoint, to: CGPoint, color: Color, in context: GraphicsContext, size: CGSize, region: CGRect) {
        let tail = display(from, size: size, region: region)
        let tip = display(to, size: size, region: region)
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

    private func drawSelection(_ bounds: CGRect, size: CGSize, region: CGRect, in context: GraphicsContext) {
        let rect = displayRect(bounds, size: size, region: region).insetBy(dx: -6, dy: -6)
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

    private func strokePath(_ points: [CGPoint], size: CGSize, region: CGRect) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: display(first, size: size, region: region))
        for point in points.dropFirst() { path.addLine(to: display(point, size: size, region: region)) }
        return path
    }

    private func roundStyle(lineWidth: CGFloat) -> StrokeStyle {
        StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
    }

    private func display(_ point: CGPoint, size: CGSize, region: CGRect) -> CGPoint {
        HaviCropGeometry.canvasFromNormalized(point, contentSize: size, visibleRegion: region)
    }

    private func displayRect(_ rect: CGRect, size: CGSize, region: CGRect) -> CGRect {
        let standardized = rect.standardized
        let origin = display(CGPoint(x: standardized.minX, y: standardized.minY), size: size, region: region)
        let far = display(CGPoint(x: standardized.maxX, y: standardized.maxY), size: size, region: region)
        return CGRect(x: origin.x, y: origin.y, width: far.x - origin.x, height: far.y - origin.y)
    }

    // MARK: - Layout

    /// The aspect ratio of the currently visible slice: the full still's while
    /// cropping, the confirmed crop's once zoomed. Driving the canvas frame with
    /// this is what re-frames the sheet so the crop fills the space.
    private var visibleAspect: CGFloat {
        let region = visibleRegion
        let width = image.size.width * region.width
        let height = image.size.height * region.height
        return height > 0 ? width / height : 1
    }

    /// The rect within `size` that renders `region`, aspect-fit and centered.
    /// When the enclosing frame already matches `visibleAspect` this fills it.
    private func contentRect(region: CGRect, in size: CGSize) -> CGRect {
        let pixelWidth = max(image.size.width * region.width, 1)
        let pixelHeight = max(image.size.height * region.height, 1)
        let scale = min(size.width / pixelWidth, size.height / pixelHeight)
        let width = pixelWidth * scale
        let height = pixelHeight * scale
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
