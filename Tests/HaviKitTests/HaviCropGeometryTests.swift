import CoreGraphics
import Foundation
import XCTest
@testable import HaviKit

/// Pure crop math for the capture sheet's crop tool (bead havi-oukr): handle
/// drag → new normalized crop rect, and the full-image-normalized →
/// crop-relative-normalized projection used to re-express marks and the
/// reported viewport once a crop is applied. Kept UIKit-free so it runs under
/// `swift test` without a Simulator, like `HaviCaptureGeometryTests`.
final class HaviCropGeometryTests: XCTestCase {
    private let accuracy: CGFloat = 0.0001

    private func assertRect(_ actual: CGRect, _ expected: CGRect, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.minX, expected.minX, accuracy: accuracy, "minX \(message)", file: file, line: line)
        XCTAssertEqual(actual.minY, expected.minY, accuracy: accuracy, "minY \(message)", file: file, line: line)
        XCTAssertEqual(actual.width, expected.width, accuracy: accuracy, "width \(message)", file: file, line: line)
        XCTAssertEqual(actual.height, expected.height, accuracy: accuracy, "height \(message)", file: file, line: line)
    }

    // MARK: - Handle resize

    func testCornerHandleMovesBothEdgesOfThatCorner() {
        let rect = CGRect(x: 0.2, y: 0.2, width: 0.5, height: 0.5)
        let resized = HaviCropGeometry.resize(rect, handle: .topLeft, to: CGPoint(x: 0.3, y: 0.35))
        assertRect(resized, CGRect(x: 0.3, y: 0.35, width: 0.4, height: 0.35))
    }

    func testEdgeHandleMovesOnlyItsOwnAxis() {
        let rect = CGRect(x: 0.2, y: 0.2, width: 0.5, height: 0.5)
        let resized = HaviCropGeometry.resize(rect, handle: .right, to: CGPoint(x: 0.6, y: 0.9))
        assertRect(resized, CGRect(x: 0.2, y: 0.2, width: 0.4, height: 0.5), "the top/bottom edges must ignore the drag's y")
    }

    func testResizeClampsDragPointToUnitSquare() {
        let rect = CGRect(x: 0.2, y: 0.2, width: 0.5, height: 0.5)
        let resized = HaviCropGeometry.resize(rect, handle: .bottomRight, to: CGPoint(x: 1.4, y: -0.3))
        assertRect(resized, CGRect(x: 0.2, y: 0.2, width: 0.8, height: 0.1))
    }

    func testResizeNeverShrinksBelowMinimumCropFraction() {
        let rect = CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4)
        let resized = HaviCropGeometry.resize(rect, handle: .left, to: CGPoint(x: 0.65, y: 0.5))
        assertRect(resized, CGRect(x: 0.6, y: 0.3, width: 0.1, height: 0.4), "the opposite edge must not cross the drag")
    }

    func testAnchorPointsSitOnRectEdgesAndMidpoints() {
        let rect = CGRect(x: 0.2, y: 0.3, width: 0.4, height: 0.2)
        let topLeft = HaviCropGeometry.anchor(of: .topLeft, in: rect)
        let bottomRight = HaviCropGeometry.anchor(of: .bottomRight, in: rect)
        XCTAssertEqual(topLeft.x, 0.2, accuracy: accuracy)
        XCTAssertEqual(topLeft.y, 0.3, accuracy: accuracy)
        XCTAssertEqual(bottomRight.x, 0.6, accuracy: accuracy)
        XCTAssertEqual(bottomRight.y, 0.5, accuracy: accuracy)
    }

    // MARK: - Projection

    func testProjectPointRebasesIntoCropRelativeSpace() {
        let crop = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        let projected = HaviCropGeometry.project(CGPoint(x: 0.5, y: 0.5), into: crop)
        XCTAssertEqual(projected.x, 0.5, accuracy: accuracy)
        XCTAssertEqual(projected.y, 0.5, accuracy: accuracy)
    }

    func testProjectedViewportScalesProportionallyToCrop() {
        let crop = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        let projected = HaviCropGeometry.projectedViewport(HaviSize(width: 400, height: 800), crop: crop)
        XCTAssertEqual(projected, HaviSize(width: 200, height: 400))
    }

    func testProjectedViewportIsUnchangedWhenNotCropped() {
        let viewport = HaviSize(width: 393, height: 852)
        XCTAssertEqual(HaviCropGeometry.projectedViewport(viewport, crop: HaviCropGeometry.fullFrame), viewport)
    }

    func testProjectedImageSizeScalesProportionallyToCrop() {
        let crop = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        let projected = HaviCropGeometry.projectedImageSize(HaviSize(width: 800, height: 1600), crop: crop)
        XCTAssertEqual(projected, HaviSize(width: 400, height: 800))
    }

    // MARK: - Mark projection / drop / clip

    func testProjectMarksIsNoOpWhenCropIsFullFrame() {
        let marks = [
            HaviMark(shape: .rectangle(CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2)), color: .red),
            HaviMark(shape: .blur(CGRect(x: 0.5, y: 0.5, width: 0.1, height: 0.1)), color: .black),
        ]
        let projected = HaviCropGeometry.projectMarks(marks, into: HaviCropGeometry.fullFrame)
        XCTAssertEqual(projected.map(\.id), marks.map(\.id))
    }

    func testProjectMarksDropsMarkFullyOutsideCrop() {
        let crop = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        let mark = HaviMark(shape: .rectangle(CGRect(x: 0.85, y: 0.85, width: 0.1, height: 0.1)), color: .red)
        XCTAssertTrue(HaviCropGeometry.projectMarks([mark], into: crop).isEmpty)
    }

    func testProjectMarksKeepsAndRebasesMarkFullyInsideCrop() {
        let crop = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        let mark = HaviMark(shape: .rectangle(CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.1)), color: .red)
        let projected = HaviCropGeometry.projectMarks([mark], into: crop)
        XCTAssertEqual(projected.count, 1)
        assertRect(projected[0].normalizedBounds, CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.2))
    }

    func testProjectMarksClipsPartiallyOutsideMarkViaExistingPixelClamping() {
        let crop = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        let mark = HaviMark(shape: .rectangle(CGRect(x: 0.6, y: 0.6, width: 0.3, height: 0.3)), color: .red)
        let projected = HaviCropGeometry.projectMarks([mark], into: crop)
        XCTAssertEqual(projected.count, 1, "a partially-overlapping mark is kept, not dropped")
        assertRect(projected[0].normalizedBounds, CGRect(x: 0.7, y: 0.7, width: 0.6, height: 0.6))

        // The out-of-[0,1] projected fraction is clipped once it reaches pixel
        // space by the EXISTING clamping in HaviCaptureGeometry.imagePixelRect —
        // no new clipping logic, per the bead's explicit instruction.
        let croppedImageSize = HaviSize(width: 400, height: 800)
        XCTAssertEqual(
            HaviMarkupSerializer.boundingBox(of: projected, imageSize: croppedImageSize),
            HaviRect(x: 280, y: 560, width: 120, height: 240)
        )
    }

    // MARK: - Byte-crop-before-redaction ordering (pure-logic level)

    func testBlurRectsAreCropRelativeProvingRedactionTargetsTheCroppedCanvas() {
        let crop = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        let blur = HaviMark(shape: .blur(CGRect(x: 0.45, y: 0.45, width: 0.1, height: 0.1)), color: .black)
        let projected = HaviCropGeometry.projectMarks([blur], into: crop)
        let rects = HaviMarkupSerializer.blurRects(of: projected)
        XCTAssertEqual(rects.count, 1)
        guard let rect = rects.first else { return }
        assertRect(rect, CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2))
        XCTAssertNotEqual(
            Double(rect.minX), 0.45,
            "would only equal the full-image fraction if redaction ran before cropping"
        )
    }

    func testBlurMarkFullyOutsideCropIsDroppedRatherThanRedactedOntoTheCroppedCanvas() {
        let crop = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        let blur = HaviMark(shape: .blur(CGRect(x: 0.0, y: 0.0, width: 0.1, height: 0.1)), color: .black)
        let projected = HaviCropGeometry.projectMarks([blur], into: crop)
        XCTAssertTrue(HaviMarkupSerializer.blurRects(of: projected).isEmpty)
    }

    // MARK: - Display transform (canvas point ↔ full-image normalized, bead havi-od6t)

    private func assertPoint(_ actual: CGPoint, _ expected: CGPoint, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.x, expected.x, accuracy: accuracy, "x \(message)", file: file, line: line)
        XCTAssertEqual(actual.y, expected.y, accuracy: accuracy, "y \(message)", file: file, line: line)
    }

    private let contentSize = CGSize(width: 200, height: 400)

    func testDisplayTransformIsPlainPointOverSizeWhenUncropped() {
        let region = HaviCropGeometry.fullFrame
        assertPoint(
            HaviCropGeometry.normalizedFromCanvas(CGPoint(x: 100, y: 200), contentSize: contentSize, visibleRegion: region),
            CGPoint(x: 0.5, y: 0.5),
            "an uncropped canvas maps point ÷ size, unchanged from before the zoom existed"
        )
        assertPoint(
            HaviCropGeometry.canvasFromNormalized(CGPoint(x: 0.25, y: 0.75), contentSize: contentSize, visibleRegion: region),
            CGPoint(x: 50, y: 300)
        )
    }

    func testUnprojectIsTheInverseOfProject() {
        let crop = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        let relative = CGPoint(x: 0.3, y: 0.7)
        assertPoint(HaviCropGeometry.project(HaviCropGeometry.unproject(relative, from: crop), into: crop), relative)
        let full = CGPoint(x: 0.4, y: 0.6)
        assertPoint(HaviCropGeometry.unproject(HaviCropGeometry.project(full, into: crop), from: crop), full)
    }

    func testDisplayTransformRoundTripsUnderCrop() {
        let region = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        let full = CGPoint(x: 0.4, y: 0.6)
        let canvas = HaviCropGeometry.canvasFromNormalized(full, contentSize: contentSize, visibleRegion: region)
        assertPoint(canvas, CGPoint(x: 60, y: 280), "the full-still point lands inside the zoomed content")
        assertPoint(
            HaviCropGeometry.normalizedFromCanvas(canvas, contentSize: contentSize, visibleRegion: region),
            full,
            "canvas → normalized → canvas is lossless inside the visible region"
        )
    }

    func testGestureAtCropEdgesMapsToTheVisibleRegionCorners() {
        let region = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        assertPoint(
            HaviCropGeometry.normalizedFromCanvas(.zero, contentSize: contentSize, visibleRegion: region),
            CGPoint(x: 0.25, y: 0.25),
            "the top-left canvas corner is the crop's top-left, not the still's"
        )
        assertPoint(
            HaviCropGeometry.normalizedFromCanvas(CGPoint(x: 200, y: 400), contentSize: contentSize, visibleRegion: region),
            CGPoint(x: 0.75, y: 0.75),
            "the bottom-right canvas corner is the crop's bottom-right"
        )
    }

    func testGestureBeyondTheCanvasClampsToTheVisibleRegion() {
        let region = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        assertPoint(
            HaviCropGeometry.normalizedFromCanvas(CGPoint(x: 320, y: -40), contentSize: contentSize, visibleRegion: region),
            CGPoint(x: 0.75, y: 0.25),
            "a drag past the zoomed edge cannot place a mark outside the crop"
        )
    }

    func testFullStillPointOutsideTheCropLandsOutsideTheContentBounds() {
        let region = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        let outside = HaviCropGeometry.canvasFromNormalized(CGPoint(x: 0.9, y: 0.9), contentSize: contentSize, visibleRegion: region)
        XCTAssertGreaterThan(outside.x, contentSize.width, "a mark outside the crop is off-canvas and gets clipped by the content bounds")
        XCTAssertGreaterThan(outside.y, contentSize.height)
    }

    // MARK: - Zoom-aware gesture thresholds (meaningfulness + hit test)

    /// A 10x zoom (the minCropFraction extreme): the visible region is a tenth of
    /// the still on each axis, so 5% of the visible view is only 0.5% of the still.
    private let zoom10x = CGRect(x: 0.4, y: 0.4, width: 0.1, height: 0.1)

    func testFreehandMeaningfulnessScalesWithZoom() {
        // A pen stroke spanning ~5% of the VISIBLE region: 0.05 on screen, which
        // is only 0.005 in full-still space at this zoom.
        let mark = HaviMark(shape: .pen(points: [CGPoint(x: 0.42, y: 0.42), CGPoint(x: 0.425, y: 0.42)]), color: .red)

        XCTAssertFalse(
            HaviCropGeometry.isMeaningfulMark(mark, visibleRegion: HaviCropGeometry.fullFrame),
            "the same full-still span (0.005) is a stray tap when unzoomed and must be discarded"
        )
        XCTAssertTrue(
            HaviCropGeometry.isMeaningfulMark(mark, visibleRegion: zoom10x),
            "a deliberate 5%-of-screen mark drawn while zoomed must survive release"
        )
    }

    func testRectangleMeaningfulnessScalesWithZoom() {
        // 0.005 x 0.005 of the still == 5% x 5% of the visible region at 10x.
        let mark = HaviMark(shape: .rectangle(CGRect(x: 0.42, y: 0.42, width: 0.005, height: 0.005)), color: .red)

        XCTAssertFalse(HaviCropGeometry.isMeaningfulMark(mark, visibleRegion: HaviCropGeometry.fullFrame))
        XCTAssertTrue(HaviCropGeometry.isMeaningfulMark(mark, visibleRegion: zoom10x))
    }

    func testStrayTapIsStillRejectedEvenWhenZoomed() {
        // 0.5% of the visible region — below threshold at any zoom.
        let mark = HaviMark(shape: .pen(points: [CGPoint(x: 0.42, y: 0.42), CGPoint(x: 0.4205, y: 0.42)]), color: .red)
        XCTAssertFalse(HaviCropGeometry.isMeaningfulMark(mark, visibleRegion: zoom10x))
    }

    func testHitTestToleranceScalesWithZoomToDisambiguateNearbyMarks() {
        // Two tiny marks 0.02 apart in full-still space, both inside the crop; a
        // tap lands on A. Unzoomed the 0.03 slop is coarse enough to reach both;
        // zoomed it stays a fraction of the visible region, so only A is hit.
        let a = HaviMark(shape: .rectangle(CGRect(x: 0.438, y: 0.448, width: 0.004, height: 0.004)), color: .red)
        let b = HaviMark(shape: .rectangle(CGRect(x: 0.458, y: 0.448, width: 0.004, height: 0.004)), color: .red)
        let tap = CGPoint(x: 0.44, y: 0.45)
        let tolerance: CGFloat = 0.03

        XCTAssertTrue(HaviCropGeometry.markHitTest(a, at: tap, tolerance: tolerance, visibleRegion: HaviCropGeometry.fullFrame))
        XCTAssertTrue(
            HaviCropGeometry.markHitTest(b, at: tap, tolerance: tolerance, visibleRegion: HaviCropGeometry.fullFrame),
            "unzoomed the fixed slop reaches the neighbour too — the ambiguity the zoom-aware path fixes"
        )

        XCTAssertTrue(HaviCropGeometry.markHitTest(a, at: tap, tolerance: tolerance, visibleRegion: zoom10x))
        XCTAssertFalse(
            HaviCropGeometry.markHitTest(b, at: tap, tolerance: tolerance, visibleRegion: zoom10x),
            "zoomed the slop is region-relative, so the tap no longer selects the wrong mark"
        )
    }

    // MARK: - Uncropped identity (full frame == byte-identical to the pre-zoom rule)

    /// The pre-zoom meaningfulness rule, reproduced verbatim, so the uncropped
    /// (full-frame) path can be proven byte-identical to it across a battery.
    private func legacyIsMeaningful(_ mark: HaviMark) -> Bool {
        switch mark.shape {
        case .pen(let points), .highlighter(let points):
            let bounds = HaviMark.bounds(of: points)
            return points.count >= 2 && max(bounds.width, bounds.height) >= HaviCaptureGeometry.minMarkupFraction
        case .arrow(let from, let to):
            return hypot(to.x - from.x, to.y - from.y) >= HaviCaptureGeometry.minMarkupFraction
        case .rectangle(let rect), .blur(let rect):
            return HaviCaptureGeometry.isMeaningful(fraction: rect.standardized)
        }
    }

    func testUncroppedMeaningfulnessIsByteIdenticalToThePreZoomRule() {
        let marks: [HaviMark] = [
            HaviMark(shape: .pen(points: [CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.109, y: 0.1)]), color: .red),   // span 0.009, just under
            HaviMark(shape: .pen(points: [CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.111, y: 0.1)]), color: .red),   // span 0.011, just over
            HaviMark(shape: .pen(points: [CGPoint(x: 0.1, y: 0.1)]), color: .red),                              // single point
            HaviMark(shape: .arrow(from: CGPoint(x: 0.2, y: 0.2), to: CGPoint(x: 0.205, y: 0.205)), color: .red),
            HaviMark(shape: .arrow(from: CGPoint(x: 0.2, y: 0.2), to: CGPoint(x: 0.25, y: 0.25)), color: .red),
            HaviMark(shape: .rectangle(CGRect(x: 0.3, y: 0.3, width: 0.009, height: 0.2)), color: .red),        // one axis under
            HaviMark(shape: .rectangle(CGRect(x: 0.3, y: 0.3, width: 0.02, height: 0.02)), color: .red),
            HaviMark(shape: .blur(CGRect(x: 0.5, y: 0.5, width: 0.005, height: 0.005)), color: .black),
        ]
        for mark in marks {
            XCTAssertEqual(
                HaviCropGeometry.isMeaningfulMark(mark, visibleRegion: HaviCropGeometry.fullFrame),
                legacyIsMeaningful(mark),
                "full-frame meaningfulness must match the pre-zoom rule for \(mark.shape)"
            )
        }
    }

    func testUncroppedHitTestIsByteIdenticalToTheRawMarkHitTest() {
        let mark = HaviMark(shape: .rectangle(CGRect(x: 0.3, y: 0.3, width: 0.2, height: 0.2)), color: .red)
        let tolerance: CGFloat = 0.03
        let points = [
            CGPoint(x: 0.4, y: 0.4),    // inside
            CGPoint(x: 0.28, y: 0.4),   // just outside, within slop
            CGPoint(x: 0.5, y: 0.5),    // on the far corner
            CGPoint(x: 0.0, y: 0.0),    // far outside
        ]
        for point in points {
            XCTAssertEqual(
                HaviCropGeometry.markHitTest(mark, at: point, tolerance: tolerance, visibleRegion: HaviCropGeometry.fullFrame),
                mark.hitTest(point, tolerance: tolerance),
                "full-frame hit test must equal the raw pre-zoom hitTest at \(point)"
            )
        }
    }
}
