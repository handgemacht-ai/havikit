#if canImport(UIKit)
import SwiftUI

/// Screen 2 of the two-screen capture flow (bead havi-oukr): diagnostics,
/// comment, priority, and submit — everything about *sending* the report,
/// once the still itself (Screen 1) is settled. Pushed via
/// `.navigationDestination` from `HaviCaptureSheet`; Back returns to Screen 1
/// with the shared `HaviCaptureModel` untouched, so marks, crop, comment, and
/// toggles all survive the round trip. A submit failure keeps this screen
/// open with everything still editable.
struct HaviCaptureDetailsScreen: View {
    @Bindable var model: HaviCaptureModel
    let runtime: HaviRuntime
    let onBack: () -> Void
    let onClose: () -> Void

    @Binding var showConnect: Bool
    @Binding var connectReconnect: Bool
    @Binding var showDiagnostics: Bool

    @FocusState private var commentFocused: Bool
    @Namespace private var prioritySlide
    @Namespace private var labelSlide
    @State private var labelsExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                diagnosticsBadge

                if runtime.isConnected {
                    if model.failure?.kind != .reconnect {
                        connectedStatusRow
                    }
                } else {
                    connectPrompt
                }
                commentField
                prioritySegments
                if !model.additionalLabelDefinitions.isEmpty {
                    additionalLabelsSection
                }
                if let failure = model.failure {
                    failureBanner(failure)
                }
                submitButton
            }
            .padding(20)
            .animation(reduceMotion ? nil : .snappy(duration: 0.3), value: runtime.isConnected)
            .animation(reduceMotion ? nil : .snappy(duration: 0.3), value: model.failure != nil)
            .animation(reduceMotion ? nil : .snappy(duration: 0.3), value: model.additionalLabelDefinitions.isEmpty)
        }
        .task { await model.loadLabelDefinitions() }
        .navigationTitle("Report to HAVI")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button(action: onBack) {
                    Label("Back", systemImage: "chevron.left")
                }
                .disabled(model.isSubmitting)
                .accessibilityIdentifier("havi-back-button")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Close", action: onClose)
                    .disabled(model.isSubmitting)
            }
        }
        .onAppear { commentFocused = true }
    }

    private var diagnosticsBadge: some View {
        HaviDiagnosticsBadgeRow(
            consoleCount: model.consoleErrorCount,
            networkCount: model.networkErrorCount,
            onOpen: { showDiagnostics = true }
        )
    }

    private var connectPrompt: some View {
        HStack(spacing: 12) {
            Image(systemName: "link.circle.fill")
                .font(.title3)
                .foregroundStyle(HaviMarkupCanvas.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("You're not connected to HAVI")
                    .font(.subheadline.weight(.semibold))
                Text("Connect to send this report.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("Connect") { openConnect(reconnect: false) }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.bordered)
                .tint(HaviMarkupCanvas.accent)
                .accessibilityIdentifier("havi-connect-prompt")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(HaviMarkupCanvas.accent.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(HaviMarkupCanvas.accent.opacity(0.18), lineWidth: 1)
        )
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    /// The always-present connected-state entry point: a compact frosted tray with
    /// a green presence dot and the workspace identity, whose gear opens the
    /// connect sheet on its connected card — the only place a connected developer
    /// can reach Sign out. Mirrors the disconnected `connectPrompt` so the two read
    /// as one component in two states.
    private var connectedStatusRow: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(HaviMarkupCanvas.success)
                .frame(width: 9, height: 9)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Connected to HAVI")
                    .font(.subheadline.weight(.semibold))
                Text(connectedIdentityLine)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button { openConnect(reconnect: false) } label: {
                Image(systemName: "gearshape")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .tint(HaviMarkupCanvas.accent)
            .disabled(model.isSubmitting)
            .accessibilityLabel("Manage HAVI connection")
            .accessibilityIdentifier("havi-manage-connection")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(HaviMarkupCanvas.success.opacity(0.08))
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.regularMaterial)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(HaviMarkupCanvas.success.opacity(0.22), lineWidth: 1)
        )
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var connectedIdentityLine: String {
        guard let session = runtime.tokenStore.connectedSession else {
            return "This device is linked to your workspace."
        }
        let workspace = session.workspaceName ?? session.workspaceID
        if let user = session.userName, !user.isEmpty {
            return "\(user) · \(workspace)"
        }
        return workspace
    }

    private var commentField: some View {
        VStack(alignment: .leading, spacing: 8) {
            eyebrow("Comment")
            TextField("What's wrong here? (optional)", text: $model.comment, axis: .vertical)
                .lineLimit(2...5)
                .textFieldStyle(.roundedBorder)
                .focused($commentFocused)
                .disabled(model.isSubmitting)
                .accessibilityIdentifier("havi-comment-field")
        }
    }

    private var prioritySegments: some View {
        VStack(alignment: .leading, spacing: 8) {
            eyebrow("Priority")
            HStack(spacing: 4) {
                segment(.high, label: "High")
                segment(.medium, label: "Medium")
                segment(.low, label: "Low")
            }
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
            .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: model.priority)
        }
    }

    private func segment(_ value: HaviPriority, label: String) -> some View {
        let selected = model.priority == value
        return Button {
            model.priority = value
        } label: {
            Text(label)
                .font(.subheadline.weight(selected ? .semibold : .regular))
                .foregroundStyle(selected ? Color.white : Color.primary.opacity(0.7))
                .frame(maxWidth: .infinity, minHeight: 38)
                .background(
                    ZStack {
                        if selected {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(HaviMarkupCanvas.accent)
                                .matchedGeometryEffect(id: "prioritySelection", in: prioritySlide)
                        }
                    }
                )
        }
        .buttonStyle(.plain)
        .disabled(model.isSubmitting)
        .accessibilityIdentifier("havi-priority-\(value.rawValue)")
    }

    // MARK: - Workspace labels (bead havi-jj51)

    /// Everything past the built-in priority: the workspace's own label
    /// vocabulary, rendered generically from `GET /api/label-definitions`. Kept in
    /// a collapsed disclosure so the details screen stays as uncluttered as it is
    /// today when a workspace defines no extra labels — the common case hides this
    /// row entirely. An accent count badge keeps applied labels visible while
    /// collapsed.
    private var additionalLabelsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.28)) {
                    labelsExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    eyebrow("Labels")
                    if appliedLabelCount > 0 {
                        Text("\(appliedLabelCount)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(HaviMarkupCanvas.accent))
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(labelsExpanded ? 0 : -90))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(model.isSubmitting)
            .accessibilityIdentifier("havi-labels-disclosure")

            if labelsExpanded {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(model.additionalLabelDefinitions) { definition in
                        labelControl(definition)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(.regularMaterial)
                        )
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var appliedLabelCount: Int { model.appliedLabels().count }

    @ViewBuilder
    private func labelControl(_ definition: HaviLabelDefinition) -> some View {
        switch definition.kind {
        case .choice:
            VStack(alignment: .leading, spacing: 8) {
                fieldCaption(definition.name)
                choiceControl(definition)
            }
        case .value:
            VStack(alignment: .leading, spacing: 8) {
                fieldCaption(definition.name)
                valueControl(definition)
            }
        case .flag:
            flagControl(definition)
        }
    }

    private func choiceControl(_ definition: HaviLabelDefinition) -> some View {
        HStack(spacing: 4) {
            ForEach(definition.allowedValues, id: \.self) { value in
                choiceSegment(definition, value: value)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
        .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: model.labelChoiceValues[definition.key])
    }

    private func choiceSegment(_ definition: HaviLabelDefinition, value: String) -> some View {
        let selected = model.labelChoiceValues[definition.key] == value
        return Button {
            if selected {
                model.labelChoiceValues[definition.key] = nil
            } else {
                model.labelChoiceValues[definition.key] = value
            }
        } label: {
            Text(value.capitalized)
                .font(.subheadline.weight(selected ? .semibold : .regular))
                .foregroundStyle(selected ? Color.white : Color.primary.opacity(0.7))
                .frame(maxWidth: .infinity, minHeight: 34)
                .background(
                    ZStack {
                        if selected {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(HaviMarkupCanvas.accent)
                                .matchedGeometryEffect(id: "labelSel-\(definition.key)", in: labelSlide)
                        }
                    }
                )
        }
        .buttonStyle(.plain)
        .disabled(model.isSubmitting)
        .accessibilityIdentifier("havi-label-\(definition.key)-\(value)")
    }

    private func flagControl(_ definition: HaviLabelDefinition) -> some View {
        let on = model.labelFlags.contains(definition.key)
        return Button {
            if on {
                model.labelFlags.remove(definition.key)
            } else {
                model.labelFlags.insert(definition.key)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.footnote)
                Text(definition.name)
                    .font(.subheadline.weight(on ? .semibold : .regular))
            }
            .foregroundStyle(on ? Color.white : Color.primary.opacity(0.8))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(on ? HaviMarkupCanvas.accent : Color.primary.opacity(0.06))
            )
        }
        .buttonStyle(.plain)
        .disabled(model.isSubmitting)
        .accessibilityIdentifier("havi-label-\(definition.key)")
    }

    private func valueControl(_ definition: HaviLabelDefinition) -> some View {
        TextField(definition.name, text: labelValueBinding(definition.key))
            .textFieldStyle(.roundedBorder)
            .disabled(model.isSubmitting)
            .accessibilityIdentifier("havi-label-\(definition.key)-field")
    }

    private func labelValueBinding(_ key: String) -> Binding<String> {
        Binding(
            get: { model.labelChoiceValues[key] ?? "" },
            set: { model.labelChoiceValues[key] = $0.isEmpty ? nil : $0 }
        )
    }

    private func fieldCaption(_ text: String) -> some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private func failureBanner(_ failure: HaviSubmitFailure) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.orange)
                Text(failure.userMessage)
                    .font(.footnote)
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            Button(action: { handleFailureAction(failure.kind) }) {
                Text(actionLabel(for: failure.kind))
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(HaviMarkupCanvas.accent)
            .disabled(model.isSubmitting)
            .accessibilityIdentifier("havi-retry-button")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.orange.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.25), lineWidth: 1)
        )
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func handleFailureAction(_ kind: HaviSubmitFailureKind) {
        switch kind {
        case .retry: model.retry()
        case .reconnect: reconnect()
        case .terminal: onClose()
        }
    }

    private var submitButton: some View {
        Button(action: { Task { await model.submit() } }) {
            HStack(spacing: 8) {
                if model.isSubmitting {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "paperplane.fill")
                }
                Text(model.isSubmitting ? "Sending…" : "Send to HAVI")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
        }
        .buttonStyle(.borderedProminent)
        .tint(HaviMarkupCanvas.accent)
        .disabled(model.isSubmitting)
        .accessibilityIdentifier("havi-submit-button")
    }

    private func eyebrow(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption2.weight(.semibold))
            .tracking(0.8)
            .foregroundStyle(.secondary)
    }

    private func actionLabel(for kind: HaviSubmitFailureKind) -> String {
        switch kind {
        case .retry: return "Retry"
        case .reconnect: return "Reconnect HAVI"
        case .terminal: return "Dismiss"
        }
    }

    private func openConnect(reconnect: Bool) {
        connectReconnect = reconnect
        showConnect = true
    }

    private func reconnect() {
        openConnect(reconnect: true)
    }
}
#endif
