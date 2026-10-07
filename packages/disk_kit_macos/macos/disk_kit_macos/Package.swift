// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "disk_kit_macos",
  platforms: [
    .macOS("12.0")
  ],
  products: [
    .library(name: "disk-kit-macos", targets: ["disk_kit_macos"])
  ],
  dependencies: [
    .package(name: "FlutterFramework", path: "../FlutterFramework")
  ],
  targets: [
    .target(
      name: "disk_kit_macos",
      dependencies: [
        .product(name: "FlutterFramework", package: "FlutterFramework")
      ],
      linkerSettings: [.linkedFramework("DiskArbitration"), .linkedFramework("IOKit")]
    )
  ]
)
