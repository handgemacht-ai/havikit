import Foundation

/// Assembles the `device-info` and `app-logs` `describing` bodies (design §3).
/// The formatting is pure so it is unit-testable; the UIKit-backed `current()`
/// (device model, iOS version, orientation) lives behind `canImport(UIKit)`.
enum HaviDeviceInfo {
    /// `"iPhone15,3 · iOS 17.5.1 · Lesewerkstatt Dev 1.4.0+812 · de_DE · landscapeLeft"`
    /// — omitting any component that is empty rather than emitting a dangling
    /// separator (omit-empty discipline, design §3).
    static func format(
        model: String?,
        systemName: String,
        systemVersion: String?,
        appName: String?,
        version: String?,
        build: String?,
        locale: String?,
        orientation: String?
    ) -> String {
        var parts: [String] = []
        if let model, !model.isEmpty { parts.append(model) }
        if let systemVersion, !systemVersion.isEmpty { parts.append("\(systemName) \(systemVersion)") }
        if let appName, !appName.isEmpty {
            var app = appName
            if let version, !version.isEmpty {
                app += " \(version)"
                if let build, !build.isEmpty { app += "+\(build)" }
            }
            parts.append(app)
        }
        if let locale, !locale.isEmpty { parts.append(locale) }
        if let orientation, !orientation.isEmpty { parts.append(orientation) }
        return parts.joined(separator: " · ")
    }

    /// One line per breadcrumb, oldest first: `"[level] message"`. Empty when the
    /// ring is empty (the caller then omits the body entirely).
    static func formatLogs(_ entries: [HaviLogEntry]) -> String {
        entries
            .map { "[\($0.level.rawValue)] \($0.message)" }
            .joined(separator: "\n")
    }
}
