pluginManagement {
    repositories {
        google {
            content {
                includeGroupByRegex("com\\.android.*")
                includeGroupByRegex("com\\.google.*")
                includeGroupByRegex("androidx.*")
            }
        }
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.PREFER_SETTINGS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "havikit-android"

// The pure-JVM wire-contract core is always part of the build; it needs no Android SDK.
include(":havikit-core")

// The Android library module (:havikit) applies the Android Gradle Plugin, which
// requires an Android SDK to configure. This host has none (Stage 1), so the module
// is only wired into the build when an SDK is present — locally `./gradlew
// :havikit-core:test` runs without it, and GitHub Actions (Android SDK preinstalled,
// ANDROID_HOME set) includes it to compile the AAR. The module's sources and build
// script are committed either way.
val androidSdkAvailable =
    System.getenv("ANDROID_HOME") != null ||
        System.getenv("ANDROID_SDK_ROOT") != null ||
        file("local.properties").let { it.exists() && it.readText().contains("sdk.dir") }

if (androidSdkAvailable) {
    include(":havikit")
} else {
    logger.lifecycle(
        "HaviKit: no Android SDK detected (ANDROID_HOME unset, no sdk.dir in local.properties) — " +
            "excluding :havikit from this build. The pure-JVM :havikit-core still builds and tests.",
    )
}
