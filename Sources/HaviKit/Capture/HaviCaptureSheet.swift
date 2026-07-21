#if canImport(UIKit)
import SwiftUI
import UIKit

/// The capture sheet (design §2, markup v2 = bead havi-6953): the frozen
/// screenshot with a multi-tool markup editor (pen / highlighter / arrow /
/// rectangle / blur-redact / select, undo+redo, 6-color swatch), a diagnostics
/// badge summarizing captured console/network errors, an autofocused comment
/// field, a 3-segment priority control, and one submit button. On failure the
/// sheet stays open — marks + comment intact — with a plain-language, `error.code`
/// -mapped reason and a Retry (or Reconnect HAVI) action; no silent drop, no disk
/// queue.
///
/// Leaf-only accessibility identifiers, per the repo UI-test rule.
struct HaviCaptureSheet: View {
    let session: HaviCaptureSession
    let runtime: HaviRuntime
    let onClose: () -> Void

    @State private var model: HaviCaptureModel
    @State private var showConnect = false
    @State private var connectReconnect = false
    @State private var showDiagnostics = false
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
                VStack(alignment: .leading, spacing: 18) {
                    markupEditor
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
        .sheet(isPresented: $showDiagnostics) {
            HaviDiagnosticsDetailSheet(model: model) { showDiagnostics = false }
        }
    }

    // MARK: - Markup

    private var markupEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HaviMarkupToolbar(model: model.markup)
                    .padding(.vertical, 2)
            }
            HaviMarkupCanvas(image: session.image, model: model.markup)
                .frame(minHeight: 300, maxHeight: 520)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
            HaviColorSwatchRow(model: model.markup)
            Text(markupHint)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var markupHint: String {
        switch model.markup.tool {
        case .select: return "Tap a mark to select it, then drag to move or delete it."
        case .blur: return "Drag over anything private — it's pixelated into the image before it's sent."
        case .highlighter: return "Drag to highlight the area of the bug."
        default: return "Draw on the screenshot to point at the bug."
        }
    }

    private var diagnosticsBadge: some View {
        HaviDiagnosticsBadgeRow(
            consoleCount: model.consoleErrorCount,
            networkCount: model.networkErrorCount,
            onOpen: { showDiagnostics = true }
        )
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
