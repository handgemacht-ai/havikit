import Foundation
import XCTest

/// Loads the committed cross-language golden table
/// (`design/havi-envelope-golden.json`, the single source of truth also vendored
/// into havi's ExUnit contract test). Located by walking up from this test
/// source file so the fixture stays at the design-mandated repo path with no
/// duplicate copy inside the package.
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

    private static func locate(file: StaticString = #filePath) throws -> URL {
        var directory = URL(fileURLWithPath: "\(file)").deletingLastPathComponent()
        for _ in 0..<12 {
            let candidate = directory.appendingPathComponent("design/havi-envelope-golden.json")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            directory = directory.deletingLastPathComponent()
        }
        throw error("could not locate design/havi-envelope-golden.json above \(file)")
    }

    private static func error(_ message: String) -> Error {
        NSError(domain: "HaviKitTests.GoldenFixture", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
