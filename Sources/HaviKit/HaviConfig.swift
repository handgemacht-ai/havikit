import Foundation
import os

/// Resolved SDK configuration, captured immutably at `Havi.start` (design §1,
/// §6). Mirrors `SentryReporting`'s DSN-gated activation: when `isEnabled` is
/// false every facade entry point no-ops, so a store build without HAVI keys
/// carries zero cost.
public struct HaviConfig: Sendable {
    public let isEnabled: Bool
    public let baseURL: URL?
    public let workspaceID: String?
    public let project: String?
    public let worktree: String?
    public let branch: String?
    public let commit: String?
    public let imageFormat: HaviImageFormat
    public let devToken: String?
    public let redaction: HaviRedactionPolicy

    public init(
        isEnabled: Bool,
        baseURL: URL?,
        workspaceID: String?,
        project: String?,
        worktree: String?,
        branch: String?,
        commit: String?,
        imageFormat: HaviImageFormat,
        devToken: String?,
        redaction: HaviRedactionPolicy
    ) {
        self.isEnabled = isEnabled
        self.baseURL = baseURL
        self.workspaceID = workspaceID
        self.project = project
        self.worktree = worktree
        self.branch = branch
        self.commit = commit
        self.imageFormat = imageFormat
        self.devToken = devToken
        self.redaction = redaction
    }

    /// The inert configuration used whenever `HAVI_ENABLED` is not set (the
    /// Release path). `Havi.start` returns before wiring anything.
    public static let inert = HaviConfig(
        isEnabled: false,
        baseURL: nil,
        workspaceID: nil,
        project: nil,
        worktree: nil,
        branch: nil,
        commit: nil,
        imageFormat: .png,
        devToken: nil,
        redaction: HaviRedactionPolicy()
    )

    private static let infoKeys = [
        "HAVI_ENABLED",
        "HAVI_BASE_URL",
        "HAVI_WORKSPACE_ID",
        "HAVI_PROJECT",
        "HAVI_WORKTREE",
        "HAVI_BRANCH",
        "HAVI_COMMIT",
        "HAVI_IMAGE_FORMAT",
        "HAVI_DEV_TOKEN",
    ]

    /// Reads the stamped `HAVI_*` Info.plist keys (design §6) and resolves them
    /// through `fromInfoValues`. A key stamped as a plist boolean (rather than
    /// the documented `YES` string) is read through its string form, so both
    /// spellings of `HAVI_ENABLED` resolve — parity with the Android manifest
    /// reader.
    public static func fromBundle(_ bundle: Bundle = .main) -> HaviConfig {
        var values: [String: String] = [:]
        for key in infoKeys {
            if let value = infoString(key, bundle) {
                values[key] = value
            }
        }
        return fromInfoValues(values)
    }

    /// The pure resolver behind `fromBundle`, twin of Android
    /// `HaviConfig.fromMetaData`:
    ///  - `HAVI_ENABLED` not `YES`/`true` → `.inert` (zero cost).
    ///  - `HAVI_ENABLED` set but `HAVI_BASE_URL` missing/invalid → one
    ///    fault-level log line and `.inert`. A misconfigured SDK stays out of the
    ///    way; it never takes the host app down.
    ///  - every other key optional; an empty string is treated as absent
    ///    ("omit, never empty-string").
    public static func fromInfoValues(_ values: [String: String]) -> HaviConfig {
        guard isEnabledValue(values["HAVI_ENABLED"]) else { return .inert }

        guard let raw = value(values, "HAVI_BASE_URL"), let url = validBaseURL(raw) else {
            logMisconfiguredBaseURL()
            return .inert
        }

        let rawFormat = value(values, "HAVI_IMAGE_FORMAT") ?? "png"
        let format = HaviImageFormat(
            rawValue: rawFormat.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        ) ?? .png
        return HaviConfig(
            isEnabled: true,
            baseURL: url,
            workspaceID: value(values, "HAVI_WORKSPACE_ID"),
            project: value(values, "HAVI_PROJECT"),
            worktree: value(values, "HAVI_WORKTREE"),
            branch: value(values, "HAVI_BRANCH"),
            commit: value(values, "HAVI_COMMIT"),
            imageFormat: format,
            devToken: value(values, "HAVI_DEV_TOKEN"),
            redaction: HaviRedactionPolicy()
        )
    }

    /// A base URL is usable only as an absolute `http`/`https` URL with a host
    /// (parity with Android `HaviConfig.validBaseUrlOrNull`). A schemeless string
    /// such as `havi.test`, a `file:` URL, or a scheme with no host is rejected.
    public static func validBaseURL(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty
        else { return nil }
        return url
    }

    /// True when a stamped `HAVI_ENABLED` arms the SDK: `YES` or `true`, trimmed
    /// and case-insensitive (parity with Android).
    private static func isEnabledValue(_ raw: String?) -> Bool {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
        return trimmed.caseInsensitiveCompare("YES") == .orderedSame
            || trimmed.caseInsensitiveCompare("true") == .orderedSame
    }

    private static func logMisconfiguredBaseURL() {
        Logger(subsystem: "ai.handgemacht.havikit", category: "config")
            .fault(
                "HaviKit is enabled but HAVI_BASE_URL is missing or invalid (an absolute http/https URL is required) — the SDK stays inert."
            )
    }

    /// Missing key OR empty string both resolve to nil (omit-never-empty).
    private static func value(_ values: [String: String], _ key: String) -> String? {
        guard let raw = values[key], !raw.isEmpty else { return nil }
        return raw
    }

    /// Info.plist values arrive as strings or, when stamped as a plist boolean,
    /// as a bridged `Bool`; anything else is ignored.
    private static func infoString(_ key: String, _ bundle: Bundle) -> String? {
        guard let raw = bundle.object(forInfoDictionaryKey: key) else { return nil }
        switch raw {
        case let text as String:
            return text
        case let flag as Bool:
            return flag ? "true" : "false"
        default:
            return nil
        }
    }
}
