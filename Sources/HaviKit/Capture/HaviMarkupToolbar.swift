#if canImport(UIKit)
import SwiftUI

/// The markup tool bar (bead havi-6953): the six tools with a clear selected
/// state, object-level undo/redo, and a delete affordance that appears only when
/// the select tool has a mark chosen. Leaf accessibility identifiers ride on each
/// control (never the container), per the repo UI-test rule.
struct HaviMarkupToolbar: View {
    @Bindable var model: HaviMarkupModel

    var body: some View {
        HStack(spacing: 8) {
            ForEach(HaviMarkTool.allCases, id: \.self) { tool in
                toolButton(tool)
            }
            Divider().frame(height: 24)
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
            }
        }
    }

    private func toolButton(_ tool: HaviMarkTool) -> some View {
        let selected = model.tool == tool
        return Button {
            model.selectTool(tool)
        } label: {
            Image(systemName: tool.systemImage)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 40, height: 40)
                .foregroundStyle(selected ? Color.white : Color.primary)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(selected ? HaviMarkupCanvas.accent : Color.secondary.opacity(0.14))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tool.title)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityIdentifier(tool.accessibilityIdentifier)
    }

    private func historyButton(system: String, identifier: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 40, height: 40)
                .foregroundStyle(enabled ? Color.primary : Color.secondary.opacity(0.4))
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.secondary.opacity(0.14)))
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
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 40, height: 40)
                .foregroundStyle(Color.white)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.red))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Delete mark")
        .accessibilityIdentifier("havi-delete-mark")
    }
}

/// The 6-preset color swatch row (design: red default). Tapping picks the color
/// applied to new marks; the current pick carries a ring.
struct HaviColorSwatchRow: View {
    @Bindable var model: HaviMarkupModel

    var body: some View {
        HStack(spacing: 14) {
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
                .frame(width: 28, height: 28)
                .overlay(Circle().stroke(Color.secondary.opacity(0.35), lineWidth: 1))
                .overlay(
                    Circle()
                        .stroke(HaviMarkupCanvas.accent, lineWidth: selected ? 3 : 0)
                        .padding(-4)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(color.name) color")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityIdentifier(color.accessibilityIdentifier)
    }
}
#endif
