package ai.handgemacht.havikit

import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.layout.boundsInWindow
import androidx.compose.ui.layout.onGloballyPositioned

/**
 * Compose integration for HaviKit (Part B3). The leaf annotations register into the
 * process-global screen/context/redaction relays, so they work whether or not the host
 * wraps the tree in [HaviOverlay]. Redaction bounds are published in window-pixel
 * space (`boundsInWindow`), the same space the PixelCopy freeze is captured in.
 */

/**
 * Root capture host — wrap the app root once. Currently a passthrough: the shake and
 * long-press triggers are installed globally by the runtime via the activity lifecycle,
 * so no host view is required to receive captures. The capture sheet UI mounts here in a
 * later stage.
 */
@Composable
public fun HaviOverlay(content: @Composable () -> Unit) {
    content()
}

/** Names the current screen for the next capture on composition (parity with iOS `onAppear`). Imperative twin: [Havi.setScreen]. */
@Composable
public fun HaviScreen(name: String) {
    DisposableEffect(name) {
        Havi.setScreen(name)
        onDispose { }
    }
}

/** Modifier form of [HaviScreen]. */
public fun Modifier.haviScreen(name: String): Modifier =
    composed {
        HaviScreen(name)
        this
    }

/** Scopes structured context to a subtree, captured into `x:havi.contexts` (secret-scrubbed). */
public fun Modifier.haviContext(
    namespace: String,
    values: Map<String, String>,
): Modifier =
    composed {
        DisposableEffect(namespace, values) {
            Havi.setContext(namespace, values)
            onDispose { }
        }
        this
    }

/** Marks a subtree secret — its window bounds are blacked out in the freeze before any bytes exist. */
public fun Modifier.haviRedacted(): Modifier =
    composed {
        val id = remember { HaviRedactionRegistry.nextId() }
        DisposableEffect(id) {
            onDispose { HaviRedactionRegistry.remove(id) }
        }
        onGloballyPositioned { coordinates ->
            HaviRedactionRegistry.setRedacted(id, coordinates.boundsInWindow())
        }
    }

/** Opts a subtree back IN when its category (e.g. text inputs) is masked by default. */
public fun Modifier.haviReveal(): Modifier =
    composed {
        val id = remember { HaviRedactionRegistry.nextId() }
        DisposableEffect(id) {
            onDispose { HaviRedactionRegistry.remove(id) }
        }
        onGloballyPositioned { coordinates ->
            HaviRedactionRegistry.setRevealed(id, coordinates.boundsInWindow())
        }
    }
