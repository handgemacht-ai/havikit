import Foundation

/// How the capture sheet should present a failed submit (design §2, §4). Auth /
/// workspace failures show an actionable *Reconnect HAVI*; transient failures a
/// *Retry*; terminal failures dismiss with the reason and no retry.
public enum HaviSubmitFailureKind: Sendable, Equatable {
    case retry
    case reconnect
    case terminal
}

public struct HaviSubmitFailure: Sendable, Equatable {
    public let userMessage: String
    public let kind: HaviSubmitFailureKind
    public let code: String?

    public init(userMessage: String, kind: HaviSubmitFailureKind, code: String?) {
        self.userMessage = userMessage
        self.kind = kind
        self.code = code
    }
}

/// Result of a best-effort foreground submit. There is no on-disk outbox
/// (design §4) — the sheet stays open on `.failure`, drawing + comment intact.
public enum HaviSubmitResult: Sendable, Equatable {
    case success(id: String?)
    case failure(HaviSubmitFailure)
}
