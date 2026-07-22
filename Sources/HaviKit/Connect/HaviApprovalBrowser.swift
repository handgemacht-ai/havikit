#if canImport(UIKit)
import AuthenticationServices
import UIKit

/// Drives the in-app sign-in browser for the connect flow (bead havi-jnjj).
///
/// Browser API choice — `ASWebAuthenticationSession`, not `SFSafariViewController`:
/// the whole point of opening approval on the phone is that an existing HAVI web
/// session (or the magic-link round trip, completed in Safari) is already there,
/// so the developer rarely re-authenticates. `ASWebAuthenticationSession` with
/// `prefersEphemeralWebBrowserSession = false` reads the persistent, shared Safari
/// cookie store, so that session carries over. `SFSafariViewController` has used a
/// per-app data store isolated from Safari since iOS 11, which would defeat that
/// carry-over — so it is the wrong tool here.
///
/// We own no custom-scheme callback: approval is not signalled by a redirect back
/// into the app but by the SDK poll loop receiving the 201 exchange. The session's
/// `callbackURLScheme` is therefore a dummy the approval page never redirects to;
/// the completion handler fires only when the user taps Done/Cancel or when we tear
/// the session down programmatically on success (`stop()`). `callbackURLScheme`
/// need not be registered in `Info.plist` — it is matched inside the auth session,
/// not routed through the app's URL handler.
@MainActor
final class HaviApprovalBrowser: NSObject, ASWebAuthenticationPresentationContextProviding {
    /// A scheme the approval page never redirects to — see the type doc.
    private static let unusedCallbackScheme = "havi-approval-noop"

    private var session: ASWebAuthenticationSession?

    /// Called when the session ends for any reason (user closed it, or `stop()`).
    /// The model clears its `isPresented` flag; polling keeps running.
    var onFinish: (() -> Void)?

    override init() {
        super.init()
    }

    /// Opens `url` in the shared-session in-app browser. A no-op if one is already
    /// up, so a re-render can't stack sessions.
    func start(url: URL) {
        guard session == nil else { return }
        let session = ASWebAuthenticationSession(
            url: url,
            callbackURLScheme: Self.unusedCallbackScheme
        ) { [weak self] _, _ in
            // Hop to the main actor for the @MainActor state touches. The work is
            // trivial and order-insensitive, so a safe hop is preferable to
            // `assumeIsolated`, which would hard-crash on an undocumented
            // threading guarantee.
            Task { @MainActor in
                self?.session = nil
                self?.onFinish?()
            }
        }
        session.prefersEphemeralWebBrowserSession = false
        session.presentationContextProvider = self
        self.session = session
        session.start()
    }

    /// Tears the session down programmatically (poll loop reached success). The
    /// completion handler still fires, which is idempotent with `onFinish`.
    func stop() {
        session?.cancel()
        session = nil
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        if let anchor = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .filter({ $0.activationState == .foregroundActive })
            .flatMap(\.windows)
            .first(where: { $0.isKeyWindow }) {
            return anchor
        }
        // No foreground window can host the browser. Rather than present on a
        // detached anchor — which would silently do nothing with no way to
        // recover — settle the browser state so the model resets and can retry.
        Task { @MainActor [weak self] in self?.stop() }
        return ASPresentationAnchor()
    }
}
#endif
