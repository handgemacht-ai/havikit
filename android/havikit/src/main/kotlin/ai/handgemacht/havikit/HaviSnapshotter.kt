package ai.handgemacht.havikit

import android.app.Activity
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Rect
import android.os.Handler
import android.os.Looper
import android.view.PixelCopy
import android.view.View

/**
 * Freezes the current window into a mutable [Bitmap] (Part B4). Primary path is
 * [PixelCopy], which reads the composited surface — the only way to capture
 * hardware-accelerated content and `SurfaceView`/`TextureView`/video that a
 * `View#draw` walk would render blank. If PixelCopy is unavailable or reports a
 * non-success result (e.g. the window has no backing surface yet) it falls back to
 * `decorView.draw(Canvas)`, which cannot reproduce surface-backed content but is
 * better than no capture.
 *
 * The result is delivered on the main thread: PixelCopy's listener runs on the main
 * looper handler, and the synchronous fallback is only reached from a caller that is
 * already on the main thread (the capture controller). `View#draw` must run on the UI
 * thread, so both delivery paths satisfy that.
 */
internal class HaviSnapshotter {
    private val mainHandler = Handler(Looper.getMainLooper())

    fun capture(
        activity: Activity,
        onResult: (Bitmap?) -> Unit,
    ) {
        val window = activity.window
        val decor: View? = window.peekDecorView()
        if (decor == null || decor.width <= 0 || decor.height <= 0) {
            onResult(null)
            return
        }

        val width = decor.width
        val height = decor.height
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)

        try {
            val location = IntArray(2)
            decor.getLocationInWindow(location)
            val src = Rect(location[0], location[1], location[0] + width, location[1] + height)
            PixelCopy.request(
                window,
                src,
                bitmap,
                { result ->
                    if (result == PixelCopy.SUCCESS) {
                        onResult(bitmap)
                    } else {
                        bitmap.recycle()
                        onResult(drawFallback(decor, width, height))
                    }
                },
                mainHandler,
            )
        } catch (_: Throwable) {
            bitmap.recycle()
            onResult(drawFallback(decor, width, height))
        }
    }

    private fun drawFallback(
        view: View,
        width: Int,
        height: Int,
    ): Bitmap? =
        try {
            val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            view.draw(Canvas(bitmap))
            bitmap
        } catch (_: Throwable) {
            null
        }
}
