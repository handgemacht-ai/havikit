import CoreGraphics
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

    func testDiagnosticsEnvelopeMatchesGolden() throws {
        try assertMatchesGolden("diagnostics", Self.diagnosticsInput)
        XCTAssertEqual(HaviEnvelopeBuilder.siblings(Self.diagnosticsInput), try GoldenFixture.siblings("diagnostics"))
    }

    func testMarkupMultiEnvelopeMatchesGolden() throws {
        try assertMatchesGolden("markup-multi", Self.markupMultiInput)
        XCTAssertEqual(HaviEnvelopeBuilder.siblings(Self.markupMultiInput), try GoldenFixture.siblings("markup-multi"))
    }

    func testCroppedEnvelopeMatchesGolden() throws {
        try assertMatchesGolden("cropped", Self.croppedInput)
        XCTAssertEqual(HaviEnvelopeBuilder.siblings(Self.croppedInput), try GoldenFixture.siblings("cropped"))
    }

    /// Proves `croppedInput`'s fragment/viewport/svg are exactly what the crop
    /// pipeline (bead havi-oukr) would produce from the marks + crop rect it
    /// describes — not just numbers that happen to match the golden by hand.
    /// A second mark drawn fully outside the crop is dropped and has no
    /// envelope side effect, matching the golden case's description.
    func testCroppedInputMatchesCropPipelineProjection() {
        let crop = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        let originalViewport = HaviSize(width: 400, height: 800)
        let originalImageSize = HaviSize(width: 800, height: 1600)
        let inside = HaviMark(shape: .rectangle(CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.1)), color: .red)
        let outside = HaviMark(shape: .rectangle(CGRect(x: 0.85, y: 0.85, width: 0.1, height: 0.1)), color: .blue)

        let projected = HaviCropGeometry.projectMarks([inside, outside], into: crop)
        XCTAssertEqual(projected.count, 1, "the fully-outside mark is dropped")

        let croppedImageSize = HaviCropGeometry.projectedImageSize(originalImageSize, crop: crop)
        let croppedViewport = HaviCropGeometry.projectedViewport(originalViewport, crop: crop)
        XCTAssertEqual(croppedImageSize, HaviSize(width: 400, height: 800))
        XCTAssertEqual(croppedViewport, Self.croppedInput.viewport)
        XCTAssertEqual(HaviMarkupSerializer.boundingBox(of: projected, imageSize: croppedImageSize), Self.croppedInput.fragment)
        XCTAssertEqual(HaviMarkupSerializer.svg(for: projected, imageSize: croppedImageSize), Self.croppedInput.markupSvg)
    }

    func testCommitRidesInDevButNotSiblings() {
        let siblings = HaviEnvelopeBuilder.siblings(Self.fullContextInput)
        XCTAssertNil(siblings["commit"])
        let envelope = HaviEnvelopeBuilder.build(Self.fullContextInput)
        let dev = ((envelope["x:havi"] as? [String: Any])?["dev"]) as? [String: Any]
        XCTAssertEqual(dev?["commit"] as? String, "a1b2c3d")
    }

    func testEmptyStringDevFieldsAreTreatedAsAbsent() {
        var input = Self.minimalInput
        input.dev = HaviDev(project: "lesewerkstatt", worktree: "", branch: "")

        // Multipart siblings: an empty worktree/branch must drop (would otherwise
        // break backend filtering), while a real project is kept.
        XCTAssertEqual(HaviEnvelopeBuilder.siblings(input), ["project": "lesewerkstatt"])

        // x:havi.dev applies the same guard.
        let dev = ((HaviEnvelopeBuilder.build(input)["x:havi"] as? [String: Any])?["dev"]) as? [String: Any]
        XCTAssertEqual(dev?["project"] as? String, "lesewerkstatt")
        XCTAssertNil(dev?["worktree"])
        XCTAssertNil(dev?["branch"])
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

    func testDiagnosticsBodiesOrderAndRoles() {
        let body = HaviEnvelopeBuilder.build(Self.diagnosticsInput)["body"] as? [[String: Any]]
        let roles = body?.compactMap { $0["x:role"] as? String }
        XCTAssertEqual(roles, ["device-info", "console-errors", "network-errors", "app-logs"])
    }

    func testConsoleAndNetworkBodiesOmittedWhenNil() {
        var input = Self.diagnosticsInput
        input.consoleErrors = nil
        input.networkErrors = nil
        let body = HaviEnvelopeBuilder.build(input)["body"] as? [[String: Any]]
        let roles = body?.compactMap { $0["x:role"] as? String }
        XCTAssertEqual(roles, ["device-info", "app-logs"])
    }

    func testExcludedNetworkGroupDropsOnlyThatBody() {
        var input = Self.diagnosticsInput
        input.networkErrors = nil
        let body = HaviEnvelopeBuilder.build(input)["body"] as? [[String: Any]]
        let roles = body?.compactMap { $0["x:role"] as? String }
        XCTAssertEqual(roles, ["device-info", "console-errors", "app-logs"])
    }

    // MARK: - Generic workspace labels (bead havi-jj51)

    /// Every applied label becomes its own `tagging` body, in input order, right
    /// after the priority body — proving mobile is no longer priority-only.
    func testAppliedLabelsEmitTaggingBodiesAfterPriority() {
        var input = Self.minimalInput
        input.comment = "Overlaps the mic button"
        input.priority = "high"
        input.labels = [
            HaviLabel(key: "area", value: "reader"),
            HaviLabel(key: "component", value: "WordCard"),
            HaviLabel(key: "blocker"),
        ]

        let tagging = taggingBodies(input)
        XCTAssertEqual(
            tagging.map { $0["x:labelKey"] as? String },
            ["priority", "area", "component", "blocker"]
        )
        XCTAssertEqual(taggingValue(tagging, key: "priority"), "high")
        XCTAssertEqual(taggingValue(tagging, key: "area"), "reader")
        XCTAssertEqual(taggingValue(tagging, key: "component"), "WordCard")
        XCTAssertTrue(tagging.allSatisfy { $0["purpose"] as? String == "tagging" })
        XCTAssertTrue(tagging.allSatisfy { $0["type"] as? String == "TextualBody" })
    }

    /// A `flag` label (nil value) emits a tagging body with NO `value` field,
    /// matching the extension's shape.
    func testFlagLabelOmitsValueField() {
        var input = Self.minimalInput
        input.labels = [HaviLabel(key: "regression")]

        let flag = taggingBodies(input).first { $0["x:labelKey"] as? String == "regression" }
        XCTAssertNotNil(flag)
        XCTAssertNil(flag?["value"])
        XCTAssertEqual(flag?["purpose"] as? String, "tagging")
    }

    /// Labels apply with no priority set — the priority body is not synthesized.
    func testLabelsApplyWithoutPriority() {
        var input = Self.minimalInput
        input.priority = nil
        input.labels = [HaviLabel(key: "area", value: "reader")]

        let tagging = taggingBodies(input)
        XCTAssertEqual(tagging.map { $0["x:labelKey"] as? String }, ["area"])
    }

    /// A stray `priority` entry in `labels` never duplicates the priority body —
    /// the `priority` field is the single source for that key.
    func testPriorityKeyInLabelsIsNotDuplicated() {
        var input = Self.minimalInput
        input.priority = "high"
        input.labels = [
            HaviLabel(key: "priority", value: "low"),
            HaviLabel(key: "area", value: "reader"),
        ]

        let priorityBodies = taggingBodies(input).filter { $0["x:labelKey"] as? String == "priority" }
        XCTAssertEqual(priorityBodies.count, 1)
        XCTAssertEqual(priorityBodies.first?["value"] as? String, "high")
        XCTAssertEqual(
            taggingBodies(input).map { $0["x:labelKey"] as? String },
            ["priority", "area"]
        )
    }

    /// No labels and no priority → no tagging bodies at all (store-safe floor).
    func testNoLabelsEmitsNoTaggingBodies() {
        XCTAssertTrue(taggingBodies(Self.minimalInput).isEmpty)
    }

    /// A custom workspace priority value (e.g. `P1`) rides through the priority
    /// body verbatim — the builder no longer assumes the high/medium/low enum.
    func testCustomPriorityValueEmitsVerbatim() {
        var input = Self.minimalInput
        input.priority = "P1"

        let tagging = taggingBodies(input)
        XCTAssertEqual(tagging.map { $0["x:labelKey"] as? String }, ["priority"])
        XCTAssertEqual(taggingValue(tagging, key: "priority"), "P1")
    }

    /// A nil or empty priority emits no priority body at all — the archived/omitted
    /// case must not ship a `priority` tagging body the backend would reject.
    func testNilOrEmptyPriorityEmitsNoPriorityBody() {
        var nilInput = Self.minimalInput
        nilInput.priority = nil
        XCTAssertTrue(taggingBodies(nilInput).isEmpty)

        var emptyInput = Self.minimalInput
        emptyInput.priority = "   "
        XCTAssertTrue(taggingBodies(emptyInput).isEmpty)
    }

    private func taggingBodies(_ input: HaviEnvelopeInput) -> [[String: Any]] {
        let body = HaviEnvelopeBuilder.build(input)["body"] as? [[String: Any]] ?? []
        return body.filter { $0["purpose"] as? String == "tagging" }
    }

    private func taggingValue(_ bodies: [[String: Any]], key: String) -> String? {
        bodies.first { $0["x:labelKey"] as? String == key }?["value"] as? String
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
        markupSvg: nil,
        cssPath: "HomeScreen",
        dev: HaviDev(project: "lesewerkstatt", worktree: "home-fix", branch: "home-fix")
    )

    static let fullContextInput = HaviEnvelopeInput(
        bundleID: "ai.handgemacht.lesewerkstatt.dev",
        screen: "ReaderScreen",
        viewport: HaviSize(width: 844, height: 390),
        fragment: HaviRect(x: 612, y: 980, width: 470, height: 190),
        markupSvg: "<svg xmlns=\"http://www.w3.org/2000/svg\"><rect x=\"612\" y=\"980\" width=\"470\" height=\"190\" fill=\"none\" stroke=\"#E8542F\" stroke-width=\"6\"/></svg>",
        cssPath: "ReaderScreen > wordCard.Haus",
        comment: "Word card overlaps the mic button in landscape",
        priority: "high",
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
        markupSvg: nil,
        cssPath: "SettingsScreen",
        comment: "Secret-shaped context keys must be scrubbed before send",
        priority: "medium",
        dev: HaviDev(project: "lesewerkstatt", worktree: "redaction-audit", branch: "redaction-audit"),
        contexts: [
            "session": ["userId": "u-42", "authToken": "eyJhbGciOi", "note": "landscape"],
            "cookies": ["sid": "abc123"],
            "vault": ["password": "hunter2", "secretKey": "k-01"],
        ],
        tags: ["authorization": "Bearer zzz", "buildConfig": "Debug"]
    )

    static let diagnosticsInput = HaviEnvelopeInput(
        bundleID: "ai.handgemacht.lesewerkstatt.dev",
        screen: "ReaderScreen",
        viewport: HaviSize(width: 393, height: 852),
        fragment: HaviRect(x: 0, y: 0, width: 786, height: 1704),
        markupSvg: nil,
        cssPath: "ReaderScreen",
        comment: "Scores never came back after the last card",
        priority: "high",
        deviceInfo: "iPhone15,3 · iOS 17.5.1 · Lesewerkstatt Dev 1.4.0+812 · de_DE · portrait",
        consoleErrors: "[error] Read-aloud scorer returned nil\n[error] Missing card asset: Haus",
        networkErrors: "POST https://havi.example/api/rpc/run 503 action=readAloudScore\nPOST https://havi.example/api/rpc/run 401 action=loadPlan",
        appLogs: "[info] card start ref=Haus\n[warning] settle timeout phase=listen",
        dev: HaviDev(project: "lesewerkstatt", worktree: "diagnostics-badges", branch: "diagnostics-badges")
    )

    static let markupMultiInput = HaviEnvelopeInput(
        bundleID: "ai.handgemacht.lesewerkstatt.dev",
        screen: "ReaderScreen",
        viewport: HaviSize(width: 500, height: 1000),
        fragment: HaviRect(x: 100, y: 200, width: 500, height: 850),
        markupSvg: "<svg xmlns=\"http://www.w3.org/2000/svg\"><path d=\"M 100 200 L 150 260 L 220 240\" fill=\"none\" stroke=\"#E8542F\" stroke-width=\"6\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/><rect x=\"400\" y=\"900\" width=\"200\" height=\"150\" fill=\"none\" stroke=\"#0A84FF\" stroke-width=\"6\"/></svg>",
        cssPath: "ReaderScreen",
        comment: "Circled the glitchy card and boxed the button",
        priority: "medium",
        dev: HaviDev(project: "lesewerkstatt", worktree: "markup-multi", branch: "markup-multi")
    )

    static let croppedInput = HaviEnvelopeInput(
        bundleID: "ai.handgemacht.lesewerkstatt.dev",
        screen: "ReaderScreen",
        viewport: HaviSize(width: 200, height: 400),
        fragment: HaviRect(x: 120, y: 240, width: 160, height: 160),
        markupSvg: "<svg xmlns=\"http://www.w3.org/2000/svg\"><rect x=\"120\" y=\"240\" width=\"160\" height=\"160\" fill=\"none\" stroke=\"#E8542F\" stroke-width=\"6\"/></svg>",
        cssPath: "ReaderScreen",
        comment: "Cropped to the card before flagging the glitch",
        priority: "medium",
        dev: HaviDev(project: "lesewerkstatt", worktree: "capture-two-screen", branch: "capture-two-screen")
    )
}
