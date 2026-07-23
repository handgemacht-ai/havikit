import * as React from 'react';

import type { HaviOverlayProps } from './HaviKit.types';

/** Web has no capture surface — the overlay renders its children unchanged. */
export function HaviOverlay(props: HaviOverlayProps) {
  return <>{props.children ?? null}</>;
}

export default HaviOverlay;
