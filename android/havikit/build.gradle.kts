// Android library module — the native Kotlin/Compose HaviKit SDK surface lands
// here in later stages (overlay host, PixelCopy snapshotter, capture sheet,
// EncryptedSharedPreferences token store). Stage 1 keeps it a near-empty
// placeholder that only wires the build: everything wire-contract lives in the
// pure-JVM :havikit-core it depends on. This module is configured only when an
// Android SDK is available (see settings.gradle.kts).
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
