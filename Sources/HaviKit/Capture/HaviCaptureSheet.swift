#if canImport(UIKit)
import SwiftUI
import UIKit

/// The capture sheet (design §2, two-screen restructure = bead havi-oukr):
/// hosts a stack-style `NavigationView` with two pushed screens sharing one
/// `HaviCaptureModel` —
///
/// 1. `HaviCaptureImageScreen` — the frozen screenshot's own canvas-focused
///    screen: the multi-tool markup editor (pen / highlighter / arrow /
///    rectangle / blur-redact / select / crop, undo+redo, 6-color swatch).
/// 2. `HaviCaptureDetailsScreen` — diagnostics, comment, priority, and submit.
///
/// Back from Screen 2 returns to Screen 1 with every mark, the crop rect, the
/// comment, and every toggle intact — both screens read and write the same
/// `HaviCaptureModel`. On submit failure the sheet stays open on Screen 2,
/// fully editable, with a plain-language, `error.code`-mapped reason and a
/// Retry (or Reconnect HAVI) action; no silent drop, no disk queue.
///
/// Leaf-only accessibility identifiers, per the repo UI-test rule.
struct HaviCaptureSheet: View {
    let session: HaviCaptureSession
    let runtime: HaviRuntime
    let onClose: () -> Void

    @StateObject private var model: HaviCaptureModel
    @State private var showDetails = false
    @State private var showConnect = false
    @State private var connectReconnect = false
    @State private var showDiagnostics = false

    init(session: HaviCaptureSession, runtime: HaviRuntime, onClose: @escaping () -> Void) {
        self.session = session
        self.runtime = runtime
        self.onClose = onClose
        _model = StateObject(wrappedValue: HaviCaptureModel(session: session, runtime: runtime))
    }

    var body: some View {
        NavigationView {
            HaviCaptureImageScreen(model: model, image: session.image) {
                showDetails = true
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onClose)
                        .disabled(model.isSubmitting)
                }
            }
            .background(detailsLink)
        }
        .navigationViewStyle(.stack)
        .interactiveDismissDisabled(model.isSubmitting)
        .sheet(isPresented: $showConnect) {
            HaviConnectSheet(runtime: runtime, reconnect: connectReconnect) {
                showConnect = false
            }
        }
        .sheet(isPresented: $showDiagnostics) {
            HaviDiagnosticsDetailSheet(model: model) { showDiagnostics = false }
        }
    }

    /// Screen 2 is pushed programmatically from Screen 1's "Next", so the link
    /// itself renders nothing and rides along as a background. Every piece of
    /// report state lives on the shared `model`, which this sheet owns, so
    /// popping back rebuilds Screen 1 over the same marks, crop, comment,
    /// priority, labels, and diagnostics toggles.
    private var detailsLink: some View {
        NavigationLink(
            isActive: $showDetails,
            destination: {
                HaviCaptureDetailsScreen(
                    model: model,
                    runtime: runtime,
                    onBack: { showDetails = false },
                    onClose: onClose,
                    showConnect: $showConnect,
                    connectReconnect: $connectReconnect,
                    showDiagnostics: $showDiagnostics
                )
            },
            label: { EmptyView() }
        )
        .accessibilityHidden(true)
    }
}
#endif
