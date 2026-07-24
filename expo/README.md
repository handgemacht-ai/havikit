# @handgemacht-ai/expo-havikit

Expo Modules bridge for [HaviKit](https://github.com/handgemacht-ai/havikit) — the
on-device HAVI mobile feedback SDK. Exposes the native iOS (Swift Package) and
Android (Kotlin AAR) SDKs to Expo / React Native apps, with a graceful no-op on
web.

> **Status: pre-release.** The native dependencies this package wraps are not yet
> published — see [Native dependencies](#native-dependencies).

## Install

```sh
npx expo install @handgemacht-ai/expo-havikit
```

Then add the config plugin to your app config so the native build is wired
correctly:

```json
{
  "expo": {
    "plugins": ["@handgemacht-ai/expo-havikit"]
  }
}
```

This package uses native code, so it does not run in Expo Go. Build a
[development build](https://docs.expo.dev/develop/development-builds/introduction/)
(`npx expo prebuild` + `npx expo run:ios` / `run:android`).

## Config plugin

The plugin wires the native build only; it carries no HAVI config values (those
flow at runtime through `start(config)`). It:

- raises the iOS deployment target to **15.0** (HaviKit's floor);
- inserts the iOS SDK pod source into the `Podfile` (`pod 'HaviKit', :git => …`),
  because the SDK is not on the CocoaPods trunk;
- raises the Android `minSdkVersion` to **26** (the AAR's floor);
- registers the Maven repository that serves `ai.handgemacht:havikit`, with
  credentials read from `gpr.user` / `gpr.token` Gradle properties or the
  `GITHUB_ACTOR` / `GITHUB_TOKEN` environment variables.

All values are overridable:

```json
{
  "expo": {
    "plugins": [
      [
        "@handgemacht-ai/expo-havikit",
        {
          "ios": {
            "deploymentTarget": "15.0",
            "gitUrl": "https://github.com/handgemacht-ai/havikit.git",
            "gitTag": "v0.2.0"
          },
          "android": {
            "minSdkVersion": 26,
            "mavenUrl": "https://maven.pkg.github.com/handgemacht-ai/havikit"
          }
        }
      ]
    ]
  }
}
```

| Prop | Default | Purpose |
| --- | --- | --- |
| `ios.deploymentTarget` | `"15.0"` | iOS deployment-target floor. |
| `ios.podName` | `"HaviKit"` | CocoaPods spec name of the wrapped SDK. |
| `ios.gitUrl` | HaviKit repo | Git source for the SDK pod. |
| `ios.gitTag` | `"v0.2.0"` | Git tag to pin (ignored when `gitBranch` is set). |
| `ios.gitBranch` | — | Git branch to track instead of a tag. |
| `android.minSdkVersion` | `26` | `minSdkVersion` floor (only raised, never lowered). |
| `android.mavenUrl` | GitHub Packages | Maven repository serving the AAR. |

## Usage

```tsx
import { StyleSheet } from 'react-native';
import * as HaviKit from '@handgemacht-ai/expo-havikit';
import { HaviOverlay } from '@handgemacht-ai/expo-havikit';

await HaviKit.start({
  enabled: true,
  baseUrl: 'https://havi.example.com',
  workspaceId: 'ws_123',
});

// Mount once at the app root — required on iOS to present the capture sheet.
<HaviOverlay style={StyleSheet.absoluteFill} pointerEvents="box-none" />;

// Later, from anywhere:
HaviKit.setScreen('Checkout');
HaviKit.log('checkout started', 'info', 'app');
HaviKit.capture(); // present the capture sheet programmatically
```

`start(config)` mirrors the stamped `HAVI_*` keys 1:1. `baseUrl` must be an
absolute `http`/`https` URL with a host; when `enabled` is set without one,
`start()` **rejects** with a catchable startup error rather than crashing the
app. When `enabled` is `false` — or `start()` is never called — every entry point
is inert.

## API

| Function | Signature | Notes |
| --- | --- | --- |
| `start` | `(config: HaviConfig) => Promise<void>` | Starts the SDK; the first call wins and later calls are ignored. Rejects when enabled without a valid `baseUrl`. |
| `capture` | `(screen?: string) => void` | Presents the capture sheet, optionally naming the screen. |
| `log` | `(message: string, level?: HaviLogLevel, category?: string) => void` | Appends a breadcrumb (records even when inert). |
| `logNetworkError` | `(message: string) => void` | Records a network/RPC failure line. |
| `setContext` | `(namespace: string, values: Record<string, string>) => void` | Merges structured context. |
| `setTag` | `(key: string, value: string) => void` | Sets a single tag. |
| `setScreen` | `(name: string \| null) => void` | Names the current screen; `null` clears it. |
| `setPriority` | `(priority: HaviPriority \| null) => void` | Seeds the next capture's priority; `null` clears it. |
| `signIn` | `(token: string, workspaceId: string) => void` | Stores a bearer token + workspace id on-device. |
| `disconnect` | `() => void` | Clears this device's stored credential. |
| `signOut` | `() => void` | Alias for `disconnect`. |
| `getAuthState` | `() => Promise<HaviAuthState>` | Reads the resolved auth state. |
| `getIsEnabled` | `() => boolean` | Whether the SDK resolved an enabled config. |
| `isAvailable` | `boolean` (constant) | `true` on native platforms, `false` on web. |

### `<HaviOverlay/>`

```tsx
<HaviOverlay style={StyleSheet.absoluteFill} pointerEvents="box-none">
  {/* optional children */}
</HaviOverlay>
```

Mount once at the app root. On **iOS** it hosts the native `.haviOverlay()`
capture surface (required for the capture sheet and the shake / two-finger
long-press triggers to present). On **Android** and **web** it renders its
children unchanged; Android's capture UI is Activity-scoped and needs no host
view.

### Types

```ts
type HaviImageFormat = 'png' | 'jpeg';
type HaviLogLevel = 'debug' | 'info' | 'warning' | 'error';
type HaviPriority = 'high' | 'medium' | 'low';

type HaviConfig = {
  enabled: boolean; // HAVI_ENABLED
  baseUrl: string; // HAVI_BASE_URL — required when enabled
  workspaceId?: string; // HAVI_WORKSPACE_ID
  project?: string; // HAVI_PROJECT
  worktree?: string; // HAVI_WORKTREE
  branch?: string; // HAVI_BRANCH
  commit?: string; // HAVI_COMMIT
  imageFormat?: HaviImageFormat; // HAVI_IMAGE_FORMAT (default 'png')
  devToken?: string; // HAVI_DEV_TOKEN
};

type HaviAuthState =
  | { status: 'unconfigured' }
  | { status: 'authenticated'; workspaceId: string }
  | { status: 'needsReconnect' };
```

Per-view redaction (`.haviRedacted()` / `.haviReveal()`) is native-only
(SwiftUI / Compose) and is not part of the JS API in v1.

## Platform behaviour

| API | iOS | Android | Web |
| --- | --- | --- | --- |
| `start` / `capture` / `log*` / `set*` / `signIn` / `disconnect` | native | native | no-op |
| `getAuthState` | native | native | `{ status: 'unconfigured' }` |
| `getIsEnabled` | native | native | `false` |
| `isAvailable` | `true` | `true` | `false` |
| `<HaviOverlay/>` | native capture host (required) | passthrough | passthrough |

Triggers on iOS: the two-finger long-press and programmatic `capture()` are the
reliable primary triggers in React Native; shake is best-effort (a focused
`TextInput` can hold first responder).

## Native dependencies

| Platform | Dependency | Minimum | Status |
| --- | --- | --- | --- |
| iOS | `HaviKit` pod (git-tag sourced) | iOS 15.0 | podspec not yet published in the HaviKit repo |
| Android | `ai.handgemacht:havikit` (artifactId `havikit`) | `minSdkVersion` 26 | AAR not yet published to a Maven repository |

- **iOS** depends on the `HaviKit` SDK via CocoaPods (git-tag sourced). SPM inside
  an Expo module is avoided per [expo/expo#37813](https://github.com/expo/expo/issues/37813).
- **Android** depends on `ai.handgemacht:havikit`, which is not on Maven Central;
  the config plugin registers the hosting Maven repository. The `implementation`
  will not resolve until the AAR is published there.

## License

MIT
