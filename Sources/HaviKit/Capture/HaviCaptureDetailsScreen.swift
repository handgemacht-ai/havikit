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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                diagnosticsBadge

                if !runtime.isConnected {
                    connectPrompt
                }
                commentField
                prioritySegments
                if let failure = model.failure {
                    failureBanner(failure)
                }
                submitButton
            }
            .padding(20)
            .animation(reduceMotion ? nil : .snappy(duration: 0.3), value: runtime.isConnected)
            .animation(reduceMotion ? nil : .snappy(duration: 0.3), value: model.failure != nil)
        }
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
