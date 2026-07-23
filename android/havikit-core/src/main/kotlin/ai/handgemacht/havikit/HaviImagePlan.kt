package ai.handgemacht.havikit

import kotlin.math.max
import kotlin.math.roundToInt

/**
 * Pure downscale-to-fit math (wire spec §9.2). The screenshot is rendered so the
 * longest side <= 1600 px (render scale = 1, retina multiplier dropped); if the
 * encoded bytes still exceed the format cap the longest side steps down the ladder
 * (1600 -> 1280 -> 1024, floor 900) and re-encodes. `payload_too_large` from the
 * server re-encodes at a fixed 1024 longest side. Kept free of any bitmap API so
 * the size math is unit-testable on the JVM.
 */
public object HaviImagePlan {
    public const val DEFAULT_MAX_LONGEST_SIDE: Int = 1600

    /** Longest-side ladder walked while an encoded image stays over the cap. */
    public val stepDownLadder: List<Int> = listOf(1600, 1280, 1024, 900)

    /** Longest side the `payload_too_large` fallback re-encodes at. */
    public const val PAYLOAD_TOO_LARGE_LONGEST_SIDE: Int = 1024

    /** `min(1, maxLongestSide / max(w, h))` — never upscales. */
    public fun scale(
        width: Int,
        height: Int,
        maxLongestSide: Int,
    ): Double {
        val longest = max(width, height)
        if (longest <= 0) return 1.0
        return minOf(1.0, maxLongestSide.toDouble() / longest.toDouble())
    }

    /** Integer pixel size after applying [scale], preserving aspect ratio. */
    public fun targetSize(
        width: Int,
        height: Int,
        maxLongestSide: Int,
    ): HaviSize {
        val factor = scale(width, height, maxLongestSide)
        return HaviSize(
            width = (width * factor).roundToInt(),
            height = (height * factor).roundToInt(),
        )
    }

    /** Next ladder value strictly below [current], or null at the floor. */
    public fun nextStepDown(below: Int): Int? = stepDownLadder.firstOrNull { it < below }
}
