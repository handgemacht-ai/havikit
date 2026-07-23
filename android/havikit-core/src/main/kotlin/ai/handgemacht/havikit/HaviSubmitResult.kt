package ai.handgemacht.havikit

/**
 * How the capture sheet should present a failed submit (wire spec §7). Auth /
 * workspace failures show an actionable *Reconnect HAVI*; transient failures a
 * *Retry*; terminal failures dismiss with the reason and no retry.
 */
public enum class HaviSubmitFailureKind {
    RETRY,
    RECONNECT,
    TERMINAL,
}

public data class HaviSubmitFailure(
    val userMessage: String,
    val kind: HaviSubmitFailureKind,
    val code: String?,
)

/**
 * Result of a best-effort foreground submit. There is no on-disk outbox — the
 * sheet stays open on [Failure], drawing + comment intact (wire spec §5.2, §7).
 */
public sealed interface HaviSubmitResult {
    public data class Success(val id: String?) : HaviSubmitResult

    public data class Failure(val failure: HaviSubmitFailure) : HaviSubmitResult
}
