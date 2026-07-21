#if canImport(UIKit)
import SwiftUI
import UIKit

/// Installs the capture triggers on the app root (design §2): a **shake**
/// (`motionEnded(.motionShake)` on a first-responder host) and a **two-finger
/// long-press** fallback on the key window for the Simulator, which has no shake.
/// A zero-size representable so it adds nothing visible; gating to
/// `#if DEBUG || DEV_LOGIN` is the integration's responsibility (`.haviOverlay()`
/// is only mounted there), and `Havi.isEnabled` guards the trigger's effect.
struct HaviTriggerInstaller: UIViewControllerRepresentable {
    let onTrigger: () -> Void

    func makeUIViewController(context: Context) -> HaviTriggerViewController {
        let controller = HaviTriggerViewController()
        controller.onTrigger = onTrigger
        return controller
    }

    func updateUIViewController(_ controller: HaviTriggerViewController, context: Context) {
        controller.onTrigger = onTrigger
    }
}

final class HaviTriggerViewController: UIViewController {
    var onTrigger: (() -> Void)?

    override var canBecomeFirstResponder: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        becomeFirstResponder()
        installTwoFingerLongPress()
    }

    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            onTrigger?()
        }
        super.motionEnded(motion, with: event)
    }

    private func installTwoFingerLongPress() {
        guard let window = view.window else { return }
        let already = window.gestureRecognizers?.contains { $0.name == Self.gestureName } ?? false
        guard !already else { return }
        let recognizer = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        recognizer.numberOfTouchesRequired = 2
        recognizer.minimumPressDuration = 0.6
        recognizer.cancelsTouchesInView = false
        recognizer.name = Self.gestureName
        window.addGestureRecognizer(recognizer)
    }

    @objc private func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began else { return }
        onTrigger?()
    }

    private static let gestureName = "havi.twoFingerLongPress"
}
#endif
