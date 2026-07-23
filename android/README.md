# HaviKit for Android

The on-device [HAVI](https://havi.handgemacht.ai) mobile feedback SDK for Android —
the native Kotlin counterpart of the iOS `HaviKit` package and the HAVI browser
extension/widget. It captures a visual + technical observation from inside a
running app — a screenshot with markup, device/app context, and recent
console/network breadcrumbs — and posts it to the hosted HAVI service as a
[W3C Web Annotation](https://www.w3.org/TR/annotation-model/). All clients build
the same annotation envelope (asserted byte-for-byte against a shared golden
fixture), so annotations from every platform land in one place.

The SDK is **config-gated and inert by default**: until `HAVI_ENABLED` plus a
base URL resolve, every entry point is a no-op, so a release build without HAVI
keys carries zero cost. Host apps typically arm it in `debug`/`dev` variants only.

## Modules

| Artifact | Coordinate | Contents |
|---|---|---|
| `havikit` | `ai.handgemacht:havikit:0.2.0` | Android library (AAR): the `Havi` facade, PixelCopy capture + pre-byte redaction, shake/long-press triggers, the Compose capture/markup/connect UI, and the submit flow. Depends on (and re-exports) `havikit-core`. |
| `havikit-core` | `ai.handgemacht:havikit-core:0.2.0` | Pure-JVM wire-contract core: config reader, canonical-JSON envelope builder, secret scrub, multipart, image plan, pairing/exchange state machine, uploader, and token store. No Android dependencies. |

## Requirements

- Android `minSdk` 26, `compileSdk` 35.
- JDK 17 toolchain (the library compiles against Java 17). JDK 21 runs the build.
- Jetpack Compose (Compose BOM). The capture UI is Compose; leaf annotations are
  `Modifier` extensions.

## Install (Gradle)

```kotlin
// build.gradle.kts (app module)
dependencies {
    debugImplementation("ai.handgemacht:havikit:0.2.0")
}
```

Adding `havikit` pulls in `havikit-core` transitively. Add `havikit-core` on its
own only for a headless (non-UI) integration.

## Configure — `AndroidManifest.xml` `<meta-data>`

`HaviConfig.fromManifest(context)` reads these keys from the `<application>` node.
`HAVI_ENABLED` unset → the SDK is inert; set but `HAVI_BASE_URL` missing/invalid →
`IllegalStateException` at start (fail-fast). Every other key is optional; an empty
value is treated as absent. Stamp them from a `debug`/`dev` variant so release
ships inert.

```xml
<application …>
  <meta-data android:name="HAVI_ENABLED"      android:value="YES"/>
  <meta-data android:name="HAVI_BASE_URL"     android:value="https://havi.handgemacht.ai"/>
  <meta-data android:name="HAVI_WORKSPACE_ID" android:value="ws_…"/>
  <meta-data android:name="HAVI_DEV_TOKEN"    android:value="…"/>
  <meta-data android:name="HAVI_PROJECT"      android:value="lesewerkstatt"/>
  <meta-data android:name="HAVI_WORKTREE"     android:value="…"/>
  <meta-data android:name="HAVI_BRANCH"       android:value="…"/>
  <meta-data android:name="HAVI_COMMIT"       android:value="…"/>
  <meta-data android:name="HAVI_IMAGE_FORMAT" android:value="png"/>
</application>
```

| `<meta-data>` key   | Meaning                                          |
|---------------------|--------------------------------------------------|
| `HAVI_ENABLED`      | `YES` (or `true`) to arm the SDK (else inert)    |
| `HAVI_BASE_URL`     | Hosted HAVI base URL (required when enabled)     |
| `HAVI_WORKSPACE_ID` | Target workspace id                              |
| `HAVI_DEV_TOKEN`    | Bearer token for dev capture                     |
| `HAVI_PROJECT`      | Project / repo name (dev context)                |
| `HAVI_WORKTREE`     | Worktree (dev context)                           |
| `HAVI_BRANCH`       | Branch (dev context)                             |
| `HAVI_COMMIT`       | Commit (dev context)                             |
| `HAVI_IMAGE_FORMAT` | `png` (default) or `jpeg`                         |

## Start the SDK

Call `Havi.start` once, with an `Application`/`Context`. It reads
`HaviConfig.fromManifest(context)` by default and is idempotent (repeat calls are
ignored). A `HaviConfig` overload starts without the manifest.

```kotlin
class MyApp : Application() {
    override fun onCreate() {
        super.onCreate()
        if (BuildConfig.DEBUG) {
            Havi.start(this)   // reads HaviConfig.fromManifest(this); no-op when inert
        }
    }
}
```

## Compose integration

```kotlin
setContent {
    HaviOverlay {            // hosts the capture sheet; passthrough when inert
        AppRoot()
    }
}
```

Leaf annotations, usable anywhere in the tree:

- `Modifier.haviScreen("ReadingView")` — names the current screen for the envelope.
- `Modifier.haviContext("namespace", mapOf("key" to "value"))` — structured context
  (secret-scrubbed before send).
- `Modifier.haviRedacted()` / `Modifier.haviReveal()` — mask/unmask a subtree in the
  freeze before any bytes exist.

## Public API — `object Havi`

| Member | Signature | Purpose |
|---|---|---|
| `isEnabled` | `val isEnabled: Boolean` | `false` until `start` resolves an enabled config. |
| `start` | `fun start(context: Context, config: HaviConfig = HaviConfig.fromManifest(context))` | Build the runtime and arm triggers. Inert config → returns; already started → returns (idempotent). |
| `capture` | `fun capture(screen: String? = null)` | Programmatic capture of the resumed activity. No-op unless started. |
| `triggerCapture` | `fun triggerCapture(screen: String? = null)` | Thread-free trigger (shake/long-press callbacks); hops to the main thread. |
| `log` | `fun log(message: String, level: HaviLogLevel = HaviLogLevel.INFO, category: String = "app")` | Breadcrumb ring. `error`-level in a non-`network` category surfaces as a console error; the rest ride in app-logs. Records even when inert. |
| `logNetworkError` | `fun logNetworkError(message: String)` | Network/RPC failure — pass a preformatted `"METHOD url status statusText"` line. |
| `setContext` | `fun setContext(namespace: String, values: Map<String, String>)` | Structured context into `x:havi.contexts` (scrubbed). Ignored when the namespace is empty. |
| `setTag` | `fun setTag(key: String, value: String)` | A single tag into `x:havi.tags`. Ignored when the key is empty. |
| `setScreen` | `fun setScreen(name: String?)` | Names the current screen for the next capture; `null` clears. Imperative twin of `Modifier.haviScreen`. |
| `setPriority` | `fun setPriority(priority: HaviPriority?)` | Seeds the next capture's priority (overridable in the sheet). |
| `signIn` | `fun signIn(token: String, workspaceId: String)` | Dev manual-paste: bearer token + workspace id into HaviKit's own store, overriding the stamped values. |
| `beginDeviceAuthorization` | `suspend fun beginDeviceAuthorization(): HaviDeviceFlow` | Reserved (v1.1); currently throws `HaviException.NotImplemented`. |
| `disconnect` | `fun disconnect()` | Local sign-out: clears this device's stored credential and the seeded priority. |
| `signOut` | `fun signOut()` | Backward-compatible alias of `disconnect`. |
| `authState` | `val authState: HaviAuthState` | `Unconfigured` when disabled; `Authenticated(workspaceId)` when a stored credential or the stamped dev token + workspace resolve; else `NeedsReconnect`. |

Public value types: `HaviConfig` (+ `HaviConfig.fromManifest`), `HaviLogLevel`,
`HaviPriority`, `HaviImageFormat`, `HaviAuthState`, `HaviDeviceFlow`,
`HaviLogEntry`, `HaviException`, `HaviRedactionPolicy`.

### Screen names

The screen name is the routing key on an annotation: it becomes the
`target.source` path (`app://<application-id>/<screen>`) and the `CssSelector`
display value the HAVI dashboard groups by. Name your screens so annotations
arrive as `…/ReadingView` rather than `…/unknown`.

- **Compose** — `Modifier.haviScreen("ReadingView")` on each screen's root.
- **View hosts** — `Havi.setScreen("ReadingView")` in `onResume`; `null` clears.
- **Per-capture override** — `Havi.capture(screen = "ReadingView")`.

Precedence: the explicit `capture(screen)` argument → the host's `haviScreen` /
`setScreen` value → a best-effort auto-detected top Activity/Fragment name →
`"unknown"`. The reported viewport is derived on-device from the screenshot's own
size.

## Capture

`HaviOverlay` installs a shake trigger and an optional two-finger long-press
(emulator fallback). The freeze uses `PixelCopy` (with a `View#draw` fallback) so
hardware-accelerated and video views come through, and blacks out
`Modifier.haviRedacted()` regions plus text inputs **before any bytes exist**. The
overlay is Activity-scoped and needs no `SYSTEM_ALERT_WINDOW` permission. The
capture sheet mirrors iOS: seven markup tools, six colors, object-level undo/redo,
a confirmed crop, diagnostics, connect/pairing, comment, priority, and workspace
labels.

## Build & test

```bash
cd android
./gradlew :havikit-core:test        # pure-JVM suites (envelope golden, transport, redaction, canonical JSON, …)
./gradlew :havikit:lint             # Android lint (needs the Android SDK)
./gradlew :havikit:assemble         # build the AAR (needs the Android SDK)
```

`:havikit-core` builds and tests with only a JDK. `:havikit` applies the Android
Gradle Plugin and is wired into the build only when an Android SDK is present
(`ANDROID_HOME`/`ANDROID_SDK_ROOT`, or `sdk.dir` in `local.properties`).
`.github/workflows/android.yml` runs all three on `ubuntu-latest`.

## Publish

Both modules apply `maven-publish` under group `ai.handgemacht`, version aligned
in `gradle.properties` (`havikit.version`).

```bash
./gradlew :havikit-core:publishToMavenLocal :havikit:publishToMavenLocal
```

The configured remote is GitHub Packages
(`maven.pkg.github.com/handgemacht-ai/havikit`); credentials come from the
`gpr.user`/`gpr.token` Gradle properties or the `GITHUB_ACTOR`/`GITHUB_TOKEN`
environment variables.

## Envelope golden fixture

`havikit-core/src/test/resources/havi-envelope-golden.json` is a byte-identical
vendored copy of the canonical fixture in the iOS repo
(`Tests/HaviKitTests/Fixtures/havi-envelope-golden.json`). `HaviEnvelopeTest`
asserts the Kotlin builder output byte-for-byte against each case after
canonicalization — the cross-platform acceptance test that keeps Android
annotations landing in the same store as iOS/web. The iOS repo is the source of
truth; on an envelope-shape change, update it there and copy the same bytes here.
