// swift-tools-version: 5.9

import PackageDescription

let package = Package(
  name: "google_maps_flutter_ios_sdk11",
  platforms: [
    .iOS("17.0")
  ],
  products: [
    .library(name: "google-maps-flutter-ios-sdk11", targets: ["google_maps_flutter_ios_sdk11"])
  ],
  dependencies: [
    .package(
      url: "https://github.com/googlemaps/ios-maps-sdk",
      exact: "11.3.0"
    ),
    .package(path: "google_maps_ios_utils_ios17"),
  ],
  targets: [
    .target(
      name: "google_maps_flutter_ios_sdk11",
      dependencies: [
        .product(
          name: "GoogleMapsUtils",
          package: "google_maps_ios_utils_ios17"
        ),
        .product(
          name: "GoogleMaps",
          package: "ios-maps-sdk"
        ),
      ],
      resources: [
        .process("Resources")
      ]
    )
  ]
)
