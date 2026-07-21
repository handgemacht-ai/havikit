import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A pending device-code pairing (design §5): the poll `deviceCode`, the full
/// approve URL to open on the laptop (the relative `approve_url` resolved against
/// the base URL), and the client-side TTL deadline after which the link is
/// treated as expired.
public struct HaviSetupLink: Sendable, Equatable {
    public let deviceCode: String
    public let approveURL: URL
    public let expiresAt: Date

    public init(deviceCode: String, approveURL: URL, expiresAt: Date) {
        self.deviceCode = deviceCode
        self.approveURL = approveURL
        self.expiresAt = expiresAt
    }
}

public struct HaviConnectFailure: Sendable, Equatable {
    public let userMessage: String

    public init(userMessage: String) {
        self.userMessage = userMessage
    }
}

/// Terminal outcome of the exchange poll loop (design §5).
public enum HaviConnectResult: Sendable, Equatable {
    case connected(HaviConnectedSession)
    case expired
    case cancelled
    case failed(HaviConnectFailure)
}

/// One completed exchange round-trip before the loop decides what to do next.
enum HaviExchangeStep: Equatable {
    case pending
    case approved(HaviConnectedSession)
    case gone
    case transient
}

/// Device-code login client (design §5). Sits alongside `HaviUploader` on the
/// transport side and reuses the live setup-link primitives: `createSetupLink`
/// requests a `client_type: mobile` pairing, `runExchange` polls the exchange
/// endpoint until the developer approves on their laptop, the link's TTL expires,
/// or the flow is cancelled. On approval the resolved session is persisted to
/// `HaviTokenStore` before returning. All network is `async` on the actor and
/// the poll cadence / clock are injectable so the state machine is unit-tested
/// without touching the network.
public actor HaviConnectService {
    static let linkTTL: TimeInterval = 600

    private let config: HaviConfig
    private let tokenStore: HaviTokenStore
    private let session: URLSession
    private let now: @Sendable () -> Date
    private let sleep: @Sendable (TimeInterval) async -> Void

    public init(config: HaviConfig, tokenStore: HaviTokenStore) {
        self.config = config
        self.tokenStore = tokenStore
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: configuration)
        self.now = { Date() }
        self.sleep = { seconds in
            try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
        }
    }

    /// Test seam: a session backed by a stub `URLProtocol`, a controllable clock,
    /// and a no-op sleep so the poll loop runs without the network or wall time.
    init(
        config: HaviConfig,
        tokenStore: HaviTokenStore,
        session: URLSession,
        now: @escaping @Sendable () -> Date,
        sleep: @escaping @Sendable (TimeInterval) async -> Void
    ) {
        self.config = config
        self.tokenStore = tokenStore
        self.session = session
        self.now = now
        self.sleep = sleep
    }

    /// Requests a fresh `client_type: mobile` pairing. A used/expired link is not
    /// refreshed here — the caller regenerates by calling this again (design §5).
    public func createSetupLink() async -> Result<HaviSetupLink, HaviConnectFailure> {
        guard let baseURL = config.baseURL else {
            return .failure(.init(userMessage: "HAVI isn't configured on this build."))
        }
        var request = URLRequest(url: baseURL.appendingPathComponent("api/setup/link"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["client_type": "mobile"])

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failure(.init(userMessage: "No connection to HAVI — try again."))
            }
            if http.statusCode == 201,
               let link = Self.parseSetupLink(data, baseURL: baseURL, now: now()) {
                return .success(link)
            }
            return .failure(.init(userMessage: Self.createFailureMessage(status: http.statusCode, body: data)))
        } catch {
            return .failure(.init(userMessage: "No connection to HAVI — try again."))
        }
    }

    /// Polls the exchange endpoint on `interval` until the developer approves, the
    /// link's TTL passes (`expired`), or `isCancelled` flips (`cancelled`). A
    /// transient blip keeps polling — the TTL bounds the loop — while a server
    /// `setup_code_expired` / `_used` / `_not_found` short-circuits to `expired`.
    public func runExchange(
        link: HaviSetupLink,
        interval: TimeInterval = 3,
        isCancelled: @escaping @Sendable () -> Bool
    ) async -> HaviConnectResult {
        guard let baseURL = config.baseURL else {
            return .failed(.init(userMessage: "HAVI isn't configured on this build."))
        }

        while true {
            if isCancelled() { return .cancelled }
            if now() >= link.expiresAt { return .expired }

            switch await exchangeStep(baseURL: baseURL, deviceCode: link.deviceCode) {
            case .approved(let session):
                tokenStore.store(session)
                return .connected(session)
            case .gone:
                return .expired
            case .pending, .transient:
                if isCancelled() { return .cancelled }
                await sleep(interval)
            }
        }
    }

    private func exchangeStep(baseURL: URL, deviceCode: String) async -> HaviExchangeStep {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/setup/link/exchange"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["device_code": deviceCode])

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .transient }
            return Self.classifyExchange(status: http.statusCode, body: data)
        } catch {
            return .transient
        }
    }

    // MARK: - Pure parsing / classification (unit-tested directly)

    /// Maps one exchange round-trip: 201 → approved (session parsed from the
    /// envelope), 202 → pending, a `setup_code_*` gone code → gone, everything
    /// else → transient so the loop keeps polling until the TTL bounds it.
    static func classifyExchange(status: Int, body: Data) -> HaviExchangeStep {
        if status == 201 {
            return parseSession(body).map(HaviExchangeStep.approved) ?? .transient
        }
        if status == 202 {
            return .pending
        }
        if let decoded = try? snakeDecoder().decode(ErrorEnvelope.self, from: body),
           let code = decoded.error?.code {
            switch code {
            case "setup_code_expired", "setup_code_used", "setup_code_not_found":
                return .gone
            default:
                return .transient
            }
        }
        return .transient
    }

    static func parseSetupLink(_ data: Data, baseURL: URL, now: Date) -> HaviSetupLink? {
        guard let decoded = try? snakeDecoder().decode(CreateEnvelope.self, from: data),
              let payload = decoded.data,
              let deviceCode = payload.deviceCode, !deviceCode.isEmpty,
              let approvePath = payload.approveUrl,
              let approveURL = URL(string: approvePath, relativeTo: baseURL)?.absoluteURL
        else { return nil }
        let expiresAt = payload.expiresAt.flatMap(parseDate) ?? now.addingTimeInterval(linkTTL)
        return HaviSetupLink(deviceCode: deviceCode, approveURL: approveURL, expiresAt: expiresAt)
    }

    static func parseSession(_ data: Data) -> HaviConnectedSession? {
        guard let decoded = try? snakeDecoder().decode(ExchangeEnvelope.self, from: data),
              let payload = decoded.data,
              let token = payload.token, !token.isEmpty,
              let workspaceID = payload.workspace?.id, !workspaceID.isEmpty
        else { return nil }
        return HaviConnectedSession(
            accessToken: token,
            workspaceID: workspaceID,
            refreshToken: nil,
            expiresAt: payload.expiresAt.flatMap(parseDate),
            userName: payload.user?.email,
            workspaceName: payload.workspace?.name
        )
    }

    static func createFailureMessage(status: Int, body: Data) -> String {
        if let decoded = try? snakeDecoder().decode(ErrorEnvelope.self, from: body),
           let code = decoded.error?.code {
            switch code {
            case "setup_code_expired", "setup_code_used":
                return "That link expired — get a new one."
            default:
                return "Couldn't start HAVI sign-in — try again."
            }
        }
        return "Couldn't start HAVI sign-in — try again."
    }

    /// Parses an RFC 3339 timestamp with or without fractional seconds (Elixir's
    /// `DateTime.to_iso8601` emits either), mirroring `SpeechTokenClient`.
    static func parseDate(_ string: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: string) { return date }
        return ISO8601DateFormatter().date(from: string)
    }

    private static func snakeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    private struct CreateEnvelope: Decodable {
        struct Payload: Decodable {
            let deviceCode: String?
            let approveUrl: String?
            let expiresAt: String?
        }
        let data: Payload?
    }

    private struct ExchangeEnvelope: Decodable {
        struct Payload: Decodable {
            let token: String?
            let expiresAt: String?
            let user: UserPayload?
            let workspace: WorkspacePayload?
        }
        let data: Payload?
    }

    private struct UserPayload: Decodable {
        let id: String?
        let email: String?
    }

    private struct WorkspacePayload: Decodable {
        let id: String?
        let name: String?
        let type: String?
    }

    private struct ErrorEnvelope: Decodable {
        struct Body: Decodable { let code: String? }
        let error: Body?
    }
}
