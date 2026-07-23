package ai.handgemacht.havikit

import android.app.Activity
import android.os.Handler
import android.os.Looper
import android.view.KeyboardShortcutGroup
import android.view.Menu
import android.view.MotionEvent
import android.view.Window
import kotlin.math.abs

/**
 * Two-finger long-press trigger (Part B4) — the emulator fallback for devices without
 * a usable shake sensor. It observes touches by wrapping the window's [Window.Callback]
 * with a delegating decorator ([TouchObservingCallback]) that forwards every event to
 * the original callback, so no touch is consumed and the app behaves normally. When two
 * pointers are held roughly still for [LONG_PRESS_MS], it fires once.
 *
 * Kotlin interface delegation (`by base`) forwards the full `Window.Callback` surface
 * to the original callback, so only [Window.Callback.dispatchTouchEvent] is
 * intercepted and future callback additions keep delegating.
 */
internal class HaviLongPressTrigger(
    private val onTrigger: () -> Unit,
) {
    private val handler = Handler(Looper.getMainLooper())

    private var window: Window? = null
    private var installed: Window.Callback? = null
    private var previous: Window.Callback? = null

    private var tracking = false
    private var fired = false
    private var anchorX = 0f
    private var anchorY = 0f

    private val pending =
        Runnable {
            if (tracking && !fired) {
                fired = true
                onTrigger()
            }
        }

    fun attach(activity: Activity) {
        detach()
        val w = activity.window
        val base = w.callback ?: return
        val wrapper = TouchObservingCallback(base) { observe(it) }
        w.callback = wrapper
        window = w
        installed = wrapper
        previous = base
    }

    fun detach() {
        cancel()
        val w = window
        val inst = installed
        val prev = previous
        if (w != null && inst != null && prev != null && w.callback === inst) {
            w.callback = prev
        }
        window = null
        installed = null
        previous = null
    }

    private fun observe(event: MotionEvent) {
        when (event.actionMasked) {
            MotionEvent.ACTION_POINTER_DOWN ->
                if (event.pointerCount == REQUIRED_POINTERS) start(event) else cancel()

            MotionEvent.ACTION_MOVE ->
                if (tracking && movedBeyondSlop(event)) cancel()

            MotionEvent.ACTION_POINTER_UP,
            MotionEvent.ACTION_UP,
            MotionEvent.ACTION_CANCEL,
            -> cancel()
        }
    }

    private fun start(event: MotionEvent) {
        cancel()
        tracking = true
        fired = false
        anchorX = centroidX(event)
        anchorY = centroidY(event)
        handler.postDelayed(pending, LONG_PRESS_MS)
    }

    private fun cancel() {
        tracking = false
        handler.removeCallbacks(pending)
    }

    private fun movedBeyondSlop(event: MotionEvent): Boolean {
        if (event.pointerCount < REQUIRED_POINTERS) return true
        val dx = abs(centroidX(event) - anchorX)
        val dy = abs(centroidY(event) - anchorY)
        return dx > MOVE_SLOP_PX || dy > MOVE_SLOP_PX
    }

    private fun centroidX(event: MotionEvent): Float = (event.getX(0) + event.getX(1)) / 2f

    private fun centroidY(event: MotionEvent): Float = (event.getY(0) + event.getY(1)) / 2f

    private class TouchObservingCallback(
        private val base: Window.Callback,
        private val onTouch: (MotionEvent) -> Unit,
    ) : Window.Callback by base {
        override fun dispatchTouchEvent(event: MotionEvent): Boolean {
            onTouch(event)
            return base.dispatchTouchEvent(event)
        }

        // Kotlin interface delegation (`by base`) does not forward the interface's Java
        // default methods, so these are forwarded explicitly to keep the wrapped callback
        // whole (both APIs are <= minSdk 26).
        override fun onProvideKeyboardShortcuts(
            data: MutableList<KeyboardShortcutGroup>?,
            menu: Menu?,
            deviceId: Int,
        ) {
            base.onProvideKeyboardShortcuts(data, menu, deviceId)
        }

        override fun onPointerCaptureChanged(hasCapture: Boolean) {
            base.onPointerCaptureChanged(hasCapture)
        }
    }

    private companion object {
        const val REQUIRED_POINTERS = 2
        const val LONG_PRESS_MS = 600L
        const val MOVE_SLOP_PX = 40f
    }
}
