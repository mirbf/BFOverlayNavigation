Pod::Spec.new do |s|
  s.name             = 'BFOverlayNavigation'
  s.version          = '0.1.2'
  s.summary          = 'Overlay-based UINavigationController to avoid system bar button background artifacts and keep stable alignment.'

  s.description      = <<-DESC
BFOverlayNavigation provides an overlay-driven navigation bar interaction model for iOS 13+.

- Overlay back button and right actions (independent from UIBarButtonItem rendering chain)
- Per-page configuration for title/back/right items
- Stable vertical alignment strategy across iPhone and iPad
- Useful for projects needing custom design parity and iOS 26+ visual consistency
  DESC

  s.homepage         = 'https://github.com/mirbf/BFOverlayNavigation'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'BF' => 'dev@mirbf.com' }
  s.source           = { :git => 'https://github.com/mirbf/BFOverlayNavigation.git', :tag => s.version.to_s }

  s.ios.deployment_target = '13.0'
  s.swift_version = '5.0'
  s.requires_arc = true

  s.source_files = 'BFOverlayNavigation/Classes/**/*.{swift}'
  s.frameworks = 'Foundation', 'UIKit'
end
