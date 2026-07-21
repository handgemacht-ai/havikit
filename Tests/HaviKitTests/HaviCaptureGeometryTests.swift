import CoreGraphics
import XCTest
@testable import HaviKit

/// Pure capture math (design §2, §3): the markup rectangle projects from a
/// normalized fraction into the downscaled image-pixel space the screenshot is
/// encoded in, and the `device-info` / `app-logs` bodies format per the
/// convention (omit-empty separators).
final class HaviCaptureGeometryTests: XCTestCase {
    func testImagePixelRectProjectsAndClamps() {
        let size = HaviSize(width: 1000, height: 2000)
        let rect = HaviCaptureGeometry.imagePixelRect(
            fraction: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.25),
            imageSize: size
        )
        XCTAssertEqual(rect, HaviRect(x: 100, y: 400, width: 300, height: 500))
    }

    func testImagePixelRectClampsOutOfBounds() {
        let size = HaviSize(width: 800, height: 600)
        let rect = HaviCaptureGeometry.imagePixelRect(
            fraction: CGRect(x: 0.8, y: 0.9, width: 0.5, height: 0.5),
            imageSize: size
        )
        XCTAssertLessThanOrEqual(rect.x + rect.width, size.width)
        XCTAssertLessThanOrEqual(rect.y + rect.height, size.height)
    }

    func testFullFrameRectCoversImage() {
        let size = HaviSize(width: 1290, height: 2796)
        XCTAssertEqual(
            HaviCaptureGeometry.fullFrameRect(imageSize: size),
            HaviRect(x: 0, y: 0, width: 1290, height: 2796)
        )
    }

    func testMeaningfulMarkupThreshold() {
        XCTAssertFalse(HaviCaptureGeometry.isMeaningful(fraction: CGRect(x: 0.5, y: 0.5, width: 0.001, height: 0.001)))
        XCTAssertTrue(HaviCaptureGeometry.isMeaningful(fraction: CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2)))
    }

    func testCssPathWithAndWithoutHint() {
        XCTAssertEqual(HaviCaptureGeometry.cssPath(screen: "ReaderScreen", hint: nil), "ReaderScreen")
        XCTAssertEqual(HaviCaptureGeometry.cssPath(screen: "ReaderScreen", hint: ""), "ReaderScreen")
        XCTAssertEqual(
            HaviCaptureGeometry.cssPath(screen: "ReaderScreen", hint: "lyric-reading-line"),
            "ReaderScreen > lyric-reading-line"
        )
    }

    func testDeviceInfoOmitsEmptyComponents() {
        let line = HaviDeviceInfo.format(
            model: "iPhone15,3",
            systemName: "iOS",
            systemVersion: "17.5.1",
            appName: "Lesewerkstatt Dev",
            version: "1.4.0",
            build: "812",
            locale: "de_DE",
            orientation: "landscapeLeft"
        )
        XCTAssertEqual(line, "iPhone15,3 · iOS 17.5.1 · Lesewerkstatt Dev 1.4.0+812 · de_DE · landscapeLeft")
    }

    func testDeviceInfoDropsMissingBuildAndOrientation() {
        let line = HaviDeviceInfo.format(
            model: "iPhone15,3",
            systemName: "iOS",
            systemVersion: "17.5.1",
            appName: "Lesewerkstatt Dev",
            version: "1.4.0",
            build: nil,
            locale: "de_DE",
            orientation: nil
        )
        XCTAssertEqual(line, "iPhone15,3 · iOS 17.5.1 · Lesewerkstatt Dev 1.4.0 · de_DE")
    }

    func testFormatLogsOneLinePerBreadcrumb() {
        let logs = HaviDeviceInfo.formatLogs([
            HaviLogEntry(level: .info, category: "app", message: "card start ref=Haus"),
            HaviLogEntry(level: .error, category: "rpc", message: "readAloudScore 503"),
        ])
        XCTAssertEqual(logs, "[info] card start ref=Haus\n[error] readAloudScore 503")
    }

    func testFormatLogsEmptyWhenNoBreadcrumbs() {
        XCTAssertEqual(HaviDeviceInfo.formatLogs([]), "")
    }
}
