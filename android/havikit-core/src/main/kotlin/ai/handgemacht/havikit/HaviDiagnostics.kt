package ai.handgemacht.havikit

/**
 * Splits the breadcrumb ring into the three describing buckets the capture sheet
 * surfaces and the envelope emits (wire spec §6.2, §A6), mirroring the browser
 * extension's console/network split:
 *  - console errors — `level == ERROR` and `category != "network"`,
 *  - network errors — `category == "network"` (any level; the host records
 *    RPC/HTTP failures here via `Havi.logNetworkError`),
 *  - breadcrumbs — everything else, which rides in the `app-logs` body.
 */
public object HaviDiagnostics {
    /** The reserved category that marks a breadcrumb as a network/RPC failure. */
    public const val NETWORK_CATEGORY: String = "network"

    public data class Split(
        val consoleErrors: List<HaviLogEntry>,
        val networkErrors: List<HaviLogEntry>,
        val breadcrumbs: List<HaviLogEntry>,
    )

    public fun split(entries: List<HaviLogEntry>): Split {
        val console = mutableListOf<HaviLogEntry>()
        val network = mutableListOf<HaviLogEntry>()
        val breadcrumbs = mutableListOf<HaviLogEntry>()
        for (entry in entries) {
            when {
                entry.category == NETWORK_CATEGORY -> network += entry
                entry.level == HaviLogLevel.ERROR -> console += entry
                else -> breadcrumbs += entry
            }
        }
        return Split(consoleErrors = console, networkErrors = network, breadcrumbs = breadcrumbs)
    }

    /** `"[level] message"` per line — the `console-errors` / `app-logs` value format. */
    public fun formatConsole(entries: List<HaviLogEntry>): String = HaviDeviceInfo.formatLogs(entries)

    /** One preformatted line per entry (no `[level]` prefix) — the `network-errors` value. */
    public fun formatNetwork(entries: List<HaviLogEntry>): String = entries.joinToString("\n") { it.message }
}
