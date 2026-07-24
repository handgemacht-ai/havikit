import fs from 'fs';
import path from 'path';

// Bridge-drift guard without a compiler: parse the native module DSLs and the
// TS wrappers straight from source and assert every native method the TS layer
// invokes is actually declared on BOTH the iOS (Swift) and Android (Kotlin)
// modules. A rename on one side that the other side (or the TS layer) misses
// fails here instead of at runtime on a device.
const SWIFT = path.join(__dirname, '..', '..', 'ios', 'HaviKitModule.swift');
const KOTLIN = path.join(
  __dirname,
  '..',
  '..',
  'android',
  'src',
  'main',
  'java',
  'ai',
  'handgemacht',
  'expo',
  'HaviKitModule.kt'
);
const TS_WRAPPERS = path.join(__dirname, '..', 'HaviKit.ts');

// Both Expo module DSLs declare bridge members as `Function("name")` /
// `AsyncFunction("name")`; `Name(...)` and `View(...)` are intentionally not
// matched.
function nativeMemberNames(source: string): string[] {
  const pattern = /\b(?:Async)?Function\(\s*"([^"]+)"/g;
  const names = new Set<string>();
  let match: RegExpExecArray | null;
  while ((match = pattern.exec(source)) !== null) {
    names.add(match[1]);
  }
  return [...names].sort();
}

// Every `HaviKitModule.<name>(` call in the TS wrapper surface.
function invokedNativeNames(source: string): string[] {
  const pattern = /HaviKitModule\.(\w+)\s*\(/g;
  const names = new Set<string>();
  let match: RegExpExecArray | null;
  while ((match = pattern.exec(source)) !== null) {
    names.add(match[1]);
  }
  return [...names].sort();
}

const swiftNames = nativeMemberNames(fs.readFileSync(SWIFT, 'utf8'));
const kotlinNames = nativeMemberNames(fs.readFileSync(KOTLIN, 'utf8'));
const invokedNames = invokedNativeNames(fs.readFileSync(TS_WRAPPERS, 'utf8'));

describe('TS <-> native bridge parity', () => {
  it('parsed a non-trivial member surface from every source', () => {
    // Guards against a silently-broken regex reporting a false all-clear.
    expect(swiftNames.length).toBeGreaterThan(0);
    expect(kotlinNames.length).toBeGreaterThan(0);
    expect(invokedNames.length).toBeGreaterThan(0);
  });

  it('every native method the TS layer invokes exists on both iOS and Android', () => {
    const missingInSwift = invokedNames.filter((name) => !swiftNames.includes(name));
    const missingInKotlin = invokedNames.filter((name) => !kotlinNames.includes(name));
    // A non-empty list names the TS calls with no matching native declaration.
    expect({ missingInSwift, missingInKotlin }).toEqual({
      missingInSwift: [],
      missingInKotlin: [],
    });
  });

  it('the iOS and Android native surfaces declare the same members', () => {
    const iosOnly = swiftNames.filter((name) => !kotlinNames.includes(name));
    const androidOnly = kotlinNames.filter((name) => !swiftNames.includes(name));
    // Either list being non-empty means one platform drifted from the other.
    expect({ iosOnly, androidOnly }).toEqual({ iosOnly: [], androidOnly: [] });
  });
});
