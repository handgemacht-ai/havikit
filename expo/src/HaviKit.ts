import { Platform } from 'react-native';

import type { HaviAuthState, HaviConfig, HaviLogLevel, HaviPriority } from './HaviKit.types';
import HaviKitModule from './HaviKitModule';

/**
 * Starts (or re-arms) the SDK from a JS config. Idempotent natively. Rejects
 * when `config.enabled` is set without a valid `baseUrl` — the catchable
 * counterpart of HaviKit's native fail-fast, rather than a hard runtime crash.
 * On web this resolves to a no-op.
 */
export function start(config: HaviConfig): Promise<void> {
  return HaviKitModule.start(config);
}

/** Programmatically presents the capture sheet. Optionally names the screen. */
export function capture(screen?: string): void {
  HaviKitModule.capture(screen ?? null);
}

/** Appends a breadcrumb to the log ring (records even when the SDK is inert). */
export function log(message: string, level?: HaviLogLevel, category?: string): void {
  HaviKitModule.log(message, level ?? null, category ?? null);
}

/** Records a network/RPC failure; pass a `"METHOD url status statusText"` line. */
export function logNetworkError(message: string): void {
  HaviKitModule.logNetworkError(message);
}

/** Merges structured context into `x:havi.contexts` (secret-scrubbed on send). */
export function setContext(namespace: string, values: Record<string, string>): void {
  HaviKitModule.setContext(namespace, values);
}

/** Sets a single tag into `x:havi.tags`. */
export function setTag(key: string, value: string): void {
  HaviKitModule.setTag(key, value);
}

/** Names the current screen for the next capture; pass `null` to clear it. */
export function setScreen(name: string | null): void {
  HaviKitModule.setScreen(name);
}

/** Seeds the priority applied to the next capture; pass `null` to clear it. */
export function setPriority(priority: HaviPriority | null): void {
  HaviKitModule.setPriority(priority);
}

/** Dev manual-paste sign-in: stores a bearer token + workspace id on-device. */
export function signIn(token: string, workspaceId: string): void {
  HaviKitModule.signIn(token, workspaceId);
}

/** Local sign-out: clears this device's stored HAVI credential. */
export function disconnect(): void {
  HaviKitModule.disconnect();
}

/** Backward-compatible alias for {@link disconnect}. */
export function signOut(): void {
  HaviKitModule.signOut();
}

/** Reads the resolved authentication state. */
export function getAuthState(): Promise<HaviAuthState> {
  return HaviKitModule.getAuthState();
}

/** Whether the SDK resolved an enabled config. */
export function getIsEnabled(): boolean {
  return HaviKitModule.getIsEnabled();
}

/** `true` on native platforms where the bridge is present; `false` on web. */
export const isAvailable: boolean = Platform.OS !== 'web';
