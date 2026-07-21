import CoreGraphics
import XCTest
@testable import HaviKit

/// Markup v2 serialization (bead havi-6953): the normalized vector marks project
/// into one image-pixel `<svg>`, the FragmentSelector is the bounding-box union of
/// the non-blur marks, blur/redact marks are excluded from both, and the arrowhead
/// geometry is deterministic. The single-rectangle case reproduces the v1 SVG bytes
/// (the golden `full-context` anchor); the multi-mark case is the golden
/// `markup-multi` anchor.
final class HaviMarkupSerializerTests: XCTestCase {
    private let imageSize = HaviSize(width: 1000, height: 2000)

    func testSingleRectangleReproducesV1Svg() {
        // Reproduces the golden `full-context` SvgSelector bytes (612,980,470,190)
        // from one rectangle mark — the v2 serializer's parity anchor with the v1
        // single-rectangle SVG. Image space 2000×4000 keeps the rect in bounds.
        let mark = HaviMark(shape: .rectangle(CGRect(x: 0.306, y: 0.245, width: 0.235, height: 0.0475)), color: .red)
        XCTAssertEqual(
            HaviMarkupSerializer.svg(for: [mark], imageSize: HaviSize(width: 2000, height: 4000)),
            "<svg xmlns=\"http://www.w3.org/2000/svg\"><rect x=\"612\" y=\"980\" width=\"470\" height=\"190\" fill=\"none\" stroke=\"#E8542F\" stroke-width=\"6\"/></svg>"
        )
    }

    func testMultiMarkSvgAndBoundingBoxMatchGolden() {
        let pen = HaviMark(
            shape: .pen(points: [CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.15, y: 0.13), CGPoint(x: 0.22, y: 0.12)]),
            color: .red
        )
        let rect = HaviMark(shape: .rectangle(CGRect(x: 0.4, y: 0.45, width: 0.2, height: 0.075)), color: .blue)
        let blur = HaviMark(shape: .blur(CGRect(x: 0.05, y: 0.8, width: 0.3, height: 0.1)), color: .black)

        XCTAssertEqual(
            HaviMarkupSerializer.svg(for: [pen, rect, blur], imageSize: imageSize),
            "<svg xmlns=\"http://www.w3.org/2000/svg\"><path d=\"M 100 200 L 150 260 L 220 240\" fill=\"none\" stroke=\"#E8542F\" stroke-width=\"6\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/><rect x=\"400\" y=\"900\" width=\"200\" height=\"150\" fill=\"none\" stroke=\"#0A84FF\" stroke-width=\"6\"/></svg>"
        )
        XCTAssertEqual(
            HaviMarkupSerializer.boundingBox(of: [pen, rect, blur], imageSize: imageSize),
            HaviRect(x: 100, y: 200, width: 500, height: 850)
        )
    }

    func testHighlighterIsSemiTransparentWiderStroke() {
        let mark = HaviMark(
            shape: .highlighter(points: [CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.2, y: 0.1)]),
            color: .yellow
        )
        let svg = HaviMarkupSerializer.svg(for: [mark], imageSize: imageSize)
        XCTAssertEqual(
            svg,
            "<svg xmlns=\"http://www.w3.org/2000/svg\"><path d=\"M 100 200 L 200 200\" fill=\"none\" stroke=\"#F5C518\" stroke-width=\"24\" stroke-linecap=\"round\" stroke-linejoin=\"round\" stroke-opacity=\"0.35\"/></svg>"
        )
    }

    func testArrowSerializesLinePlusPolygonHead() {
        let arrow = HaviMark(shape: .arrow(from: CGPoint(x: 0.1, y: 0.5), to: CGPoint(x: 0.9, y: 0.5)), color: .red)
        XCTAssertEqual(
            HaviMarkupSerializer.svg(for: [arrow], imageSize: imageSize),
            "<svg xmlns=\"http://www.w3.org/2000/svg\"><line x1=\"100\" y1=\"1000\" x2=\"900\" y2=\"1000\" stroke=\"#E8542F\" stroke-width=\"6\" stroke-linecap=\"round\"/><polygon points=\"900,1000 866,1013 866,987\" fill=\"#E8542F\"/></svg>"
        )
    }

    func testArrowHeadGeometryIsDeterministic() {
        let head = HaviMarkupSerializer.arrowHead(
            tip: CGPoint(x: 100, y: 0),
            tail: CGPoint(x: 0, y: 0),
            length: 20,
            width: 20
        )
        XCTAssertEqual(head, [CGPoint(x: 100, y: 0), CGPoint(x: 80, y: 10), CGPoint(x: 80, y: -10)])
    }

    func testBlurMarksAreExcludedFromEnvelopeGeometry() {
        let blur = HaviMark(shape: .blur(CGRect(x: 0.1, y: 0.1, width: 0.3, height: 0.3)), color: .black)
        XCTAssertNil(HaviMarkupSerializer.svg(for: [blur], imageSize: imageSize))
        XCTAssertNil(HaviMarkupSerializer.boundingBox(of: [blur], imageSize: imageSize))
        XCTAssertEqual(HaviMarkupSerializer.blurRects(of: [blur]), [CGRect(x: 0.1, y: 0.1, width: 0.3, height: 0.3)])
    }

    func testNoMarksProducesNoSvgOrBox() {
        XCTAssertNil(HaviMarkupSerializer.svg(for: [], imageSize: imageSize))
        XCTAssertNil(HaviMarkupSerializer.boundingBox(of: [], imageSize: imageSize))
        XCTAssertTrue(HaviMarkupSerializer.blurRects(of: []).isEmpty)
    }

    func testBoundingBoxUnionSpansAllNonBlurMarks() {
        let a = HaviMark(shape: .rectangle(CGRect(x: 0.1, y: 0.1, width: 0.1, height: 0.1)), color: .red)
        let b = HaviMark(shape: .rectangle(CGRect(x: 0.6, y: 0.7, width: 0.2, height: 0.2)), color: .blue)
        XCTAssertEqual(
            HaviMarkupSerializer.boundingBox(of: [a, b], imageSize: imageSize),
            HaviRect(x: 100, y: 200, width: 700, height: 1600)
        )
    }
}
