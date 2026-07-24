#if canImport(UIKit)
import SwiftUI
import UIKit

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

    /// `HaviRuntime` is not itself observable, so the presenter it holds is what
    /// this view observes — the floating button, the confirmation toast, and the
    /// capture sheet all hang off its published state.
    @ObservedObject private var presenter: HaviCapturePresenter

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(runtime: HaviRuntime, content: Content) {
        self.runtime = runtime
        self.content = content
        _presenter = ObservedObject(wrappedValue: runtime.presenter)
    }

    var body: some View {
        content
            .onPreferenceChange(HaviRedactionPreferenceKey.self) { regions in
                HaviRedactionRelay.shared.setRegions(regions)
            }
            .background(HaviTriggerInstaller { Havi.triggerCapture() })
            .overlay(alignment: .bottomTrailing) {
                if presenter.showsFloatingButton {
                    HaviFloatingCaptureButton { Havi.triggerCapture() }
                        .padding(20)
                }
            }
            .overlay(alignment: .top) {
                if let confirmation = presenter.confirmation {
                    HaviSubmitConfirmationToast(message: confirmation.message) {
                        presenter.clearConfirmation(confirmation.id)
                    }
                    .id(confirmation.id)
                    .transition(.opacity)
                }
            }
            .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: presenter.confirmation)
            .sheet(item: sheetBinding) { session in
                HaviCaptureSheet(
                    session: session,
                    runtime: runtime,
                    onClose: { presenter.dismiss() }
                )
            }
    }

    private var sheetBinding: Binding<HaviCaptureSession?> {
        Binding(
            get: { presenter.session },
            set: { presenter.session = $0 }
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

/// The brief "Report sent" confirmation shown after a successful submit (design
/// §2, phone-QA finding 3): a frosted `.regularMaterial` pill with a system-green
/// check, matching the connected-state success treatment. Auto-dismisses after a
/// short window and announces itself to VoiceOver on appear.
struct HaviSubmitConfirmationToast: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(HaviMarkupCanvas.success)
            Text(message)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(HaviMarkupCanvas.success.opacity(0.25), lineWidth: 1))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .padding(.top, 12)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
        .accessibilityAddTraits(.isStaticText)
        .accessibilityIdentifier("havi-submit-confirmation")
        .task {
            UIAccessibility.post(notification: .announcement, argument: message)
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            onDismiss()
        }
    }
}
#endif
