import XCTest
@testable import HaviKit

/// Markup v2 diagnostics split (bead havi-6953): the breadcrumb ring partitions
/// into console errors (error level, non-network), network errors (category
/// `network`, any level), and the remaining breadcrumbs, and each bucket formats
/// to the browser extension's value shape.
final class HaviDiagnosticsTests: XCTestCase {
    private func entry(_ level: HaviLogLevel, _ category: String, _ message: String) -> HaviLogEntry {
        HaviLogEntry(level: level, category: category, message: message)
    }

    func testSplitRoutesByLevelAndCategory() {
        let split = HaviDiagnostics.split([
            entry(.info, "app", "card start ref=Haus"),
            entry(.error, "app", "scorer returned nil"),
            entry(.warning, "app", "settle timeout"),
            entry(.error, "network", "POST /api/rpc/run 503 action=readAloudScore"),
            entry(.debug, "network", "POST /api/rpc/run retry action=loadPlan"),
        ])

        XCTAssertEqual(split.consoleErrors.map(\.message), ["scorer returned nil"])
        XCTAssertEqual(split.networkErrors.map(\.message), [
            "POST /api/rpc/run 503 action=readAloudScore",
            "POST /api/rpc/run retry action=loadPlan",
        ])
        XCTAssertEqual(split.breadcrumbs.map(\.message), ["card start ref=Haus", "settle timeout"])
    }

    func testNetworkCategoryWinsOverErrorLevel() {
        let split = HaviDiagnostics.split([entry(.error, "network", "POST /api/rpc/run 500")])
        XCTAssertTrue(split.consoleErrors.isEmpty)
        XCTAssertEqual(split.networkErrors.count, 1)
    }

    func testFormatConsoleMatchesExtensionShape() {
        let value = HaviDiagnostics.formatConsole([
            entry(.error, "app", "scorer returned nil"),
            entry(.error, "app", "missing asset Haus"),
        ])
        XCTAssertEqual(value, "[error] scorer returned nil\n[error] missing asset Haus")
    }

    func testFormatNetworkHasNoLevelPrefix() {
        let value = HaviDiagnostics.formatNetwork([
            entry(.error, "network", "POST https://havi.example/api/rpc/run 503 action=readAloudScore"),
            entry(.error, "network", "POST https://havi.example/api/rpc/run 401 action=loadPlan"),
        ])
        XCTAssertEqual(
            value,
            "POST https://havi.example/api/rpc/run 503 action=readAloudScore\nPOST https://havi.example/api/rpc/run 401 action=loadPlan"
        )
    }

    func testLogNetworkErrorRecordsNetworkErrorLevelEntry() {
        HaviLogBuffer.shared.clear()
        defer { HaviLogBuffer.shared.clear() }

        Havi.logNetworkError("POST https://havi.example/api/rpc/run 503 action=readAloudScore")
        Havi.log("card start ref=Haus", level: .info, category: "app")

        let split = HaviDiagnostics.split(HaviLogBuffer.shared.snapshot())
        XCTAssertEqual(split.networkErrors.map(\.message), ["POST https://havi.example/api/rpc/run 503 action=readAloudScore"])
        XCTAssertEqual(split.networkErrors.first?.level, .error)
        XCTAssertEqual(split.networkErrors.first?.category, "network")
        XCTAssertEqual(split.breadcrumbs.map(\.message), ["card start ref=Haus"])
        XCTAssertTrue(split.consoleErrors.isEmpty)
    }
}
