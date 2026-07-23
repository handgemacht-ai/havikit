package ai.handgemacht.havikit

/**
 * Formatting for the `device-info` describing body and the breadcrumb log lines
 * (wire spec §6.7). The device field *values* are gathered by the Android capture
 * layer; this pure joiner encodes the omit-empty ` · `-joined format so it is
 * byte-reproducible and unit-tested on the JVM.
 */
public object HaviDeviceInfo {
    private const val SEPARATOR = " · "

    /**
     * ` · `-joined, each component omitted if blank (no dangling separators), e.g.
     * `iPhone15,3 · iOS 17.5.1 · Lesewerkstatt Dev 1.4.0+812 · de_DE · landscapeLeft`.
     */
    public fun describe(components: List<String?>): String? =
        components
            .mapNotNull { it?.takeIf { c -> c.isNotBlank() } }
            .takeIf { it.isNotEmpty() }
            ?.joinToString(SEPARATOR)

    /** `"[level] message"` per line, oldest first — the app-logs / console-errors value. */
    public fun formatLogs(entries: List<HaviLogEntry>): String =
        entries.joinToString("\n") { "[${it.level.wireValue}] ${it.message}" }
}
