#if canImport(UIKit)
import CoreGraphics
import Observation
import UIKit

/// Drives one capture sheet (design §2): the drawn markup rectangle, comment,
/// priority, and the submit lifecycle. Submit encodes + downscales the frozen
/// still (§4), assembles the W3C envelope (§3) with markup projected into
/// image-pixel space, snapshots the credential + context, and hands an immutable
/// `PendingAnnotation` to the uploader actor. On failure the sheet stays open
/// with the drawing/comment intact and an honest, `error.code`-mapped reason.
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
    /// Normalized (0…1, image space) markup rectangle, or nil when nothing is
    /// drawn — then the `FragmentSelector` covers the full frame (§3).
    var markupFraction: CGRect?
    private(set) var phase: Phase = .editing

    private let session: HaviCaptureSession
    private let runtime: HaviRuntime

    init(session: HaviCaptureSession, runtime: HaviRuntime) {
        self.session = session
        self.runtime = runtime
        self.priority = session.initialPriority
    }

    var isSubmitting: Bool { phase == .submitting }

    var failure: HaviSubmitFailure? {
        if case .failed(let failure) = phase { return failure }
        return nil
    }

    func submit() async {
        guard phase != .submitting else { return }
        phase = .submitting

        let config = runtime.config
        guard let encoded = HaviImageRenderer.encodeWithSize(
            session.image,
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

        let input = buildInput(imageSize: encoded.size, config: config)

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
                reencoder: HaviImageRenderer.reencoder(for: session.image)
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

    private func buildInput(imageSize: HaviSize, config: HaviConfig) -> HaviEnvelopeInput {
        let markupRect = markupFraction.flatMap { fraction -> HaviRect? in
            guard HaviCaptureGeometry.isMeaningful(fraction: fraction) else { return nil }
            return HaviCaptureGeometry.imagePixelRect(fraction: fraction, imageSize: imageSize)
        }
        let fragment = markupRect ?? HaviCaptureGeometry.fullFrameRect(imageSize: imageSize)

        let hint = markupFraction.flatMap { fraction -> String? in
            guard HaviCaptureGeometry.isMeaningful(fraction: fraction) else { return nil }
            let center = CGPoint(
                x: fraction.midX * CGFloat(session.viewport.width),
                y: fraction.midY * CGFloat(session.viewport.height)
            )
            return HaviSnapshotter.nearestIdentifier(at: center, in: session.a11yFrames)
        }

        let logs = HaviDeviceInfo.formatLogs(HaviLogBuffer.shared.snapshot())

        return HaviEnvelopeInput(
            bundleID: Bundle.main.bundleIdentifier ?? "unknown",
            screen: session.screen,
            viewport: session.viewport,
            fragment: fragment,
            markup: markupRect,
            cssPath: HaviCaptureGeometry.cssPath(screen: session.screen, hint: hint),
            comment: comment,
            priority: priority,
            deviceInfo: HaviDeviceInfo.current(orientation: session.orientation),
            appLogs: logs.isEmpty ? nil : logs,
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
