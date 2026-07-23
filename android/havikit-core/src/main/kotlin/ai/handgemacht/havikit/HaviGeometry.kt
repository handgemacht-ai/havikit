package ai.handgemacht.havikit

/**
 * Integer size in **logical points**, used for `target.state`'s `viewport=WxH`
 * value (wire spec §6.3).
 */
public data class HaviSize(
    val width: Int,
    val height: Int,
)

/**
 * Integer rectangle in **downscaled image-pixel** space, matching the screenshot
 * the coordinates are drawn against — the `FragmentSelector` region (wire spec §6.3).
 */
public data class HaviRect(
    val x: Int,
    val y: Int,
    val width: Int,
    val height: Int,
)
