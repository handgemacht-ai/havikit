package ai.handgemacht.havikit

import android.view.View
import android.view.ViewGroup
import android.widget.EditText

/** A view carrying an accessibility hint (content description or resource-entry id) and its window rect. */
internal data class HaviAccessibilityFrame(
    val id: String,
    val rect: HaviWindowRect,
)

internal data class HaviViewScanResult(
    val textFields: List<HaviWindowRect>,
    val accessibility: List<HaviAccessibilityFrame>,
)

/**
 * One depth-first walk of the decor view tree at freeze time (Part B4), collecting the
 * window rects of visible [EditText] inputs (the default-masked text category, iOS
 * `UITextField`/`UITextView` parity) and the accessibility-id frames used later to
 * derive the `CssSelector` hint. Compose text fields are not `EditText`, so a Compose
 * host masks them with `Modifier.haviRedacted()` instead.
 */
internal object HaviViewScan {
    private const val MAX_ACCESSIBILITY_FRAMES = 200

    fun scan(root: View): HaviViewScanResult {
        val textFields = ArrayList<HaviWindowRect>()
        val accessibility = ArrayList<HaviAccessibilityFrame>()
        walk(root, IntArray(2), textFields, accessibility)
        return HaviViewScanResult(textFields, accessibility)
    }

    private fun walk(
        view: View,
        location: IntArray,
        textFields: MutableList<HaviWindowRect>,
        accessibility: MutableList<HaviAccessibilityFrame>,
    ) {
        if (view.visibility != View.VISIBLE) return
        if (view.width <= 0 || view.height <= 0) return

        val rect = windowRectOf(view, location)
        if (view is EditText) {
            textFields.add(rect)
        }
        if (accessibility.size < MAX_ACCESSIBILITY_FRAMES) {
            accessibilityId(view)?.let { accessibility.add(HaviAccessibilityFrame(it, rect)) }
        }
        if (view is ViewGroup) {
            for (i in 0 until view.childCount) {
                val child = view.getChildAt(i) ?: continue
                walk(child, location, textFields, accessibility)
            }
        }
    }

    private fun windowRectOf(
        view: View,
        location: IntArray,
    ): HaviWindowRect {
        view.getLocationInWindow(location)
        val left = location[0]
        val top = location[1]
        return HaviWindowRect(left, top, left + view.width, top + view.height)
    }

    private fun accessibilityId(view: View): String? {
        view.contentDescription?.toString()?.takeIf { it.isNotBlank() }?.let { return it }
        val id = view.id
        if (id == View.NO_ID) return null
        return runCatching { view.resources.getResourceEntryName(id) }.getOrNull()
    }
}
