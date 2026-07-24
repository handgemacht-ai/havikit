Pod::Spec.new do |s|
  s.name             = 'HaviKit'
  s.version          = '0.2.0'
  s.summary          = 'The on-device HAVI mobile feedback SDK for iOS.'
  s.description      = <<-DESC
    HaviKit lets a developer or QA capture a visual and technical observation
    from inside a running iOS app — a screenshot with markup, the device/app
    context, and recent console/network breadcrumbs — and post it to the hosted
    HAVI service as a W3C Web Annotation. Config-gated and inert by default.
  DESC
  s.homepage         = 'https://github.com/handgemacht-ai/havikit'
  s.license          = { :type => 'MIT' }
  s.author           = 'handgemacht-ai'
  s.source           = { :git => 'https://github.com/handgemacht-ai/havikit.git', :tag => "v#{s.version}" }

  s.ios.deployment_target = '15.0'
  s.swift_version    = '5.10'

  s.source_files     = 'Sources/HaviKit/**/*.swift'
end
