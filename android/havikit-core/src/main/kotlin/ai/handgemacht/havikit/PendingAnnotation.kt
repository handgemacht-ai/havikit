package ai.handgemacht.havikit

/**
 * Re-encodes the outgoing (already cropped + redacted) image at a new format /
 * longest side for the server-driven fallbacks (wire spec §7.3). Returns null when
 * re-encoding is unavailable. The Android module supplies a Bitmap-backed
 * implementation; the core keeps it a plain function so the uploader stays pure.
 */
public fun interface HaviImageReencoder {
    public fun reencode(
        format: HaviImageFormat,
        longestSide: Int,
    ): ByteArray?
}

/**
 * Immutable value handed to [HaviUploader] on submit (wire spec §1). Carries the
 * canonical envelope JSON string, the encoded screenshot, the load-bearing
 * multipart siblings, the snapshotted credential, and a reencoder over the
 * cropped, redacted outgoing image for the server-driven fallbacks — nothing
 * mutable, so a later context/tag mutation or credential change cannot race an
 * in-flight send.
 */
public data class PendingAnnotation(
    val annotationJson: String,
    val imageData: ByteArray?,
    val imageFormat: HaviImageFormat,
    val siblings: Map<String, String>,
    val workspaceId: String?,
    val bearerToken: String? = null,
    val reencoder: HaviImageReencoder? = null,
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is PendingAnnotation) return false
        return annotationJson == other.annotationJson &&
            (imageData?.contentEquals(other.imageData) ?: (other.imageData == null)) &&
            imageFormat == other.imageFormat &&
            siblings == other.siblings &&
            workspaceId == other.workspaceId &&
            bearerToken == other.bearerToken &&
            reencoder == other.reencoder
    }

    override fun hashCode(): Int {
        var result = annotationJson.hashCode()
        result = 31 * result + (imageData?.contentHashCode() ?: 0)
        result = 31 * result + imageFormat.hashCode()
        result = 31 * result + siblings.hashCode()
        result = 31 * result + (workspaceId?.hashCode() ?: 0)
        result = 31 * result + (bearerToken?.hashCode() ?: 0)
        result = 31 * result + (reencoder?.hashCode() ?: 0)
        return result
    }

    public companion object {
        /**
         * Assembles the pending annotation from a builder input plus encoded image
         * bytes. The envelope, siblings, and format come from the builder; the
         * credential + reencoder are snapshotted from the runtime at submit time.
         */
        public fun make(
            input: HaviEnvelopeInput,
            imageData: ByteArray?,
            imageFormat: HaviImageFormat,
            workspaceId: String?,
            bearerToken: String? = null,
            reencoder: HaviImageReencoder? = null,
        ): PendingAnnotation =
            PendingAnnotation(
                annotationJson = HaviEnvelopeBuilder.jsonString(input),
                imageData = imageData,
                imageFormat = imageFormat,
                siblings = HaviEnvelopeBuilder.siblings(input),
                workspaceId = workspaceId,
                bearerToken = bearerToken,
                reencoder = reencoder,
            )
    }
}
