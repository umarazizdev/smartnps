# google_maps_flutter_ios_sdk11

Local iOS implementation of `google_maps_flutter` that uses **SwiftPM Google Maps SDK 11.3.0**, matching `google_navigation_flutter`.

## Why

`google_maps_flutter`'s default iOS plugin pulls GoogleMaps via CocoaPods (≤10.x). Navigation pulls GoogleMaps 11.3 via SPM. Linking both caused ~1033 duplicate symbols.

This package replaces the default iOS implementation so both Maps and Navigation share one SPM `ios-maps-sdk` 11.3.0 binary (same approach as excluding `play-services-maps` on Android).

## Notes

- Bundles a trimmed `google-maps-ios-utils` 7.1.2 with platform raised to iOS 17 (required by Maps 11.3).
- CocoaPods GoogleMaps is not used.
- App already targets iOS 17+.
