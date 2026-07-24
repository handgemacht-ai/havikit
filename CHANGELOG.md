# Changelog

All notable changes to HaviKit are recorded here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and
the project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
One version number covers every platform in this repo: the Swift package, the
Android artifacts (`ai.handgemacht:havikit*`), and the Expo module
(`@handgemacht-ai/expo-havikit`).

Each entry names the platform it affects — **iOS**, **Android**,
**React Native**, or **All** for changes that reach every client.

## [Unreleased]

_Hardening work still in review appends to this section as it merges._

### Added

- **Android** — HaviKit for Android: `ai.handgemacht:havikit` (the SDK with its
  Compose UI) and `ai.handgemacht:havikit-core` (a headless, pure-JVM core for
  non-UI integrations). Shake and two-finger-long-press capture, screenshot with
  redaction applied before the bytes leave the device, a Compose markup and crop
  editor, device pairing, and report submit. It builds the same annotation
  envelope as iOS, asserted byte-for-byte against the shared golden fixture.
  Requires `minSdk` 26 and Compose; see `android/README.md`.
- **React Native** — `@handgemacht-ai/expo-havikit`, an Expo module that wraps
  the native iOS and Android SDKs. Typed TypeScript API (`start`, `capture`,
  `log`, `logNetworkError`, `setScreen`, `setContext`, `setTag`, `getAuthState`,
  `getIsEnabled`, `signOut`), a `<HaviOverlay/>` component, and a config plugin
  that wires the native build (iOS deployment target, Android `minSdkVersion`,
  the SDK pod source, and the Maven repository serving the AAR). Inert no-op on
  web. Not available in Expo Go — build a development build. See
  `expo/README.md`.
- **iOS** — `HaviKit.podspec` at the repo root, so CocoaPods hosts (including
  the Expo bridge) can resolve `pod 'HaviKit'`. It mirrors `Package.swift`:
  iOS 15, Swift 5.10, sources only, no bundled resources.
- **Android** — `Havi.attachActivity(activity)`, a public entry point for hosts
  that start the SDK after their first Activity has already resumed.
- **React Native** — config-plugin options for local development against an
  unpublished SDK build: `android.useMavenLocal` resolves the AAR from the local
  Maven repository instead of the credentialed remote, and `ios.havikitPodPath`
  consumes the podspec from a path instead of a git tag.
- **Android** — `android/sample`, a Compose app that exercises the SDK end to
  end: three named screens, the shake trigger, a manual capture button, and
  pairing.
- **React Native** — `expo/example`, an Expo app that dogfoods the module
  against the in-repo bridge.
- **All** — a root MIT `LICENSE`, which the podspec and `expo/package.json`
  already claimed.

### Changed

- **iOS** — the minimum deployment target is now **iOS 15** (was iOS 17), so
  HaviKit drops into apps that still support older devices. Capture, the markup
  and crop editors, the two-screen report flow, and pairing all behave as
  before. The one visible difference on iOS 15: the comment box is a fixed
  multi-line editor instead of one that grows as you type.
- **React Native** — the config plugin's default iOS deployment target is now
  `15.0`. A project that already targets something higher keeps it; the plugin
  only ever raises the floor.

### Fixed

- **Android** — capture works on the first cold start. `Havi.capture()`
  previously did nothing at all when `Havi.start()` ran after the host's first
  Activity had resumed — the normal case for React Native and Expo apps, which
  start the SDK from JavaScript. The shake and long-press triggers were dead in
  the same window; one background/foreground cycle was needed before any capture
  entry point worked. Hosts that start the SDK from `Application.onCreate` were
  unaffected. A capture that still cannot resolve a window now leaves a warning
  breadcrumb instead of returning silently.
- **All** — a report that times out *after* the service already stored it no
  longer lands twice. Every send of one report — the transient retry and both
  re-encode fallbacks — now carries the same idempotency key. Server-side
  de-duplication on that key follows separately; this is the client half.
- **All** — a chatty `Havi.log()` can no longer balloon memory or the uploaded
  log body. Each message is capped at 4 KiB (cut on a character boundary, never
  mid-character) and the whole ring at 256 KiB, oldest evicted first.
- **All** — a rate-limited response carrying no error body is retried like any
  other transient failure instead of dead-ending the report.
- **All** — a credential the service rejects is cleared from the device
  immediately. Previously, dismissing the reconnect prompt left the dead
  credential in place and every later report failed until the app was
  reinstalled.
- **All** — one rule now decides whether a base URL is usable on every platform:
  absolute, `http` or `https`, with a host. iOS previously accepted schemeless
  values like `havi.test` and then failed at request time.
- **All** — HaviKit armed without a usable base URL no longer takes the host app
  down. It writes a single console line and resolves to its inert state; the
  Expo `start()` still rejects with an error you can catch.
- **iOS** — `HAVI_ENABLED` is read the way the documentation describes:
  `YES`/`true` in any case, with surrounding whitespace, and as a plist boolean
  (which previously failed silently).
- **iOS** — uploads, pairing, and label requests refuse redirects, so the bearer
  token and workspace header are never replayed to a host the SDK never trusted.
  Keychain items are written as after-first-unlock, this-device-only.
- **React Native** — the documented behaviour of `start()` matches the code: the
  first call wins and later calls are ignored.
- **Android** — the stored HAVI credential is encrypted at rest. An
  already-connected device migrates on its next launch and stays connected, with
  no cleartext copy left behind. If the device keystore cannot produce a key,
  pairing keeps working and the weakened storage is recorded in the diagnostics
  that ship with the next report rather than passed over in silence.
- **Android** — a screenshot the device cannot process — a degenerate crop, an
  out-of-memory frame, a failing transport — shows the ordinary "Couldn't
  prepare the screenshot." message instead of crashing the host app.
- **Android** — a report survives Activity recreation. Rotating, switching to
  dark mode, or resizing mid-send no longer cancels the upload and loses the
  report; the sheet comes back on the recreated Activity with the markup,
  comment, and "Sending…" state intact, and settles to sent or to the failure
  banner as usual. System Back now closes the sheet (the connect sheet first,
  when it is layered on top) and is ignored while a report is sending.

### Internal

- Tests and CI: a guard keeping the iOS and Android copies of the golden
  envelope fixture byte-identical, a Jest suite and a TypeScript-to-native
  parity check for the Expo bridge, Android Gradle build/test/lint, an
  Android compile of the Expo example, and `pod lib lint` for the podspec. Expo
  dependencies aligned to a single SDK 57 set.

## [0.2.0] - 2026-07-23

### Added

- **iOS** — workspace labels in capture. The SDK fetches the workspace's label
  vocabulary and renders one control per definition — segmented choice, toggle
  flag, or text value — inside a collapsed **Labels** section on the capture
  details screen. Applied labels travel with the annotation as tagging bodies.
  Priority stays the built-in control, and a workspace that defines no extra
  labels looks exactly as before. A failed or empty fetch falls back to the
  priority control; capture never blocks on it.
- **iOS** — public API (additive): `HaviLabel`, `HaviLabelKind`,
  `HaviLabelDefinition`, `HaviLabelService`, and `HaviEnvelopeInput.labels`.

## [0.1.2] - 2026-07-23

### Added

- **iOS** — sign-out is reachable on device. The capture details screen now
  always shows a HAVI status row: the connect prompt when disconnected, and a
  connected row with a gear when connected. The gear opens the connect sheet on
  its connected card, where **Sign out** sits behind a confirmation dialog. The
  gear is disabled while a report is submitting, and the row is hidden when the
  stored credential is rejected.
- **iOS** — `Havi.disconnect()` clears this device's stored HAVI credential.
  `Havi.signOut()` remains as an alias.

## [0.1.1] - 2026-07-23

### Fixed

- **iOS** — the connect sheet no longer stays stuck on the sign-in prompt after
  approval. Returning from the in-app browser reconciles against the stored
  credential and resumes the same pairing link instead of minting a new code, so
  an approval — on this device or another one — settles the sheet to connected.
- **iOS** — "Connected to HAVI" reads as success rather than an error: the
  confirmation now uses a green checkmark on a frosted success tray.
- **iOS** — sending a report is confirmed by a brief "Report sent" toast,
  reduce-motion gated and announced to VoiceOver, as the capture sheet dismisses.
  Failures keep the existing error with retry.
- **iOS** — annotations carry real viewport and screen metadata. The viewport is
  derived from the captured screenshot itself, so it can no longer arrive as
  "Unknown", and the screen name falls back to a best-effort detected view
  controller when the host sets none. Hosts should still name their screens with
  `.haviScreen(_:)` or `Havi.setScreen(_:)`.

## [0.1.0] - 2026-07-22

First tagged release. iOS only.

### Added

- **iOS** — the `HaviKit` Swift package (iOS 17+, Swift 5.10). Config-gated and
  inert by default: until `HAVI_ENABLED` and a base URL resolve from
  `Info.plist`, every entry point is a no-op.
- **iOS** — capture from inside a running app via shake, two-finger long press,
  or `Havi.capture(screen:)`: a frozen screenshot, a crop tool, a multi-mark
  markup editor, and redaction of masked subtrees burned into the image before
  the bytes leave the device.
- **iOS** — device pairing through an in-app sign-in browser, with the resulting
  credential stored in the Keychain.
- **iOS** — context for each report: console and network breadcrumbs
  (`Havi.log`, `Havi.logNetworkError`), structured host context
  (`.haviContext`), and screen naming (`.haviScreen`, `Havi.setScreen`), all
  scrubbed of secrets.
- **iOS** — reports post to the hosted HAVI service as W3C Web Annotations. The
  envelope is asserted byte-for-byte against the cross-language golden fixture,
  so mobile reports match those from the browser extension and widget.

[Unreleased]: https://github.com/handgemacht-ai/havikit/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/handgemacht-ai/havikit/compare/v0.1.2...v0.2.0
[0.1.2]: https://github.com/handgemacht-ai/havikit/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/handgemacht-ai/havikit/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/handgemacht-ai/havikit/releases/tag/v0.1.0
