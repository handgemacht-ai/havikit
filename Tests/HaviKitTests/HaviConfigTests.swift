import Foundation
import HaviKit
import XCTest

/// Config resolution (design §6), the iOS twin of the Android `HaviConfigTest`:
/// inert when unconfigured, inert (never fatal) on a misconfiguration, the same
/// base-URL rules on both platforms, and omit-never-empty for every other key.
final class HaviConfigTests: XCTestCase {
    /// The armed baseline every case starts from, plus the keys under test.
    private func enabled(_ extra: [String: String] = [:]) -> [String: String] {
        var values = ["HAVI_ENABLED": "YES", "HAVI_BASE_URL": "https://havi.test"]
        for (key, value) in extra {
            values[key] = value
        }
        return values
    }

    func testUnsetOrDisabledEnabledFlagIsInert() {
        XCTAssertFalse(HaviConfig.fromInfoValues([:]).isEnabled)
        XCTAssertFalse(HaviConfig.fromInfoValues(["HAVI_ENABLED": "no", "HAVI_BASE_URL": "https://havi.test"]).isEnabled)
        XCTAssertFalse(HaviConfig.fromInfoValues(["HAVI_ENABLED": "", "HAVI_BASE_URL": "https://havi.test"]).isEnabled)
        XCTAssertNil(HaviConfig.fromInfoValues([:]).baseURL)
    }

    func testEnabledAcceptsYesOrTrueTrimmedAndCaseInsensitive() {
        for raw in ["YES", "yes", "Yes", "true", "TRUE", " yes ", "\ttrue\n"] {
            let config = HaviConfig.fromInfoValues(["HAVI_ENABLED": raw, "HAVI_BASE_URL": "https://havi.test"])
            XCTAssertTrue(config.isEnabled, "expected \(raw) to arm the SDK")
        }
    }

    func testEnabledRejectsOtherSpellings() {
        for raw in ["1", "on", "enabled", "y", "yes please"] {
            let config = HaviConfig.fromInfoValues(["HAVI_ENABLED": raw, "HAVI_BASE_URL": "https://havi.test"])
            XCTAssertFalse(config.isEnabled, "expected \(raw) to leave the SDK inert")
        }
    }

    func testValidBaseURLAcceptsAbsoluteHTTPAndHTTPS() {
        for raw in [
            "https://havi.handgemacht.ai",
            "https://havi.handgemacht.ai/",
            "https://havi.test:8443/base",
            "http://localhost:4000",
            "  https://havi.test  ",
        ] {
            XCTAssertNotNil(HaviConfig.validBaseURL(raw), "expected \(raw) to be accepted")
        }
    }

    func testValidBaseURLRejectsAnythingElse() {
        for raw in [
            "",
            "   ",
            "havi.test",
            "havi.handgemacht.ai/api",
            "not a url",
            "/relative/path",
            "ftp://havi.test",
            "file:///tmp/havi",
            "https://",
        ] {
            XCTAssertNil(HaviConfig.validBaseURL(raw), "expected \(raw) to be rejected")
        }
    }

    func testEnabledWithMissingOrInvalidBaseURLIsInertInsteadOfFatal() {
        for values in [
            ["HAVI_ENABLED": "YES"],
            ["HAVI_ENABLED": "YES", "HAVI_BASE_URL": ""],
            ["HAVI_ENABLED": "YES", "HAVI_BASE_URL": "havi.test"],
            ["HAVI_ENABLED": "YES", "HAVI_BASE_URL": "not a url"],
            ["HAVI_ENABLED": "YES", "HAVI_BASE_URL": "ftp://havi.test"],
        ] {
            let config = HaviConfig.fromInfoValues(values)
            XCTAssertFalse(config.isEnabled)
            XCTAssertNil(config.baseURL)
            XCTAssertNil(config.devToken)
        }
    }

    func testReadsEveryKeyWithOmitNeverEmptyDiscipline() {
        let config = HaviConfig.fromInfoValues([
            "HAVI_ENABLED": "YES",
            "HAVI_BASE_URL": "https://havi.handgemacht.ai",
            "HAVI_WORKSPACE_ID": "ws-9",
            "HAVI_PROJECT": "lesewerkstatt",
            "HAVI_WORKTREE": "",
            "HAVI_BRANCH": "main",
            "HAVI_COMMIT": "a1b2c3d",
            "HAVI_DEV_TOKEN": "tok",
            "HAVI_IMAGE_FORMAT": "jpeg",
        ])
        XCTAssertTrue(config.isEnabled)
        XCTAssertEqual(config.baseURL, URL(string: "https://havi.handgemacht.ai"))
        XCTAssertEqual(config.workspaceID, "ws-9")
        XCTAssertEqual(config.project, "lesewerkstatt")
        XCTAssertNil(config.worktree)
        XCTAssertEqual(config.branch, "main")
        XCTAssertEqual(config.commit, "a1b2c3d")
        XCTAssertEqual(config.devToken, "tok")
        XCTAssertEqual(config.imageFormat, .jpeg)
    }

    func testImageFormatIsTrimmedAndFallsBackToPNG() {
        XCTAssertEqual(HaviConfig.fromInfoValues(enabled()).imageFormat, .png)
        XCTAssertEqual(HaviConfig.fromInfoValues(enabled(["HAVI_IMAGE_FORMAT": "  JPEG "])).imageFormat, .jpeg)
        XCTAssertEqual(HaviConfig.fromInfoValues(enabled(["HAVI_IMAGE_FORMAT": " png "])).imageFormat, .png)
        XCTAssertEqual(HaviConfig.fromInfoValues(enabled(["HAVI_IMAGE_FORMAT": "webp"])).imageFormat, .png)
        XCTAssertEqual(HaviConfig.fromInfoValues(enabled(["HAVI_IMAGE_FORMAT": ""])).imageFormat, .png)
    }

    func testUnstampedBundleResolvesToInert() {
        let config = HaviConfig.fromBundle(.main)
        XCTAssertFalse(config.isEnabled)
        XCTAssertNil(config.baseURL)
    }
}
