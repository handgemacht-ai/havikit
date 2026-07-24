// Android library module — the native Kotlin/Compose HaviKit SDK surface. It hosts
// the platform layer (Havi facade, PixelCopy snapshotter + redaction, capture
// triggers, activity tracking, Compose integration, the capture/markup/connect UI,
// and the submit flow) on top of the wire-contract types in the pure-JVM
// :havikit-core it depends on. This module applies the Android Gradle Plugin, so it
// is configured only when an Android SDK is available (see settings.gradle.kts) —
// locally only :havikit-core builds/tests; CI (Android SDK present) compiles the AAR.
plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.compose.compiler)
    `maven-publish`
}

group = providers.gradleProperty("havikit.group").get()
version = providers.gradleProperty("havikit.version").get()

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

    testOptions {
        unitTests {
            isReturnDefaultValues = true
            all { it.useJUnitPlatform() }
        }
    }

    publishing {
        singleVariant("release") {
            withSourcesJar()
        }
    }
}

dependencies {
    api(project(":havikit-core"))

    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.security.crypto)
    implementation(libs.kotlinx.coroutines.android)
    implementation(platform(libs.compose.bom))
    implementation(libs.compose.ui)
    implementation(libs.compose.foundation)
    implementation(libs.compose.material3)

    testImplementation(libs.junit.jupiter)
    testRuntimeOnly(libs.junit.platform.launcher)
}

// The Android `release` software component is created late by AGP (after the
// `android {}` block is evaluated), so the publication is wired in `afterEvaluate`
// per the Android Gradle Plugin's documented pattern.
afterEvaluate {
    publishing {
        publications {
            create<MavenPublication>("release") {
                from(components["release"])
                artifactId = "havikit"
                pom {
                    name.set("HaviKit")
                    description.set("On-device HAVI mobile feedback SDK for Android.")
                    url.set("https://github.com/handgemacht-ai/havikit")
                }
            }
        }
        repositories {
            maven {
                name = "GitHubPackages"
                url = uri("https://maven.pkg.github.com/handgemacht-ai/havikit")
                credentials {
                    username = providers.gradleProperty("gpr.user").orNull ?: System.getenv("GITHUB_ACTOR")
                    password = providers.gradleProperty("gpr.token").orNull ?: System.getenv("GITHUB_TOKEN")
                }
            }
        }
    }
}
