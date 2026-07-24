import Foundation

/// What the uploader should do next for a given failure (design §4). The
/// re-encode actions are handled inside the actor; the others fall through to a
/// `HaviSubmitFailure` the capture sheet surfaces.
enum HaviErrorAction: Equatable {
    /// `unsupported_media_type` — re-encode to PNG once and retry (design §4).
    case reencodePNG
    /// `payload_too_large` — re-encode at 1024 longest side and retry.
    case reencodeSmaller
    /// Network / timeout / `storage_error` — one in-memory retry, then Retry.
    case transientRetry
    /// Auth / workspace — route to the reconnect path, never blind-retry.
    case reauth
    /// `validation_error` / `forbidden` / `not_found` — do not retry.
    case terminal
}

struct HaviMappedError: Equatable {
    let code: String?
    let userMessage: String
    let action: HaviErrorAction
}

/// The outcome of one completed HTTP round-trip, before any fallback handling.
enum HaviResponseClassification: Equatable {
    case success(id: String?)
    case mapped(HaviMappedError)
}

/// Decodes the standard error envelope and maps on `error.code`, never HTTP
/// status (design §4 — the controller returns stable codes while statuses vary).
enum HaviErrorMapping {
    private struct ServerError: Decodable {
        struct Body: Decodable {
            let code: String?
            let message: String?
        }
        let error: Body?
    }

    private struct CreatedEnvelope: Decodable {
        struct Resource: Decodable { let id: String? }
        let data: Resource?
    }

    static func mapCode(_ code: String?) -> HaviMappedError {
        switch code {
        case "unauthorized":
            return .init(code: code, userMessage: "HAVI sign-in expired — reconnect.", action: .reauth)
        case "workspace_required", "missing_workspace_id", "invalid_workspace_id", "workspace_not_found":
            return .init(code: code, userMessage: "HAVI workspace not set up — reconnect.", action: .reauth)
        case "forbidden":
            return .init(code: code, userMessage: "Not allowed for this workspace.", action: .terminal)
        case "unsupported_media_type":
            return .init(code: code, userMessage: "Screenshot format rejected.", action: .reencodePNG)
        case "payload_too_large":
            return .init(code: code, userMessage: "Screenshot too large — retrying smaller.", action: .reencodeSmaller)
        case "validation_error":
            return .init(code: code, userMessage: "Couldn't submit annotation (validation).", action: .terminal)
        case "storage_error":
            return .init(code: code, userMessage: "Server storage hiccup — retry.", action: .transientRetry)
        case "not_found":
            return .init(code: code, userMessage: "Annotation not found.", action: .terminal)
        default:
            return .init(code: code, userMessage: "Couldn't submit annotation.", action: .terminal)
        }
    }

    /// Transport-class failure (URLSession threw, or no HTTP response): treated
    /// as transient (design §4 network row).
    static let transientTransport = HaviMappedError(
        code: nil,
        userMessage: "No connection to HAVI — retry.",
        action: .transientRetry
    )

    static func classify(status: Int, body: Data) -> HaviResponseClassification {
        if (200 ..< 300).contains(status) {
            let id = (try? JSONDecoder().decode(CreatedEnvelope.self, from: body))?.data?.id
            return .success(id: id)
        }
        if let decoded = try? JSONDecoder().decode(ServerError.self, from: body), let code = decoded.error?.code {
            return .mapped(mapCode(code))
        }
        // No JSON error.code: classify by transport class — 5xx and a bare 429
        // (rate limit / edge throttle, often body-less) transient, else terminal.
        if status == tooManyRequests || status >= 500 {
            return .mapped(transientTransport)
        }
        return .mapped(.init(code: nil, userMessage: "Couldn't submit annotation.", action: .terminal))
    }

    private static let tooManyRequests = 429
}
