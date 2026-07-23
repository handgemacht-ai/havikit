package ai.handgemacht.havikit

import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import java.util.Locale

/**
 * Gathers the live `device-info` field values on Android and hands them to the
 * pure `HaviDeviceInfo` joiner (wire spec §6.7), which owns the omit-empty
 * ` · `-joined format so the string stays byte-reproducible. Configured once at
 * [Havi.start] so a submit never has to touch the `PackageManager` on the hot path:
 * `<model> · Android <release> · <appName> <version>+<build> · <locale> · <orientation>`.
 */
internal object HaviAndroidDeviceInfo {
    @Volatile
    private var appName: String? = null

    @Volatile
    private var version: String? = null

    @Volatile
    private var build: String? = null

    fun configure(context: Context) {
        val ctx = context.applicationContext
        val pm = ctx.packageManager
        appName =
            runCatching {
                ctx.applicationInfo.loadLabel(pm).toString().takeIf { it.isNotBlank() }
            }.getOrNull()
        runCatching {
            @Suppress("DEPRECATION")
            val info = pm.getPackageInfo(ctx.packageName, 0)
            version = info.versionName?.takeIf { it.isNotBlank() }
            build =
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    info.longVersionCode.toString()
                } else {
                    @Suppress("DEPRECATION")
                    info.versionCode.toString()
                }
        }
    }

    fun describe(orientation: HaviCaptureOrientation): String? =
        HaviDeviceInfo.describe(
            listOf(
                model(),
                "Android ${Build.VERSION.RELEASE}",
                appVersionComponent(),
                Locale.getDefault().toString().takeIf { it.isNotBlank() },
                orientationName(orientation),
            ),
        )

    private fun model(): String {
        val manufacturer = Build.MANUFACTURER?.takeIf { it.isNotBlank() }
        val model = Build.MODEL?.takeIf { it.isNotBlank() }
        return listOfNotNull(manufacturer, model).joinToString(" ").ifBlank { "Android" }
    }

    private fun appVersionComponent(): String? {
        val name = appName ?: return null
        val ver = version
        val buildNo = build
        val versionPart =
            when {
                ver != null && buildNo != null -> "$ver+$buildNo"
                ver != null -> ver
                else -> null
            }
        return if (versionPart != null) "$name $versionPart" else name
    }

    private fun orientationName(orientation: HaviCaptureOrientation): String =
        when (orientation) {
            HaviCaptureOrientation.PORTRAIT -> "portrait"
            HaviCaptureOrientation.LANDSCAPE -> "landscape"
        }
}
