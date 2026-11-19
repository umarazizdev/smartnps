// swift-tools-version:5.9

import PackageDescription

let package = Package(
  name: "GoogleMapsUtils",
  platforms: [
    .iOS("17.0"),
  ],
  products: [
    .library(
      name: "GoogleMapsUtils",
      targets: ["GoogleMapsUtils", "GoogleMapsUtilsObjC"]),
  ],
  dependencies: [
    .package(
      url: "https://github.com/googlemaps/ios-maps-sdk",
      "10.0.0"..<"12.0.0"),
  ],
  targets: [
    .target(
      name: "GoogleMapsUtilsObjC",
      dependencies: [
        .product(name: "GoogleMaps", package: "ios-maps-sdk"),
      ],
      publicHeadersPath: "include",
      cSettings: [
          .headerSearchPath("."),
      ],
      linkerSettings: [
        .linkedFramework("UIKit", .when(platforms: [.iOS])),
      ]
    ),
    .target(
      name: "GoogleMapsUtils",
      dependencies: [
        .target(name: "GoogleMapsUtilsObjC"),
        .product(name: "GoogleMaps", package: "ios-maps-sdk"),
      ]
    ),
  ]
)
