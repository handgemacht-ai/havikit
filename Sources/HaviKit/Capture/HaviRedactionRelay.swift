import CoreGraphics
import Foundation

/// Lock-guarded relay for the latest `.haviRedacted()` / `.haviReveal()` frames
/// published up the view tree through `HaviRedactionPreferenceKey` (design §2).
/// The overlay writes the current regions here on every preference change; the
/// snapshotter reads them synchronously at trigger time and paints opaque rects
/// **before** any capture bytes exist. A singleton (mirroring `HaviLogBuffer` /
/// `HaviContextStore`) so the SwiftUI `onPreferenceChange` closure captures only
/// a `Sendable` reference, never the `@MainActor` presenter.
final class HaviRedactionRelay: @unchecked Sendable {
    static let shared = HaviRedactionRelay()

    private let lock = HaviUnfairLock()
    private var regions: [HaviRedactionRegion] = []

    func setRegions(_ regions: [HaviRedactionRegion]) {
        lock.withLock { self.regions = regions }
    }

    func currentRegions() -> [HaviRedactionRegion] {
        lock.withLock { regions }
    }

    /// The opaque rectangles to paint on the freeze snapshot: every non-reveal
    /// region, minus the area of any `.haviReveal()` region layered on top (a
    /// subtree explicitly opted back in). Reveal never *adds* paint — it only
    /// carves back a masked-by-default area, so a redacted region wins over a
    /// reveal it does not overlap.
    func maskFrames() -> [CGRect] {
        let all = currentRegions()
        return all.filter { !$0.reveal }.map(\.frame)
    }

    /// The reveal frames, used to exclude default-masked text fields the
    /// integration explicitly opted back in.
    func revealFrames() -> [CGRect] {
        currentRegions().filter(\.reveal).map(\.frame)
    }
}
