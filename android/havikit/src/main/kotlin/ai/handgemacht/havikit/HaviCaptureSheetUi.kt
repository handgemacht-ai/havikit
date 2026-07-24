package ai.handgemacht.havikit

import androidx.activity.compose.BackHandler
import androidx.activity.compose.LocalOnBackPressedDispatcherOwner
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
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
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp

/**
 * What system Back does while the capture sheet is up. Without an interceptor Back
 * falls straight through to the host app, which navigates or finishes underneath a
 * sheet that is still on screen.
 */
internal enum class HaviBackAction {
    /** A submit is in flight: the sheet locks every affordance, and Back is one of them. */
    IGNORE,

    /** The connect sheet is layered over the capture flow and takes the gesture first. */
    CLOSE_CONNECT,

    /** Back is the Close affordance. */
    DISMISS,

    ;

    internal companion object {
        fun resolve(
            isSubmitting: Boolean,
            connectOpen: Boolean,
        ): HaviBackAction =
            when {
                isSubmitting -> IGNORE
                connectOpen -> CLOSE_CONNECT
                else -> DISMISS
            }
    }
}

/**
 * The capture flow (Part B4), mirroring the iOS two-screen `HaviCaptureSheet`:
 * Screen 1 is the frozen screenshot's markup canvas (seven tools, six colors,
 * undo+redo, confirmed crop); Screen 2 is diagnostics, connect state, comment,
 * priority, workspace labels, and submit. Back preserves everything — both screens
 * read/write one shared [HaviCaptureViewModel]. On submit failure the sheet stays
 * open on Screen 2 with the `error.code`-mapped reason; on success the host
 * dismisses it and raises the "Report sent" confirmation.
 *
 * The model is passed in rather than remembered: [HaviCaptureHost] owns it for the
 * whole capture session so a recreated Activity re-enters the flow exactly where it
 * left off. Back is intercepted per [HaviBackAction], but only when the host Activity
 * actually provides a back dispatcher — HaviKit drops into apps whose Activities are
 * not `ComponentActivity`, and a missing dispatcher owner must not be a crash.
 */
@OptIn(ExperimentalComposeUiApi::class)
@Composable
internal fun HaviCaptureFlow(
    model: HaviCaptureViewModel,
    runtime: HaviRuntime,
    onClose: () -> Unit,
) {
    MaterialTheme {
        Surface(
            modifier = Modifier.fillMaxSize().semantics { testTagsAsResourceId = true },
            color = MaterialTheme.colorScheme.surface,
        ) {
            val frame = model.frame
            val image = remember(frame) { frame.bitmap.asImageBitmap() }

            var showConnect by remember { mutableStateOf(false) }
            var connectReconnect by remember { mutableStateOf(false) }
            var showDiagnostics by remember { mutableStateOf(false) }

            if (LocalOnBackPressedDispatcherOwner.current != null) {
                BackHandler {
                    when (HaviBackAction.resolve(model.isSubmitting, showConnect)) {
                        HaviBackAction.IGNORE -> Unit
                        HaviBackAction.CLOSE_CONNECT -> showConnect = false
                        HaviBackAction.DISMISS -> onClose()
                    }
                }
            }

            if (!model.showDetails) {
                HaviCaptureImageScreen(
                    model = model,
                    image = image,
                    imagePixelSize = frame.imagePixelSize,
                    onClose = onClose,
                    onNext = { model.showDetails = true },
                )
            } else {
                HaviCaptureDetailsScreen(
                    model = model,
                    runtime = runtime,
                    onBack = { model.showDetails = false },
                    onClose = onClose,
                    openConnect = { reconnect ->
                        connectReconnect = reconnect
                        showConnect = true
                    },
                    openDiagnostics = { showDiagnostics = true },
                )
            }

            if (showConnect) {
                HaviConnectSheetUi(runtime = runtime, reconnect = connectReconnect, onClose = { showConnect = false })
            }
            if (showDiagnostics) {
                HaviDiagnosticsDialog(model = model, onDismiss = { showDiagnostics = false })
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun HaviCaptureImageScreen(
    model: HaviCaptureViewModel,
    image: androidx.compose.ui.graphics.ImageBitmap,
    imagePixelSize: HaviSize,
    onClose: () -> Unit,
    onNext: () -> Unit,
) {
    val isCropping = model.markup.tool == HaviMarkTool.CROP
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Report to HAVI") },
                navigationIcon = {
                    TextButton(onClick = onClose, enabled = !model.isSubmitting) { Text("Close") }
                },
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier.fillMaxSize().padding(padding).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Surface(
                tonalElevation = 2.dp,
                shape = RoundedCornerShape(16.dp),
                modifier = Modifier.fillMaxWidth(),
            ) {
                HaviMarkupToolbar(model.markup)
            }

            Box(
                modifier =
                    Modifier
                        .fillMaxWidth()
                        .weight(1f)
                        .clip(RoundedCornerShape(14.dp))
                        .background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.3f)),
            ) {
                HaviMarkupCanvasUi(
                    image = image,
                    imagePixelSize = imagePixelSize,
                    markup = model.markup,
                    crop = model.crop,
                )
            }

            if (!isCropping) {
                HaviColorSwatchRow(model.markup)
                HintRow(model)
            } else {
                CropControls(model)
            }

            Button(
                onClick = onNext,
                enabled = model.canProceed,
                modifier = Modifier.fillMaxWidth().height(52.dp).testTag("havi-next-button"),
                colors = ButtonDefaults.buttonColors(containerColor = HaviBrand.Accent),
            ) {
                Text("Next", fontWeight = FontWeight.SemiBold)
            }
        }
    }
}

@Composable
private fun HintRow(model: HaviCaptureViewModel) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = model.markup.tool.hint,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.weight(1f),
        )
        if (model.crop.isCropped) {
            Text(
                text = "Cropped",
                style = MaterialTheme.typography.labelMedium,
                color = HaviBrand.Accent,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier.testTag("havi-crop-indicator"),
            )
        }
    }
}

@Composable
private fun CropControls(model: HaviCaptureViewModel) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        OutlinedButton(onClick = { model.cancelCrop() }, modifier = Modifier.testTag("havi-crop-cancel")) {
            Text("Cancel")
        }
        OutlinedButton(
            onClick = { model.crop.reset() },
            enabled = model.crop.isCropped,
            modifier = Modifier.testTag("havi-crop-reset"),
        ) {
            Text("Reset")
        }
        Spacer(Modifier.weight(1f))
        Button(
            onClick = { model.confirmCrop() },
            colors = ButtonDefaults.buttonColors(containerColor = HaviBrand.Accent),
            modifier = Modifier.testTag("havi-crop-confirm"),
        ) {
            Text("Crop", fontWeight = FontWeight.SemiBold)
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun HaviCaptureDetailsScreen(
    model: HaviCaptureViewModel,
    runtime: HaviRuntime,
    onBack: () -> Unit,
    onClose: () -> Unit,
    openConnect: (reconnect: Boolean) -> Unit,
    openDiagnostics: () -> Unit,
) {
    LaunchedEffect(Unit) { model.loadLabelDefinitions() }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Report to HAVI") },
                navigationIcon = {
                    TextButton(onClick = onBack, enabled = !model.isSubmitting) {
                        Text("Back", modifier = Modifier.testTag("havi-back-button"))
                    }
                },
                actions = {
                    TextButton(onClick = onClose, enabled = !model.isSubmitting) { Text("Close") }
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
            DiagnosticsBadge(model, openDiagnostics)

            if (runtime.isConnected) {
                if (model.failure?.kind != HaviSubmitFailureKind.RECONNECT) {
                    ConnectedStatusRow(runtime, model, onManage = { openConnect(false) })
                }
            } else {
                ConnectPrompt(onConnect = { openConnect(false) })
            }

            CommentField(model)

            if (model.showsPriority) {
                Eyebrow("Priority")
                SegmentedRow(
                    options = model.priorityOptions,
                    selected = model.prioritySelection,
                    enabled = !model.isSubmitting,
                    tag = { "havi-priority-$it" },
                    onSelect = { model.prioritySelection = it },
                )
            }

            if (model.additionalLabelDefinitions.isNotEmpty()) {
                AdditionalLabels(model)
            }

            model.failure?.let { FailureBanner(it, model, onClose, openConnect) }

            SubmitButton(model)
        }
    }
}

@Composable
private fun DiagnosticsBadge(
    model: HaviCaptureViewModel,
    onOpen: () -> Unit,
) {
    val console = model.consoleErrorCount
    val network = model.networkErrorCount
    Surface(
        shape = RoundedCornerShape(12.dp),
        color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.4f),
        modifier = Modifier.fillMaxWidth().clickable(onClick = onOpen).testTag("havi-diagnostics-badge"),
    ) {
        Row(
            modifier = Modifier.padding(14.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Text("Diagnostics", fontWeight = FontWeight.SemiBold, style = MaterialTheme.typography.bodyMedium)
            Spacer(Modifier.weight(1f))
            Text(
                "$console console · $network network",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun ConnectPrompt(onConnect: () -> Unit) {
    Surface(
        shape = RoundedCornerShape(14.dp),
        color = HaviBrand.Accent.copy(alpha = 0.08f),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Row(
            modifier = Modifier.padding(14.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Column(Modifier.weight(1f)) {
                Text("You're not connected to HAVI", fontWeight = FontWeight.SemiBold, style = MaterialTheme.typography.bodyMedium)
                Text(
                    "Connect to send this report.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            OutlinedButton(onClick = onConnect, modifier = Modifier.testTag("havi-connect-prompt")) { Text("Connect") }
        }
    }
}

@Composable
private fun ConnectedStatusRow(
    runtime: HaviRuntime,
    model: HaviCaptureViewModel,
    onManage: () -> Unit,
) {
    Surface(
        shape = RoundedCornerShape(14.dp),
        color = HaviBrand.Success.copy(alpha = 0.08f),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Row(
            modifier = Modifier.padding(14.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Box(Modifier.size(9.dp).clip(CircleShape).background(HaviBrand.Success))
            Column(Modifier.weight(1f)) {
                Text("Connected to HAVI", fontWeight = FontWeight.SemiBold, style = MaterialTheme.typography.bodyMedium)
                Text(
                    connectedIdentityLine(runtime.tokenStore.connectedSession),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                )
            }
            OutlinedButton(
                onClick = onManage,
                enabled = !model.isSubmitting,
                modifier = Modifier.testTag("havi-manage-connection"),
            ) {
                Text("Manage")
            }
        }
    }
}

private fun connectedIdentityLine(session: HaviConnectedSession?): String {
    session ?: return "This device is linked to your workspace."
    val workspace = session.workspaceName ?: session.workspaceId
    val user = session.userName
    return if (!user.isNullOrEmpty()) "$user · $workspace" else workspace
}

@Composable
private fun CommentField(model: HaviCaptureViewModel) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Eyebrow("Comment")
        OutlinedTextField(
            value = model.comment,
            onValueChange = { model.comment = it },
            placeholder = { Text("What's wrong here? (optional)") },
            enabled = !model.isSubmitting,
            modifier = Modifier.fillMaxWidth().testTag("havi-comment-field"),
        )
    }
}

@Composable
private fun AdditionalLabels(model: HaviCaptureViewModel) {
    var expanded by remember { mutableStateOf(false) }
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(
            modifier = Modifier.fillMaxWidth().clickable { expanded = !expanded }.testTag("havi-labels-disclosure"),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Eyebrow("Labels")
            val count = model.appliedLabelCount
            if (count > 0) {
                Box(
                    Modifier.clip(CircleShape).background(HaviBrand.Accent).padding(horizontal = 6.dp, vertical = 1.dp),
                ) {
                    Text("$count", color = Color.White, style = MaterialTheme.typography.labelSmall)
                }
            }
            Spacer(Modifier.weight(1f))
            Text(if (expanded) "Hide" else "Show", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        if (expanded) {
            Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
                for (definition in model.additionalLabelDefinitions) {
                    LabelControl(model, definition)
                }
            }
        }
    }
}

@Composable
private fun LabelControl(
    model: HaviCaptureViewModel,
    definition: HaviLabelDefinition,
) {
    when (definition.kind) {
        HaviLabelKind.CHOICE ->
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                FieldCaption(definition.name)
                SegmentedRow(
                    options = definition.allowedValues,
                    selected = model.labelChoiceValues[definition.key],
                    enabled = !model.isSubmitting,
                    tag = { "havi-label-${definition.key}-$it" },
                    onSelect = { value ->
                        if (model.labelChoiceValues[definition.key] == value) {
                            model.labelChoiceValues.remove(definition.key)
                        } else {
                            model.labelChoiceValues[definition.key] = value
                        }
                    },
                )
            }

        HaviLabelKind.VALUE ->
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                FieldCaption(definition.name)
                OutlinedTextField(
                    value = model.labelChoiceValues[definition.key] ?: "",
                    onValueChange = { v ->
                        if (v.isEmpty()) model.labelChoiceValues.remove(definition.key) else model.labelChoiceValues[definition.key] = v
                    },
                    enabled = !model.isSubmitting,
                    modifier = Modifier.fillMaxWidth().testTag("havi-label-${definition.key}-field"),
                )
            }

        HaviLabelKind.FLAG -> {
            val on = model.labelFlags.contains(definition.key)
            val shape = RoundedCornerShape(50)
            Box(
                modifier =
                    Modifier
                        .clip(shape)
                        .background(if (on) HaviBrand.Accent else MaterialTheme.colorScheme.surfaceVariant)
                        .clickable(enabled = !model.isSubmitting) {
                            if (on) model.labelFlags.remove(definition.key) else model.labelFlags.add(definition.key)
                        }
                        .padding(horizontal = 14.dp, vertical = 8.dp)
                        .testTag("havi-label-${definition.key}"),
            ) {
                Text(
                    text = definition.name,
                    color = if (on) Color.White else MaterialTheme.colorScheme.onSurfaceVariant,
                    fontWeight = if (on) FontWeight.SemiBold else FontWeight.Normal,
                    style = MaterialTheme.typography.bodyMedium,
                )
            }
        }
    }
}

@Composable
private fun SegmentedRow(
    options: List<String>,
    selected: String?,
    enabled: Boolean,
    tag: (String) -> String,
    onSelect: (String) -> Unit,
) {
    Row(
        modifier =
            Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(12.dp))
                .background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.4f))
                .padding(4.dp),
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        for (value in options) {
            val isSelected = selected == value
            Box(
                modifier =
                    Modifier
                        .weight(1f)
                        .height(38.dp)
                        .clip(RoundedCornerShape(9.dp))
                        .background(if (isSelected) HaviBrand.Accent else Color.Transparent)
                        .clickable(enabled = enabled) { onSelect(value) }
                        .testTag(tag(value)),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    text = value.replaceFirstChar { it.uppercase() },
                    color = if (isSelected) Color.White else MaterialTheme.colorScheme.onSurfaceVariant,
                    fontWeight = if (isSelected) FontWeight.SemiBold else FontWeight.Normal,
                    style = MaterialTheme.typography.bodyMedium,
                )
            }
        }
    }
}

@Composable
private fun FailureBanner(
    failure: HaviSubmitFailure,
    model: HaviCaptureViewModel,
    onClose: () -> Unit,
    openConnect: (reconnect: Boolean) -> Unit,
) {
    Surface(
        shape = RoundedCornerShape(14.dp),
        color = Color(0xFFF59E0B).copy(alpha = 0.14f),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(failure.userMessage, style = MaterialTheme.typography.bodyMedium)
            Button(
                onClick = {
                    when (failure.kind) {
                        HaviSubmitFailureKind.RETRY -> model.retry()
                        HaviSubmitFailureKind.RECONNECT -> openConnect(true)
                        HaviSubmitFailureKind.TERMINAL -> onClose()
                    }
                },
                enabled = !model.isSubmitting,
                colors = ButtonDefaults.buttonColors(containerColor = HaviBrand.Accent),
                modifier = Modifier.fillMaxWidth().testTag("havi-retry-button"),
            ) {
                Text(
                    when (failure.kind) {
                        HaviSubmitFailureKind.RETRY -> "Retry"
                        HaviSubmitFailureKind.RECONNECT -> "Reconnect HAVI"
                        HaviSubmitFailureKind.TERMINAL -> "Dismiss"
                    },
                    fontWeight = FontWeight.SemiBold,
                )
            }
        }
    }
}

@Composable
private fun SubmitButton(model: HaviCaptureViewModel) {
    Button(
        onClick = { model.submit() },
        enabled = !model.isSubmitting,
        colors = ButtonDefaults.buttonColors(containerColor = HaviBrand.Accent),
        modifier = Modifier.fillMaxWidth().height(52.dp).testTag("havi-submit-button"),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            if (model.isSubmitting) {
                CircularProgressIndicator(color = Color.White, strokeWidth = 2.dp, modifier = Modifier.size(18.dp))
            }
            Text(if (model.isSubmitting) "Sending…" else "Send to HAVI", fontWeight = FontWeight.SemiBold)
        }
    }
}

@Composable
private fun Eyebrow(text: String) {
    Text(
        text = text.uppercase(),
        style = MaterialTheme.typography.labelSmall,
        fontWeight = FontWeight.SemiBold,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
}

@Composable
private fun FieldCaption(text: String) {
    Text(
        text = text,
        style = MaterialTheme.typography.bodySmall,
        fontWeight = FontWeight.SemiBold,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
}
