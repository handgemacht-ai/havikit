import ExpoModulesCore
import HaviKit
import SwiftUI
import UIKit

/// Mounts HaviKit's `.haviOverlay()` into the live RN window hierarchy. RN has no
/// SwiftUI root, so `Havi.captureRuntime.presenter` would never be observed and
/// nothing would present the capture sheet. Hosting `Color.clear.haviOverlay()`
/// in a `UIHostingController` restores that: it installs the shake /
/// two-finger-long-press triggers and drives `.sheet(item:)`, so both
/// programmatic `capture()` and the triggers present. Mount once at the app root
/// (`<HaviOverlay style={StyleSheet.absoluteFill} pointerEvents="box-none" />`).
///
/// The content disables hit-testing so RN touches pass through; the trigger
/// installer works on the key window and the presented sheet hit-tests normally.
/// When HaviKit is inert (`Havi.captureRuntime == nil`) the overlay is a pure
/// passthrough that renders nothing extra.
final class HaviOverlayView: ExpoView {
  private let host: UIHostingController<HaviOverlayRoot>

  required init(appContext: AppContext? = nil) {
    host = UIHostingController(rootView: HaviOverlayRoot())
    super.init(appContext: appContext)

    host.view.backgroundColor = .clear
    host.view.translatesAutoresizingMaskIntoConstraints = false
    addSubview(host.view)
    NSLayoutConstraint.activate([
      host.view.leadingAnchor.constraint(equalTo: leadingAnchor),
      host.view.trailingAnchor.constraint(equalTo: trailingAnchor),
      host.view.topAnchor.constraint(equalTo: topAnchor),
      host.view.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    if window == nil {
      detachHost()
    } else {
      attachHost()
    }
  }

  private func attachHost() {
    guard host.parent == nil, let parent = closestViewController() else { return }
    parent.addChild(host)
    host.didMove(toParent: parent)
  }

  private func detachHost() {
    guard host.parent != nil else { return }
    host.willMove(toParent: nil)
    host.removeFromParent()
  }

  /// The nearest enclosing view controller in the responder chain, so the hosted
  /// SwiftUI sheet presents from the RN screen that mounts the overlay.
  private func closestViewController() -> UIViewController? {
    var responder: UIResponder? = next
    while let current = responder {
      if let controller = current as? UIViewController {
        return controller
      }
      responder = current.next
    }
    return window?.rootViewController
  }
}

private struct HaviOverlayRoot: View {
  var body: some View {
    Color.clear
      .allowsHitTesting(false)
      .haviOverlay()
  }
}
