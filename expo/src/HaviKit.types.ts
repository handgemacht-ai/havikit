import type { ReactNode } from 'react';
import type { ViewProps } from 'react-native';

export type HaviImageFormat = 'png' | 'jpeg';
export type HaviLogLevel = 'debug' | 'info' | 'warning' | 'error';
export type HaviPriority = 'high' | 'medium' | 'low';

/**
 * Mirrors the stamped `HAVI_*` keys (iOS `Info.plist` / Android `<meta-data>`).
 * The native bridge maps this 1:1 into `HaviConfig` on each platform.
 */
export type HaviConfig = {
  /** `HAVI_ENABLED` — the SDK stays inert (a no-op) unless this is `true`. */
  enabled: boolean;
  /** `HAVI_BASE_URL` — REQUIRED when `enabled`; otherwise `start()` rejects. */
  baseUrl: string;
  /** `HAVI_WORKSPACE_ID` */
  workspaceId?: string;
  /** `HAVI_PROJECT` */
  project?: string;
  /** `HAVI_WORKTREE` */
  worktree?: string;
  /** `HAVI_BRANCH` */
  branch?: string;
  /** `HAVI_COMMIT` */
  commit?: string;
  /** `HAVI_IMAGE_FORMAT` — defaults to `'png'`. */
  imageFormat?: HaviImageFormat;
  /** `HAVI_DEV_TOKEN` */
  devToken?: string;
};

export type HaviAuthState =
  | { status: 'unconfigured' }
  | { status: 'authenticated'; workspaceId: string }
  | { status: 'needsReconnect' };

/**
 * Props for the `<HaviOverlay/>` host. Mounted once at the app root; on iOS it
 * hosts the native `.haviOverlay()` capture surface, elsewhere it renders its
 * children unchanged.
 */
export type HaviOverlayProps = ViewProps & {
  children?: ReactNode;
};
