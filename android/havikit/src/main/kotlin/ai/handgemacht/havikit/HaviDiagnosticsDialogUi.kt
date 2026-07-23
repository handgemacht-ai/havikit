package ai.handgemacht.havikit

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp

/**
 * The captured-diagnostics preview (Part B4/§6.2): the console-error and
 * network-error buckets the freeze snapshotted, each with an include toggle that
 * feeds the submit body (`console-errors` / `network-errors`). Read-only preview —
 * the entries themselves are fixed at freeze time. Toggling maps directly to the
 * capture model's `includeConsoleErrors` / `includeNetworkErrors`.
 */
@Composable
internal fun HaviDiagnosticsDialog(
    model: HaviCaptureViewModel,
    onDismiss: () -> Unit,
) {
    val split = model.diagnosticsSplit
    AlertDialog(
        onDismissRequest = onDismiss,
        confirmButton = {
            TextButton(onClick = onDismiss, modifier = Modifier.testTag("havi-diagnostics-done")) { Text("Done") }
        },
        title = { Text("Diagnostics") },
        text = {
            Column(
                modifier = Modifier.fillMaxWidth().verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                ToggleRow(
                    title = "Console errors",
                    count = model.consoleErrorCount,
                    checked = model.includeConsoleErrors,
                    tag = "havi-diagnostics-console-toggle",
                    onCheckedChange = { model.includeConsoleErrors = it },
                )
                Preview(split.consoleErrors.map { "[${it.level.wireValue}] ${it.message}" })

                ToggleRow(
                    title = "Network errors",
                    count = model.networkErrorCount,
                    checked = model.includeNetworkErrors,
                    tag = "havi-diagnostics-network-toggle",
                    onCheckedChange = { model.includeNetworkErrors = it },
                )
                Preview(split.networkErrors.map { it.message })
            }
        },
    )
}

@Composable
private fun ToggleRow(
    title: String,
    count: Int,
    checked: Boolean,
    tag: String,
    onCheckedChange: (Boolean) -> Unit,
) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Column(Modifier.weight(1f)) {
            Text(title, fontWeight = FontWeight.SemiBold, style = MaterialTheme.typography.bodyMedium)
            Text("$count captured", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Switch(
            checked = checked,
            onCheckedChange = onCheckedChange,
            modifier = Modifier.testTag(tag),
            colors = SwitchDefaults.colors(checkedTrackColor = HaviBrand.Accent),
        )
    }
}

@Composable
private fun Preview(lines: List<String>) {
    if (lines.isEmpty()) return
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        for (line in lines.take(4)) {
            Text(
                text = line,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 2,
            )
        }
        if (lines.size > 4) {
            Text(
                "+${lines.size - 4} more",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}
