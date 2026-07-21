import Foundation

/// Redaction policy (design §1). Privacy-first / default-mask: every SwiftUI
/// `TextField` / `SecureField` is masked in the frozen snapshot unless
/// explicitly `.haviReveal()`-ed. The reading passage, OCR previews, and any
/// child-name view are the integration's responsibility to tag `.haviRedacted()`
/// (design §7) — the default `TextField` mask is a safety net, not a guarantee.
public struct HaviRedactionPolicy: Sendable {
    public var maskTextFieldsByDefault: Bool

    public init(maskTextFieldsByDefault: Bool = true) {
        self.maskTextFieldsByDefault = maskTextFieldsByDefault
    }
}

/// The KEY-name secret scrub, ported verbatim from
/// `assets/shared/enrichment.js` (`scrubSecrets` / `isSecretKey`). It is a
/// **key-name denylist** (matching the repo), not a value-pattern scanner:
/// every object key whose name matches the regex is dropped at any nesting
/// depth. Applied on device to `x:havi.contexts` and `x:havi.tags` before send
/// (design §3) so secrets captured via `setContext` / `setTag` never reach the
/// stored annotation.
public enum HaviRedaction {
    /// `token|secret|password|api[_-]?key|authorization|cookie`, case-insensitive
    /// — byte-identical to `SECRET_KEY_RE` in `enrichment.js`.
    static let secretKeyPattern = "token|secret|password|api[_-]?key|authorization|cookie"

    public static func isSecretKey(_ key: String) -> Bool {
        key.range(of: secretKeyPattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// Deep, non-mutating copy with every secret-shaped key dropped at any depth.
    /// Objects and arrays recurse; scalars pass through unchanged — mirroring the
    /// JS `scrubSecrets` recursion (objects, arrays, else passthrough).
    public static func scrub(_ value: Any) -> Any {
        if let dictionary = value as? [String: Any] {
            var out: [String: Any] = [:]
            for (key, nested) in dictionary {
                if isSecretKey(key) { continue }
                out[key] = scrub(nested)
            }
            return out
        }
        if let array = value as? [Any] {
            return array.map { scrub($0) }
        }
        return value
    }
}
