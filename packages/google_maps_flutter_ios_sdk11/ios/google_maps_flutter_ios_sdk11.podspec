Pod::Spec.new do |s|
  s.name             = 'google_maps_flutter_ios_sdk11'
  s.version          = '0.0.1'
  s.summary          = 'Google Maps for Flutter (SDK 11 SPM)'
  s.description      = <<-DESC
SPM-only Google Maps Flutter iOS implementation pinned to Maps SDK 11.3.
CocoaPods GoogleMaps is intentionally omitted to avoid duplicate symbols with google_navigation_flutter.
                       DESC
  s.homepage         = 'https://github.com/flutter/packages'
  s.license          = { :type => 'BSD', :file => '../LICENSE' }
  s.author           = { 'Flutter Dev Team' => 'flutter-dev@googlegroups.com' }
  s.source           = { :path => '.' }
  s.source_files = 'google_maps_flutter_ios_sdk11/Sources/google_maps_flutter_ios_sdk11/**/*.swift'
  s.dependency 'Flutter'
  s.static_framework = true
  s.platform = :ios, '17.0'
  s.swift_version = '5.9'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.resource_bundles = {'google_maps_flutter_ios_sdk11_privacy' => ['google_maps_flutter_ios_sdk11/Sources/google_maps_flutter_ios_sdk11/Resources/PrivacyInfo.xcprivacy']}
end
