import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Fetches the workspace label vocabulary from `GET /api/label-definitions`
/// (API.md), using the same bearer + `x-havi-workspace-id` auth the annotation
/// submit uses. Sits alongside `HaviUploader` / `HaviConnectService` on the
/// transport actor side; all network is `async` on the actor. The fetch is
/// best-effort and never blocks capture: any failure (no base URL, non-200,
/// transport error, unparseable body) resolves to `nil`, and the capture sheet
/// falls back to the built-in priority control alone.
public actor HaviLabelService {
    private let config: HaviConfig
    private let session: URLSession

    public init(config: HaviConfig) {
        self.config = config
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        self.session = URLSession(
            configuration: configuration,
            delegate: HaviNoRedirectDelegate(),
            delegateQueue: nil
        )
    }

    /// Test seam: a session backed by a stub `URLProtocol` so the fetch runs
    /// without the network.
    init(config: HaviConfig, session: URLSession) {
        self.config = config
        self.session = session
    }

    /// Resolves the active label definitions for `workspaceID`, ordered by
    /// position. `nil` on any failure so the caller degrades to priority-only.
    func fetch(token: String, workspaceID: String) async -> [HaviLabelDefinition]? {
        guard let baseURL = config.baseURL, !token.isEmpty, !workspaceID.isEmpty else {
            return nil
        }

        var request = URLRequest(url: baseURL.appendingPathComponent("api/label-definitions"))
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(workspaceID, forHTTPHeaderField: "x-havi-workspace-id")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return nil
            }
            return HaviLabelDefinition.parseList(data)
        } catch {
            return nil
        }
    }
}
