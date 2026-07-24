import {
  WarningAggregator,
  withDangerousMod,
  withGradleProperties,
  withPodfile,
  withProjectBuildGradle,
  type ConfigPlugin,
} from 'expo/config-plugins';
import { createRunOncePlugin } from 'expo/config-plugins';
import fs from 'fs';
import path from 'path';

const pkg = require('../../package.json') as { name: string; version: string };

/**
 * `@handgemacht-ai/expo-havikit` ships two native SDKs whose build floors sit
 * above the Expo defaults, and an Android artifact that is not on Maven Central.
 * This plugin wires only the *build*, never config values — those flow at runtime
 * through JS `start(config)`.
 */
export type HaviKitPluginProps = {
  ios?: {
    /** iOS deployment-target floor. Default `'15.0'` (the HaviKit SPM floor). */
    deploymentTarget?: string;
    /** CocoaPods spec name of the wrapped SDK. Default `'HaviKit'`. */
    podName?: string;
    /** Git URL the SDK pod is sourced from (not on the CocoaPods trunk). */
    gitUrl?: string;
    /** Git tag to pin (default `'v0.2.0'`). Ignored when `gitBranch` is set. */
    gitTag?: string;
    /** Git branch to track instead of a tag. */
    gitBranch?: string;
    /**
     * Local-development escape hatch: source the `HaviKit` pod from an on-disk
     * checkout via `:path` (resolved from the project root) instead of `:git`.
     * Mutually exclusive with the git-tag/branch form — when set, that form is
     * skipped. Used by this repo's in-tree example app.
     */
    havikitPodPath?: string;
  };
  android?: {
    /** `minSdkVersion` floor. Default `26` (the `ai.handgemacht:havikit` floor). */
    minSdkVersion?: number;
    /** Maven repository serving `ai.handgemacht:havikit`. */
    mavenUrl?: string;
    /**
     * Local-development escape hatch: register `mavenLocal()` (instead of the
     * credentialed GitHub Packages `mavenUrl`) so a `publishToMavenLocal` build
     * of `ai.handgemacht:havikit` resolves without credentials. Mutually
     * exclusive with `mavenUrl`. Used by this repo's in-tree example app.
     */
    useMavenLocal?: boolean;
  };
};

const DEFAULTS = {
  ios: {
    deploymentTarget: '15.0',
    podName: 'HaviKit',
    gitUrl: 'https://github.com/handgemacht-ai/havikit.git',
    gitTag: 'v0.2.0',
  },
  android: {
    minSdkVersion: 26,
    mavenUrl: 'https://maven.pkg.github.com/handgemacht-ai/havikit',
  },
} as const;

/** Semver-ish compare limited to the numeric `a.b.c` fields; returns `a > b`. */
export function isVersionGreater(a: string, b: string): boolean {
  const pa = a.split('.').map((n) => parseInt(n, 10) || 0);
  const pb = b.split('.').map((n) => parseInt(n, 10) || 0);
  const len = Math.max(pa.length, pb.length);
  for (let i = 0; i < len; i++) {
    const da = pa[i] ?? 0;
    const db = pb[i] ?? 0;
    if (da !== db) return da > db;
  }
  return false;
}

/** Inserts a fully-formed `pod` line once, right after `use_expo_modules!`. */
function insertPodLine(contents: string, podName: string, podLine: string): string {
  if (new RegExp(`pod ['"]${podName}['"]`).test(contents)) {
    return contents;
  }
  const anchor = 'use_expo_modules!';
  if (contents.includes(anchor)) {
    return contents.replace(anchor, `${anchor}\n${podLine}`);
  }
  const targetMatch = contents.match(/target ['"][^'"]+['"] do\r?\n/);
  if (targetMatch) {
    const at = contents.indexOf(targetMatch[0]) + targetMatch[0].length;
    return `${contents.slice(0, at)}${podLine}\n${contents.slice(at)}`;
  }
  return contents;
}

/** Inserts the git-sourced SDK pod once, right after `use_expo_modules!`. */
export function addPodDependency(
  contents: string,
  opts: { podName: string; gitUrl: string; ref: { key: string; value: string } }
): string {
  const podLine = `  pod '${opts.podName}', :git => '${opts.gitUrl}', :${opts.ref.key} => '${opts.ref.value}'`;
  return insertPodLine(contents, opts.podName, podLine);
}

/** Inserts the local `:path`-sourced SDK pod once, right after `use_expo_modules!`. */
export function addPodPathDependency(
  contents: string,
  opts: { podName: string; podPath: string }
): string {
  const podLine = `  pod '${opts.podName}', :path => '${opts.podPath}'`;
  return insertPodLine(contents, opts.podName, podLine);
}

/** Adds the credentialed Maven repo once, into `allprojects { repositories { … } }`. */
export function addMavenRepository(contents: string, url: string): string {
  const marker = '// @handgemacht-ai/expo-havikit';
  if (contents.includes(marker)) {
    return contents;
  }
  const block = [
    `    maven { ${marker}`,
    `      url = uri("${url}")`,
    `      credentials {`,
    `        username = (project.findProperty("gpr.user") ?: System.getenv("GITHUB_ACTOR"))?.toString()`,
    `        password = (project.findProperty("gpr.token") ?: System.getenv("GITHUB_TOKEN"))?.toString()`,
    `      }`,
    `    }`,
  ].join('\n');
  const anchor = /allprojects\s*\{\s*repositories\s*\{/;
  if (anchor.test(contents)) {
    return contents.replace(anchor, (matched) => `${matched}\n${block}`);
  }
  return `${contents}\n\nallprojects {\n  repositories {\n${block}\n  }\n}\n`;
}

/** Registers `mavenLocal()` once, into `allprojects { repositories { … } }`. */
export function addMavenLocalRepository(contents: string): string {
  const marker = '// mavenLocal @handgemacht-ai/expo-havikit';
  if (contents.includes(marker)) {
    return contents;
  }
  const block = `    mavenLocal() ${marker}`;
  const anchor = /allprojects\s*\{\s*repositories\s*\{/;
  if (anchor.test(contents)) {
    return contents.replace(anchor, (matched) => `${matched}\n${block}`);
  }
  return `${contents}\n\nallprojects {\n  repositories {\n${block}\n  }\n}\n`;
}

type GradlePropertiesItem =
  | { type: 'comment'; value: string }
  | { type: 'empty' }
  | { type: 'property'; key: string; value: string };

/** Raises `android.minSdkVersion` to at least `minSdkVersion`; never lowers it. */
export function raiseMinSdkVersion(
  items: GradlePropertiesItem[],
  minSdkVersion: number
): GradlePropertiesItem[] {
  const key = 'android.minSdkVersion';
  const existing = items.find(
    (item): item is { type: 'property'; key: string; value: string } =>
      item.type === 'property' && item.key === key
  );
  if (existing) {
    const current = parseInt(existing.value, 10);
    if (!Number.isNaN(current) && current >= minSdkVersion) {
      return items;
    }
    existing.value = String(minSdkVersion);
    return items;
  }
  items.push({ type: 'property', key, value: String(minSdkVersion) });
  return items;
}

const withIosDeploymentTarget: ConfigPlugin<{ deploymentTarget: string }> = (config, { deploymentTarget }) =>
  withDangerousMod(config, [
    'ios',
    async (config) => {
      const filePath = path.join(config.modRequest.platformProjectRoot, 'Podfile.properties.json');
      let json: Record<string, string> = {};
      try {
        json = JSON.parse(await fs.promises.readFile(filePath, 'utf8')) as Record<string, string>;
      } catch {
        json = {};
      }
      const current = json['ios.deploymentTarget'];
      if (!current || isVersionGreater(deploymentTarget, current)) {
        json['ios.deploymentTarget'] = deploymentTarget;
        await fs.promises.writeFile(filePath, `${JSON.stringify(json, null, 2)}\n`);
      }
      return config;
    },
  ]);

const withIosPodSource: ConfigPlugin<{
  podName: string;
  gitUrl: string;
  ref: { key: string; value: string };
}> = (config, opts) =>
  withPodfile(config, (config) => {
    config.modResults.contents = addPodDependency(config.modResults.contents, opts);
    return config;
  });

const withIosPodPath: ConfigPlugin<{ podName: string; podPath: string }> = (config, { podName, podPath }) =>
  withPodfile(config, (config) => {
    const resolved = path.isAbsolute(podPath)
      ? podPath
      : path.resolve(config.modRequest.projectRoot, podPath);
    config.modResults.contents = addPodPathDependency(config.modResults.contents, { podName, podPath: resolved });
    return config;
  });

const withAndroidMinSdk: ConfigPlugin<{ minSdkVersion: number }> = (config, { minSdkVersion }) =>
  withGradleProperties(config, (config) => {
    config.modResults = raiseMinSdkVersion(config.modResults, minSdkVersion);
    return config;
  });

const withAndroidMavenRepo: ConfigPlugin<{ mavenUrl: string }> = (config, { mavenUrl }) =>
  withProjectBuildGradle(config, (config) => {
    if (config.modResults.language !== 'groovy') {
      WarningAggregator.addWarningAndroid(
        'expo-havikit',
        `Cannot add the HaviKit Maven repository to a ${config.modResults.language} build.gradle — add it to your android/build.gradle allprojects.repositories manually.`
      );
      return config;
    }
    config.modResults.contents = addMavenRepository(config.modResults.contents, mavenUrl);
    return config;
  });

const withAndroidMavenLocal: ConfigPlugin = (config) =>
  withProjectBuildGradle(config, (config) => {
    if (config.modResults.language !== 'groovy') {
      WarningAggregator.addWarningAndroid(
        'expo-havikit',
        `Cannot add mavenLocal() to a ${config.modResults.language} build.gradle — add it to your android/build.gradle allprojects.repositories manually.`
      );
      return config;
    }
    config.modResults.contents = addMavenLocalRepository(config.modResults.contents);
    return config;
  });

const withHaviKit: ConfigPlugin<HaviKitPluginProps | void> = (config, props) => {
  const ios = { ...DEFAULTS.ios, ...(props?.ios ?? {}) };
  const android = { ...DEFAULTS.android, ...(props?.android ?? {}) };
  const ref = props?.ios?.gitBranch
    ? { key: 'branch', value: props.ios.gitBranch }
    : { key: 'tag', value: ios.gitTag };

  config = withIosDeploymentTarget(config, { deploymentTarget: ios.deploymentTarget });
  if (props?.ios?.havikitPodPath) {
    config = withIosPodPath(config, { podName: ios.podName, podPath: props.ios.havikitPodPath });
  } else {
    config = withIosPodSource(config, { podName: ios.podName, gitUrl: ios.gitUrl, ref });
  }
  config = withAndroidMinSdk(config, { minSdkVersion: android.minSdkVersion });
  if (props?.android?.useMavenLocal) {
    config = withAndroidMavenLocal(config);
  } else {
    config = withAndroidMavenRepo(config, { mavenUrl: android.mavenUrl });
  }
  return config;
};

export default createRunOncePlugin(withHaviKit, pkg.name, pkg.version);
