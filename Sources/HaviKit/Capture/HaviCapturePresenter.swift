#if canImport(UIKit)
import Observation
import UIKit

/// One frozen capture cycle (design §2): the redacted still plus the context the
/// envelope needs — logical viewport, the a11y-id frames for the `CssSelector`
/// hint, orientation, screen name, and the priority carried in from
/// `Havi.setPriority`. Identifiable so the overlay can drive `.sheet(item:)`.
struct HaviCaptureSession: Identifiable {
    let id = UUID()
    let image: UIImage
    let viewport: HaviSize
    let a11yFrames: [HaviA11yFrame]
    let orientation: String
    let screen: String
    let initialPriority: HaviPriority
}

/// MainActor-observable presentation state the overlay binds to. `session` is
/// non-nil exactly while the capture sheet is up; `showsFloatingButton` mirrors
/// the (off-by-default) floating "bug" affordance from the config.
@MainActor
@Observable
final class HaviCapturePresenter {
    var session: HaviCaptureSession?
    var showsFloatingButton: Bool

    init(showsFloatingButton: Bool = false) {
        self.showsFloatingButton = showsFloatingButton
    }

    func present(_ session: HaviCaptureSession) {
        self.session = session
    }

    func dismiss() {
        session = nil
    }
}
#endif
