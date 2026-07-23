# HaviKit

The on-device [HAVI](https://havi.handgemacht.ai) mobile feedback SDK for iOS.

HaviKit lets a developer (or QA) capture a visual + technical observation from
inside a running iOS app — a screenshot with markup, the device/app context, and
recent console/network breadcrumbs — and post it to the hosted HAVI service as a
[W3C Web Annotation](https://www.w3.org/TR/annotation-model/). It is the mobile
counterpart of the HAVI browser extension and embeddable widget: all three build
the same annotation envelope so annotations from every client land in one place.

The SDK is **config-gated and inert by default**: until `HAVI_ENABLED` plus a
base URL resolve, every entry point is a no-op, so a store build without HAVI
keys carries zero cost. Host apps typically compile it in for `DEBUG`/dev builds
only.

## Requirements

- iOS 17+ (the capture/overlay UI). The pure-logic targets (envelope builder,
  secret scrub, transport) also build for macOS 12+, which is how `swift test`
  runs on a Mac host with no Simulator.
- Swift 5.10 / Xcode 16+.

## Install (Swift Package Manager)

Add the package with the versioned tag. HaviKit follows semver; pin to an exact
version or a range.

### Xcode

File → Add Package Dependencies… → enter the repository URL:

```
https://github.com/handgemacht-ai/havikit
```

Choose **Exact Version** `0.1.0` (or "Up to Next Minor"), then add the `HaviKit`
library to your app target.

### Package.swift

```swift
dependencies: [
    .package(url: "https://github.com/handgemacht-ai/havikit", exact: "0.1.0"),
],
targets: [
    .target(
        name: "YourApp",
        dependencies: [.product(name: "HaviKit", package: "havikit")]
    ),
]
```

### XcodeGen (`project.yml`)

```yaml
packages:
  HaviKit:
    url: https://github.com/handgemacht-ai/havikit
    exact: "0.1.0"
targets:
  YourApp:
    dependencies:
      - package: HaviKit
        product: HaviKit
```

> **Private-repo access.** While `handgemacht-ai/havikit` is private, resolving
> the dependency needs credentials for the repo: an SSH key or an HTTPS token
> with read access. On CI, rewrite HTTPS fetches with a token that can read the
> repo, e.g.
> `git config --global url."https://x-access-token:${TOKEN}@github.com/".insteadOf "https://github.com/"`.

## Integration

Three touch points in the host app.

### 1. Stamp the `HAVI_*` config into `Info.plist`

`HaviConfig.fromBundle()` reads these keys. `HAVI_ENABLED` unset → the SDK is
inert; set (`YES`) but `HAVI_BASE_URL` missing/invalid → `fatalError` (fail
fast). Every other key is optional. With XcodeGen you inject them from an
`.xcconfig`:

| Info.plist key      | Meaning                                         |
|---------------------|-------------------------------------------------|
| `HAVI_ENABLED`      | `YES` to arm the SDK (else fully inert)         |
| `HAVI_BASE_URL`     | Hosted HAVI base URL (required when enabled)    |
| `HAVI_WORKSPACE_ID` | Target workspace id                             |
| `HAVI_DEV_TOKEN`    | Bearer token for dev capture                    |
| `HAVI_PROJECT`      | Project / repo name (dev context)               |
| `HAVI_WORKTREE`     | Worktree (dev context)                          |
| `HAVI_BRANCH`       | Branch (dev context)                            |
| `HAVI_COMMIT`       | Commit (dev context)                            |
| `HAVI_IMAGE_FORMAT` | `png` (default) or `jpeg`                        |

### 2. Start the SDK

```swift
import HaviKit

@main
struct MyApp: App {
    init() {
        #if DEBUG
        Havi.start()          // reads HaviConfig.fromBundle(); idempotent; no-op when inert
        #endif
    }
}
```

### 3. Mount the capture overlay

```swift
var body: some Scene {
    WindowGroup {
        #if DEBUG
        RootView().haviOverlay()   // installs shake / two-finger-long-press capture; passthrough when inert
        #else
        RootView()
        #endif
    }
}
```

Optional annotations you can add anywhere in the view tree / app code:

- `.haviScreen("Home")` — names the current screen for the envelope.
- `.haviContext("namespace", ["key": "value"])` — structured context (secret-scrubbed).
- `.haviRedacted()` / `.haviReveal()` — mask/unmask a subtree in the snapshot.
- `Havi.log(_:level:category:)`, `Havi.logNetworkError(_:)` — breadcrumbs that
  surface as the annotation's console/network describing bodies.
- `Havi.capture(screen:)` — trigger capture programmatically.
- `Havi.disconnect()` — sign out, clearing this device's stored HAVI credential.

### Screen names (recommended)

The screen name is the most valuable piece of routing metadata on an annotation:
it becomes the `target.source` path (`app://<bundle-id>/<screen>`) and the
`CssSelector` display value the HAVI dashboard groups and filters by. **Name your
screens** so annotations arrive as `…/ReadingView` rather than `…/unknown`.

Set it whichever way fits the host:

- **SwiftUI** — attach `.haviScreen("ReadingView")` to each screen's root view.
  It updates the current screen on appear.
- **UIKit / navigation callbacks** — call `Havi.setScreen("ReadingView")` (e.g.
  in `viewDidAppear`). Pass `nil` to clear. This is the imperative counterpart of
  the modifier.
- **Per-capture override** — `Havi.capture(screen: "ReadingView")` names just that
  one capture.

Precedence for a capture's screen name is: the explicit `capture(screen:)`
argument → the host's `.haviScreen` / `Havi.setScreen` value → a best-effort
**auto-detected** top view-controller class name → `"unknown"`. Auto-detection is
a safety net only: it cannot name a plain `UIHostingController`/container (it
falls through to `"unknown"` there), so a SwiftUI host that wants meaningful
names must set one of the above. The reported viewport (`target.state`) is always
derived on-device from the captured screenshot's own point size and needs no host
cooperation.

## Testing

```bash
swift test          # pure-logic suites on the macOS host (envelope, transport, redaction, canonical JSON)
```

The UIKit capture/overlay suites compile only where `canImport(UIKit)` holds, so
run them against an iOS Simulator:

```bash
xcodebuild test -scheme HaviKit -destination 'platform=iOS Simulator,name=iPhone 16'
```

CI (`.github/workflows/ci.yml`) runs both on `macos-latest`.

## Envelope golden fixture (cross-repo contract)

`Tests/HaviKitTests/Fixtures/havi-envelope-golden.json` is the **canonical home**
of the cross-language envelope golden table. `HaviKitEnvelopeTests` asserts the
on-device builder output byte-for-byte against it (after canonicalization).

The **havi backend** repo keeps a **vendored copy** at
`test/support/fixtures/havi-envelope-golden.json`, guarded by
`test/havi_web/mobile_golden_contract_test.exs`, which POSTs the golden cases
through the real annotation-create path to prove the emitted bytes are what the
backend accepts.

**Sync rule** (mirrors the browser-extension shared-artifact pattern): this repo
is the source of truth. When the envelope shape changes, update the fixture here,
then copy the same bytes into the havi backend's vendored path so its contract
test stays green. The two copies must be byte-identical; a drift means one side's
builder/consumer has diverged.
