// jest-expo's preset eagerly installs Expo's WinterCG `fetch`, which pulls in
// the native `ExpoFetchModule` binding that does not exist under plain Node and
// crashes the preset's setup before any test runs. These bridge tests mock the
// native layer and never exercise `fetch`, so opt into React Native's own fetch
// to keep the preset's global install from loading Expo's native fetch. Running
// here (before workers fork) lets the flag reach every worker's setup file.
module.exports = () => {
  process.env.EXPO_PUBLIC_USE_RN_FETCH = '1';
};
