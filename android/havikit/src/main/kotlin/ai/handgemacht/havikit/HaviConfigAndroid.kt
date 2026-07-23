package ai.handgemacht.havikit

import android.content.Context
import android.content.pm.PackageManager
import android.os.Bundle

/**
 * The Android reader for the stamped `HAVI_*` `<meta-data>` (wire spec §14, Part B2)
 * — the manifest twin of iOS `HaviConfig.fromBundle`. It only lifts the application
 * node's `<meta-data>` into a plain map and delegates to the pure-JVM
 * [HaviConfig.fromMetaData], so the inert / fail-fast / omit-empty semantics stay in
 * one unit-tested place.
 *
 * A `<meta-data>` value stamped as an `android:value="true"` boolean (rather than the
 * documented `"YES"` string) is read through its string form, so both the string and
 * boolean spellings of `HAVI_ENABLED` resolve.
 */
private val HAVI_META_KEYS =
    listOf(
        "HAVI_ENABLED",
        "HAVI_BASE_URL",
        "HAVI_WORKSPACE_ID",
        "HAVI_PROJECT",
        "HAVI_WORKTREE",
        "HAVI_BRANCH",
        "HAVI_COMMIT",
        "HAVI_IMAGE_FORMAT",
        "HAVI_DEV_TOKEN",
    )

public fun HaviConfig.Companion.fromManifest(context: Context): HaviConfig {
    val metaData: Bundle =
        runCatching {
            context.packageManager
                .getApplicationInfo(context.packageName, PackageManager.GET_META_DATA)
                .metaData
        }.getOrNull() ?: return HaviConfig.Inert

    val values = HAVI_META_KEYS.associateWith { key -> metaData.get(key)?.toString() }
    return HaviConfig.fromMetaData(values)
}
