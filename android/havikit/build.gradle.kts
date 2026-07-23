// Android library module — the native Kotlin/Compose HaviKit SDK surface. It hosts
// the platform layer (Havi facade, PixelCopy snapshotter + redaction, capture
// triggers, activity tracking, Compose integration) on top of the wire-contract
// types in the pure-JVM :havikit-core it depends on; the capture sheet and connect
// UI arrive in later stages. This module applies the Android Gradle Plugin, so it is
// configured only when an Android SDK is available (see settings.gradle.kts) — locally
// only :havikit-core builds/tests; CI (Android SDK present) compiles the AAR.
plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.compose.compiler)
}

android {
    namespace = "ai.handgemacht.havikit"
    compileSdk = 35

    defaultConfig {
        minSdk = 26
        consumerProguardFiles("consumer-rules.pro")
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
    }
}

dependencies {
    api(project(":havikit-core"))

    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.activity.compose)
    implementation(platform(libs.compose.bom))
    implementation(libs.compose.ui)
    implementation(libs.compose.foundation)
    implementation(libs.compose.material3)
}
