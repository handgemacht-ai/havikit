package ai.handgemacht.havikit

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner

/**
 * The connect / pairing sub-sheet (Part B5), mirroring iOS `HaviConnectSheet`: it
 * drives the device-code flow through [HaviConnectController] and renders the
 * setup / approve / connected / expired / error states, plus the manual token
 * paste fallback. Approval opens in the system browser (a plain `ACTION_VIEW`
 * intent — the protocol doesn't depend on a redirect back); polling keeps running
 * in the background and settles the sheet the moment the developer approves. On
 * appear the flow starts; on resume it reconciles from the store and resumes
 * polling; on dismiss an unfinished flow is cancelled so no approved code is
 * orphaned.
 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalComposeUiApi::class)
@Composable
internal fun HaviConnectSheetUi(
    runtime: HaviRuntime,
    reconnect: Boolean,
    onClose: () -> Unit,
) {
    val scope = rememberCoroutineScope()
    val controller = remember { HaviConnectController(runtime, reconnect, scope) }
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current

    DisposableEffect(lifecycleOwner) {
        controller.onAppear()
        val observer =
            LifecycleEventObserver { _, event ->
                if (event == Lifecycle.Event.ON_RESUME) controller.applicationBecameActive()
            }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose {
            lifecycleOwner.lifecycle.removeObserver(observer)
            if (controller.phase !is HaviConnectController.Phase.Connected) controller.cancel()
        }
    }

    LaunchedEffect(controller.browser.isPresented) {
        if (controller.browser.isPresented) {
            controller.approveUrl?.let { uri ->
                runCatching {
                    context.startActivity(
                        Intent(Intent.ACTION_VIEW, Uri.parse(uri.toString()))
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                    )
                }
            }
            controller.browserClosed()
        }
    }

    fun close() {
        if (controller.phase !is HaviConnectController.Phase.Connected) controller.cancel()
        onClose()
    }

    Surface(
        modifier = Modifier.fillMaxSize().semantics { testTagsAsResourceId = true },
        color = MaterialTheme.colorScheme.surface,
    ) {
        Scaffold(
            topBar = {
                TopAppBar(
                    title = { Text("Connect HAVI") },
                    navigationIcon = {
                        TextButton(onClick = { close() }, modifier = Modifier.testTag("havi-connect-close")) { Text("Close") }
                    },
                )
            },
        ) { padding ->
            Column(
                modifier =
                    Modifier
                        .fillMaxSize()
                        .padding(padding)
                        .verticalScroll(rememberScrollState())
                        .padding(20.dp),
                verticalArrangement = Arrangement.spacedBy(20.dp),
            ) {
                when (val phase = controller.phase) {
                    is HaviConnectController.Phase.Connected -> ConnectedState(phase.session, controller, onDone = onClose)
                    HaviConnectController.Phase.Creating -> CreatingState()
                    is HaviConnectController.Phase.Awaiting -> {
                        AwaitingState(controller)
                        PasteFallback(controller)
                    }
                    HaviConnectController.Phase.Expired -> {
                        RetryState("The setup link expired.", controller)
                        PasteFallback(controller)
                    }
                    is HaviConnectController.Phase.Error -> {
                        RetryState(phase.message, controller)
                        PasteFallback(controller)
                    }
                }
            }
        }
    }
}

@Composable
private fun CreatingState() {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
        CircularProgressIndicator(strokeWidth = 2.dp, modifier = Modifier.size(22.dp), color = HaviBrand.Accent)
        Text("Setting up a secure link…", style = MaterialTheme.typography.bodyMedium)
    }
}

@Composable
private fun AwaitingState(controller: HaviConnectController) {
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text("Approve this device", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
        Text(
            "Open the approval page and confirm it's you. This sheet finishes automatically once you approve.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Button(
            onClick = { controller.openApproval() },
            colors = ButtonDefaults.buttonColors(containerColor = HaviBrand.Accent),
            modifier = Modifier.fillMaxWidth().height(50.dp).testTag("havi-connect-open-approval"),
        ) {
            Text("Open approval page", fontWeight = FontWeight.SemiBold)
        }
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            CircularProgressIndicator(strokeWidth = 2.dp, modifier = Modifier.size(16.dp), color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text("Waiting for approval…", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun RetryState(
    message: String,
    controller: HaviConnectController,
) {
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(message, style = MaterialTheme.typography.bodyMedium)
        Button(
            onClick = { controller.start() },
            colors = ButtonDefaults.buttonColors(containerColor = HaviBrand.Accent),
            modifier = Modifier.fillMaxWidth().height(50.dp).testTag("havi-connect-retry"),
        ) {
            Text("Try again", fontWeight = FontWeight.SemiBold)
        }
    }
}

@Composable
private fun ConnectedState(
    session: HaviConnectedSession,
    controller: HaviConnectController,
    onDone: () -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Surface(
            shape = RoundedCornerShape(14.dp),
            color = HaviBrand.Success.copy(alpha = 0.08f),
            modifier = Modifier.fillMaxWidth(),
        ) {
            Row(
                modifier = Modifier.padding(16.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Box(Modifier.size(10.dp).clip(CircleShape).background(HaviBrand.Success))
                Column(Modifier.weight(1f)) {
                    Text("Connected to HAVI", fontWeight = FontWeight.SemiBold)
                    val workspace = session.workspaceName ?: session.workspaceId
                    val line = session.userName?.takeIf { it.isNotEmpty() }?.let { "$it · $workspace" } ?: workspace
                    Text(line, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
        Button(
            onClick = onDone,
            colors = ButtonDefaults.buttonColors(containerColor = HaviBrand.Accent),
            modifier = Modifier.fillMaxWidth().height(50.dp).testTag("havi-connect-done"),
        ) {
            Text("Done", fontWeight = FontWeight.SemiBold)
        }
        OutlinedButton(
            onClick = { controller.disconnect() },
            modifier = Modifier.fillMaxWidth().testTag("havi-connect-disconnect"),
        ) {
            Text("Disconnect")
        }
    }
}

@Composable
private fun PasteFallback(controller: HaviConnectController) {
    var expanded by remember { androidx.compose.runtime.mutableStateOf(false) }
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Spacer(Modifier.height(4.dp))
        TextButton(onClick = { expanded = !expanded }, modifier = Modifier.testTag("havi-connect-paste-toggle")) {
            Text(if (expanded) "Hide manual token" else "Paste a token instead")
        }
        if (expanded) {
            OutlinedTextField(
                value = controller.pasteToken,
                onValueChange = { controller.pasteToken = it },
                label = { Text("Access token") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth().testTag("havi-connect-paste-token"),
            )
            OutlinedTextField(
                value = controller.pasteWorkspaceId,
                onValueChange = { controller.pasteWorkspaceId = it },
                label = { Text("Workspace ID") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth().testTag("havi-connect-paste-workspace"),
            )
            Button(
                onClick = { controller.usePastedToken() },
                enabled = controller.pasteToken.isNotBlank() && controller.pasteWorkspaceId.isNotBlank(),
                colors = ButtonDefaults.buttonColors(containerColor = HaviBrand.Accent),
                modifier = Modifier.fillMaxWidth().testTag("havi-connect-use-token"),
            ) {
                Text("Use token", fontWeight = FontWeight.SemiBold)
            }
        }
    }
}
