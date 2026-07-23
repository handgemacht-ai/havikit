#if canImport(UIKit)
import CoreGraphics
import UIKit
import XCTest
@testable import HaviKit

/// State retention across the two-screen capture flow (bead havi-oukr): both
/// `HaviCaptureImageScreen` and `HaviCaptureDetailsScreen` bind to the SAME
/// `HaviCaptureModel`, so nothing here simulates the actual push/pop — it
/// proves the shared model itself holds marks, crop, comment, and toggles
/// steady regardless of which screen is reading/writing them, which is what
/// makes the Back round trip lossless.
@MainActor
final class HaviCaptureModelStateTests: XCTestCase {
    private func makeModel(imageSize: CGSize = CGSize(width: 20, height: 40)) -> HaviCaptureModel {
        let image = UIGraphicsImageRenderer(size: imageSize).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(origin: .zero, size: imageSize))
        }
        let session = HaviCaptureSession(
            image: image,
            a11yFrames: [],
            orientation: "portrait",
            screen: "ReaderScreen",
            initialPriority: .medium
        )
        let runtime = HaviRuntime(config: .inert, tokenStore: HaviTokenStore(backing: HaviInMemoryCredentialBacking()))
        return HaviCaptureModel(session: session, runtime: runtime)
    }

    func testMarkupAndCropStateSurviveScreenOneToScreenTwoTransition() {
        let model = makeModel()

        model.markup.selectTool(.rectangle)
        model.markup.begin(at: CGPoint(x: 0.2, y: 0.2))
        model.markup.extend(to: CGPoint(x: 0.5, y: 0.4))
        model.markup.end()
        model.crop.updateResize(handle: .topLeft, to: CGPoint(x: 0.1, y: 0.1))

        XCTAssertEqual(model.markup.marks.count, 1)
        let cropAfterScreenOne = model.crop.rect

        // Screen 2 only touches comment/priority/toggles — Screen 1's state
        // must be untouched by that, since both screens share one model.
        model.comment = "Card overlaps the mic button"
        model.priority = .high
        model.includeNetworkErrors = false

        XCTAssertEqual(model.markup.marks.count, 1)
        XCTAssertEqual(model.crop.rect, cropAfterScreenOne)
        XCTAssertEqual(model.comment, "Card overlaps the mic button")
        XCTAssertEqual(model.priority, .high)
        XCTAssertFalse(model.includeNetworkErrors)
        XCTAssertTrue(model.includeConsoleErrors)
    }

    // MARK: - Viewport comes from the captured still (phone-QA finding 4)

    func testViewportComesFromTheCapturedStillPointSize() {
        // The session carries no separate viewport — the reported viewport must be
        // the still's own point size, so it can never degrade to unknown/zero when
        // a real screenshot exists.
        let model = makeModel(imageSize: CGSize(width: 393, height: 852))
        XCTAssertEqual(model.reportedViewport, HaviSize(width: 393, height: 852))
    }

    func testReportedViewportTracksAConfirmedCrop() {
        let model = makeModel(imageSize: CGSize(width: 400, height: 800))
        XCTAssertEqual(model.reportedViewport, HaviSize(width: 400, height: 800))

        // Crop to the middle half on each axis (like the golden "cropped" case):
        // the reported viewport projects proportionally into the cropped still.
        model.beginCropEditing(previousTool: .pen)
        model.crop.updateResize(handle: .topLeft, to: CGPoint(x: 0.25, y: 0.25))
        model.crop.updateResize(handle: .bottomRight, to: CGPoint(x: 0.75, y: 0.75))
        model.confirmCrop()

        XCTAssertEqual(model.reportedViewport, HaviSize(width: 200, height: 400))
    }

    func testCropDefaultsToFullFrameAndResetRestoresIt() {
        let model = makeModel()
        XCTAssertFalse(model.crop.isCropped)

        model.crop.updateResize(handle: .bottomRight, to: CGPoint(x: 0.6, y: 0.6))
        XCTAssertTrue(model.crop.isCropped)

        model.crop.reset()
        XCTAssertEqual(model.crop.rect, HaviCropGeometry.fullFrame)
        XCTAssertFalse(model.crop.isCropped)
    }

    // MARK: - Crop confirmation flow (bead havi-od6t)

    func testConfirmingACropZoomsAndReturnsToThePreviousTool() {
        let model = makeModel()
        model.markup.selectTool(.arrow)
        model.beginCropEditing(previousTool: .arrow)
        XCTAssertTrue(model.crop.isEditing)

        model.crop.updateResize(handle: .bottomRight, to: CGPoint(x: 0.6, y: 0.6))
        model.confirmCrop()

        XCTAssertFalse(model.crop.isEditing)
        XCTAssertTrue(model.crop.isCropped)
        XCTAssertEqual(model.markup.tool, .arrow, "confirming returns to the tool that was active before cropping")
    }

    func testCancellingACropRevertsToTheLastConfirmedCropAndPreviousTool() {
        let model = makeModel()
        model.markup.selectTool(.pen)
        model.beginCropEditing(previousTool: .pen)
        model.crop.updateResize(handle: .bottomRight, to: CGPoint(x: 0.7, y: 0.7))
        model.confirmCrop()
        let confirmed = model.crop.rect

        model.markup.selectTool(.crop)
        model.beginCropEditing(previousTool: .pen)
        model.crop.updateResize(handle: .topLeft, to: CGPoint(x: 0.2, y: 0.2))
        XCTAssertNotEqual(model.crop.rect, confirmed, "the draft moved while editing")

        model.cancelCrop()
        XCTAssertEqual(model.crop.rect, confirmed, "cancel restores the last confirmed crop")
        XCTAssertFalse(model.crop.isEditing)
        XCTAssertEqual(model.markup.tool, .pen)
    }

    func testReCroppingCanWidenNotOnlyNarrowThePreviousCrop() {
        let model = makeModel()
        model.beginCropEditing(previousTool: .pen)
        model.crop.updateResize(handle: .topLeft, to: CGPoint(x: 0.4, y: 0.4))
        model.confirmCrop()
        let narrow = model.crop.rect

        model.markup.selectTool(.crop)
        model.beginCropEditing(previousTool: .pen)
        model.crop.updateResize(handle: .topLeft, to: CGPoint(x: 0.1, y: 0.1))
        model.confirmCrop()

        XCTAssertLessThan(model.crop.rect.minX, narrow.minX, "re-crop can widen the region")
        XCTAssertLessThan(model.crop.rect.minY, narrow.minY)
    }

    func testResetWidensTheDraftToFullFrameWithoutLeavingCropMode() {
        let model = makeModel()
        model.beginCropEditing(previousTool: .pen)
        model.crop.updateResize(handle: .bottomRight, to: CGPoint(x: 0.5, y: 0.5))
        XCTAssertTrue(model.crop.isCropped)

        model.crop.reset()
        XCTAssertEqual(model.crop.rect, HaviCropGeometry.fullFrame)
        XCTAssertTrue(model.crop.isEditing, "Reset keeps crop mode open so the user can re-drag or confirm the full frame")
    }

    // MARK: - Next is gated on an unconfirmed crop (crop must be confirmed first)

    func testCannotProceedWhileCropModeIsActive() {
        let model = makeModel()
        XCTAssertTrue(model.canProceed, "a fresh model with no open crop can advance")

        model.markup.selectTool(.arrow)
        model.beginCropEditing(previousTool: .arrow)
        XCTAssertTrue(model.crop.isEditing)
        XCTAssertFalse(model.canProceed, "an open, unconfirmed crop draft must block Next")

        model.crop.updateResize(handle: .bottomRight, to: CGPoint(x: 0.6, y: 0.6))
        model.confirmCrop()
        XCTAssertTrue(model.canProceed, "confirming the crop re-enables Next")
    }

    func testCancellingAnOpenCropReEnablesProceeding() {
        let model = makeModel()
        model.beginCropEditing(previousTool: .pen)
        XCTAssertFalse(model.canProceed, "an open crop draft blocks Next")

        model.cancelCrop()
        XCTAssertTrue(model.canProceed, "cancelling the crop re-enables Next")
    }

    // MARK: - Submit confirmation toast identity (QA m2)

    /// Back-to-back submits: toast A's un-cancelled auto-dismiss timer must not
    /// clear the newer toast B. The presenter only clears when the id still names
    /// the current confirmation.
    func testStaleToastTimerDoesNotClearANewerBackToBackToast() {
        let presenter = HaviCapturePresenter()

        presenter.confirmSubmission() // toast A
        let staleID = presenter.confirmation!.id
        presenter.confirmSubmission() // toast B replaces A

        presenter.clearConfirmation(staleID) // A's stale timer fires late
        XCTAssertNotNil(presenter.confirmation, "toast A's timer must not clear the newer toast B")

        presenter.clearConfirmation(presenter.confirmation!.id) // B's own timer
        XCTAssertNil(presenter.confirmation, "the matching timer clears its own toast")
    }

    func testGoingBackToScreenOneAfterASubmitFailureKeepsMarksAndCropEditable() async {
        let model = makeModel()
        model.markup.selectTool(.rectangle)
        model.markup.begin(at: CGPoint(x: 0.1, y: 0.1))
        model.markup.extend(to: CGPoint(x: 0.4, y: 0.3))
        model.markup.end()
        model.crop.updateResize(handle: .topLeft, to: CGPoint(x: 0.05, y: 0.05))

        await model.submit()

        XCTAssertNotNil(model.failure, "the inert config has no baseURL, so HaviUploader fails fast without a network call")
        XCTAssertEqual(model.markup.marks.count, 1, "a failed submit must not drop marks")
        XCTAssertTrue(model.crop.isCropped, "a failed submit must not reset the crop")
    }

    // MARK: - Workspace labels (bead havi-jj51)

    private static let labelVocabularyJSON = """
    {
      "data": [
        { "id": "id-priority", "key": "priority", "name": "Priority", "kind": "choice",
          "allowed_values": ["high", "medium", "low"], "position": 0 },
        { "id": "id-area", "key": "area", "name": "Area", "kind": "value",
          "allowed_values": [], "position": 1 },
        { "id": "id-flag", "key": "regression", "name": "Regression", "kind": "flag",
          "allowed_values": [], "position": 2 }
      ]
    }
    """

    private func makeLabelModel(enqueue: (status: Int, json: String)?) -> HaviCaptureModel {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let urlSession = URLSession(configuration: configuration)
        StubURLProtocol.reset()
        if let enqueue { StubURLProtocol.enqueue(status: enqueue.status, json: enqueue.json) }

        let config = HaviConfig(
            isEnabled: true,
            baseURL: URL(string: "https://havi.example"),
            workspaceID: nil,
            project: nil,
            worktree: nil,
            branch: nil,
            commit: nil,
            imageFormat: .png,
            devToken: nil,
            redaction: HaviRedactionPolicy()
        )
        let store = HaviTokenStore(backing: HaviInMemoryCredentialBacking())
        store.signIn(token: "tok", workspaceID: "ws")
        let runtime = HaviRuntime(
            config: config,
            tokenStore: store,
            labelService: HaviLabelService(config: config, session: urlSession)
        )

        let image = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 40)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 20, height: 40))
        }
        let session = HaviCaptureSession(
            image: image,
            a11yFrames: [],
            orientation: "portrait",
            screen: "ReaderScreen",
            initialPriority: .medium
        )
        return HaviCaptureModel(session: session, runtime: runtime)
    }

    /// A failed label fetch degrades to exactly today's screen: no additional
    /// labels, no applied labels, priority untouched — capture is never blocked.
    func testLabelFetchFailureFallsBackToPriorityOnly() async {
        let model = makeLabelModel(enqueue: (500, #"{"error":{"code":"server_error"}}"#))
        await model.loadLabelDefinitions()

        XCTAssertTrue(model.additionalLabelDefinitions.isEmpty)
        XCTAssertTrue(model.appliedLabels().isEmpty)
        XCTAssertEqual(model.priority, .medium, "priority still works after a failed labels fetch")
    }

    /// The vocabulary loads without the built-in priority (the segmented control
    /// already owns it), keeps position order, and applied selections become the
    /// exact `HaviLabel` list fed to the envelope.
    func testVocabularyLoadsAndSelectionsBecomeAppliedLabels() async {
        let model = makeLabelModel(enqueue: (200, Self.labelVocabularyJSON))
        await model.loadLabelDefinitions()

        XCTAssertEqual(model.additionalLabelDefinitions.map(\.key), ["area", "regression"])
        XCTAssertTrue(model.appliedLabels().isEmpty, "nothing applied until the user selects")

        model.labelChoiceValues["area"] = "reader"
        model.labelFlags.insert("regression")

        XCTAssertEqual(
            model.appliedLabels(),
            [HaviLabel(key: "area", value: "reader"), HaviLabel(key: "regression")]
        )
    }

    /// An empty value string leaves the label unapplied (no empty tagging body).
    func testEmptyValueLabelIsNotApplied() async {
        let model = makeLabelModel(enqueue: (200, Self.labelVocabularyJSON))
        await model.loadLabelDefinitions()

        model.labelChoiceValues["area"] = ""
        XCTAssertTrue(model.appliedLabels().isEmpty)
    }
}
#endif
