const path = require('path');
const { getDefaultConfig } = require('expo/metro-config');

const projectRoot = __dirname;
const moduleRoot = path.resolve(projectRoot, '..');

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

const config = getDefaultConfig(projectRoot);

config.watchFolders = [moduleRoot];

config.resolver.nodeModulesPaths = [
  path.resolve(projectRoot, 'node_modules'),
  path.resolve(moduleRoot, 'node_modules'),
];

config.resolver.extraNodeModules = {
  '@handgemacht-ai/expo-havikit': moduleRoot,
};

config.resolver.blockList = [
  new RegExp(`^${escapeRegExp(path.resolve(moduleRoot, 'node_modules', 'react'))}\\/.*$`),
  new RegExp(`^${escapeRegExp(path.resolve(moduleRoot, 'node_modules', 'react-native'))}\\/.*$`),
];

module.exports = config;
