package ai.handgemacht.havikit.sample

import ai.handgemacht.havikit.Havi
import android.app.Application

class SampleApp : Application() {
    override fun onCreate() {
        super.onCreate()
        if (BuildConfig.DEBUG) {
            Havi.start(this)
        }
    }
}
