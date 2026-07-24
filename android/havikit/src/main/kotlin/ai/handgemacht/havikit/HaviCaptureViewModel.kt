package ai.handgemacht.havikit

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Drives one capture sheet (Part B4), mirroring iOS `HaviCaptureModel`: the markup
 * marks, comment, priority, workspace labels, captured diagnostics, and the submit
 * lifecycle. Submit runs the exact iOS order — byte-crop, project marks, burn
 * blur, encode, build the W3C envelope, hand an immutable [PendingAnnotation] to
 * the uploader — off the main thread ([HaviSubmitPipeline]); on failure the sheet
 * stays open on the details screen, fully editable, with the `error.code`-mapped
 * reason. Compose-observable so both screens read/write one shared model.
 *
 * The model is owned by [HaviCaptureHost], not by the composition, and [scope] is
 * the SDK-owned [HaviSubmitScope]: one capture session survives the host Activity
 * being destroyed and recreated, so a configuration change mid-submit neither
 * cancels the upload nor loses the markup, the comment or which screen the user was
 * on. Everything the sheet renders — including [showDetails] — therefore lives here.
 */
internal class HaviCaptureViewModel(
    val frame: HaviCaptureFrame,
    private val runtime: HaviRuntime,
    private val scope: CoroutineScope,
    initialPriority: HaviPriority,
    private val onSubmitSuccess: () -> Unit,
) {
    sealed interface Phase {
        data object Editing : Phase

        data object Submitting : Phase

        data class Failed(val failure: HaviSubmitFailure) : Phase
    }

    val markup = HaviMarkupEditor()
    val crop = HaviCropEditor()

    init {
        markup.onToolChange = ::onToolChanged
    }

    /** Screen 1 (markup) vs Screen 2 (details); the sheet returns to it after a recreation. */
    var showDetails by mutableStateOf(false)

    var comment by mutableStateOf("")
    var prioritySelection by mutableStateOf(initialPriority.wireValue)
    var includeConsoleErrors by mutableStateOf(true)
    var includeNetworkErrors by mutableStateOf(true)

    var phase by mutableStateOf<Phase>(Phase.Editing)
        private set

    var priorityDefinition by mutableStateOf<HaviLabelDefinition?>(null)
        private set

    private var vocabularyResolved by mutableStateOf(false)

    val additionalLabelDefinitions = mutableStateListOf<HaviLabelDefinition>()
    val labelChoiceValues = mutableStateMapOf<String, String>()
    val labelFlags = mutableStateListOf<String>()

    private val diagnostics = HaviDiagnostics.split(frame.logEntries)
    val consoleErrorCount: Int get() = diagnostics.consoleErrors.size
    val networkErrorCount: Int get() = diagnostics.networkErrors.size
    val diagnosticsSplit: HaviDiagnostics.Split get() = diagnostics

    private var toolBeforeCrop: HaviMarkTool = HaviMarkTool.PEN

    val isSubmitting: Boolean get() = phase is Phase.Submitting
    val failure: HaviSubmitFailure? get() = (phase as? Phase.Failed)?.failure

    /** Crop is a confirmed step, so an open draft must be confirmed/cancelled before Screen 2. */
    val canProceed: Boolean get() = !isSubmitting && !crop.isEditing

    val priorityOptions: List<String>
        get() = priorityDefinition?.allowedValues ?: HaviPriority.entries.map { it.wireValue }

    /** True in the offline fallback and when the vocabulary carries a `priority` choice. */
    val showsPriority: Boolean get() = !vocabularyResolved || priorityDefinition != null

    private val emittedPriority: String? get() = if (showsPriority) prioritySelection.ifBlank { null } else null

    // Crop-mode transitions (mirror iOS HaviCaptureModel).

    fun onToolChanged(
        oldTool: HaviMarkTool,
        newTool: HaviMarkTool,
    ) {
        if (newTool == HaviMarkTool.CROP) {
            if (oldTool != HaviMarkTool.CROP) toolBeforeCrop = oldTool
            crop.beginEditing()
        } else if (oldTool == HaviMarkTool.CROP && crop.isEditing) {
            crop.cancel()
        }
    }

    fun confirmCrop() {
        crop.confirm()
        markup.selectTool(toolBeforeCrop)
    }

    fun cancelCrop() {
        crop.cancel()
        markup.selectTool(toolBeforeCrop)
    }

    fun submit() {
        if (isSubmitting) return
        phase = Phase.Submitting

        val draft =
            HaviSubmitPipeline.Draft(
                cropRect = crop.rect,
                marks = markup.marks,
                comment = comment.ifBlank { null },
                priority = emittedPriority,
                labels = appliedLabels(),
                includeConsoleErrors = includeConsoleErrors,
                includeNetworkErrors = includeNetworkErrors,
            )
        val config = runtime.config
        val token = runtime.resolvedToken()
        val workspace = runtime.resolvedWorkspaceId()

        scope.launch {
            val result =
                HaviSubmitPipeline.guarded {
                    val prepared =
                        withContext(Dispatchers.Default) {
                            HaviSubmitPipeline.prepare(
                                frame = frame,
                                draft = draft,
                                config = config,
                                workspaceId = workspace,
                                bearerToken = token,
                            )
                        }
                    prepared?.let { withContext(Dispatchers.IO) { runtime.uploader.submit(it.pending) } }
                } ?: HaviSubmitResult.Failure(HaviSubmitPipeline.preparationFailure)

            when (result) {
                is HaviSubmitResult.Success -> {
                    Havi.clearLogBuffer()
                    Havi.clearPendingPriority()
                    onSubmitSuccess()
                }
                is HaviSubmitResult.Failure -> phase = Phase.Failed(result.failure)
            }
        }
    }

    fun retry() {
        if (phase !is Phase.Failed) return
        phase = Phase.Editing
        submit()
    }

    suspend fun loadLabelDefinitions() {
        if (vocabularyResolved) return
        val token = runtime.resolvedToken() ?: return
        val workspace = runtime.resolvedWorkspaceId() ?: return
        val definitions = withContext(Dispatchers.IO) { runtime.labelDefinitions(token, workspace) } ?: return

        vocabularyResolved = true
        priorityDefinition = definitions.firstOrNull { it.key == "priority" && it.kind == HaviLabelKind.CHOICE }
        additionalLabelDefinitions.clear()
        additionalLabelDefinitions.addAll(definitions.filter { it.key != "priority" })
        reconcilePrioritySelection()
    }

    /** Snaps the seeded priority onto a custom option set (the middle option as medium-equivalent). */
    private fun reconcilePrioritySelection() {
        val options = priorityOptions
        if (options.isEmpty() || options.contains(prioritySelection)) return
        prioritySelection = options[options.size / 2]
    }

    fun appliedLabels(): List<HaviLabel> =
        additionalLabelDefinitions.mapNotNull { definition ->
            when (definition.kind) {
                HaviLabelKind.FLAG ->
                    if (labelFlags.contains(definition.key)) HaviLabel(definition.key) else null
                HaviLabelKind.CHOICE, HaviLabelKind.VALUE -> {
                    val trimmed = (labelChoiceValues[definition.key] ?: "").trim()
                    if (trimmed.isEmpty()) null else HaviLabel(definition.key, trimmed)
                }
            }
        }

    val appliedLabelCount: Int get() = appliedLabels().size
}
