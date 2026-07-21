#if canImport(UIKit)
import SwiftUI

/// The live capture host mounted by `.haviOverlay()` (design §2, §7). It wraps
/// the app root so it sits over every auth state without touching their
/// internals, installs the shake / two-finger-long-press triggers, relays
/// `.haviRedacted()` frames to the snapshotter, and presents the capture sheet.
/// When HaviKit is inert (`Havi.captureRuntime == nil`, the Release path) it is a
/// pure passthrough that renders nothing extra.
struct HaviOverlayContainer<Content: View>: View {
    let content: Content

    var body: some View {
        if let runtime = Havi.captureRuntime {
            HaviOverlayActive(runtime: runtime, content: content)
        } else {
            content
        }
    }
}

private struct HaviOverlayActive<Content: View>: View {
    let runtime: HaviRuntime
    let content: Content

    var body: some View {
        content
            .onPreferenceChange(HaviRedactionPreferenceKey.self) { regions in
                HaviRedactionRelay.shared.setRegions(regions)
            }
            .background(HaviTriggerInstaller { Havi.triggerCapture() })
            .overlay(alignment: .bottomTrailing) {
                if runtime.presenter.showsFloatingButton {
                    HaviFloatingCaptureButton { Havi.triggerCapture() }
                        .padding(20)
                }
            }
            .sheet(item: sheetBinding) { session in
                HaviCaptureSheet(
                    session: session,
                    runtime: runtime,
                    onClose: { runtime.presenter.dismiss() }
                )
            }
    }

    private var sheetBinding: Binding<HaviCaptureSession?> {
        Binding(
            get: { runtime.presenter.session },
            set: { runtime.presenter.session = $0 }
        )
    }
}

/// The optional, off-by-default floating "bug" affordance (design §2). Carries
/// the `havi-capture-button` leaf identifier so it is exercisable by UI tests
/// even though it is hidden by default (it auto-hides during read-aloud in the
/// integration so it never covers a child's word).
struct HaviFloatingCaptureButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "ladybug.fill")
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 54, height: 54)
                .background(Circle().fill(HaviMarkupCanvas.accent))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
                .shadow(color: HaviMarkupCanvas.accent.opacity(0.35), radius: 10, y: 4)
                .shadow(color: Color.black.opacity(0.15), radius: 3, y: 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Report to HAVI")
        .accessibilityIdentifier("havi-capture-button")
    }
}
#endif
