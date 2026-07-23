// Only the pure-JVM plugins are declared at the root, so a build that targets
// :havikit-core never has to resolve the Android Gradle Plugin. The Android
// plugins are declared inside :havikit/build.gradle.kts, which is configured only
// when an Android SDK is present (see settings.gradle.kts).
plugins {
    alias(libs.plugins.kotlin.jvm) apply false
    alias(libs.plugins.kotlin.serialization) apply false
}
