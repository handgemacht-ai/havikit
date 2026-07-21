import Foundation

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

    /// Reads the stamped `HAVI_*` Info.plist keys (design §6). `HAVI_ENABLED`
    /// unset → `.inert`. `HAVI_ENABLED` set but `HAVI_BASE_URL`
    /// missing/invalid → `fatalError` (fail-fast, mirroring `Config.apiBaseURL`).
    /// Every other key is optional and simply absent when empty — the same
    /// "omit, never empty-string" discipline the stamper enforces end to end.
    public static func fromBundle(_ bundle: Bundle = .main) -> HaviConfig {
        guard infoValue("HAVI_ENABLED", bundle)?.uppercased() == "YES" else {
            return .inert
        }
        guard let raw = infoValue("HAVI_BASE_URL", bundle), let url = URL(string: raw) else {
            fatalError("HAVI_ENABLED is set but HAVI_BASE_URL is missing or invalid in Info.plist")
        }
        let format = HaviImageFormat(rawValue: (infoValue("HAVI_IMAGE_FORMAT", bundle) ?? "png").lowercased()) ?? .png
        return HaviConfig(
            isEnabled: true,
            baseURL: url,
            workspaceID: infoValue("HAVI_WORKSPACE_ID", bundle),
            project: infoValue("HAVI_PROJECT", bundle),
            worktree: infoValue("HAVI_WORKTREE", bundle),
            branch: infoValue("HAVI_BRANCH", bundle),
            commit: infoValue("HAVI_COMMIT", bundle),
            imageFormat: format,
            devToken: infoValue("HAVI_DEV_TOKEN", bundle),
            redaction: HaviRedactionPolicy()
        )
    }

    private static func infoValue(_ key: String, _ bundle: Bundle) -> String? {
        guard let value = bundle.object(forInfoDictionaryKey: key) as? String, !value.isEmpty else {
            return nil
        }
        return value
    }
}
