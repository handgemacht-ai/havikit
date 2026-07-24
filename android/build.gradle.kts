// Every plugin the build uses is pinned here with `apply false`, so all resolve into
// one shared root build-script classloader and their versions are fixed build-wide.
//
// `kotlin.jvm` and `kotlin.android` are the same `kotlin-gradle-plugin` artifact:
// pinning both here lets :havikit-core apply the jvm variant and :havikit the android
// variant without the "already on the classpath with an unknown version" clash.
//
// The Android Gradle Plugin (`android.library` for :havikit, `android.application`
// for :sample — both the same AGP artifact, pinned at one `agp` version) must be
// pinned here too. Kotlin's android plugin instantiates `KotlinAndroidTarget`, which
// references AGP's `com.android.build.gradle.api.BaseVariant`. With `kotlin.android`
// on the shared root classloader but AGP loaded only into a subproject's child
// classloader, that class is invisible and applying `kotlin.android` fails ("Could
// not create an instance of type KotlinAndroidTarget >
// com/android/build/gradle/api/BaseVariant"). Pinning AGP here hoists it onto the
// same classloader.
//
// `apply false` only resolves/loads these plugins — none is applied at the root, so no
// `android {}` block is configured and no Android SDK is required here. AGP and the
// Compose compiler are applied (and the SDK needed) only inside :havikit, which
// settings.gradle.kts includes solely when an Android SDK is present.
plugins {
    alias(libs.plugins.kotlin.jvm) apply false
    alias(libs.plugins.kotlin.android) apply false
    alias(libs.plugins.kotlin.serialization) apply false
    alias(libs.plugins.android.library) apply false
    alias(libs.plugins.android.application) apply false
    alias(libs.plugins.compose.compiler) apply false
}
