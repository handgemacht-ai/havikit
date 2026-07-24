require 'json'

package = JSON.parse(File.read(File.join(__dir__, '..', 'package.json')))

# Dependency strategy (BRIDGE DESIGN SPEC §0, §5): the wrapped native SDK is
# pulled in as a CocoaPods dependency on the `HaviKit` pod — a hand-written,
# git-tag-sourced spec published in the handgemacht-ai/havikit repo (zero
# third-party deps: only UIKit / SwiftUI / Foundation). The app's Podfile
# supplies the git source line (`pod 'HaviKit', :git => '…', :tag => 'v<x>'`),
# injected by this package's Expo config plugin. The SPM-inside-Expo path is
# deliberately NOT used: expo/expo#37813 (duplicate-symbol link errors, closed
# stale/unresolved on Expo ~53 / RN 0.79) makes it unsafe today; a plain pod
# dependency is trivial and stable for a zero-dependency SDK, and mirrors the
# Android side (a versioned, published artifact).
#
# Pod naming: this Expo bridge pod is `ExpoHaviKit` so its Swift module does not
# collide with the wrapped SDK's `HaviKit` module (two pods cannot share a name,
# and the bridge must `import HaviKit`). The JS module name stays `HaviKit` via
# the Swift `Name("HaviKit")` definition, which is independent of the pod name.
Pod::Spec.new do |s|
  s.name           = 'ExpoHaviKit'
  s.version        = package['version']
  s.summary        = package['description']
  s.description    = package['description']
  s.license        = package['license']
  s.author         = package['author']
  s.homepage       = package['homepage']
  s.platform       = :ios, '15.0'
  s.swift_version  = '5.10'
  s.source         = { git: 'https://github.com/handgemacht-ai/havikit.git', tag: "v#{s.version}" }
  s.static_framework = true

  s.dependency 'ExpoModulesCore'
  # The wrapped native SDK. Version is pinned by the git :tag the app's Podfile
  # (config plugin) supplies, so it is intentionally left unconstrained here.
  s.dependency 'HaviKit'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'SWIFT_COMPILATION_MODE' => 'wholemodule'
  }

  s.source_files = 'HaviKitModule.swift', 'HaviOverlayView.swift'
end
