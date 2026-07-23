package ai.handgemacht.havikit

import android.graphics.Bitmap
import java.io.ByteArrayOutputStream

/**
 * Turns a captured [Bitmap] into the upload bytes the core models consume (wire spec
 * §9) — the concrete "wire bitmaps to the core upload models" bridge. It applies the
 * pure [HaviImagePlan] downscale ladder and encodes per [HaviImageFormat]
 * (`HAVI_IMAGE_FORMAT` semantics): PNG lossless / 2 MiB cap, JPEG quality 0.7 / 5 MiB
 * cap. [reencoder] hands [HaviUploader] a [HaviImageReencoder] over the same
 * (already cropped + redacted) bitmap for the server-driven `unsupported_media_type`
 * (→ PNG) and `payload_too_large` (→ 1024 px) fallbacks.
 */
internal object HaviImagePipeline {
    private const val JPEG_QUALITY = 70
    private const val PNG_QUALITY = 100

    /** Walks the ladder and returns the largest encoding within the format cap (or the smallest step if none fit). */
    fun encode(
        bitmap: Bitmap,
        format: HaviImageFormat,
    ): ByteArray? {
        val cap = format.maxUploadBytes
        var last: ByteArray? = null
        for (longestSide in HaviImagePlan.stepDownLadder) {
            val bytes = encodeAt(bitmap, format, longestSide) ?: continue
            last = bytes
            if (bytes.size <= cap) return bytes
        }
        return last
    }

    fun encodeAt(
        bitmap: Bitmap,
        format: HaviImageFormat,
        longestSide: Int,
    ): ByteArray? {
        val target = HaviImagePlan.targetSize(bitmap.width, bitmap.height, longestSide)
        if (target.width <= 0 || target.height <= 0) return null
        val scaled = scale(bitmap, target)
        return try {
            compress(scaled, format)
        } finally {
            if (scaled !== bitmap) scaled.recycle()
        }
    }

    fun reencoder(bitmap: Bitmap): HaviImageReencoder =
        HaviImageReencoder { format, longestSide -> encodeAt(bitmap, format, longestSide) }

    private fun scale(
        src: Bitmap,
        target: HaviSize,
    ): Bitmap =
        if (target.width == src.width && target.height == src.height) {
            src
        } else {
            Bitmap.createScaledBitmap(src, target.width, target.height, true)
        }

    private fun compress(
        bitmap: Bitmap,
        format: HaviImageFormat,
    ): ByteArray? {
        val stream = ByteArrayOutputStream()
        val ok =
            when (format) {
                HaviImageFormat.PNG -> bitmap.compress(Bitmap.CompressFormat.PNG, PNG_QUALITY, stream)
                HaviImageFormat.JPEG -> bitmap.compress(Bitmap.CompressFormat.JPEG, JPEG_QUALITY, stream)
            }
        return if (ok) stream.toByteArray() else null
    }
}
