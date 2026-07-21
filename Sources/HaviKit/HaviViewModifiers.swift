#if canImport(SwiftUI)
import SwiftUI

/// A frame published by a `.haviRedacted()` / `.haviReveal()` subtree, in global
/// (window) coordinates. The snapshotter (SDK-4) paints opaque rects over these
/// **before** the capture bytes exist (design §2).
public struct HaviRedactionRegion: Equatable, Sendable {
    public let frame: CGRect
    public let reveal: Bool

    public init(frame: CGRect, reveal: Bool) {
        self.frame = frame
        self.reveal = reveal
    }
}

public struct HaviRedactionPreferenceKey: PreferenceKey {
    public static let defaultValue: [HaviRedactionRegion] = []

    public static func reduce(value: inout [HaviRedactionRegion], nextValue: () -> [HaviRedactionRegion]) {
        value.append(contentsOf: nextValue())
    }
}

struct HaviRedactionModifier: ViewModifier {
    let reveal: Bool

    func body(content: Content) -> some View {
        content.background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: HaviRedactionPreferenceKey.self,
                    value: [HaviRedactionRegion(frame: proxy.frame(in: .global), reveal: reveal)]
                )
            }
        )
    }
}

struct HaviScreenModifier: ViewModifier {
    let name: String

    func body(content: Content) -> some View {
        content.onAppear { HaviContextStore.shared.setScreen(name) }
    }
}

struct HaviContextModifier: ViewModifier {
    let namespace: String
    let values: [String: String]

    func body(content: Content) -> some View {
        content.onAppear { HaviContextStore.shared.setContext(namespace, values) }
    }
}

/// Root capture host. Installed once at the app root; the shake overlay +
/// capture sheet (design §2) are wired in SDK-4. Inert passthrough today so
/// Release (where `Havi.isEnabled == false`) renders nothing extra.
struct HaviOverlayModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
    }
}

public extension View {
    /// Marks a subtree secret — its frame is blacked out in the freeze snapshot.
    func haviRedacted() -> some View {
        modifier(HaviRedactionModifier(reveal: false))
    }

    /// Opts a subtree back IN when its category is masked by default.
    func haviReveal() -> some View {
        modifier(HaviRedactionModifier(reveal: true))
    }

    /// Names the current screen — becomes the `CssSelector` value + source path.
    func haviScreen(_ name: String) -> some View {
        modifier(HaviScreenModifier(name: name))
    }

    /// Scopes context to a subtree (captured into `x:havi.contexts`).
    func haviContext(_ namespace: String, _ values: [String: String]) -> some View {
        modifier(HaviContextModifier(namespace: namespace, values: values))
    }

    /// Installs the shake overlay + capture host. Mounted once at the app root.
    func haviOverlay() -> some View {
        modifier(HaviOverlayModifier())
    }
}
#endif
