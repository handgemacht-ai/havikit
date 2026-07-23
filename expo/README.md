# @handgemacht-ai/expo-havikit

Expo Modules bridge for [HaviKit](https://github.com/handgemacht-ai/havikit) — the
on-device HAVI mobile feedback SDK. Exposes the native iOS (Swift Package) and
Android (Kotlin AAR) SDKs to Expo / React Native apps, with a graceful no-op on
web.

> Status: pre-release. The native dependencies this package wraps are not yet
> published — see [Native dependencies](#native-dependencies).

## Install

```sh
npx expo install @handgemacht-ai/expo-havikit
```

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

`start(config)` mirrors the stamped `HAVI_*` keys 1:1. When `enabled` is set
without a valid `baseUrl`, `start()` **rejects** (a catchable startup error)
rather than crashing the app. When `enabled` is `false` — or `start()` is never
called — every entry point is inert.

## Platform behaviour

| API | iOS | Android | Web |
| --- | --- | --- | --- |
| `start` / `capture` / `log*` / `set*` / `signIn` / `disconnect` | native | native | no-op |
| `getAuthState` | native | native | `{ status: 'unconfigured' }` |
| `getIsEnabled` | native | native | `false` |
| `isAvailable` | `true` | `true` | `false` |
| `<HaviOverlay/>` | native capture host (required) | passthrough | passthrough |

Per-view redaction (`.haviRedacted()` / `.haviReveal()`) is native-only and not
part of the JS API in v1.

## Native dependencies

- **iOS** depends on the `HaviKit` SDK via CocoaPods (git-tag sourced). SPM inside
  an Expo module is avoided per [expo/expo#37813](https://github.com/expo/expo/issues/37813).
- **Android** depends on `ai.handgemacht:havikit` (artifactId `havikit`), which is
  not yet on Maven Central; the app must register the hosting Maven repository.

The Expo config plugin bumps the iOS deployment target to 17.0, the Android
`minSdkVersion` to 26, and wires the Android Maven repository.
