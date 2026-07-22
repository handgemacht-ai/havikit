import Foundation
import XCTest

/// Loads the committed cross-language golden table
/// (`Tests/HaviKitTests/Fixtures/havi-envelope-golden.json`). This repo is the
/// canonical home of the envelope golden fixture; the havi backend keeps a
/// vendored copy guarded by its `mobile_golden_contract_test.exs`. The fixture
/// is bundled as an SPM test resource and loaded from `Bundle.module`.
enum GoldenFixture {
    struct Case {
        let id: String
        let envelope: [String: Any]
        let siblings: [String: String]
    }

    static func load() throws -> [Case] {
        let data = try Data(contentsOf: locate())
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let rawCases = root["cases"] as? [[String: Any]]
        else {
            throw error("golden fixture is not the expected { cases: [...] } shape")
        }
        return try rawCases.map { raw in
            guard
                let id = raw["id"] as? String,
                let envelope = raw["envelope"] as? [String: Any]
            else {
                throw error("golden case missing id/envelope")
            }
            let siblings = (raw["siblings"] as? [String: String]) ?? [:]
            return Case(id: id, envelope: envelope, siblings: siblings)
        }
    }

    static func envelope(_ id: String) throws -> [String: Any] {
        guard let match = try load().first(where: { $0.id == id }) else {
            throw error("no golden case with id \(id)")
        }
        return match.envelope
    }

    static func siblings(_ id: String) throws -> [String: String] {
        guard let match = try load().first(where: { $0.id == id }) else {
            throw error("no golden case with id \(id)")
        }
        return match.siblings
    }

    private static func locate() throws -> URL {
        guard let url = Bundle.module.url(forResource: "havi-envelope-golden", withExtension: "json") else {
            throw error("could not locate havi-envelope-golden.json in Bundle.module resources")
        }
        return url
    }

    private static func error(_ message: String) -> Error {
        NSError(domain: "HaviKitTests.GoldenFixture", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
