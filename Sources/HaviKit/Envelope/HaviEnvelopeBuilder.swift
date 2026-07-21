import Foundation

/// Builds the same W3C envelope shape the web `buildAnnotation` produces
/// (design §3), so mobile annotations land in existing storage, dashboard, and
/// MCP unchanged. The backend stamps `id` / `created` / `modified` / `creator`
/// and the `Image` body's `id`, so this omits them.
///
/// Body order: comment → priority `tagging` → `describing` bodies
/// (`device-info`, `app-logs`) → `{ "type": "Image" }` last. Selector order:
/// `FragmentSelector` → `CssSelector` → `SvgSelector` (only when markup exists).
/// Omit-empty discipline throughout — any body / bucket / field that would be
/// empty is dropped entirely (no `""`, `[]`, or `{}`).
public enum HaviEnvelopeBuilder {
    public static func build(_ input: HaviEnvelopeInput) -> [String: Any] {
        var body: [[String: Any]] = []

        if let comment = input.comment?.trimmingCharacters(in: .whitespacesAndNewlines), !comment.isEmpty {
            body.append([
                "type": "TextualBody",
                "value": comment,
                "purpose": "commenting",
            ])
        }

        if let priority = input.priority {
            body.append([
                "type": "TextualBody",
                "value": priority.rawValue,
                "purpose": "tagging",
                "x:labelKey": "priority",
            ])
        }

        if let deviceInfo = nonEmpty(input.deviceInfo) {
            body.append(describingBody(role: "device-info", value: deviceInfo))
        }

        if let appLogs = nonEmpty(input.appLogs) {
            body.append(describingBody(role: "app-logs", value: appLogs))
        }

        body.append(["type": "Image"])

        var selector: [[String: Any]] = [
            [
                "type": "FragmentSelector",
                "conformsTo": "http://www.w3.org/TR/media-frags/",
                "value": fragmentValue(input.fragment),
            ],
            [
                "type": "CssSelector",
                "value": input.cssPath,
            ],
        ]

        if let markup = input.markup {
            selector.append([
                "type": "SvgSelector",
                "value": svgValue(markup, strokeColor: input.strokeColor, strokeWidth: input.strokeWidth),
            ])
        }

        var annotation: [String: Any] = [
            "@context": "http://www.w3.org/ns/anno.jsonld",
            "type": "Annotation",
            "motivation": "commenting",
            "body": body,
            "target": [
                "source": "app://\(input.bundleID)/\(input.screen)",
                "selector": selector,
                "state": [
                    "type": "HttpRequestState",
                    "value": "viewport=\(input.viewport.width)x\(input.viewport.height)",
                ],
            ],
        ]

        if let xHavi = buildXHavi(input) {
            annotation["x:havi"] = xHavi
        }

        return annotation
    }

    /// Envelope JSON as the UTF-8 string sent in the multipart `annotation` part.
    public static func jsonString(_ input: HaviEnvelopeInput) throws -> String {
        try HaviCanonicalJSON.string(build(input))
    }

    /// The multipart siblings actually read by the controller — `project` /
    /// `worktree` / `branch` only (design §4). `commit` is not a sibling.
    public static func siblings(_ input: HaviEnvelopeInput) -> [String: String] {
        var out: [String: String] = [:]
        if let project = input.dev.project { out["project"] = project }
        if let worktree = input.dev.worktree { out["worktree"] = worktree }
        if let branch = input.dev.branch { out["branch"] = branch }
        return out
    }

    // MARK: - Pieces

    private static func describingBody(role: String, value: String) -> [String: Any] {
        [
            "type": "TextualBody",
            "value": value,
            "purpose": "describing",
            "format": "text/plain",
            "x:role": role,
        ]
    }

    private static func fragmentValue(_ rect: HaviRect) -> String {
        "xywh=\(rect.x),\(rect.y),\(rect.width),\(rect.height)"
    }

    private static func svgValue(_ rect: HaviRect, strokeColor: String, strokeWidth: Int) -> String {
        "<svg xmlns=\"http://www.w3.org/2000/svg\">"
            + "<rect x=\"\(rect.x)\" y=\"\(rect.y)\" width=\"\(rect.width)\" height=\"\(rect.height)\" "
            + "fill=\"none\" stroke=\"\(strokeColor)\" stroke-width=\"\(strokeWidth)\"/>"
            + "</svg>"
    }

    /// Single top-level `x:havi` object with the web's fixed buckets. `contexts`
    /// and `tags` are secret-scrubbed on device with the `enrichment.js` KEY
    /// regex; any bucket (or nested namespace) that scrubs to empty is dropped.
    private static func buildXHavi(_ input: HaviEnvelopeInput) -> [String: Any]? {
        var xHavi: [String: Any] = [:]

        let dev = buildDev(input.dev)
        if !dev.isEmpty { xHavi["dev"] = dev }

        if !input.contexts.isEmpty {
            let scrubbed = HaviRedaction.scrub(input.contexts as [String: Any])
            if let contexts = pruneEmptyObjects(scrubbed) as? [String: Any], !contexts.isEmpty {
                xHavi["contexts"] = contexts
            }
        }

        if !input.tags.isEmpty {
            if let tags = HaviRedaction.scrub(input.tags as [String: Any]) as? [String: Any], !tags.isEmpty {
                xHavi["tags"] = tags
            }
        }

        return xHavi.isEmpty ? nil : xHavi
    }

    private static func buildDev(_ dev: HaviDev) -> [String: Any] {
        var out: [String: Any] = [:]
        if let project = dev.project { out["project"] = project }
        if let worktree = dev.worktree { out["worktree"] = worktree }
        if let branch = dev.branch { out["branch"] = branch }
        if let commit = dev.commit { out["commit"] = commit }
        return out
    }

    /// Drops object values that became empty after scrubbing, at any depth, so a
    /// namespace whose keys were all secret is omitted rather than shipped as
    /// `{}` (omit-empty rule, design §3).
    private static func pruneEmptyObjects(_ value: Any) -> Any {
        if let dictionary = value as? [String: Any] {
            var out: [String: Any] = [:]
            for (key, nested) in dictionary {
                let pruned = pruneEmptyObjects(nested)
                if let nestedObject = pruned as? [String: Any], nestedObject.isEmpty { continue }
                out[key] = pruned
            }
            return out
        }
        if let array = value as? [Any] {
            return array.map { pruneEmptyObjects($0) }
        }
        return value
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}
