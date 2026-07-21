import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import HaviKit

/// Device-code poll state-machine tests (design §5): pending→approved (with the
/// session persisted), pending→expired via the client TTL, and cancel — all
/// against the stubbed `URLProtocol` and an injected clock / no-op sleep so
/// nothing touches the network or wall time. Plus the pure classify/parse seams.
final class HaviConnectServiceTests: XCTestCase {
    private let approvedJSON = """
    {"data":{"status":"approved","client_type":"mobile","token":"tok-abc","token_type":"Bearer",\
    "expires_at":"2026-10-19T10:30:00Z","user":{"id":"u1","email":"marco@alimax.at"},\
    "workspace":{"id":"ws-9","name":"Team HAVI","type":"team"}}}
    """
    private let pendingJSON = #"{"data":{"status":"pending","token_returned":false}}"#

    private func stubSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func config() -> HaviConfig {
        HaviConfig(
            isEnabled: true,
            baseURL: URL(string: "https://havi.example.test")!,
            workspaceID: nil,
            project: nil,
            worktree: nil,
            branch: nil,
            commit: nil,
            imageFormat: .png,
            devToken: nil,
            redaction: HaviRedactionPolicy()
        )
    }

    private func link(expiresAt: TimeInterval = 1_000_000) -> HaviSetupLink {
        HaviSetupLink(
            deviceCode: "dev-1",
            approveURL: URL(string: "https://havi.example.test/?setup_code=dev-1")!,
            expiresAt: Date(timeIntervalSince1970: expiresAt)
        )
    }

    // MARK: - Poll loop

    func testPendingThenApprovedPersistsSession() async {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(status: 202, json: pendingJSON)
        StubURLProtocol.enqueue(status: 201, json: approvedJSON)

        let store = HaviTokenStore(backing: HaviInMemoryCredentialBacking())
        let service = HaviConnectService(
            config: config(),
            tokenStore: store,
            session: stubSession(),
            now: { Date(timeIntervalSince1970: 0) },
            sleep: { _ in }
        )

        let result = await service.runExchange(link: link(), interval: 0, isCancelled: { false })

        guard case .connected(let session) = result else {
            return XCTFail("expected connected, got \(result)")
        }
        XCTAssertEqual(session.accessToken, "tok-abc")
        XCTAssertEqual(session.workspaceID, "ws-9")
        XCTAssertEqual(session.userName, "marco@alimax.at")
        XCTAssertEqual(session.workspaceName, "Team HAVI")
        XCTAssertNil(session.refreshToken)

        // Persisted to the store before returning.
        XCTAssertEqual(store.accessToken, "tok-abc")
        XCTAssertEqual(store.workspaceID, "ws-9")
        XCTAssertEqual(store.userName, "marco@alimax.at")
        XCTAssertEqual(store.workspaceName, "Team HAVI")
        XCTAssertEqual(StubURLProtocol.consumedCount, 2)
    }

    func testPendingThenExpiredViaTTL() async {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(status: 202, json: pendingJSON)
        StubURLProtocol.enqueue(status: 202, json: pendingJSON)

        let clock = TimeBox(start: 0)
        let store = HaviTokenStore(backing: HaviInMemoryCredentialBacking())
        let service = HaviConnectService(
            config: config(),
            tokenStore: store,
            session: stubSession(),
            now: { clock.current() },
            sleep: { _ in clock.advance(by: 100) }
        )

        let result = await service.runExchange(link: link(expiresAt: 50), interval: 0, isCancelled: { false })

        XCTAssertEqual(result, .expired)
        XCTAssertEqual(StubURLProtocol.consumedCount, 1) // one poll, then the TTL elapses
        XCTAssertNil(store.accessToken)
    }

    func testServerGoneCodeYieldsExpired() async {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(status: 410, json: #"{"error":{"code":"setup_code_expired"}}"#)

        let store = HaviTokenStore(backing: HaviInMemoryCredentialBacking())
        let service = HaviConnectService(
            config: config(),
            tokenStore: store,
            session: stubSession(),
            now: { Date(timeIntervalSince1970: 0) },
            sleep: { _ in }
        )

        let result = await service.runExchange(link: link(), interval: 0, isCancelled: { false })
        XCTAssertEqual(result, .expired)
    }

    func testCancelStopsPolling() async {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(status: 202, json: pendingJSON)
        StubURLProtocol.enqueue(status: 202, json: pendingJSON)

        let flag = CancelBox()
        let store = HaviTokenStore(backing: HaviInMemoryCredentialBacking())
        let service = HaviConnectService(
            config: config(),
            tokenStore: store,
            session: stubSession(),
            now: { Date(timeIntervalSince1970: 0) },
            sleep: { _ in flag.cancel() } // approval hasn't landed; the user cancels between polls
        )

        let result = await service.runExchange(link: link(), interval: 0, isCancelled: { flag.isCancelled })

        XCTAssertEqual(result, .cancelled)
        XCTAssertEqual(StubURLProtocol.consumedCount, 1)
        XCTAssertNil(store.accessToken)
    }

    // MARK: - Pure classify / parse seams

    func testClassifyExchange() {
        XCTAssertEqual(HaviConnectService.classifyExchange(status: 202, body: Data("{}".utf8)), .pending)
        if case .approved(let session) = HaviConnectService.classifyExchange(status: 201, body: Data(approvedJSON.utf8)) {
            XCTAssertEqual(session.accessToken, "tok-abc")
        } else {
            XCTFail("expected approved")
        }
        XCTAssertEqual(
            HaviConnectService.classifyExchange(status: 410, body: Data(#"{"error":{"code":"setup_code_expired"}}"#.utf8)),
            .gone
        )
        XCTAssertEqual(
            HaviConnectService.classifyExchange(status: 409, body: Data(#"{"error":{"code":"setup_code_used"}}"#.utf8)),
            .gone
        )
        XCTAssertEqual(HaviConnectService.classifyExchange(status: 500, body: Data("boom".utf8)), .transient)
        XCTAssertEqual(
            HaviConnectService.classifyExchange(status: 400, body: Data(#"{"error":{"code":"whatever"}}"#.utf8)),
            .transient
        )
    }

    func testParseSetupLinkResolvesRelativeApproveURL() {
        let base = URL(string: "https://havi.example.test")!
        let json = """
        {"data":{"device_code":"abc","status":"pending","client_type":"mobile",\
        "approve_url":"/?setup_code=abc","expires_at":"2026-10-19T10:30:00Z"}}
        """
        let parsed = HaviConnectService.parseSetupLink(Data(json.utf8), baseURL: base, now: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(parsed?.deviceCode, "abc")
        XCTAssertEqual(parsed?.approveURL.absoluteString, "https://havi.example.test/?setup_code=abc")
    }

    func testParseSetupLinkFallsBackToTTLWhenNoExpiry() {
        let json = #"{"data":{"device_code":"abc","approve_url":"/?setup_code=abc"}}"#
        let parsed = HaviConnectService.parseSetupLink(Data(json.utf8), baseURL: URL(string: "https://x.test")!, now: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(parsed?.expiresAt, Date(timeIntervalSince1970: HaviConnectService.linkTTL))
    }
}

/// A mutable clock the injected `now` reads and the injected `sleep` advances, so
/// a pending→expired run is deterministic without wall time.
final class TimeBox: @unchecked Sendable {
    private let lock = NSLock()
    private var seconds: TimeInterval

    init(start: TimeInterval) { seconds = start }

    func current() -> Date {
        lock.lock(); defer { lock.unlock() }
        return Date(timeIntervalSince1970: seconds)
    }

    func advance(by delta: TimeInterval) {
        lock.lock(); seconds += delta; lock.unlock()
    }
}

final class CancelBox: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock(); cancelled = true; lock.unlock()
    }
}
