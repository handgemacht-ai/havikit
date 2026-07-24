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

    // MARK: - Ring bounds: count, per-entry bytes, and the whole-ring budget

    private func utf8Count(_ message: String) -> Int { message.utf8.count }

    func testRingKeepsTheNewestEntriesUpToCapacity() {
        let buffer = HaviLogBuffer(capacity: 3)
        for index in 0 ..< 5 { buffer.append(entry(.info, "app", "m\(index)")) }
        XCTAssertEqual(buffer.snapshot().map(\.message), ["m2", "m3", "m4"])
    }

    func testShortMessagesAreUntouched() {
        let buffer = HaviLogBuffer()
        buffer.append(entry(.info, "app", "card start ref=Haus"))
        XCTAssertEqual(buffer.snapshot().first?.message, "card start ref=Haus")
    }

    func testOversizedMessageIsTruncatedWithAMarkerAndFitsTheEntryCap() {
        let buffer = HaviLogBuffer()
        buffer.append(entry(.info, "app", String(repeating: "x", count: HaviLogBuffer.maxEntryBytes * 3)))

        let stored = buffer.snapshot().first?.message ?? ""
        XCTAssertTrue(stored.hasSuffix(HaviLogBuffer.truncationMarker))
        XCTAssertEqual(utf8Count(stored), HaviLogBuffer.maxEntryBytes)
        XCTAssertTrue(stored.hasPrefix("xxx"))
    }

    /// The cut lands on a character boundary, never inside a multi-byte scalar.
    func testTruncationNeverSplitsAMultiByteCharacter() {
        let truncated = HaviLogBuffer.truncate(String(repeating: "ä", count: HaviLogBuffer.maxEntryBytes))
        let body = String(truncated.dropLast(HaviLogBuffer.truncationMarker.count))

        XCTAssertLessThanOrEqual(utf8Count(truncated), HaviLogBuffer.maxEntryBytes)
        XCTAssertTrue(truncated.hasSuffix(HaviLogBuffer.truncationMarker))
        XCTAssertEqual(body.count, body.filter { $0 == "ä" }.count, "no replacement character from a split scalar")
    }

    func testEmojiAtTheCutSurviveIntact() {
        let truncated = HaviLogBuffer.truncate(String(repeating: "🙂", count: HaviLogBuffer.maxEntryBytes))
        let body = String(truncated.dropLast(HaviLogBuffer.truncationMarker.count))

        XCTAssertLessThanOrEqual(utf8Count(truncated), HaviLogBuffer.maxEntryBytes)
        XCTAssertEqual(utf8Count(body) % 4, 0, "the cut fell on a whole 4-byte scalar")
        XCTAssertEqual(body.count, body.filter { $0 == "🙂" }.count, "no replacement character from a split scalar")
    }

    /// Well under the count cap, the byte budget is what evicts.
    func testTotalByteBudgetEvictsOldestFirst() {
        let buffer = HaviLogBuffer()
        let chunk = String(repeating: "y", count: HaviLogBuffer.maxEntryBytes)
        let fitting = HaviLogBuffer.maxTotalBytes / HaviLogBuffer.maxEntryBytes

        for _ in 0 ..< fitting { buffer.append(entry(.info, "app", chunk)) }
        XCTAssertEqual(buffer.snapshot().count, fitting)

        buffer.append(entry(.info, "app", "newest"))
        let retained = buffer.snapshot()

        XCTAssertEqual(retained.count, fitting, "the oldest chunk made room for the newest entry")
        XCTAssertEqual(retained.last?.message, "newest")
        XCTAssertLessThanOrEqual(retained.reduce(0) { $0 + utf8Count($1.message) }, HaviLogBuffer.maxTotalBytes)
    }

    func testClearResetsTheByteBudgetToo() {
        let buffer = HaviLogBuffer()
        for _ in 0 ..< 40 {
            buffer.append(entry(.info, "app", String(repeating: "z", count: HaviLogBuffer.maxEntryBytes)))
        }
        buffer.clear()

        for _ in 0 ..< 3 { buffer.append(entry(.info, "app", "after")) }
        XCTAssertEqual(buffer.snapshot().count, 3)
    }

    func testByteCapsMatchTheDocumentedConstants() {
        XCTAssertEqual(HaviLogBuffer.maxEntryBytes, 4 * 1024)
        XCTAssertEqual(HaviLogBuffer.maxTotalBytes, 256 * 1024)
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
