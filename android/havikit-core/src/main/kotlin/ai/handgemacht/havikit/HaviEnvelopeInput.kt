package ai.handgemacht.havikit

/**
 * The `x:havi.dev` scoping block. `project` / `worktree` / `branch` are the
 * load-bearing triage axes (also sent as multipart siblings); `commit` rides in
 * `x:havi.dev` only. Each field is omitted from the envelope when null/empty —
 * except `commit`, which is included whenever non-null (wire spec §6.4).
 */
public data class HaviDev(
    val project: String? = null,
    val worktree: String? = null,
    val branch: String? = null,
    val commit: String? = null,
)

/**
 * One applied workspace label → a `TextualBody` with `purpose: "tagging"` and an
 * `x:labelKey` (wire spec §6.2). `value` carries the applied value for a
 * `choice`/`value` label; a `flag` label applies with `value == null`, so the
 * builder omits the `value` field entirely. A `priority` entry here is skipped —
 * the built-in priority control feeds `HaviEnvelopeInput.priority` instead.
 */
public data class HaviLabel(
    val key: String,
    val value: String? = null,
)

/**
 * Everything the envelope builder needs to assemble one annotation (wire spec §6).
 * The builder is a pure function over it. Mirrors iOS `HaviEnvelopeInput`.
 */
public data class HaviEnvelopeInput(
    val bundleId: String,
    val screen: String,
    val viewport: HaviSize,
    /**
     * The `FragmentSelector` region in image pixels — the bounding-box union of
     * the non-blur markup marks, or the full frame when there is no markup.
     */
    val fragment: HaviRect,
    /**
     * The pre-serialized `SvgSelector` value (`<svg>…</svg>`) holding every
     * non-blur mark in image-pixel space, built by `HaviMarkupSerializer`. Null
     * when there is no markup (no `SvgSelector` emitted).
     */
    val markupSvg: String? = null,
    /** Display-only `CssSelector` value: `"<screen> > <a11y-id path>"`. */
    val cssPath: String,
    val comment: String? = null,
    /**
     * The applied priority value, emitted verbatim as the `priority` tagging
     * body's value (a raw string so a workspace's custom priority vocabulary
     * rides through unchanged). Null/blank emits no priority body.
     */
    val priority: String? = null,
    /** Applied workspace labels other than the built-in priority, in input order. */
    val labels: List<HaviLabel> = emptyList(),
    val deviceInfo: String? = null,
    val consoleErrors: String? = null,
    val networkErrors: String? = null,
    val appLogs: String? = null,
    val dev: HaviDev = HaviDev(),
    val contexts: Map<String, Map<String, String>> = emptyMap(),
    val tags: Map<String, String> = emptyMap(),
)
