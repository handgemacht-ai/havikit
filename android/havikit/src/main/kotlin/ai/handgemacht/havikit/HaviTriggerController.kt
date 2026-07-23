package ai.handgemacht.havikit

import android.app.Activity
import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorManager

/**
 * Owns the capture triggers (Part B4): the app-global shake sensor and the per-window
 * two-finger long-press. The runtime arms/disarms the shake with the app
 * foreground/background transition and attaches/detaches the long-press to the resumed
 * window, so neither keeps running while the app is backgrounded. All trigger
 * callbacks funnel through [onTrigger], which the runtime bounces to the main thread.
 */
internal class HaviTriggerController(
    context: Context?,
    private val longPressEnabled: Boolean,
    onTrigger: () -> Unit,
) {
    private val sensorManager: SensorManager? =
        context?.getSystemService(Context.SENSOR_SERVICE) as? SensorManager
    private val shakeDetector = HaviShakeDetector(onTrigger)
    private val longPressTrigger = HaviLongPressTrigger(onTrigger)
    private var shakeArmed = false

    fun armShake() {
        if (shakeArmed) return
        val manager = sensorManager ?: return
        val sensor = manager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER) ?: return
        manager.registerListener(shakeDetector, sensor, SensorManager.SENSOR_DELAY_UI)
        shakeArmed = true
    }

    fun disarmShake() {
        if (!shakeArmed) return
        sensorManager?.unregisterListener(shakeDetector)
        shakeArmed = false
        shakeDetector.reset()
    }

    fun attachLongPress(activity: Activity) {
        if (!longPressEnabled) return
        longPressTrigger.attach(activity)
    }

    fun detachLongPress() {
        if (!longPressEnabled) return
        longPressTrigger.detach()
    }
}
