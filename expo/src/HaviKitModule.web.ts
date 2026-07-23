import { NativeModule, registerWebModule } from 'expo';

import type { HaviAuthState } from './HaviKit.types';

/**
 * Web is always inert: every entry point is a no-op, `getAuthState()` resolves
 * `unconfigured`, and `getIsEnabled()` is `false`. This lets universal app code
 * call the HaviKit API unconditionally without a platform guard.
 */
class HaviKitWebModule extends NativeModule {
  async start(): Promise<void> {}
  capture(): void {}
  log(): void {}
  logNetworkError(): void {}
  setContext(): void {}
  setTag(): void {}
  setScreen(): void {}
  setPriority(): void {}
  signIn(): void {}
  disconnect(): void {}
  signOut(): void {}
  async getAuthState(): Promise<HaviAuthState> {
    return { status: 'unconfigured' };
  }
  getIsEnabled(): boolean {
    return false;
  }
}

export default registerWebModule(HaviKitWebModule, 'HaviKitModule');
