// Sample application module — a minimal Compose app that exercises the HaviKit
// Android SDK end to end: it starts the SDK at launch, names each screen on
// navigation, arms the shake trigger (via start), offers a manual capture button
// for emulators, and reaches the connect/pairing flow through the capture sheet.
//
// It applies the Android *application* Gradle Plugin, so — like :havikit — it is
// wired into the build only when an Android SDK is present (see settings.gradle.kts).
// On a host without an SDK it is excluded and CI compiles it via :sample:assembleDebug.
plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.compose.compiler)
}

// Overridable via `-PhaviBaseUrl=…`; stamped into the HAVI_BASE_URL <meta-data>
// placeholder that HaviConfig.fromManifest reads at start.
val haviBaseUrl = (project.findProperty("haviBaseUrl") as String?) ?: "https://havi.handgemacht.ai"

android {
    namespace = "ai.handgemacht.havikit.sample"
    compileSdk = 35

    defaultConfig {
        applicationId = "ai.handgemacht.havikit.sample"
        minSdk = 26
        targetSdk = 35
        versionCode = 1
        versionName = "0.2.0"
        manifestPlaceholders["haviBaseUrl"] = haviBaseUrl
    }

    buildTypes {
        release {
            isMinifyEnabled = false
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }
}

dependencies {
    implementation(project(":havikit"))

    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(platform(libs.compose.bom))
    implementation(libs.compose.ui)
    implementation(libs.compose.foundation)
    implementation(libs.compose.material3)
}
