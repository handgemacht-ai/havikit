import Foundation

/// Pure derivation of a display screen name from a view-controller type name,
/// used by the snapshotter's best-effort auto-detection when the host set no
/// screen via `.haviScreen(_:)` / `Havi.setScreen(_:)`. Kept UIKit-free so the
/// filter runs under `swift test` without a Simulator.
enum HaviScreenName {
    /// Generic container / hosting controllers carry no screen-specific name —
    /// naming a capture "UIHostingController" is worse than falling through to
    /// "unknown", so these resolve to `nil`.
    private static let genericControllers: Set<String> = [
        "UIViewController",
        "UIHostingController",
        "UINavigationController",
        "UITabBarController",
        "UISplitViewController",
        "UIPageViewController",
    ]

    /// The screen name for a fully-qualified controller type name
    /// (`MyApp.ReaderViewController`, `UIHostingController<AnyView>`), or `nil`
    /// when it is a generic container that carries no useful name. The module
    /// prefix and any generic arguments are stripped.
    static func screen(forControllerType typeName: String) -> String? {
        let withoutModule = typeName.split(separator: ".").last.map(String.init) ?? typeName
        let base = withoutModule.split(separator: "<").first.map(String.init) ?? withoutModule
        let trimmed = base.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !genericControllers.contains(trimmed) else { return nil }
        return trimmed
    }
}
