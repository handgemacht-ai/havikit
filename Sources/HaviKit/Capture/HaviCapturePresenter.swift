#if canImport(UIKit)
import Observation
import UIKit

/// One frozen capture cycle (design §2): the redacted still plus the context the
/// envelope needs — the a11y-id frames for the `CssSelector` hint, orientation,
/// screen name, and the priority carried in from `Havi.setPriority`. The reported
/// viewport is derived from the still's own point size (`image.size`) at
/// envelope-build time, not carried separately. Identifiable so the overlay can
/// drive `.sheet(item:)`.
struct HaviCaptureSession: Identifiable {
    let id = UUID()
    let image: UIImage
    let a11yFrames: [HaviA11yFrame]
    let orientation: String
    let screen: String
    let initialPriority: HaviPriority
}

/// A transient "Report sent" confirmation the overlay renders as a brief frosted
/// toast after a submit succeeds and the capture sheet dismisses. Fresh identity
/// per submission so the toast re-appears (and re-announces to VoiceOver) each
/// time, even back-to-back.
struct HaviSubmitConfirmation: Identifiable, Equatable {
    let id = UUID()
    var message = "Report sent"
}

/// MainActor-observable presentation state the overlay binds to. `session` is
/// non-nil exactly while the capture sheet is up; `showsFloatingButton` mirrors
/// the (off-by-default) floating "bug" affordance from the config; `confirmation`
/// is set for the brief window the "Report sent" toast is on screen.
@MainActor
@Observable
final class HaviCapturePresenter {
    var session: HaviCaptureSession?
    var showsFloatingButton: Bool
    private(set) var confirmation: HaviSubmitConfirmation?

    init(showsFloatingButton: Bool = false) {
        self.showsFloatingButton = showsFloatingButton
    }

    func present(_ session: HaviCaptureSession) {
        self.session = session
    }

    func dismiss() {
        session = nil
    }

    /// Submit succeeded: dismiss the capture sheet and raise the brief "Report
    /// sent" confirmation the overlay renders (design §2, phone-QA finding 3).
    func confirmSubmission() {
        session = nil
        confirmation = HaviSubmitConfirmation()
    }

    func clearConfirmation() {
        confirmation = nil
    }
}
#endif
