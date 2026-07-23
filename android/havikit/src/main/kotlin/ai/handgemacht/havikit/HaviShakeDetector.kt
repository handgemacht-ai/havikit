package ai.handgemacht.havikit

import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.SystemClock
import kotlin.math.sqrt

/**
 * Accelerometer shake trigger (Part B4), the Android analog of iOS `motionShake`.
 * Fires when the total g-force crosses [SHAKE_THRESHOLD_G], debounced by
 * [MIN_INTERVAL_MS] so one physical shake is one capture. [onShake] runs on the
 * sensor delivery thread; the caller hops to the main thread before capturing.
 */
internal class HaviShakeDetector(
    private val onShake: () -> Unit,
) : SensorEventListener {
    private var lastShakeAt = 0L

    override fun onSensorChanged(event: SensorEvent) {
        if (event.sensor.type != Sensor.TYPE_ACCELEROMETER) return
        val values = event.values
        if (values.size < 3) return

        val gx = values[0] / SensorManager.GRAVITY_EARTH
        val gy = values[1] / SensorManager.GRAVITY_EARTH
        val gz = values[2] / SensorManager.GRAVITY_EARTH
        val gForce = sqrt(gx * gx + gy * gy + gz * gz)

        if (gForce > SHAKE_THRESHOLD_G) {
            val now = SystemClock.elapsedRealtime()
            if (now - lastShakeAt < MIN_INTERVAL_MS) return
            lastShakeAt = now
            onShake()
        }
    }

    override fun onAccuracyChanged(
        sensor: Sensor?,
        accuracy: Int,
    ) = Unit

    fun reset() {
        lastShakeAt = 0L
    }

    private companion object {
        const val SHAKE_THRESHOLD_G = 2.7f
        const val MIN_INTERVAL_MS = 1_000L
    }
}
