#if canImport(UIKit)
import SwiftUI
import UIKit

/// The device-code connect sheet (design §5; in-app sign-in = bead havi-jnjj),
/// reachable from the capture sheet when no credential resolves or a submit
/// returns `unauthorized`. Its primary action, "Sign in with HAVI", opens the
/// approval page in the in-app sign-in browser (shared Safari session), and the
/// screen flips to the success state the moment the poll loop connects — the
/// browser dismisses itself. Approving on another signed-in device (the short
/// code + full URL) is a demoted, collapsed fallback, and manual token paste
/// stays available below it. A "Connected as … / Sign out" row (with a confirm
/// step) handles local revocation.
///
/// Leaf-only accessibility identifiers, per the repo UI-test rule.
struct HaviConnectSheet: View {
    let runtime: HaviRuntime
    let onClose: () -> Void

    @StateObject private var model: HaviConnectModel
    @State private var approvalBrowser = HaviApprovalBrowser()
    @State private var pasteExpanded = false
    @State private var otherDeviceExpanded = false
    @State private var confirmSignOut = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    init(runtime: HaviRuntime, reconnect: Bool = false, onClose: @escaping () -> Void) {
        self.runtime = runtime
        self.onClose = onClose
        _model = StateObject(wrappedValue: HaviConnectModel(runtime: runtime, reconnect: reconnect))
    }

    var body: some View {
        NavigationView {
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
                .animation(reduceMotion ? nil : .snappy(duration: 0.3), value: model.phase)
            }
            .navigationTitle("Connect to HAVI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onClose)
                }
            }
        }
        .navigationViewStyle(.stack)
        .onAppear {
            model.onAppear()
            approvalBrowser.onFinish = { model.browserClosed() }
        }
        .onChange(of: model.browser.isPresented) { presented in
            if presented, let url = model.approveURL {
                approvalBrowser.start(url: url)
            } else {
                approvalBrowser.stop()
            }
        }
        .onChange(of: scenePhase) { phase in
            // Returning to the foreground (from the in-app sign-in browser or a
            // background magic-link round trip) settles to the connected state if
            // the approval landed while we were away, and otherwise keeps the poll
            // alive on the same code.
            if phase == .active { model.applicationBecameActive() }
        }
        .onDisappear {
            // The in-app sign-in browser covers the sheet, which SwiftUI reports as
            // a disappear. That must NOT tear down the poll — closing the browser
            // never ends the pairing (design §5). Only a real dismiss (browser not
            // up) cancels.
            guard !model.browser.isPresented else { return }
            model.cancel()
            approvalBrowser.stop()
        }
    }

    /// The connected success state: an unmistakably positive composition — a
    /// system-green checkmark on a frosted success-tinted tray — while the sheet
    /// stays on HAVI branding (title, and the accent-tinted Sign out action).
    private func connectedCard(_ session: HaviConnectedSession) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label {
                Text("Connected to HAVI").font(.headline)
            } icon: {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(HaviMarkupCanvas.success)
            }
            .accessibilityIdentifier("havi-connected")
            Text(identityLine(session))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Sign out") { confirmSignOut = true }
                .buttonStyle(.bordered)
                .tint(HaviMarkupCanvas.accent)
                .accessibilityIdentifier("havi-sign-out")
                .confirmationDialog(
                    "Sign out of HAVI?",
                    isPresented: $confirmSignOut,
                    titleVisibility: .visible
                ) {
                    Button("Sign out", role: .destructive) { model.disconnect() }
                        .accessibilityIdentifier("havi-sign-out-confirm")
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This unlinks HAVI on this device. You can sign in again anytime.")
                }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(HaviMarkupCanvas.success.opacity(0.10))
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.regularMaterial)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(HaviMarkupCanvas.success.opacity(0.22), lineWidth: 1)
        )
    }

    private var creatingCard: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text("Getting things ready…").font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private func awaitingCard(_ link: HaviSetupLink) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            signInHero
            otherDeviceFallback(link)
            Button("Cancel") {
                model.cancel()
                onClose()
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("havi-connect-cancel")
        }
    }

    /// The signature moment: a frosted, brand-accent card whose one bold element is
    /// the sign-in button. Everything else on the sheet stays quiet around it.
    private var signInHero: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Sign in to connect this app to HAVI")
                    .font(.headline)
                Text("Open a quick sign-in, approve, and this device is linked to your workspace.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Button { model.openApproval() } label: {
                Label("Sign in with HAVI", systemImage: "arrow.up.forward.app.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(HaviMarkupCanvas.accent)
            .accessibilityIdentifier("havi-signin-button")

            HStack(spacing: 10) {
                ProgressView()
                Text("This screen updates the moment you approve.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(HaviMarkupCanvas.accent.opacity(0.06))
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.regularMaterial)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(HaviMarkupCanvas.accent.opacity(0.18), lineWidth: 1)
        )
    }

    private func otherDeviceFallback(_ link: HaviSetupLink) -> some View {
        DisclosureGroup(isExpanded: $otherDeviceExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Open this on a device where you're already signed in to HAVI, then approve.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Code")
                        .font(.caption)
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                    Text(shortCode(link))
                        .font(.title3.monospaced().weight(.semibold))
                        .accessibilityIdentifier("havi-connect-code")
                }

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
            }
            .padding(.top, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text("Approve on another device")
                .font(.subheadline.weight(.medium))
        }
        .tint(HaviMarkupCanvas.accent)
        .accessibilityIdentifier("havi-connect-other-device")
        .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: otherDeviceExpanded)
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

    /// The user-facing pairing code shown on the approve page — the `setup_code`
    /// carried in the approve URL, falling back to the poll `deviceCode`.
    private func shortCode(_ link: HaviSetupLink) -> String {
        if let items = URLComponents(url: link.approveURL, resolvingAgainstBaseURL: false)?.queryItems,
           let code = items.first(where: { $0.name == "setup_code" })?.value,
           !code.isEmpty {
            return code
        }
        return link.deviceCode
    }

    private func copy(_ string: String) {
        UIPasteboard.general.string = string
    }
}
#endif
