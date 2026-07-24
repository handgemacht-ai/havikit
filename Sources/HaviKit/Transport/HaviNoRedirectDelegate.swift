import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Refuses every HTTP redirect on the SDK's sessions (parity with Android's
/// `Redirect.NEVER`). Requests carry `Authorization: Bearer …` and the workspace
/// header, and `URLSession` replays those headers when it follows a redirect —
/// including one that points at a host the SDK never trusted. Returning `nil`
/// hands the 3xx response itself back to the caller instead, where the normal
/// status classification takes over.
final class HaviNoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
