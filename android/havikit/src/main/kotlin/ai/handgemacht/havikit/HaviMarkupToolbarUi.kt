package ai.handgemacht.havikit

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp

/**
 * The markup tool tray (Part B4): the seven tools with a clear selected state,
 * object-level undo/redo, and a delete affordance shown only when the select tool
 * has a mark chosen. Leaf test tags ride on each control (parity with the iOS
 * leaf-only accessibility-identifier rule), so `havi-tool-*` / `havi-undo` /
 * `havi-redo` / `havi-delete-mark` resolve in UI tests.
 */
@Composable
internal fun HaviMarkupToolbar(markup: HaviMarkupEditor) {
    Row(
        modifier = Modifier.horizontalScroll(rememberScrollState()).padding(horizontal = 8.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        for (tool in HaviMarkTool.entries) {
            ToolButton(tool = tool, selected = markup.tool == tool) { markup.selectTool(tool) }
        }
        Spacer(Modifier.width(2.dp))
        Box(Modifier.width(1.dp).height(22.dp).background(MaterialTheme.colorScheme.outline.copy(alpha = 0.4f)))
        Spacer(Modifier.width(2.dp))
        HistoryButton(label = "Undo", tag = "havi-undo", enabled = markup.canUndo) { markup.undo() }
        HistoryButton(label = "Redo", tag = "havi-redo", enabled = markup.canRedo) { markup.redo() }
        if (markup.selectedMark != null) {
            DeleteButton { markup.deleteSelected() }
        }
    }
}

@Composable
private fun ToolButton(
    tool: HaviMarkTool,
    selected: Boolean,
    onClick: () -> Unit,
) {
    val background = if (selected) HaviBrand.Accent else MaterialTheme.colorScheme.surfaceVariant
    val foreground = if (selected) Color.White else MaterialTheme.colorScheme.onSurfaceVariant
    Box(
        modifier =
            Modifier
                .height(40.dp)
                .clip8()
                .background(background)
                .clickable(onClick = onClick)
                .padding(horizontal = 12.dp)
                .testTag(tool.accessibilityId),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = tool.shortTitle,
            color = foreground,
            style = MaterialTheme.typography.labelLarge,
            fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Medium,
        )
    }
}

@Composable
private fun HistoryButton(
    label: String,
    tag: String,
    enabled: Boolean,
    onClick: () -> Unit,
) {
    Box(
        modifier =
            Modifier
                .height(40.dp)
                .clip8()
                .background(MaterialTheme.colorScheme.surfaceVariant)
                .clickable(enabled = enabled, onClick = onClick)
                .alpha(if (enabled) 1f else 0.4f)
                .padding(horizontal = 12.dp)
                .testTag(tag),
        contentAlignment = Alignment.Center,
    ) {
        Text(text = label, style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun DeleteButton(onClick: () -> Unit) {
    Box(
        modifier =
            Modifier
                .height(40.dp)
                .clip8()
                .background(MaterialTheme.colorScheme.error)
                .clickable(onClick = onClick)
                .padding(horizontal = 12.dp)
                .testTag("havi-delete-mark"),
        contentAlignment = Alignment.Center,
    ) {
        Text(text = "Delete", color = MaterialTheme.colorScheme.onError, style = MaterialTheme.typography.labelLarge)
    }
}

/**
 * The 6-preset color swatch row (red default). Tapping picks the color new marks
 * use; the current pick lifts with an accent ring. Leaf tags: `havi-color-<name>`.
 */
@Composable
internal fun HaviColorSwatchRow(markup: HaviMarkupEditor) {
    Row(
        horizontalArrangement = Arrangement.spacedBy(16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        for (color in HaviMarkColor.Presets) {
            val selected = markup.color == color
            Box(
                modifier =
                    Modifier
                        .size(28.dp)
                        .clip(CircleShape)
                        .background(color.toColor())
                        .border(
                            width = if (selected) 2.5.dp else 1.dp,
                            color = if (selected) HaviBrand.Accent else MaterialTheme.colorScheme.outline.copy(alpha = 0.4f),
                            shape = CircleShape,
                        )
                        .clickable { markup.setColor(color) }
                        .testTag(color.accessibilityId),
            )
        }
    }
}

private fun Modifier.clip8(): Modifier = clip(RoundedCornerShape(11.dp))

private fun Modifier.clip(shape: androidx.compose.ui.graphics.Shape): Modifier =
    this.then(androidx.compose.ui.draw.clip(shape))
