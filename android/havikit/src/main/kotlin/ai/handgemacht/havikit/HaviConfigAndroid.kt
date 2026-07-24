package ai.handgemacht.havikit

import android.content.Context
import android.content.pm.PackageManager
import android.os.Bundle
import android.util.Log

/**
 * The Android reader for the stamped `HAVI_*` `<meta-data>` (wire spec §14, Part B2)
 * — the manifest twin of iOS `HaviConfig.fromBundle`. It only lifts the application
 * node's `<meta-data>` into a plain map and delegates to the pure-JVM
 * [HaviConfig.fromMetaData], so the inert / misconfiguration / omit-empty semantics
 * stay in one unit-tested place.
 *
 * A `<meta-data>` value stamped as an `android:value="true"` boolean (rather than the
 * documented `"YES"` string) is read through its string form, so both the string and
 * boolean spellings of `HAVI_ENABLED` resolve.
 *
 * `HAVI_ENABLED` armed without a usable `HAVI_BASE_URL` resolves to the inert config
 * and logs one error line — the SDK's only console output, and the alternative to
 * crashing the host app over a build-time stamping mistake.
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
    val config = HaviConfig.fromMetaData(values)
    if (!config.isEnabled && HaviConfig.isEnabledValue(values["HAVI_ENABLED"])) {
        Log.e(
            "HaviKit",
            "HaviKit is enabled but HAVI_BASE_URL is missing or invalid " +
                "(an absolute http/https URL is required) — the SDK stays inert.",
        )
    }
    return config
}
