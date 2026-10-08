// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "disk_kit_macos_extensions",
  platforms: [.macOS("12.0")],
  products: [.library(name: "disk-kit-macos-extensions", targets: ["disk_kit_macos_extensions"])],
  dependencies: [.package(name: "FlutterFramework", path: "../FlutterFramework")],
  targets: [.target(
    name: "disk_kit_macos_extensions",
    dependencies: [.product(name: "FlutterFramework", package: "FlutterFramework")],
    linkerSettings: [.linkedFramework("DiskArbitration"), .linkedFramework("IOKit")]
  )]
)
