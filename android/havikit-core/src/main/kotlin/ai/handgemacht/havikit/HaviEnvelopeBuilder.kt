package ai.handgemacht.havikit

/**
 * Builds the same W3C Web Annotation envelope shape the web `buildAnnotation`
 * produces (wire spec §6), so Android annotations land in identical storage. The
 * backend stamps `id` / `created` / `modified` / `creator` and the `Image` body's
 * `id`, so this omits them.
 *
 * Body order: comment -> priority tagging -> other label tagging bodies ->
 * describing bodies (device-info -> console-errors -> network-errors -> app-logs)
 * -> `{ "type": "Image" }` last. Selector order: FragmentSelector -> CssSelector
 * -> SvgSelector (only when markup exists). Omit-empty discipline throughout — any
 * body / bucket / field that would be empty is dropped entirely.
 *
 * The builder emits an ordered `Map<String, Any?>` tree; [HaviCanonicalJson]
 * sorts keys and serializes it byte-exactly, so map insertion order here is
 * cosmetic (it never reaches the wire).
 */
public object HaviEnvelopeBuilder {
    /** The assembled envelope as a plain tree, ready for [HaviCanonicalJson]. */
    public fun build(input: HaviEnvelopeInput): Map<String, Any?> {
        val body = mutableListOf<Map<String, Any?>>()

        nonEmpty(input.comment?.trim())?.let { comment ->
            body += mapOf(
                "type" to "TextualBody",
                "value" to comment,
                "purpose" to "commenting",
            )
        }

        nonEmpty(input.priority?.trim())?.let { priority ->
            body += mapOf(
                "type" to "TextualBody",
                "value" to priority,
                "purpose" to "tagging",
                "x:labelKey" to "priority",
            )
        }

        for (label in input.labels) {
            if (label.key == "priority") continue
            val taggingBody = linkedMapOf<String, Any?>(
                "type" to "TextualBody",
                "purpose" to "tagging",
                "x:labelKey" to label.key,
            )
            if (label.value != null) taggingBody["value"] = label.value
            body += taggingBody
        }

        nonEmpty(input.deviceInfo)?.let { body += describingBody("device-info", it) }
        nonEmpty(input.consoleErrors)?.let { body += describingBody("console-errors", it) }
        nonEmpty(input.networkErrors)?.let { body += describingBody("network-errors", it) }
        nonEmpty(input.appLogs)?.let { body += describingBody("app-logs", it) }

        body += mapOf("type" to "Image")

        val selector = mutableListOf<Map<String, Any?>>(
            mapOf(
                "type" to "FragmentSelector",
                "conformsTo" to "http://www.w3.org/TR/media-frags/",
                "value" to fragmentValue(input.fragment),
            ),
            mapOf(
                "type" to "CssSelector",
                "value" to input.cssPath,
            ),
        )

        nonEmpty(input.markupSvg)?.let { markupSvg ->
            selector += mapOf(
                "type" to "SvgSelector",
                "value" to markupSvg,
            )
        }

        val annotation = linkedMapOf<String, Any?>(
            "@context" to "http://www.w3.org/ns/anno.jsonld",
            "type" to "Annotation",
            "motivation" to "commenting",
            "body" to body,
            "target" to mapOf(
                "source" to "app://${input.bundleId}/${input.screen}",
                "selector" to selector,
                "state" to mapOf(
                    "type" to "HttpRequestState",
                    "value" to "viewport=${input.viewport.width}x${input.viewport.height}",
                ),
            ),
        )

        buildXHavi(input)?.let { annotation["x:havi"] = it }

        return annotation
    }

    /** Envelope JSON as the UTF-8 string sent in the multipart `annotation` part. */
    public fun jsonString(input: HaviEnvelopeInput): String = HaviCanonicalJson.encode(build(input))

    /**
     * The multipart siblings the controller reads — `project` / `worktree` /
     * `branch` only (wire spec §5.1). `commit` is never a sibling.
     */
    public fun siblings(input: HaviEnvelopeInput): Map<String, String> {
        val out = LinkedHashMap<String, String>()
        nonEmpty(input.dev.project)?.let { out["project"] = it }
        nonEmpty(input.dev.worktree)?.let { out["worktree"] = it }
        nonEmpty(input.dev.branch)?.let { out["branch"] = it }
        return out
    }

    private fun describingBody(
        role: String,
        value: String,
    ): Map<String, Any?> =
        mapOf(
            "type" to "TextualBody",
            "value" to value,
            "purpose" to "describing",
            "format" to "text/plain",
            "x:role" to role,
        )

    private fun fragmentValue(rect: HaviRect): String = "xywh=${rect.x},${rect.y},${rect.width},${rect.height}"

    /**
     * Single top-level `x:havi` object with the web's fixed buckets. `contexts`
     * and `tags` are secret-scrubbed on device; any bucket (or nested namespace)
     * that scrubs to empty is dropped rather than shipped as `{}`.
     */
    private fun buildXHavi(input: HaviEnvelopeInput): Map<String, Any?>? {
        val xHavi = LinkedHashMap<String, Any?>()

        val dev = buildDev(input.dev)
        if (dev.isNotEmpty()) xHavi["dev"] = dev

        if (input.contexts.isNotEmpty()) {
            val scrubbed = HaviRedaction.scrub(input.contexts)
            @Suppress("UNCHECKED_CAST")
            val pruned = pruneEmptyObjects(scrubbed) as? Map<String, Any?>
            if (!pruned.isNullOrEmpty()) xHavi["contexts"] = pruned
        }

        if (input.tags.isNotEmpty()) {
            @Suppress("UNCHECKED_CAST")
            val scrubbed = HaviRedaction.scrub(input.tags) as? Map<String, Any?>
            if (!scrubbed.isNullOrEmpty()) xHavi["tags"] = scrubbed
        }

        return xHavi.ifEmpty { null }
    }

    private fun buildDev(dev: HaviDev): Map<String, Any?> {
        val out = LinkedHashMap<String, Any?>()
        nonEmpty(dev.project)?.let { out["project"] = it }
        nonEmpty(dev.worktree)?.let { out["worktree"] = it }
        nonEmpty(dev.branch)?.let { out["branch"] = it }
        if (dev.commit != null) out["commit"] = dev.commit
        return out
    }

    /**
     * Drops object values that became empty after scrubbing, at any depth, so a
     * namespace whose keys were all secret is omitted rather than shipped as `{}`.
     */
    private fun pruneEmptyObjects(value: Any?): Any? =
        when (value) {
            is Map<*, *> -> {
                val out = LinkedHashMap<String, Any?>()
                for ((rawKey, nested) in value) {
                    val key = rawKey as? String ?: continue
                    val pruned = pruneEmptyObjects(nested)
                    if (pruned is Map<*, *> && pruned.isEmpty()) continue
                    out[key] = pruned
                }
                out
            }

            is List<*> -> value.map { pruneEmptyObjects(it) }

            else -> value
        }

    private fun nonEmpty(value: String?): String? = value?.takeIf { it.isNotEmpty() }
}
