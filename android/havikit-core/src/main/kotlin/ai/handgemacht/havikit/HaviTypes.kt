package ai.handgemacht.havikit

/** Log severity; the wire value is the lowercase enum name (parity with iOS `HaviLogLevel`). */
public enum class HaviLogLevel(public val wireValue: String) {
    DEBUG("debug"),
    INFO("info"),
    WARNING("warning"),
    ERROR("error"),
}

/** Built-in triage priority; a workspace may override the vocabulary with custom values. */
public enum class HaviPriority(public val wireValue: String) {
    HIGH("high"),
    MEDIUM("medium"),
    LOW("low"),
}

/** Screenshot upload format. Unknown/empty config resolves to [PNG]. */
public enum class HaviImageFormat(public val wireValue: String) {
    PNG("png"),
    JPEG("jpeg"),
    ;

    public companion object {
        /** Case-insensitive parse; anything unrecognized (or null/blank) falls back to [PNG]. */
        public fun fromRawOrPng(raw: String?): HaviImageFormat =
            when (raw?.trim()?.lowercase()) {
                "jpeg" -> JPEG
                else -> PNG
            }
    }
}

/** Resolved authentication state, mirroring iOS `HaviAuthState`. */
public sealed interface HaviAuthState {
    public data object Unconfigured : HaviAuthState

    public data class Authenticated(val workspaceId: String) : HaviAuthState

    public data object NeedsReconnect : HaviAuthState
}

/** Reserved device-flow descriptor (v1.1); currently unused. */
public data class HaviDeviceFlow(
    val userCode: String,
    val verificationUri: String,
    val interval: Int,
)

/** One breadcrumb entry in the fixed-capacity log ring. */
public data class HaviLogEntry(
    val level: HaviLogLevel,
    val category: String,
    val message: String,
)

/** SDK errors, mirroring iOS `HaviError`. */
public sealed class HaviException(message: String) : Exception(message) {
    public data object NotImplemented : HaviException("not implemented") {
        private fun readResolve(): Any = NotImplemented
    }

    public data object NotEnabled : HaviException("not enabled") {
        private fun readResolve(): Any = NotEnabled
    }

    public data object Encoding : HaviException("encoding failed") {
        private fun readResolve(): Any = Encoding
    }
}
