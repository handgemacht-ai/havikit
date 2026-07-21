import Foundation

/// Deterministic JSON serialization used for both the wire body and the
/// byte-exact golden comparison. `.sortedKeys` gives a stable object key order
/// regardless of Swift dictionary iteration order; the envelope carries no
/// numeric fields (coordinates/viewport ride as strings), so there is no float
/// formatting to diverge. Passing any parsed JSON back through `data(_:)`
/// canonicalizes it, so a hand-formatted golden fixture and the builder's output
/// compare byte-for-byte after both are canonicalized.
enum HaviCanonicalJSON {
    static func data(_ object: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    static func string(_ object: Any) throws -> String {
        String(decoding: try data(object), as: UTF8.self)
    }

    static func canonicalize(_ raw: Data) throws -> Data {
        let object = try JSONSerialization.jsonObject(with: raw, options: [])
        return try data(object)
    }
}
