package ai.handgemacht.havikit

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * The Compose markup surface (Part B4), mirroring iOS `HaviMarkupCanvas`: the
 * frozen screenshot with a live overlay that renders the typed vector marks (pen,
 * highlighter, arrow, rectangle, blur/redact) plus the in-progress stroke and the
 * selection. Drawing happens over the still so mark coordinates stay aligned; all
 * geometry is normalized (0..1) in [HaviMarkupEditor], and this view only converts
 * display points to/from that space via the pure `HaviCropGeometry` transform.
 *
 * Crop is a confirmed step: selecting the crop tool shows the whole still with a
 * dimmed-outside draft rect and eight handles; confirming zooms the canvas into the
 * cropped region (display-only) so further annotation happens on a bigger surface.
 */
@Composable
internal fun HaviMarkupCanvasUi(
    image: ImageBitmap,
    imagePixelSize: HaviSize,
    markup: HaviMarkupEditor,
    crop: HaviCropEditor,
    modifier: Modifier = Modifier,
) {
    val editingCrop = markup.tool == HaviMarkTool.CROP
    val region = if (editingCrop) HaviCropGeometry.fullFrame else crop.rect
    val density = LocalDensity.current

    BoxWithConstraints(modifier.fillMaxSize()) {
        val boxW = with(density) { maxWidth.toPx() }
        val boxH = with(density) { maxHeight.toPx() }
        val content = contentRect(imagePixelSize, region, boxW, boxH)
        val contentWpx = content.width
        val contentHpx = content.height

        Box(
            Modifier
                .offset { IntOffset(content.left.roundToInt(), content.top.roundToInt()) }
                .size(with(density) { contentWpx.toDp() }, with(density) { contentHpx.toDp() }),
        ) {
            Canvas(
                Modifier
                    .fillMaxSize()
                    .markupGestures(markup, crop, region, contentWpx, contentHpx, editingCrop),
            ) {
                drawVisibleImage(image, imagePixelSize, region)
                for (mark in markup.marks) {
                    drawMark(mark, region, mark.id == markup.selectedMarkId)
                }
                markup.inProgress?.let { drawMark(it, region, selected = false) }
                if (editingCrop) drawCropOverlay(crop.rect)
            }
        }
    }
}

private fun Modifier.markupGestures(
    markup: HaviMarkupEditor,
    crop: HaviCropEditor,
    region: HaviRectF,
    contentWpx: Float,
    contentHpx: Float,
    editingCrop: Boolean,
): Modifier =
    pointerInput(editingCrop, region, contentWpx, contentHpx) {
        awaitEachGesture {
            val down = awaitFirstDown(requireUnconsumed = false)
            if (editingCrop) {
                val handle = nearestHandle(crop.rect, down.position, contentWpx, contentHpx)
                crop.updateResize(handle, normalized(down.position, contentWpx, contentHpx, HaviCropGeometry.fullFrame))
                down.consume()
                while (true) {
                    val event = awaitPointerEvent()
                    val change = event.changes.firstOrNull { it.id == down.id } ?: break
                    if (!change.pressed) break
                    crop.updateResize(handle, normalized(change.position, contentWpx, contentHpx, HaviCropGeometry.fullFrame))
                    change.consume()
                }
            } else {
                markup.begin(normalized(down.position, contentWpx, contentHpx, region), region)
                down.consume()
                while (true) {
                    val event = awaitPointerEvent()
                    val change = event.changes.firstOrNull { it.id == down.id } ?: break
                    if (!change.pressed) break
                    markup.extend(normalized(change.position, contentWpx, contentHpx, region))
                    change.consume()
                }
                markup.end(region)
            }
        }
    }

private fun normalized(
    position: Offset,
    contentWpx: Float,
    contentHpx: Float,
    region: HaviRectF,
): HaviPointF =
    HaviCropGeometry.normalizedFromCanvas(
        canvasX = position.x.toDouble(),
        canvasY = position.y.toDouble(),
        contentWidth = contentWpx.toDouble(),
        contentHeight = contentHpx.toDouble(),
        visibleRegion = region,
    )

private fun nearestHandle(
    rect: HaviRectF,
    position: Offset,
    contentWpx: Float,
    contentHpx: Float,
): HaviCropGeometry.Handle =
    HaviCropGeometry.Handle.entries.minByOrNull { handle ->
        val anchor = HaviCropGeometry.anchor(handle, rect)
        val ax = anchor.x * contentWpx
        val ay = anchor.y * contentHpx
        hypot((ax - position.x).toDouble(), (ay - position.y).toDouble())
    } ?: HaviCropGeometry.Handle.BOTTOM_RIGHT

private fun DrawScope.drawVisibleImage(
    image: ImageBitmap,
    imagePixelSize: HaviSize,
    region: HaviRectF,
) {
    val clamped = region.standardized()
    val srcX = (clamped.minX * imagePixelSize.width).roundToInt().coerceIn(0, imagePixelSize.width)
    val srcY = (clamped.minY * imagePixelSize.height).roundToInt().coerceIn(0, imagePixelSize.height)
    val srcW = max(1, (clamped.width * imagePixelSize.width).roundToInt()).coerceAtMost(imagePixelSize.width - srcX)
    val srcH = max(1, (clamped.height * imagePixelSize.height).roundToInt()).coerceAtMost(imagePixelSize.height - srcY)
    drawImage(
        image = image,
        srcOffset = IntOffset(srcX, srcY),
        srcSize = IntSize(srcW, srcH),
        dstOffset = IntOffset.Zero,
        dstSize = IntSize(size.width.roundToInt(), size.height.roundToInt()),
    )
}

private fun DrawScope.canvasPoint(
    point: HaviPointF,
    region: HaviRectF,
): Offset {
    val mapped =
        HaviCropGeometry.canvasFromNormalized(
            point = point,
            contentWidth = size.width.toDouble(),
            contentHeight = size.height.toDouble(),
            visibleRegion = region,
        )
    return Offset(mapped.x.toFloat(), mapped.y.toFloat())
}

private fun DrawScope.drawMark(
    mark: HaviMark,
    region: HaviRectF,
    selected: Boolean,
) {
    val color = mark.color.toColor()
    when (val s = mark.shape) {
        is HaviMark.Shape.Pen -> drawStroke(s.points, region, color, 4f, alpha = 1f)
        is HaviMark.Shape.Highlighter -> drawStroke(s.points, region, color, 16f, alpha = 0.35f)
        is HaviMark.Shape.Arrow -> drawArrow(s.from, s.to, region, color)
        is HaviMark.Shape.Rectangle -> {
            val r = displayRect(s.rect, region)
            drawRect(color = color, topLeft = r.topLeft, size = r.size, style = Stroke(width = 4f))
        }
        is HaviMark.Shape.Blur -> drawBlurPlaceholder(displayRect(s.rect, region))
    }
    if (selected) drawSelection(mark.normalizedBounds, region)
}

private fun DrawScope.drawStroke(
    points: List<HaviPointF>,
    region: HaviRectF,
    color: Color,
    width: Float,
    alpha: Float,
) {
    val first = points.firstOrNull() ?: return
    val path = Path()
    val start = canvasPoint(first, region)
    path.moveTo(start.x, start.y)
    for (p in points.drop(1)) {
        val o = canvasPoint(p, region)
        path.lineTo(o.x, o.y)
    }
    drawPath(
        path = path,
        color = color,
        alpha = alpha,
        style = Stroke(width = width, cap = StrokeCap.Round, join = StrokeJoin.Round),
    )
}

private fun DrawScope.drawArrow(
    from: HaviPointF,
    to: HaviPointF,
    region: HaviRectF,
    color: Color,
) {
    val tail = canvasPoint(from, region)
    val tip = canvasPoint(to, region)
    drawLine(color = color, start = tail, end = tip, strokeWidth = 4f, cap = StrokeCap.Round)
    val head =
        HaviMarkupSerializer.arrowHead(
            tip = HaviPointF(tip.x.toDouble(), tip.y.toDouble()),
            tail = HaviPointF(tail.x.toDouble(), tail.y.toDouble()),
            length = 20.0,
            width = 16.0,
        )
    val path = Path()
    head.firstOrNull()?.let { path.moveTo(it.x.toFloat(), it.y.toFloat()) }
    for (p in head.drop(1)) path.lineTo(p.x.toFloat(), p.y.toFloat())
    path.close()
    drawPath(path = path, color = color)
}

private fun DrawScope.drawBlurPlaceholder(rect: Rect) {
    drawRect(color = Color.Black, topLeft = rect.topLeft, size = rect.size)
    drawRect(
        color = Color.White.copy(alpha = 0.6f),
        topLeft = rect.topLeft,
        size = rect.size,
        style = Stroke(width = 1.5f, pathEffect = PathEffect.dashPathEffect(floatArrayOf(4f, 3f))),
    )
}

private fun DrawScope.drawSelection(
    bounds: HaviRectF,
    region: HaviRectF,
) {
    val rect = displayRect(bounds, region)
    val inflated = Rect(rect.left - 6f, rect.top - 6f, rect.right + 6f, rect.bottom + 6f)
    drawRect(
        color = HaviBrand.Accent,
        topLeft = inflated.topLeft,
        size = inflated.size,
        style = Stroke(width = 1.5f, pathEffect = PathEffect.dashPathEffect(floatArrayOf(5f, 3f))),
    )
}

private fun DrawScope.drawCropOverlay(cropRect: HaviRectF) {
    val rect = displayRect(cropRect, HaviCropGeometry.fullFrame)
    // Dim everything outside the draft crop (four bands around the bright rect).
    val scrim = Color.Black.copy(alpha = 0.55f)
    drawRect(color = scrim, topLeft = Offset.Zero, size = Size(size.width, rect.top))
    drawRect(color = scrim, topLeft = Offset(0f, rect.bottom), size = Size(size.width, size.height - rect.bottom))
    drawRect(color = scrim, topLeft = Offset(0f, rect.top), size = Size(rect.left, rect.height))
    drawRect(color = scrim, topLeft = Offset(rect.right, rect.top), size = Size(size.width - rect.right, rect.height))
    drawRect(color = Color.White, topLeft = rect.topLeft, size = rect.size, style = Stroke(width = 2f))
    for (handle in HaviCropGeometry.Handle.entries) {
        val a = HaviCropGeometry.anchor(handle, cropRect)
        val center = Offset((a.x * size.width).toFloat(), (a.y * size.height).toFloat())
        drawCircle(color = Color.White, radius = 7f, center = center)
        drawCircle(color = HaviBrand.Accent, radius = 7f, center = center, style = Stroke(width = 2f))
    }
}

private fun DrawScope.displayRect(
    rect: HaviRectF,
    region: HaviRectF,
): Rect {
    val s = rect.standardized()
    val origin = canvasPoint(HaviPointF(s.minX, s.minY), region)
    val far = canvasPoint(HaviPointF(s.maxX, s.maxY), region)
    return Rect(origin.x, origin.y, far.x, far.y)
}

/** Aspect-fit + center the visible [region] of the still inside a [boxW] x [boxH] box. */
private fun contentRect(
    imagePixelSize: HaviSize,
    region: HaviRectF,
    boxW: Float,
    boxH: Float,
): Rect {
    val pixelWidth = max(imagePixelSize.width * region.width, 1.0)
    val pixelHeight = max(imagePixelSize.height * region.height, 1.0)
    val scale = min(boxW / pixelWidth, boxH / pixelHeight)
    val width = (pixelWidth * scale).toFloat()
    val height = (pixelHeight * scale).toFloat()
    val left = (boxW - width) / 2f
    val top = (boxH - height) / 2f
    return Rect(left, top, left + width, top + height)
}
