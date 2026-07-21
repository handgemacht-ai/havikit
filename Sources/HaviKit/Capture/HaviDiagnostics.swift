import Foundation

/// Splits the breadcrumb ring into the three describing buckets the capture sheet
/// surfaces and the envelope emits (bead havi-6953), mirroring the browser
/// extension's console/network split:
///
/// - **console errors** — `level == .error` and `category != "network"`,
/// - **network errors** — `category == "network"` (any level; the host records
///   RPC/HTTP failures here via `Havi.logNetworkError`),
/// - **breadcrumbs** — everything else, which still rides in the `app-logs` body.
///
/// Pure (Foundation only) so the split + formatting run under `swift test`.
enum HaviDiagnostics {
    /// The reserved category that marks a breadcrumb as a network/RPC failure.
    static let networkCategory = "network"

    struct Split: Equatable {
        var consoleErrors: [HaviLogEntry]
        var networkErrors: [HaviLogEntry]
        var breadcrumbs: [HaviLogEntry]
    }

    static func split(_ entries: [HaviLogEntry]) -> Split {
        var console: [HaviLogEntry] = []
        var network: [HaviLogEntry] = []
        var breadcrumbs: [HaviLogEntry] = []
        for entry in entries {
            if entry.category == networkCategory {
                network.append(entry)
            } else if entry.level == .error {
                console.append(entry)
            } else {
                breadcrumbs.append(entry)
            }
        }
        return Split(consoleErrors: console, networkErrors: network, breadcrumbs: breadcrumbs)
    }

    /// `"[level] message"` per line — the browser extension's `console-errors`
    /// value format (`annotation-envelope.js`), mirrored byte-for-byte.
    static func formatConsole(_ entries: [HaviLogEntry]) -> String {
        HaviDeviceInfo.formatLogs(entries)
    }

    /// One preformatted line per entry — the host passes a composed
    /// `"METHOD url status statusText"` string via `Havi.logNetworkError`, matching
    /// the extension's `network-errors` value (no `[level]` prefix).
    static func formatNetwork(_ entries: [HaviLogEntry]) -> String {
        entries.map(\.message).joined(separator: "\n")
    }
}
