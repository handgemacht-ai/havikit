import { isAvailable } from '../HaviKit';
import WebModule from '../HaviKitModule.web';

// Force the web branch of `isAvailable` and give the web module a minimal
// `expo` surface: `registerWebModule` just instantiates the class, and
// `requireNativeModule` is stubbed so importing `../HaviKit` never touches a
// real native bridge. (`jest.mock` is hoisted above these imports.)
jest.mock('react-native', () => ({ Platform: { OS: 'web' } }));
jest.mock('expo', () => ({
  NativeModule: class {},
  registerWebModule: (ModuleClass: new () => unknown) => new ModuleClass(),
  requireNativeModule: () => ({}),
}));

describe('web fallback module is inert', () => {
  it('getIsEnabled() is false', () => {
    expect(WebModule.getIsEnabled()).toBe(false);
  });

  it('getAuthState() resolves to unconfigured', async () => {
    await expect(WebModule.getAuthState()).resolves.toEqual({ status: 'unconfigured' });
  });

  it('start() resolves to a no-op', async () => {
    await expect(WebModule.start()).resolves.toBeUndefined();
  });

  it('every synchronous entry point is a no-op returning undefined', () => {
    expect(WebModule.capture()).toBeUndefined();
    expect(WebModule.log()).toBeUndefined();
    expect(WebModule.logNetworkError()).toBeUndefined();
    expect(WebModule.setContext()).toBeUndefined();
    expect(WebModule.setTag()).toBeUndefined();
    expect(WebModule.setScreen()).toBeUndefined();
    expect(WebModule.setPriority()).toBeUndefined();
    expect(WebModule.signIn()).toBeUndefined();
    expect(WebModule.disconnect()).toBeUndefined();
    expect(WebModule.signOut()).toBeUndefined();
  });
});

describe('isAvailable gating on web', () => {
  it('is false when Platform.OS === "web"', () => {
    expect(isAvailable).toBe(false);
  });
});
