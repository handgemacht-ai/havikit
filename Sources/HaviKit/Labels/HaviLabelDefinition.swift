import Foundation

/// The label kinds the SDK renders, mirroring the browser extension's picker
/// (`extension/src/content/content.js`): a `choice` value drawn from
/// `allowedValues`, a free-form `value`, or a boolean `flag`. The server may add
/// other kinds later; an unrecognized `kind` is dropped at parse time rather than
/// guessed at, so the capture sheet never invents a control it does not support.
public enum HaviLabelKind: String, Sendable, Equatable, CaseIterable {
    case choice
    case value
    case flag
}

/// One workspace label definition from `GET /api/label-definitions` (API.md).
/// The capture sheet renders a control per definition, ordered by `position`;
/// the built-in `priority` definition (`key == "priority"`) is the one the
/// existing segmented control already represents.
public struct HaviLabelDefinition: Sendable, Equatable, Identifiable {
    public let id: String
    public let key: String
    public let name: String
    public let kind: HaviLabelKind
    public let allowedValues: [String]
    public let color: String?
    public let description: String?
    public let position: Int

    public init(
        id: String,
        key: String,
        name: String,
        kind: HaviLabelKind,
        allowedValues: [String] = [],
        color: String? = nil,
        description: String? = nil,
        position: Int = 0
    ) {
        self.id = id
        self.key = key
        self.name = name
        self.kind = kind
        self.allowedValues = allowedValues
        self.color = color
        self.description = description
        self.position = position
    }

    /// Parses the `{ "data": [ … ] }` envelope from `GET /api/label-definitions`
    /// into definitions ordered by `position`. Archived entries and any with an
    /// unknown `kind`, a missing key/id, or (for `choice`) no allowed values are
    /// dropped so only renderable definitions survive. Returns `nil` when the
    /// bytes are not the expected envelope shape at all.
    static func parseList(_ data: Data) -> [HaviLabelDefinition]? {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let rawList = root["data"] as? [[String: Any]]
        else {
            return nil
        }

        return rawList
            .compactMap(fromResource)
            .sorted { $0.position < $1.position }
    }

    private static func fromResource(_ raw: [String: Any]) -> HaviLabelDefinition? {
        guard
            let id = raw["id"] as? String, !id.isEmpty,
            let key = raw["key"] as? String, !key.isEmpty,
            let kindRaw = raw["kind"] as? String,
            let kind = HaviLabelKind(rawValue: kindRaw)
        else {
            return nil
        }

        if raw["archived"] as? Bool == true {
            return nil
        }

        let allowedValues = (raw["allowed_values"] as? [Any])?.compactMap { $0 as? String } ?? []
        if kind == .choice, allowedValues.isEmpty {
            return nil
        }

        return HaviLabelDefinition(
            id: id,
            key: key,
            name: (raw["name"] as? String) ?? key,
            kind: kind,
            allowedValues: allowedValues,
            color: raw["color"] as? String,
            description: raw["description"] as? String,
            position: (raw["position"] as? Int) ?? 0
        )
    }
}
