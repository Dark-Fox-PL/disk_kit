# disk_kit_macos

macOS implementation of the federated DiskKit Flutter plugin. Applications should depend on and import `disk_kit`; this package registers automatically.

The plugin uses Disk Arbitration for descriptions, notifications, mounting, unmounting, and ejecting. IOKit enumerates existing IOMedia objects for initial discovery. `FileManager` copies files and directories on a serial background queue. `/usr/sbin/diskutil` performs formatting using explicit process arguments without a shell.

Requires macOS 12+, Flutter 3.27+, and Dart 3.6+. The first version requires an application outside App Sandbox and does not elevate privileges. Formatting is limited to media identified as external. Operating system restrictions are returned as structured errors.

The native and Dart method/event channels are `eu.byfox.disk_kit/methods` and `eu.byfox.disk_kit/disks`. Native requests targeting the same containing whole disk are rejected while another DiskKit operation on it is pending.

See the [public API guide](https://github.com/Dark-Fox-PL/disk_kit/blob/main/packages/disk_kit/README.md) and the [example testing guide](https://github.com/Dark-Fox-PL/disk_kit/blob/main/packages/disk_kit_macos/example/README.md).

## Development

Run `flutter pub get` from the workspace root. Native filesystem tests can be run independently with `sh tool/test_macos.sh`; they only use temporary files and validate formatting arguments without launching a format operation.

[Source and issues](https://github.com/Dark-Fox-PL/disk_kit). Distributed under the [MIT License](LICENSE).

Publisher: [darkfox.pl](https://pub.dev/publishers/darkfox.pl).

## Native dependency managers

The package supports CocoaPods and Swift Package Manager. Its SwiftPM product is `disk-kit-macos`; the target imports `FlutterFramework` and links Disk Arbitration and IOKit. Current SwiftPM builds and native channel tests were verified using Flutter 3.47.5. CocoaPods remains available for applications using older supported Flutter versions.

The manifest follows the [official Flutter plugin guide](https://docs.flutter.dev/packages-and-plugins/swift-package-manager/for-plugin-authors). Flutter generates the `FlutterFramework` dependency while integrating the consuming application; running `swift build` directly inside the published plugin is not the application integration test.
