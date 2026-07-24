#if canImport(UIKit)
import SwiftUI

/// The capture sheet's diagnostics badge (bead havi-6953): a severity-colored
/// summary of the console/network errors captured with this annotation, tappable
/// to a detail sheet. When nothing was captured it degrades to a muted, tasteful
/// "all clear" state rather than a colored alarm. Leaf identifier on the tappable
/// control only (`havi-diagnostics-row`).
struct HaviDiagnosticsBadgeRow: View {
    let consoleCount: Int
    let networkCount: Int
    let onOpen: () -> Void

    private var hasDiagnostics: Bool { consoleCount > 0 || networkCount > 0 }

    var body: some View {
        if hasDiagnostics {
            Button(action: onOpen) {
                HStack(spacing: 8) {
                    if consoleCount > 0 {
                        pill(system: "exclamationmark.triangle.fill", text: "\(consoleCount) console", color: .orange)
                    }
                    if networkCount > 0 {
                        pill(system: "xmark.octagon.fill", text: "\(networkCount) network", color: .red)
                    }
                    Spacer(minLength: 4)
                    Text("Review")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("havi-diagnostics-row")
        } else {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(Color.green.opacity(0.7))
                Text("No console or network errors captured")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 6)
        }
    }

    private func pill(system: String, text: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: system)
                .font(.caption)
                .foregroundStyle(color)
            Text(text)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 9)
        .background(Capsule().fill(color.opacity(0.15)))
    }
}

/// The diagnostics detail sheet: grouped Console / Network sections, each entry an
/// expandable `DisclosureGroup` showing the full message, with a per-group
/// include/exclude toggle (default ON) that controls whether the group is attached
/// to the submission.
struct HaviDiagnosticsDetailSheet: View {
    @ObservedObject var model: HaviCaptureModel
    let onClose: () -> Void

    var body: some View {
        NavigationView {
            List {
                if !model.diagnostics.consoleErrors.isEmpty {
                    Section {
                        Toggle("Attach console errors", isOn: $model.includeConsoleErrors)
                            .tint(HaviMarkupCanvas.accent)
                            .accessibilityIdentifier("havi-diagnostics-console-toggle")
                        ForEach(Array(model.diagnostics.consoleErrors.enumerated()), id: \.offset) { _, entry in
                            entryRow(title: entry.message, detail: "[\(entry.level.rawValue)] \(entry.message)")
                        }
                    } header: {
                        header("Console", systemImage: "exclamationmark.triangle.fill", color: .orange,
                               count: model.diagnostics.consoleErrors.count)
                    }
                }

                if !model.diagnostics.networkErrors.isEmpty {
                    Section {
                        Toggle("Attach network errors", isOn: $model.includeNetworkErrors)
                            .tint(HaviMarkupCanvas.accent)
                            .accessibilityIdentifier("havi-diagnostics-network-toggle")
                        ForEach(Array(model.diagnostics.networkErrors.enumerated()), id: \.offset) { _, entry in
                            entryRow(title: entry.message, detail: entry.message)
                        }
                    } header: {
                        header("Network", systemImage: "xmark.octagon.fill", color: .red,
                               count: model.diagnostics.networkErrors.count)
                    }
                }
            }
            .navigationTitle("Captured diagnostics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onClose)
                        .accessibilityIdentifier("havi-diagnostics-done")
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private func entryRow(title: String, detail: String) -> some View {
        DisclosureGroup {
            Text(detail)
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                )
                .padding(.vertical, 4)
        } label: {
            Text(title)
                .font(.system(.footnote, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .tint(HaviMarkupCanvas.accent)
    }

    private func header(_ title: String, systemImage: String, color: Color, count: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.caption)
                .foregroundStyle(color)
            Text(title)
                .font(.footnote.weight(.semibold))
                .textCase(nil)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
            Text("\(count)")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Capsule().fill(color.opacity(0.15)))
        }
        .padding(.vertical, 2)
    }
}
#endif
