import { requireNativeModule } from 'expo';

import * as HaviKit from '../HaviKit';
import type { HaviConfig } from '../HaviKit.types';

// The native bridge is mocked at the `requireNativeModule('HaviKit')` seam:
// `HaviKitModule.ts` resolves its default export through it, so these tests
// exercise the real `HaviKit.ts` wrappers against a fake native module and
// assert the method name + argument shape each wrapper forwards.
jest.mock('expo', () => {
  const native = {
    start: jest.fn(() => Promise.resolve()),
    capture: jest.fn(),
    log: jest.fn(),
    logNetworkError: jest.fn(),
    setContext: jest.fn(),
    setTag: jest.fn(),
    setScreen: jest.fn(),
    setPriority: jest.fn(),
    signIn: jest.fn(),
    disconnect: jest.fn(),
    signOut: jest.fn(),
    getAuthState: jest.fn(() => Promise.resolve({ status: 'unconfigured' })),
    getIsEnabled: jest.fn(() => false),
  };
  return {
    NativeModule: class {},
    requireNativeModule: jest.fn(() => native),
  };
});

// The same singleton `HaviKitModule.ts` resolved at import time.
const native = (requireNativeModule as jest.Mock)('HaviKit');

beforeEach(() => {
  jest.clearAllMocks();
});

describe('HaviKit native wrappers forward to the bridge', () => {
  it('start() passes the config object straight through and returns a promise', async () => {
    const config: HaviConfig = { enabled: true, baseUrl: 'https://havi.example' };
    await expect(HaviKit.start(config)).resolves.toBeUndefined();
    expect(native.start).toHaveBeenCalledTimes(1);
    expect(native.start).toHaveBeenCalledWith(config);
  });

  it('capture() normalizes the optional screen to explicit null', () => {
    HaviKit.capture();
    expect(native.capture).toHaveBeenCalledWith(null);
  });

  it('capture(screen) forwards the named screen', () => {
    HaviKit.capture('Checkout');
    expect(native.capture).toHaveBeenCalledWith('Checkout');
  });

  it('log() sends explicit nulls for the optional level and category', () => {
    HaviKit.log('boom');
    expect(native.log).toHaveBeenCalledWith('boom', null, null);
  });

  it('log(message, level, category) forwards all three', () => {
    HaviKit.log('boom', 'error', 'network');
    expect(native.log).toHaveBeenCalledWith('boom', 'error', 'network');
  });

  it('logNetworkError() forwards the message', () => {
    HaviKit.logNetworkError('GET /x 500 Internal');
    expect(native.logNetworkError).toHaveBeenCalledWith('GET /x 500 Internal');
  });

  it('setContext() forwards the namespace and values map', () => {
    HaviKit.setContext('order', { id: '42' });
    expect(native.setContext).toHaveBeenCalledWith('order', { id: '42' });
  });

  it('setTag() forwards the key/value pair', () => {
    HaviKit.setTag('build', '1234');
    expect(native.setTag).toHaveBeenCalledWith('build', '1234');
  });

  it('setScreen() forwards the name and passes null through unchanged', () => {
    HaviKit.setScreen('Home');
    expect(native.setScreen).toHaveBeenCalledWith('Home');
    HaviKit.setScreen(null);
    expect(native.setScreen).toHaveBeenLastCalledWith(null);
  });

  it('setPriority() forwards the priority and passes null through unchanged', () => {
    HaviKit.setPriority('high');
    expect(native.setPriority).toHaveBeenCalledWith('high');
    HaviKit.setPriority(null);
    expect(native.setPriority).toHaveBeenLastCalledWith(null);
  });

  it('signIn() forwards the token and workspace id', () => {
    HaviKit.signIn('tok', 'ws_1');
    expect(native.signIn).toHaveBeenCalledWith('tok', 'ws_1');
  });

  it('disconnect() forwards with no arguments', () => {
    HaviKit.disconnect();
    expect(native.disconnect).toHaveBeenCalledWith();
  });

  it('signOut() forwards with no arguments', () => {
    HaviKit.signOut();
    expect(native.signOut).toHaveBeenCalledWith();
  });

  it('getAuthState() returns the native promise', async () => {
    await expect(HaviKit.getAuthState()).resolves.toEqual({ status: 'unconfigured' });
    expect(native.getAuthState).toHaveBeenCalledTimes(1);
  });

  it('getIsEnabled() returns the native value', () => {
    expect(HaviKit.getIsEnabled()).toBe(false);
    expect(native.getIsEnabled).toHaveBeenCalledTimes(1);
  });
});

describe('isAvailable gating', () => {
  it('is true on a native platform (Platform.OS !== "web")', () => {
    expect(HaviKit.isAvailable).toBe(true);
  });
});
