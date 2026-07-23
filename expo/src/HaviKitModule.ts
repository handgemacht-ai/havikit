import { NativeModule, requireNativeModule } from 'expo';

import type { HaviAuthState, HaviConfig, HaviLogLevel, HaviPriority } from './HaviKit.types';

/**
 * The raw native contract, resolved on iOS and Android. Arguments are passed
 * exactly as the native `Function`/`AsyncFunction` handlers expect them —
 * optional values are sent as explicit `null` rather than omitted, so the
 * typed wrappers in `HaviKit.ts` own the ergonomic (optional-argument) surface.
 */
export declare class HaviKitNativeModule extends NativeModule {
  start(config: HaviConfig): Promise<void>;
  capture(screen: string | null): void;
  log(message: string, level: HaviLogLevel | null, category: string | null): void;
  logNetworkError(message: string): void;
  setContext(namespace: string, values: Record<string, string>): void;
  setTag(key: string, value: string): void;
  setScreen(name: string | null): void;
  setPriority(priority: HaviPriority | null): void;
  signIn(token: string, workspaceId: string): void;
  disconnect(): void;
  signOut(): void;
  getAuthState(): Promise<HaviAuthState>;
  getIsEnabled(): boolean;
}

export default requireNativeModule<HaviKitNativeModule>('HaviKit');
