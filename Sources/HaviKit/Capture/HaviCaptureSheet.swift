#if canImport(UIKit)
import SwiftUI
import UIKit

/// The thumb-friendly capture sheet (design §2): the frozen screenshot with
/// single-rectangle markup, an autofocused comment field, a 3-segment priority
/// control (default from `Havi.setPriority`), and one submit button. On failure
/// the sheet stays open — drawing + comment intact — with a plain-language reason
/// mapped from `error.code` and a *Retry* (or *Reconnect HAVI* for auth) action;
/// there is no silent drop and no disk queue.
///
/// Leaf-only accessibility identifiers, per the repo UI-test rule: the comment
/// field, each priority segment, and submit — never a container.
struct HaviCaptureSheet: View {
    let session: HaviCaptureSession
    let runtime: HaviRuntime
    let onClose: () -> Void

    @State private var model: HaviCaptureModel
    @State private var showConnect = false
    @State private var connectReconnect = false
    @FocusState private var commentFocused: Bool

    init(session: HaviCaptureSession, runtime: HaviRuntime, onClose: @escaping () -> Void) {
        self.session = session
        self.runtime = runtime
        self.onClose = onClose
        _model = State(initialValue: HaviCaptureModel(session: session, runtime: runtime))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HaviMarkupCanvas(image: session.image, markupFraction: $model.markupFraction)
                        .frame(maxHeight: 360)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                        )

                    Text("Drag on the screenshot to point at the bug.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

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
            }
            .navigationTitle("Report to HAVI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onClose)
                        .disabled(model.isSubmitting)
                }
            }
            .interactiveDismissDisabled(model.isSubmitting)
        }
        .onAppear { commentFocused = true }
        .sheet(isPresented: $showConnect) {
            HaviConnectSheet(runtime: runtime, reconnect: connectReconnect) {
                showConnect = false
            }
        }
    }

    private var connectPrompt: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Not connected to HAVI yet.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("Connect to HAVI") { openConnect(reconnect: false) }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.bordered)
                .accessibilityIdentifier("havi-connect-prompt")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.blue.opacity(0.12)))
    }

    private var commentField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Comment")
                .font(.subheadline.weight(.semibold))
            TextField("What's wrong here? (optional)", text: $model.comment, axis: .vertical)
                .lineLimit(2...5)
                .textFieldStyle(.roundedBorder)
                .focused($commentFocused)
                .disabled(model.isSubmitting)
                .accessibilityIdentifier("havi-comment-field")
        }
    }

    private var prioritySegments: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Priority")
                .font(.subheadline.weight(.semibold))
            HStack(spacing: 0) {
                segment(.high, label: "High")
                segment(.medium, label: "Medium")
                segment(.low, label: "Low")
            }
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.secondary.opacity(0.12)))
        }
    }

    private func segment(_ value: HaviPriority, label: String) -> some View {
        Button {
            model.priority = value
        } label: {
            Text(label)
                .font(.subheadline.weight(model.priority == value ? .semibold : .regular))
                .frame(maxWidth: .infinity, minHeight: 40)
                .foregroundStyle(model.priority == value ? Color.white : Color.primary)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(model.priority == value ? HaviMarkupCanvas.accent : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .disabled(model.isSubmitting)
        .accessibilityIdentifier("havi-priority-\(value.rawValue)")
    }

    private func failureBanner(_ failure: HaviSubmitFailure) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(failure.userMessage)
                .font(.footnote)
                .foregroundStyle(.primary)
            Button(action: { handleFailureAction(failure.kind) }) {
                Text(actionLabel(for: failure.kind))
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .disabled(model.isSubmitting)
            .accessibilityIdentifier("havi-retry-button")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.yellow.opacity(0.18)))
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
                if model.isSubmitting { ProgressView() }
                Text(model.isSubmitting ? "Sending…" : "Submit")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity, minHeight: 50)
        }
        .buttonStyle(.borderedProminent)
        .tint(HaviMarkupCanvas.accent)
        .disabled(model.isSubmitting)
        .accessibilityIdentifier("havi-submit-button")
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
