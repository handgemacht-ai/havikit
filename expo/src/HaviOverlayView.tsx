import { requireNativeView } from 'expo';
import * as React from 'react';
import { Platform } from 'react-native';

import type { HaviOverlayProps } from './HaviKit.types';

/**
 * On iOS the capture sheet is presented by a SwiftUI `.haviOverlay()` mounted in
 * the live window hierarchy, so the bridge exposes a native host view. Mount it
 * once at the app root:
 *
 * ```tsx
 * <HaviOverlay style={StyleSheet.absoluteFill} pointerEvents="box-none" />
 * ```
 *
 * On Android the capture UI is Activity-scoped (no host view is required) and on
 * web there is nothing to present, so both platforms render `children` unchanged.
 */
const NativeHaviOverlayView: React.ComponentType<HaviOverlayProps> | null =
  Platform.OS === 'ios' ? requireNativeView('HaviKit', 'HaviOverlayView') : null;

export function HaviOverlay(props: HaviOverlayProps) {
  if (NativeHaviOverlayView) {
    return <NativeHaviOverlayView {...props} />;
  }
  return <>{props.children ?? null}</>;
}

export default HaviOverlay;
