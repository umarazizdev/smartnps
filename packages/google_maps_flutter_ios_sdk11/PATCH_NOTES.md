# Patch notes

Local iOS implementation for `google_maps_flutter` that uses SwiftPM Google Maps SDK **11.3.0**, matching `google_navigation_flutter`.

## Why

Default `google_maps_flutter_ios` pulls GoogleMaps through CocoaPods (≤10.x). Navigation pulls GoogleMaps 11.3 through SPM. Linking both produced ~1033 duplicate symbols at link time.

## Changes vs upstream `google_maps_flutter_ios_sdk10`

- Renamed package to `google_maps_flutter_ios_sdk11`.
- `Package.swift` pins `ios-maps-sdk` to exact `11.3.0`.
- Vendors a trimmed `google-maps-ios-utils` 7.1.2 with platform raised to iOS 17.
- CocoaPods GoogleMaps / Google-Maps-iOS-Utils dependencies removed from the podspec.
