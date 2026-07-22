#if canImport(UIKit)
import CoreGraphics
import Observation
import UIKit

/// Drives one capture sheet (design §2): the markup marks, comment, priority,
/// captured diagnostics, and the submit lifecycle. Submit burns the blur/redact
/// regions into the still, encodes + downscales it (§4), assembles the W3C
/// envelope (§3) with the marks serialized into image-pixel space, snapshots the
/// credential + context, and hands an immutable `PendingAnnotation` to the uploader
/// actor. On failure the sheet stays open with the marks/comment intact and an
/// honest, `error.code`-mapped reason.
@MainActor
@Observable
final class HaviCaptureModel {
    enum Phase: Equatable {
        case editing
        case submitting
        case failed(HaviSubmitFailure)
    }

    var comment: String = ""
    var priority: HaviPriority
    /// The multi-mark markup editor (bead havi-6953). Owned here so `submit`
    /// serializes its marks into the envelope and burns its blur regions into the
    /// pixels before encoding.
    let markup = HaviMarkupModel()
    /// The crop tool's rect (bead havi-oukr), normalized to the full frozen
    /// still — the same space marks live in. Shared by both capture screens.
    let crop = HaviCropModel()
    private(set) var phase: Phase = .editing

    /// Diagnostics frozen at capture time so the badge, the detail sheet, and the
    /// submitted envelope all describe the exact same breadcrumb snapshot.
    let diagnostics: HaviDiagnostics.Split
    var includeConsoleErrors = true
    var includeNetworkErrors = true

    private let session: HaviCaptureSession
    private let runtime: HaviRuntime

    init(session: HaviCaptureSession, runtime: HaviRuntime) {
        self.session = session
        self.runtime = runtime
        self.priority = session.initialPriority
        self.diagnostics = HaviDiagnostics.split(HaviLogBuffer.shared.snapshot())
    }

    /// The drawing tool to restore when crop mode ends, so confirming/cancelling
    /// a crop returns the user to the tool they were annotating with.
    private var toolBeforeCrop: HaviMarkTool = .pen

    var isSubmitting: Bool { phase == .submitting }

    /// Whether the flow may advance to Screen 2. Crop is a confirmed step, so an
    /// open crop draft (`crop.isEditing`) must be confirmed or cancelled first —
    /// advancing with a live, unconfirmed crop would bypass the very confirmation
    /// the crop tray exists for.
    var canProceed: Bool { !isSubmitting && !crop.isEditing }

    // MARK: - Crop mode (bead havi-od6t)

    /// Opens crop mode: remembers the tool to return to and snapshots the crop so
    /// Cancel can revert. Called when the crop tool becomes active.
    func beginCropEditing(previousTool: HaviMarkTool) {
        if previousTool != .crop { toolBeforeCrop = previousTool }
        crop.beginEditing()
    }

    /// Keeps the drafted crop, zooms the canvas into it, and returns to the
    /// prior drawing tool.
    func confirmCrop() {
        crop.confirm()
        markup.selectTool(toolBeforeCrop)
    }

    /// Reverts to the last confirmed crop and returns to the prior drawing tool.
    func cancelCrop() {
        crop.cancel()
        markup.selectTool(toolBeforeCrop)
    }

    var consoleErrorCount: Int { diagnostics.consoleErrors.count }
    var networkErrorCount: Int { diagnostics.networkErrors.count }

    var failure: HaviSubmitFailure? {
        if case .failed(let failure) = phase { return failure }
        return nil
    }

    func submit() async {
        guard phase != .submitting else { return }
        phase = .submitting

        let config = runtime.config
        let cropRect = crop.rect

        // Crop is a real byte crop and runs FIRST: pixels outside the crop
        // never leave the device — the same privacy posture as redaction.
        // Redaction burns into the already-cropped canvas, so every downstream
        // step (encode and every re-encode fallback) only ever sees it.
        let cropped = HaviImageCropper.crop(session.image, to: cropRect)

        // Marks stay normalized to the full frozen still while editing; only
        // now, once the crop is final, are they re-expressed in the cropped
        // image's own 0…1 space — anything that landed fully outside is
        // dropped, anything partially outside is clipped by the existing
        // pixel-rect clamping once it reaches pixel space.
        let projectedMarks = HaviCropGeometry.projectMarks(markup.marks, into: cropRect)

        let outgoing = HaviImageRedactor.burn(
            blurRects: HaviMarkupSerializer.blurRects(of: projectedMarks),
            into: cropped
        )
        guard let encoded = HaviImageRenderer.encodeWithSize(
            outgoing,
            format: config.imageFormat,
            maxBytes: config.imageFormat.maxUploadBytes
        ) else {
            phase = .failed(HaviSubmitFailure(
                userMessage: "Couldn't prepare the screenshot.",
                kind: .terminal,
                code: nil
            ))
            return
        }

        let input = buildInput(marks: projectedMarks, cropRect: cropRect, imageSize: encoded.size, config: config)

        let token = runtime.tokenStore.accessToken ?? config.devToken
        let workspace = runtime.tokenStore.workspaceID ?? config.workspaceID

        let pending: PendingAnnotation
        do {
            pending = try PendingAnnotation.make(
                input: input,
                imageData: encoded.data,
                imageFormat: config.imageFormat,
                workspaceID: workspace,
                bearerToken: token,
                reencoder: HaviImageRenderer.reencoder(for: outgoing)
            )
        } catch {
            phase = .failed(HaviSubmitFailure(
                userMessage: "Couldn't submit annotation (validation).",
                kind: .terminal,
                code: nil
            ))
            return
        }

        let result = await runtime.uploader.submit(pending)
        switch result {
        case .success:
            HaviLogBuffer.shared.clear()
            runtime.pendingPriority = nil
            runtime.presenter.dismiss()
        case .failure(let failure):
            phase = .failed(failure)
        }
    }

    func retry() {
        guard case .failed = phase else { return }
        phase = .editing
        Task { await submit() }
    }

    // MARK: - Envelope input

    private func buildInput(marks: [HaviMark], cropRect: CGRect, imageSize: HaviSize, config: HaviConfig) -> HaviEnvelopeInput {
        let markupSvg = HaviMarkupSerializer.svg(for: marks, imageSize: imageSize)
        let fragment = HaviMarkupSerializer.boundingBox(of: marks, imageSize: imageSize)
            ?? HaviCaptureGeometry.fullFrameRect(imageSize: imageSize)

        // The CssSelector hint's center still needs FULL-image / window-point
        // space (a11yFrames were captured there, unaffected by crop) — so it is
        // derived from the surviving marks' ORIGINAL (pre-projection) geometry,
        // not the crop-relative `marks` used for the fragment/svg above.
        let survivingIDs = Set(marks.map(\.id))
        let hintSourceMarks = markup.marks.filter { survivingIDs.contains($0.id) }
        let hint = HaviMarkupSerializer.normalizedBoundingBox(of: hintSourceMarks).flatMap { bounds -> String? in
            let center = CGPoint(
                x: bounds.midX * CGFloat(session.viewport.width),
                y: bounds.midY * CGFloat(session.viewport.height)
            )
            return HaviSnapshotter.nearestIdentifier(at: center, in: session.a11yFrames)
        }

        let consoleErrors = includeConsoleErrors
            ? nonEmpty(HaviDiagnostics.formatConsole(diagnostics.consoleErrors))
            : nil
        let networkErrors = includeNetworkErrors
            ? nonEmpty(HaviDiagnostics.formatNetwork(diagnostics.networkErrors))
            : nil
        let appLogs = nonEmpty(HaviDeviceInfo.formatLogs(diagnostics.breadcrumbs))

        return HaviEnvelopeInput(
            bundleID: Bundle.main.bundleIdentifier ?? "unknown",
            screen: session.screen,
            viewport: HaviCropGeometry.projectedViewport(session.viewport, crop: cropRect),
            fragment: fragment,
            markupSvg: markupSvg,
            cssPath: HaviCaptureGeometry.cssPath(screen: session.screen, hint: hint),
            comment: comment,
            priority: priority,
            deviceInfo: HaviDeviceInfo.current(orientation: session.orientation),
            consoleErrors: consoleErrors,
            networkErrors: networkErrors,
            appLogs: appLogs,
            dev: HaviDev(
                project: config.project,
                worktree: config.worktree,
                branch: config.branch,
                commit: config.commit
            ),
            contexts: HaviContextStore.shared.snapshotContexts(),
            tags: HaviContextStore.shared.snapshotTags()
        )
    }

    private func nonEmpty(_ value: String) -> String? { value.isEmpty ? nil : value }
}

extension HaviDeviceInfo {
    /// The live `device-info` line for this device + build (design §3).
    static func current(orientation: String) -> String {
        format(
            model: machineIdentifier(),
            systemName: UIDevice.current.systemName,
            systemVersion: UIDevice.current.systemVersion,
            appName: bundleString("CFBundleDisplayName") ?? bundleString("CFBundleName"),
            version: bundleString("CFBundleShortVersionString"),
            build: bundleString("CFBundleVersion"),
            locale: Locale.current.identifier,
            orientation: orientation
        )
    }

    private static func bundleString(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String, !value.isEmpty else { return nil }
        return value
    }

    /// The hardware model string (`iPhone15,3`), which `UIDevice.model` does not
    /// expose — read from `uname`. Falls back to `UIDevice.model` on a Simulator.
    private static func machineIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let identifier = withUnsafeBytes(of: &systemInfo.machine) { raw -> String in
            let bytes = raw.prefix { $0 != 0 }
            return String(decoding: bytes, as: UTF8.self)
        }
        return identifier.isEmpty ? UIDevice.current.model : identifier
    }
}
#endif
