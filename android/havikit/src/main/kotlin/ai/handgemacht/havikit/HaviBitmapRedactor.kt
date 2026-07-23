package ai.handgemacht.havikit

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint

/**
 * Burns opaque black rectangles into the frozen bitmap before any bytes exist (Part
 * B4 / wire spec §5 privacy posture), so redacted regions never reach the encoder,
 * the multipart image part, or the envelope. Mutates the bitmap in place; the caller
 * passes a mutable bitmap (PixelCopy dest / a fresh fallback bitmap are both mutable).
 */
internal object HaviBitmapRedactor {
    fun apply(
        bitmap: Bitmap,
        rects: List<HaviWindowRect>,
    ) {
        if (rects.isEmpty()) return
        val canvas = Canvas(bitmap)
        val paint =
            Paint().apply {
                color = Color.BLACK
                style = Paint.Style.FILL
                isAntiAlias = false
            }
        for (rect in rects) {
            if (rect.isDegenerate()) continue
            canvas.drawRect(
                rect.left.toFloat(),
                rect.top.toFloat(),
                rect.right.toFloat(),
                rect.bottom.toFloat(),
                paint,
            )
        }
    }
}
