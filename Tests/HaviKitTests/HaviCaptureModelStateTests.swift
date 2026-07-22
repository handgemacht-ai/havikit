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
    private func makeModel() -> HaviCaptureModel {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 40)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 20, height: 40))
        }
        let session = HaviCaptureSession(
            image: image,
            viewport: HaviSize(width: 20, height: 40),
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

    func testCropDefaultsToFullFrameAndResetRestoresIt() {
        let model = makeModel()
        XCTAssertFalse(model.crop.isCropped)

        model.crop.updateResize(handle: .bottomRight, to: CGPoint(x: 0.6, y: 0.6))
        XCTAssertTrue(model.crop.isCropped)

        model.crop.reset()
        XCTAssertEqual(model.crop.rect, HaviCropGeometry.fullFrame)
        XCTAssertFalse(model.crop.isCropped)
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
}
#endif
