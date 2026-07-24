import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Owns `URLSession` and the send path (design §1, §4): all network is `async`
/// on this actor and it receives an immutable `PendingAnnotation` on submit.
/// Best-effort foreground delivery — no on-disk outbox: one send attempt, one
/// in-memory retry on a transient failure, then the outcome is surfaced to the
/// capture sheet. Server-driven re-encode fallbacks (`unsupported_media_type` →
/// PNG, `payload_too_large` → 1024 px) run transparently once each.
///
/// `tokenStore`, when supplied, is cleared the moment the server rejects the
/// credential: the reconnect prompt can be dismissed, and a revoked token left in
/// the Keychain would 401 every later capture forever.
public actor HaviUploader {
    private let config: HaviConfig
    private let session: URLSession
    private let retryDelayNanoseconds: UInt64
    private let tokenStore: HaviTokenStore?

    init(config: HaviConfig, tokenStore: HaviTokenStore? = nil) {
        self.config = config
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: configuration)
        self.retryDelayNanoseconds = 1_500_000_000
        self.tokenStore = tokenStore
    }

    /// Test seam: inject a session backed by a stub `URLProtocol` and a zero
    /// retry delay so the transport tests do not touch the network or sleep.
    init(config: HaviConfig, session: URLSession, retryDelayNanoseconds: UInt64, tokenStore: HaviTokenStore? = nil) {
        self.config = config
        self.session = session
        self.retryDelayNanoseconds = retryDelayNanoseconds
        self.tokenStore = tokenStore
    }

    public func submit(_ pending: PendingAnnotation) async -> HaviSubmitResult {
        guard let baseURL = config.baseURL else {
            return .failure(.init(userMessage: "HAVI workspace not set up — reconnect.", kind: .reconnect, code: nil))
        }
        guard let token = pending.bearerToken, !token.isEmpty,
              let workspace = pending.workspaceID, !workspace.isEmpty
        else {
            return .failure(.init(userMessage: "HAVI workspace not set up — reconnect.", kind: .reconnect, code: nil))
        }

        var format = pending.imageFormat
        var imageData = pending.imageData
        var didRetryTransient = false
        var didFallBackToPNG = false
        var didReencodeSmaller = false

        while true {
            let classification = await sendOnce(
                baseURL: baseURL,
                token: token,
                workspace: workspace,
                annotationJSON: pending.annotationJSON,
                imageData: imageData,
                format: format,
                siblings: pending.siblings,
                idempotencyKey: pending.idempotencyKey
            )

            switch classification {
            case .success(let id):
                return .success(id: id)

            case .mapped(let mapped):
                switch mapped.action {
                case .reencodePNG:
                    if !didFallBackToPNG, format == .jpeg,
                       let reencoded = pending.reencoder?(.png, HaviImagePlan.defaultMaxLongestSide) {
                        didFallBackToPNG = true
                        format = .png
                        imageData = reencoded
                        continue
                    }
                    return .failure(.init(userMessage: mapped.userMessage, kind: .terminal, code: mapped.code))

                case .reencodeSmaller:
                    if !didReencodeSmaller,
                       let reencoded = pending.reencoder?(format, HaviImagePlan.payloadTooLargeLongestSide) {
                        didReencodeSmaller = true
                        imageData = reencoded
                        continue
                    }
                    return .failure(.init(userMessage: mapped.userMessage, kind: .terminal, code: mapped.code))

                case .transientRetry:
                    if !didRetryTransient {
                        didRetryTransient = true
                        try? await Task.sleep(nanoseconds: retryDelayNanoseconds)
                        continue
                    }
                    return .failure(.init(userMessage: mapped.userMessage, kind: .retry, code: mapped.code))

                case .reauth:
                    tokenStore?.clear()
                    return .failure(.init(userMessage: mapped.userMessage, kind: .reconnect, code: mapped.code))

                case .terminal:
                    return .failure(.init(userMessage: mapped.userMessage, kind: .terminal, code: mapped.code))
                }
            }
        }
    }

    private func sendOnce(
        baseURL: URL,
        token: String,
        workspace: String,
        annotationJSON: String,
        imageData: Data?,
        format: HaviImageFormat,
        siblings: [String: String],
        idempotencyKey: String
    ) async -> HaviResponseClassification {
        let boundary = HaviMultipart.boundary()
        var request = URLRequest(url: baseURL.appendingPathComponent("api/annotations"))
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(workspace, forHTTPHeaderField: "x-havi-workspace-id")
        request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
        request.httpBody = HaviMultipart.body(
            boundary: boundary,
            annotationJSON: annotationJSON,
            imageData: imageData,
            imageFilename: format.multipartFilename,
            imageContentType: format.multipartContentType,
            siblings: siblings
        )

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .mapped(HaviErrorMapping.transientTransport)
            }
            return HaviErrorMapping.classify(status: http.statusCode, body: data)
        } catch {
            return .mapped(HaviErrorMapping.transientTransport)
        }
    }
}
