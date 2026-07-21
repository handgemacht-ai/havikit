import XCTest
@testable import HaviKit

/// Builds an envelope from a fixed input and asserts it byte-for-byte against
/// the committed golden JSON (design §10). Both sides go through
/// `HaviCanonicalJSON` (`.sortedKeys`), so the comparison is order-independent
/// and truly byte-exact on the canonical form.
final class HaviKitEnvelopeTests: XCTestCase {
    private func assertMatchesGolden(_ id: String, _ input: HaviEnvelopeInput) throws {
        let built = try HaviCanonicalJSON.data(HaviEnvelopeBuilder.build(input))
        let golden = try HaviCanonicalJSON.data(GoldenFixture.envelope(id))
        XCTAssertEqual(
            built, golden,
            "envelope for \(id) diverged from golden.\nbuilt:  \(String(decoding: built, as: UTF8.self))\ngolden: \(String(decoding: golden, as: UTF8.self))"
        )
    }

    func testMinimalEnvelopeMatchesGolden() throws {
        try assertMatchesGolden("minimal", Self.minimalInput)
        XCTAssertEqual(HaviEnvelopeBuilder.siblings(Self.minimalInput), try GoldenFixture.siblings("minimal"))
    }

    func testFullContextEnvelopeMatchesGolden() throws {
        try assertMatchesGolden("full-context", Self.fullContextInput)
        XCTAssertEqual(HaviEnvelopeBuilder.siblings(Self.fullContextInput), try GoldenFixture.siblings("full-context"))
    }

    func testRedactedEnvelopeMatchesGolden() throws {
        try assertMatchesGolden("redacted", Self.redactedInput)
        XCTAssertEqual(HaviEnvelopeBuilder.siblings(Self.redactedInput), try GoldenFixture.siblings("redacted"))
    }

    func testCommitRidesInDevButNotSiblings() {
        let siblings = HaviEnvelopeBuilder.siblings(Self.fullContextInput)
        XCTAssertNil(siblings["commit"])
        let envelope = HaviEnvelopeBuilder.build(Self.fullContextInput)
        let dev = ((envelope["x:havi"] as? [String: Any])?["dev"]) as? [String: Any]
        XCTAssertEqual(dev?["commit"] as? String, "a1b2c3d")
    }

    func testEmptyCommentIsOmitted() {
        var input = Self.minimalInput
        input.comment = "   "
        let body = HaviEnvelopeBuilder.build(input)["body"] as? [[String: Any]]
        XCTAssertEqual(body?.count, 1)
        XCTAssertEqual(body?.first?["type"] as? String, "Image")
    }

    func testNoMarkupOmitsSvgSelector() {
        let selector = target(Self.minimalInput)["selector"] as? [[String: Any]]
        XCTAssertEqual(selector?.compactMap { $0["type"] as? String }, ["FragmentSelector", "CssSelector"])
    }

    func testMarkupEmitsSvgSelector() {
        let selector = target(Self.fullContextInput)["selector"] as? [[String: Any]]
        XCTAssertEqual(selector?.compactMap { $0["type"] as? String }, ["FragmentSelector", "CssSelector", "SvgSelector"])
    }

    private func target(_ input: HaviEnvelopeInput) -> [String: Any] {
        (HaviEnvelopeBuilder.build(input)["target"] as? [String: Any]) ?? [:]
    }

    // MARK: - Fixtures (mirror design/havi-envelope-golden.json inputs)

    static let minimalInput = HaviEnvelopeInput(
        bundleID: "ai.handgemacht.lesewerkstatt.dev",
        screen: "HomeScreen",
        viewport: HaviSize(width: 393, height: 852),
        fragment: HaviRect(x: 0, y: 0, width: 786, height: 1704),
        markup: nil,
        cssPath: "HomeScreen",
        dev: HaviDev(project: "lesewerkstatt", worktree: "home-fix", branch: "home-fix")
    )

    static let fullContextInput = HaviEnvelopeInput(
        bundleID: "ai.handgemacht.lesewerkstatt.dev",
        screen: "ReaderScreen",
        viewport: HaviSize(width: 844, height: 390),
        fragment: HaviRect(x: 612, y: 980, width: 470, height: 190),
        markup: HaviRect(x: 612, y: 980, width: 470, height: 190),
        cssPath: "ReaderScreen > wordCard.Haus",
        comment: "Word card overlaps the mic button in landscape",
        priority: .high,
        deviceInfo: "iPhone15,3 · iOS 17.5.1 · Lesewerkstatt Dev 1.4.0+812 · de_DE · landscapeLeft",
        appLogs: "[info] card start ref=Haus\n[warning] settle timeout phase=listen\n[error] RPC readAloudScore 503",
        dev: HaviDev(project: "lesewerkstatt", worktree: "reader-landscape-fix", branch: "reader-landscape-fix", commit: "a1b2c3d"),
        contexts: ["reader": ["cardType": "known-word", "phase": "listen"]],
        tags: ["buildConfig": "DevRelease"]
    )

    static let redactedInput = HaviEnvelopeInput(
        bundleID: "ai.handgemacht.lesewerkstatt.dev",
        screen: "SettingsScreen",
        viewport: HaviSize(width: 393, height: 852),
        fragment: HaviRect(x: 0, y: 0, width: 786, height: 1704),
        markup: nil,
        cssPath: "SettingsScreen",
        comment: "Secret-shaped context keys must be scrubbed before send",
        priority: .medium,
        dev: HaviDev(project: "lesewerkstatt", worktree: "redaction-audit", branch: "redaction-audit"),
        contexts: [
            "session": ["userId": "u-42", "authToken": "eyJhbGciOi", "note": "landscape"],
            "cookies": ["sid": "abc123"],
            "vault": ["password": "hunter2", "secretKey": "k-01"],
        ],
        tags: ["authorization": "Bearer zzz", "buildConfig": "Debug"]
    )
}
