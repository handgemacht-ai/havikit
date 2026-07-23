package ai.handgemacht.havikit

import java.net.URI

/**
 * Resolved SDK configuration, captured immutably at start (wire spec §14). When
 * [isEnabled] is false every facade entry point no-ops, so a release build
 * without HAVI keys carries zero cost.
 *
 * The pure-JVM core keeps the reader that turns the stamped `HAVI_*` values into a
 * config ([fromMetaData]); the Android module's `HaviConfig.fromManifest(context)`
 * simply reads the `<meta-data>` bundle into a map and delegates here, so the
 * inert / fail-fast / omit-empty semantics live in one tested place.
 */
public data class HaviConfig(
    val isEnabled: Boolean,
    val baseUrl: URI?,
    val workspaceId: String?,
    val project: String?,
    val worktree: String?,
    val branch: String?,
    val commit: String?,
    val imageFormat: HaviImageFormat,
    val devToken: String?,
    val redaction: HaviRedactionPolicy = HaviRedactionPolicy(),
) {
    public companion object {
        /** The inert config used whenever `HAVI_ENABLED` is not set (release path). */
        public val Inert: HaviConfig =
            HaviConfig(
                isEnabled = false,
                baseUrl = null,
                workspaceId = null,
                project = null,
                worktree = null,
                branch = null,
                commit = null,
                imageFormat = HaviImageFormat.PNG,
                devToken = null,
                redaction = HaviRedactionPolicy(),
            )

        /**
         * Reads the stamped `HAVI_*` keys, mirroring iOS `HaviConfig.fromBundle`
         * (wire spec §14):
         *  - `HAVI_ENABLED` not `YES`/`true` -> [Inert] (zero cost).
         *  - `HAVI_ENABLED` set but `HAVI_BASE_URL` missing/invalid -> throws
         *    [IllegalStateException] (fail-fast; the Android intent equivalent of
         *    the iOS `fatalError`).
         *  - every other key optional; an empty string is treated as absent
         *    ("omit, never empty-string").
         */
        public fun fromMetaData(
            meta: Map<String, String?>,
            redaction: HaviRedactionPolicy = HaviRedactionPolicy(),
        ): HaviConfig {
            if (!isYes(value(meta, "HAVI_ENABLED"))) return Inert

            val raw = value(meta, "HAVI_BASE_URL")
                ?: error("HAVI_ENABLED is set but HAVI_BASE_URL is missing or invalid")
            val url = validBaseUrlOrNull(raw)
                ?: error("HAVI_ENABLED is set but HAVI_BASE_URL is missing or invalid")

            return HaviConfig(
                isEnabled = true,
                baseUrl = url,
                workspaceId = value(meta, "HAVI_WORKSPACE_ID"),
                project = value(meta, "HAVI_PROJECT"),
                worktree = value(meta, "HAVI_WORKTREE"),
                branch = value(meta, "HAVI_BRANCH"),
                commit = value(meta, "HAVI_COMMIT"),
                imageFormat = HaviImageFormat.fromRawOrPng(value(meta, "HAVI_IMAGE_FORMAT")),
                devToken = value(meta, "HAVI_DEV_TOKEN"),
                redaction = redaction,
            )
        }

        /** Missing key OR empty string both resolve to null (omit-never-empty). */
        private fun value(
            meta: Map<String, String?>,
            key: String,
        ): String? = meta[key]?.takeIf { it.isNotEmpty() }

        private fun isYes(raw: String?): Boolean =
            raw?.trim()?.let { it.equals("YES", ignoreCase = true) || it.equals("true", ignoreCase = true) } == true

        /** A base URL is valid only when it is an absolute http/https URL with a host. */
        public fun validBaseUrlOrNull(raw: String): URI? =
            runCatching { URI(raw.trim()) }.getOrNull()?.takeIf { uri ->
                val scheme = uri.scheme?.lowercase()
                (scheme == "http" || scheme == "https") && !uri.host.isNullOrEmpty()
            }
    }
}
