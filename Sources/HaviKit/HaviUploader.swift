import Foundation

/// Owns `URLSession` and the send path (design §1 threading): all network is
/// `async` on this actor and it receives an immutable `PendingAnnotation` on
/// submit. The multipart assembly + error-code mapping land in SDK-3; this
/// establishes the actor's ownership of the session (30 s request / 60 s
/// resource timeouts, design §4) so the send path has a single home.
public actor HaviUploader {
    private let config: HaviConfig
    private let session: URLSession

    init(config: HaviConfig) {
        self.config = config
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        session = URLSession(configuration: configuration)
    }
}
