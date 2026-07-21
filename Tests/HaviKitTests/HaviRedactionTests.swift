import XCTest
@testable import HaviKit

/// The Swift KEY-name scrub must match the `enrichment.js` reference
/// (`SECRET_KEY_RE = /token|secret|password|api[_-]?key|authorization|cookie/i`,
/// recursive over objects and arrays; scalars pass through). These rows mirror
/// that behavior directly.
final class HaviRedactionTests: XCTestCase {
    func testSecretKeyMatchesReferenceRegex() {
        for key in ["token", "accessToken", "refresh_token", "SECRET", "clientSecret",
                    "password", "passwordConfirmation", "apiKey", "api_key", "api-key",
                    "APIKEY", "authorization", "Authorization", "cookie", "Cookies"] {
            XCTAssertTrue(HaviRedaction.isSecretKey(key), "\(key) should be treated as secret")
        }
    }

    func testNonSecretKeysAreKept() {
        for key in ["userId", "note", "cardType", "phase", "buildConfig", "auth", "key", "sid"] {
            XCTAssertFalse(HaviRedaction.isSecretKey(key), "\(key) should not be treated as secret")
        }
    }

    func testScrubDropsSecretKeysAtTopLevel() {
        let input: [String: Any] = ["userId": "u-1", "authToken": "x", "note": "ok"]
        let scrubbed = HaviRedaction.scrub(input) as? [String: Any]
        XCTAssertEqual(scrubbed?.keys.sorted(), ["note", "userId"])
    }

    func testScrubRecursesIntoNestedObjects() {
        let input: [String: Any] = [
            "session": ["userId": "u-1", "password": "p", "nested": ["apiKey": "k", "keep": "v"]],
        ]
        let scrubbed = HaviRedaction.scrub(input) as? [String: Any]
        let session = scrubbed?["session"] as? [String: Any]
        XCTAssertEqual(session?.keys.sorted(), ["nested", "userId"])
        let nested = session?["nested"] as? [String: Any]
        XCTAssertEqual(nested?.keys.sorted(), ["keep"])
    }

    func testScrubRecursesIntoArrays() {
        let input: [String: Any] = [
            "items": [
                ["name": "a", "secret": "s"],
                ["name": "b", "cookie": "c"],
            ],
        ]
        let scrubbed = HaviRedaction.scrub(input) as? [String: Any]
        let items = scrubbed?["items"] as? [[String: Any]]
        XCTAssertEqual(items?.count, 2)
        XCTAssertEqual(items?[0].keys.sorted(), ["name"])
        XCTAssertEqual(items?[1].keys.sorted(), ["name"])
    }

    func testScrubDropsSecretlyNamedNamespace() {
        let input: [String: Any] = ["cookies": ["sid": "abc"], "reader": ["phase": "listen"]]
        let scrubbed = HaviRedaction.scrub(input) as? [String: Any]
        XCTAssertEqual(scrubbed?.keys.sorted(), ["reader"])
    }

    func testScrubLeavesScalarsUntouched() {
        XCTAssertEqual(HaviRedaction.scrub("plain") as? String, "plain")
        XCTAssertEqual(HaviRedaction.scrub(42) as? Int, 42)
    }
}
