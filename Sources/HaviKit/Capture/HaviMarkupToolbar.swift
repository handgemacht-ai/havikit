#if canImport(UIKit)
import SwiftUI

/// The markup tool bar (bead havi-6953): the seven tools with a clear selected
/// state, object-level undo/redo, and a delete affordance that appears only when
/// the select tool has a mark chosen. Leaf accessibility identifiers ride on each
/// control (never the container), per the repo UI-test rule.
struct HaviMarkupToolbar: View {
    @Bindable var model: HaviMarkupModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let buttonCorner: CGFloat = 11
    private let quietFill = Color.primary.opacity(0.06)

    var body: some View {
        HStack(spacing: 6) {
            ForEach(HaviMarkTool.allCases, id: \.self) { tool in
                toolButton(tool)
            }
            trayDivider
            historyButton(
                system: "arrow.uturn.backward",
                identifier: "havi-undo",
                enabled: model.canUndo,
                action: { model.undo() }
            )
            historyButton(
                system: "arrow.uturn.forward",
                identifier: "havi-redo",
                enabled: model.canRedo,
                action: { model.redo() }
            )
            if model.selectedMark != nil {
                deleteButton
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.22), value: model.selectedMarkID)
    }

    private var trayDivider: some View {
        Capsule()
            .fill(Color.primary.opacity(0.12))
            .frame(width: 1, height: 22)
            .padding(.horizontal, 3)
    }

    private func toolButton(_ tool: HaviMarkTool) -> some View {
        let selected = model.tool == tool
        return Button {
            model.selectTool(tool)
        } label: {
            Image(systemName: tool.systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(selected ? Color.white : Color.primary.opacity(0.72))
                .frame(width: 40, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: buttonCorner, style: .continuous)
                        .fill(selected ? HaviMarkupCanvas.accent : quietFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: buttonCorner, style: .continuous)
                        .strokeBorder(Color.white.opacity(selected ? 0.18 : 0), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .animation(reduceMotion ? nil : .snappy(duration: 0.22), value: selected)
        .accessibilityLabel(tool.title)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityIdentifier(tool.accessibilityIdentifier)
    }

    private func historyButton(system: String, identifier: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(enabled ? Color.primary.opacity(0.72) : Color.secondary.opacity(0.35))
                .frame(width: 40, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: buttonCorner, style: .continuous).fill(quietFill)
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityIdentifier(identifier)
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            model.deleteSelected()
        } label: {
            Image(systemName: "trash")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: 40, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: buttonCorner, style: .continuous).fill(Color.red)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Delete mark")
        .accessibilityIdentifier("havi-delete-mark")
    }
}

/// The 6-preset color swatch row (design: red default). Tapping picks the color
/// applied to new marks; the current pick lifts with an accent ring.
struct HaviColorSwatchRow: View {
    @Bindable var model: HaviMarkupModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 16) {
            ForEach(HaviMarkColor.presets, id: \.name) { color in
                swatch(color)
            }
            Spacer(minLength: 0)
        }
    }

    private func swatch(_ color: HaviMarkColor) -> some View {
        let selected = model.color == color
        return Button {
            model.color = color
        } label: {
            Circle()
                .fill(color.swiftUIColor)
                .frame(width: 26, height: 26)
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.18), lineWidth: 1))
                .overlay(
                    Circle()
                        .strokeBorder(HaviMarkupCanvas.accent, lineWidth: selected ? 2.5 : 0)
                        .padding(-4)
                )
                .scaleEffect(selected && !reduceMotion ? 1.12 : 1)
                .shadow(color: selected ? color.swiftUIColor.opacity(0.35) : .clear, radius: selected ? 4 : 0, y: 1)
        }
        .buttonStyle(.plain)
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: model.color)
        .accessibilityLabel("\(color.name) color")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityIdentifier(color.accessibilityIdentifier)
    }
}
#endif
