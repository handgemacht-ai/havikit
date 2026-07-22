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
struct HaviCaptureImageScreen: View {
    let model: HaviCaptureModel
    let image: UIImage
    let onNext: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            toolbarTray

            HaviMarkupCanvas(image: image, model: model.markup, crop: model.crop)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.08), radius: 10, y: 4)

            HaviColorSwatchRow(model: model.markup)

            hintRow

            nextButton
        }
        .padding(20)
        .navigationTitle("Report to HAVI")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var toolbarTray: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HaviMarkupToolbar(model: model.markup)
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

    private var hintRow: some View {
        HStack(spacing: 12) {
            Label {
                Text(markupHint)
            } icon: {
                Image(systemName: model.markup.tool.systemImage)
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .animation(reduceMotion ? nil : .snappy, value: model.markup.tool)

            Spacer(minLength: 8)

            if model.crop.isCropped {
                Button("Reset crop") { model.crop.reset() }
                    .font(.footnote.weight(.semibold))
                    .buttonStyle(.borderless)
                    .tint(HaviMarkupCanvas.accent)
                    .accessibilityIdentifier("havi-crop-reset")
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .snappy, value: model.crop.isCropped)
    }

    private var markupHint: String {
        switch model.markup.tool {
        case .select: return "Tap a mark to select it, then drag to move or delete it."
        case .blur: return "Drag over anything private — it's blacked out in the image before it's sent."
        case .highlighter: return "Drag to highlight the area of the bug."
        case .crop: return "Drag a corner or edge to crop the screenshot before sending."
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
        .disabled(model.isSubmitting)
        .accessibilityIdentifier("havi-next-button")
    }
}
#endif
