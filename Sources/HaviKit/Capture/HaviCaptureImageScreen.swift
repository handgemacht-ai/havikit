#if canImport(UIKit)
import SwiftUI
import UIKit

/// Screen 1 of the two-screen capture flow (bead havi-oukr): the frozen
/// screenshot gets its own canvas-focused screen — the multi-tool markup
/// editor (pen / highlighter / arrow / rectangle / blur-redact / select) plus
/// the crop tool, with nothing else competing for space. "Next" carries the
/// still, marks, and crop rect forward to Screen 2 (`HaviCaptureDetailsScreen`)
/// unchanged; `HaviCaptureModel` is shared across both, so nothing here is
/// lost on the round trip.
///
/// Crop is a confirmed step (bead havi-od6t): selecting the crop tool opens crop
/// mode, swapping the swatch/hint row for a Cancel / Reset / Crop tray. Confirming
/// zooms the canvas into the cropped region so the rest of the annotation happens
/// on a bigger surface.
struct HaviCaptureImageScreen: View {
    @ObservedObject var model: HaviCaptureModel
    let image: UIImage
    let onNext: () -> Void

    /// The markup and crop editors this screen reads (the tool, the crop
    /// indicator, whether Next is unlocked) are observed directly: they are
    /// nested `ObservableObject`s, and a change inside one never reaches an
    /// observer of `model` alone.
    @ObservedObject private var markup: HaviMarkupModel
    @ObservedObject private var crop: HaviCropModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The tool the crop handler needs as its "before" value, kept here because
    /// `onChange(of:perform:)` reports only the new one.
    @State private var previousTool: HaviMarkTool = .pen

    init(model: HaviCaptureModel, image: UIImage, onNext: @escaping () -> Void) {
        self.image = image
        self.onNext = onNext
        _model = ObservedObject(wrappedValue: model)
        _markup = ObservedObject(wrappedValue: model.markup)
        _crop = ObservedObject(wrappedValue: model.crop)
    }

    private var isCropping: Bool { markup.tool == .crop }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            toolbarTray

            HaviMarkupCanvas(image: image, model: markup, crop: crop)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.08), radius: 10, y: 4)

            if !isCropping {
                HaviColorSwatchRow(model: markup)
                    .transition(.opacity)
            }

            bottomRow

            nextButton
        }
        .padding(20)
        .navigationTitle("Report to HAVI")
        .navigationBarTitleDisplayMode(.inline)
        .animation(reduceMotion ? nil : .snappy(duration: 0.24), value: isCropping)
        .onChange(of: markup.tool) { newTool in
            let oldTool = previousTool
            previousTool = newTool
            if newTool == .crop {
                model.beginCropEditing(previousTool: oldTool)
            } else if oldTool == .crop, crop.isEditing {
                crop.cancel()
            }
        }
    }

    private var toolbarTray: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HaviMarkupToolbar(model: markup)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 6, y: 3)
    }

    @ViewBuilder private var bottomRow: some View {
        if isCropping {
            cropControls
                .transition(.opacity.combined(with: .move(edge: .bottom)))
        } else {
            hintRow
        }
    }

    // MARK: - Crop mode tray

    private var cropControls: some View {
        HStack(spacing: 10) {
            cropSecondaryButton(
                title: "Cancel",
                systemImage: "xmark",
                identifier: "havi-crop-cancel",
                enabled: true
            ) {
                model.cancelCrop()
            }

            cropSecondaryButton(
                title: "Reset",
                systemImage: "arrow.counterclockwise",
                identifier: "havi-crop-reset",
                enabled: crop.isCropped
            ) {
                crop.reset()
            }

            Spacer(minLength: 8)

            Button {
                model.confirmCrop()
            } label: {
                Label("Crop", systemImage: "checkmark")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 18)
                    .frame(minHeight: 38)
            }
            .buttonStyle(.borderedProminent)
            .tint(HaviMarkupCanvas.accent)
            .accessibilityIdentifier("havi-crop-confirm")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private func cropSecondaryButton(
        title: String,
        systemImage: String,
        identifier: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(enabled ? Color.primary.opacity(0.75) : Color.secondary.opacity(0.4))
                .padding(.horizontal, 12)
                .frame(minHeight: 38)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityIdentifier(identifier)
    }

    // MARK: - Hint row

    private var hintRow: some View {
        HStack(spacing: 12) {
            Label {
                Text(markupHint)
            } icon: {
                Image(systemName: markup.tool.systemImage)
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .animation(reduceMotion ? nil : .snappy, value: markup.tool)

            Spacer(minLength: 8)

            if crop.isCropped {
                Label("Cropped", systemImage: "crop")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(HaviMarkupCanvas.accent)
                    .transition(.opacity)
                    .accessibilityIdentifier("havi-crop-indicator")
            }
        }
        .animation(reduceMotion ? nil : .snappy, value: crop.isCropped)
    }

    private var markupHint: String {
        switch markup.tool {
        case .select: return "Tap a mark to select it, then drag to move or delete it."
        case .blur: return "Drag over anything private — it's blacked out in the image before it's sent."
        case .highlighter: return "Drag to highlight the area of the bug."
        case .crop: return "Drag a corner or edge, then Crop to zoom in and keep annotating."
        default: return "Draw on the screenshot to point at the bug."
        }
    }

    private var nextButton: some View {
        Button(action: onNext) {
            HStack(spacing: 8) {
                Text("Next").font(.headline)
                Image(systemName: "arrow.right")
            }
            .frame(maxWidth: .infinity, minHeight: 52)
        }
        .buttonStyle(.borderedProminent)
        .tint(HaviMarkupCanvas.accent)
        .disabled(!model.canProceed)
        .accessibilityIdentifier("havi-next-button")
    }
}
#endif
