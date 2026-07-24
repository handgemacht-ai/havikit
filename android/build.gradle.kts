// The Kotlin Gradle plugins are declared (with `apply false`) at the root so their
// version is known build-wide. `kotlin.jvm` and `kotlin.android` are the same
// `kotlin-gradle-plugin` artifact: once `kotlin.jvm` puts it on the shared classpath,
// a subproject requesting `kotlin.android` *with* a version can no longer be checked
// for compatibility ("already on the classpath with an unknown version") and fails.
// Declaring `kotlin.android` here too pins that id to the same version so :havikit can
// apply it. This resolves only the Kotlin plugin — not the Android Gradle Plugin — so
// a build that targets :havikit-core still never resolves AGP. AGP (`android.library`)
// and the Compose compiler plugin stay in :havikit/build.gradle.kts, which is
// configured only when an Android SDK is present (see settings.gradle.kts).
plugins {
    alias(libs.plugins.kotlin.jvm) apply false
    alias(libs.plugins.kotlin.android) apply false
    alias(libs.plugins.kotlin.serialization) apply false
}
