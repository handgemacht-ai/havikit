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
                HStack(spacing: 10) {
                    if consoleCount > 0 {
                        badge(system: "exclamationmark.triangle.fill",
                              text: "\(consoleCount) console \(consoleCount == 1 ? "error" : "errors")",
                              color: .orange)
                    }
                    if consoleCount > 0, networkCount > 0 {
                        Text("·").foregroundStyle(.secondary)
                    }
                    if networkCount > 0 {
                        badge(system: "xmark.octagon.fill",
                              text: "\(networkCount) network \(networkCount == 1 ? "error" : "errors")",
                              color: .red)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.secondary.opacity(0.10)))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("havi-diagnostics-row")
        } else {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal").foregroundStyle(.secondary)
                Text("No console or network errors captured")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
        }
    }

    private func badge(system: String, text: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: system).foregroundStyle(color)
            Text(text).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
        }
    }
}

/// The diagnostics detail sheet: grouped Console / Network sections, each entry an
/// expandable `DisclosureGroup` showing the full message, with a per-group
/// include/exclude toggle (default ON) that controls whether the group is attached
/// to the submission.
struct HaviDiagnosticsDetailSheet: View {
    @Bindable var model: HaviCaptureModel
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            List {
                if !model.diagnostics.consoleErrors.isEmpty {
                    Section {
                        Toggle("Attach console errors", isOn: $model.includeConsoleErrors)
                            .accessibilityIdentifier("havi-diagnostics-console-toggle")
                        ForEach(Array(model.diagnostics.consoleErrors.enumerated()), id: \.offset) { _, entry in
                            entryRow(title: entry.message, detail: "[\(entry.level.rawValue)] \(entry.message)")
                        }
                    } header: {
                        label("Console", systemImage: "exclamationmark.triangle.fill", color: .orange,
                              count: model.diagnostics.consoleErrors.count)
                    }
                }

                if !model.diagnostics.networkErrors.isEmpty {
                    Section {
                        Toggle("Attach network errors", isOn: $model.includeNetworkErrors)
                            .accessibilityIdentifier("havi-diagnostics-network-toggle")
                        ForEach(Array(model.diagnostics.networkErrors.enumerated()), id: \.offset) { _, entry in
                            entryRow(title: entry.message, detail: entry.message)
                        }
                    } header: {
                        label("Network", systemImage: "xmark.octagon.fill", color: .red,
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
    }

    private func entryRow(title: String, detail: String) -> some View {
        DisclosureGroup {
            Text(detail)
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text(title)
                .font(.footnote)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private func label(_ title: String, systemImage: String, color: Color, count: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage).foregroundStyle(color)
            Text("\(title) (\(count))")
        }
    }
}
#endif
