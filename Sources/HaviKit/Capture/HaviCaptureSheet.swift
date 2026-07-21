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
    @Namespace private var prioritySlide
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(session: HaviCaptureSession, runtime: HaviRuntime, onClose: @escaping () -> Void) {
        self.session = session
        self.runtime = runtime
        self.onClose = onClose
        _model = State(initialValue: HaviCaptureModel(session: session, runtime: runtime))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
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
                .animation(reduceMotion ? nil : .snappy(duration: 0.3), value: runtime.isConnected)
                .animation(reduceMotion ? nil : .snappy(duration: 0.3), value: model.failure != nil)
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
        VStack(alignment: .leading, spacing: 14) {
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

            HaviMarkupCanvas(image: session.image, model: model.markup)
                .frame(minHeight: 300, maxHeight: 520)
                .background(Color.black.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.08), radius: 10, y: 4)

            HaviColorSwatchRow(model: model.markup)
                .padding(.top, 2)

            markupHintLabel
        }
    }

    private var markupHintLabel: some View {
        Label {
            Text(markupHint)
        } icon: {
            Image(systemName: model.markup.tool.systemImage)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .animation(reduceMotion ? nil : .snappy, value: model.markup.tool)
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
