import Foundation

/// Pure downscale-to-fit math (design §4). The screenshot is rendered so the
/// **longest side ≤ 1600 px** (dropping the retina multiplier); if the encoded
/// bytes still exceed the format cap the longest side steps down the ladder
/// (1600 → 1280 → 1024, floor 900) and re-encodes. `payload_too_large` from the
/// server re-encodes at a fixed 1024 longest side. Kept separate from any UIKit
/// rendering so the size math is unit-testable on Linux/macOS without a
/// Simulator.
enum HaviImagePlan {
    static let defaultMaxLongestSide = 1600

    /// Longest-side ladder walked while an encoded image stays over the cap.
    static let stepDownLadder = [1600, 1280, 1024, 900]

    /// Longest side the `payload_too_large` fallback re-encodes at (design §4).
    static let payloadTooLargeLongestSide = 1024

    /// `min(1, maxLongestSide / max(w, h))` — never upscales.
    static func scale(width: Int, height: Int, maxLongestSide: Int) -> Double {
        let longest = max(width, height)
        guard longest > 0 else { return 1 }
        return min(1.0, Double(maxLongestSide) / Double(longest))
    }

    /// Integer pixel size after applying `scale`, preserving aspect ratio.
    static func targetSize(width: Int, height: Int, maxLongestSide: Int) -> HaviSize {
        let factor = scale(width: width, height: height, maxLongestSide: maxLongestSide)
        return HaviSize(
            width: Int((Double(width) * factor).rounded()),
            height: Int((Double(height) * factor).rounded())
        )
    }

    /// Next ladder value strictly below `current`, or nil at the floor.
    static func nextStepDown(below current: Int) -> Int? {
        stepDownLadder.first(where: { $0 < current })
    }
}
