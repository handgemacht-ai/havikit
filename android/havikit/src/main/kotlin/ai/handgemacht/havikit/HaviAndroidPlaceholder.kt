package ai.handgemacht.havikit

/**
 * Stage-1 placeholder so the Android library module has a compilable Kotlin
 * source set. The real Android surface — the `Havi` facade, `HaviOverlay`
 * capture host, PixelCopy snapshotter, capture sheet, and the
 * EncryptedSharedPreferences token store — arrives in later stages on top of the
 * wire-contract types in `:havikit-core`.
 */
internal object HaviAndroidPlaceholder {
    const val CORE_MODULE: String = "havikit-core"
}
