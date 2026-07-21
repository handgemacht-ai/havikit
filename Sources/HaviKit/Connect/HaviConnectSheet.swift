#if canImport(UIKit)
import SwiftUI
import UIKit

/// The device-code connect sheet (design §5), reachable from the capture sheet
/// when no credential resolves or a submit returns `unauthorized`. It shows the
/// approve URL to open on the laptop, a copy button, a live polling indicator,
/// and success / expired / error states, plus a "Connected as … / Disconnect"
/// row for local revocation and a secondary manual-paste path.
///
/// Leaf-only accessibility identifiers, per the repo UI-test rule.
struct HaviConnectSheet: View {
    let runtime: HaviRuntime
    let onClose: () -> Void

    @State private var model: HaviConnectModel
    @State private var pasteExpanded = false

    init(runtime: HaviRuntime, reconnect: Bool = false, onClose: @escaping () -> Void) {
        self.runtime = runtime
        self.onClose = onClose
        _model = State(initialValue: HaviConnectModel(runtime: runtime, reconnect: reconnect))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch model.phase {
                    case .connected(let session): connectedCard(session)
                    case .creating: creatingCard
                    case .awaiting(let link): awaitingCard(link)
                    case .expired: expiredCard
                    case .error(let message): errorCard(message)
                    }

                    if model.connectedSession == nil {
                        pasteFallback
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("Connect to HAVI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onClose)
                }
            }
        }
        .onAppear { model.onAppear() }
        .onDisappear { model.cancel() }
    }

    private func connectedCard(_ session: HaviConnectedSession) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label {
                Text("Connected to HAVI").font(.headline)
            } icon: {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(HaviMarkupCanvas.accent)
            }
            Text(identityLine(session))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Disconnect") { model.disconnect() }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("havi-disconnect")
        }
    }

    private var creatingCard: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text("Getting a link…").font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private func awaitingCard(_ link: HaviSetupLink) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Open this link on your laptop where you're signed in to HAVI, then approve and name the workspace:")
                .font(.subheadline)

            Button { copy(link.approveURL.absoluteString) } label: {
                Text(link.approveURL.absoluteString)
                    .font(.footnote.monospaced())
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(HaviMarkupCanvas.accent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.secondary.opacity(0.12)))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("havi-connect-link")

            Button { copy(link.approveURL.absoluteString) } label: {
                Label("Copy link", systemImage: "doc.on.doc")
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("havi-connect-copy")

            HStack(spacing: 10) {
                ProgressView()
                Text("Waiting for approval…").font(.footnote).foregroundStyle(.secondary)
            }

            Button("Cancel") {
                model.cancel()
                onClose()
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("havi-connect-cancel")
        }
    }

    private var expiredCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("This link is invalid or has expired.")
                .font(.subheadline)
            Button("Get a new link") { model.start() }
                .buttonStyle(.borderedProminent)
                .tint(HaviMarkupCanvas.accent)
                .accessibilityIdentifier("havi-connect-new-link")
        }
    }

    private func errorCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(message).font(.subheadline)
            Button("Try again") { model.start() }
                .buttonStyle(.borderedProminent)
                .tint(HaviMarkupCanvas.accent)
                .accessibilityIdentifier("havi-connect-retry")
        }
    }

    private var pasteFallback: some View {
        DisclosureGroup(isExpanded: $pasteExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                SecureField("Bearer token", text: $model.pasteToken)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .accessibilityIdentifier("havi-connect-token-field")
                TextField("Workspace id", text: $model.pasteWorkspaceID)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .accessibilityIdentifier("havi-connect-workspace-field")
                Button("Use token") { model.usePastedToken() }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("havi-connect-paste-submit")
            }
            .padding(.top, 8)
        } label: {
            Text("Paste a token instead").font(.subheadline)
        }
    }

    private func identityLine(_ session: HaviConnectedSession) -> String {
        let user = session.userName ?? "this device"
        let workspace = session.workspaceName ?? session.workspaceID
        return "\(user) · \(workspace)"
    }

    private func copy(_ string: String) {
        UIPasteboard.general.string = string
    }
}
#endif
