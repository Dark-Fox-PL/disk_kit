# DiskKit

Flutter package for communicating with storage devices through a shared Dart API. The initial platform target is macOS; Windows and Linux may be added in future releases.

DiskKit is being prepared for publication on [pub.dev](https://pub.dev). The current package is an early scaffold and does not yet expose disk management operations.

## Packages

- [`disk_kit`](https://pub.dev/packages/disk_kit): app-facing package.
- [`disk_kit_platform_interface`](https://pub.dev/packages/disk_kit_platform_interface): shared contract for platform implementations.
- [`disk_kit_macos`](https://pub.dev/packages/disk_kit_macos): macOS implementation, intended to communicate with macOS Disk Arbitration.

## Requirements

- Flutter 3.27.0 or later
- Dart 3.6.0 or later
- macOS for the initial platform implementation

## Installation

The packages are not published yet. During development, add the package from this workspace using a path dependency:

```yaml
dependencies:
  disk_kit:
    path: ../packages/disk_kit
```

After publication, use the version listed on pub.dev.

## Usage

The public disk API is not implemented yet. Usage documentation will be added when the first supported operations are available.

## Development

Run `flutter pub get` from the workspace root to resolve all workspace packages.

Source code is available on [GitHub](https://github.com/Dark-Fox-PL/disk_kit). Report bugs and propose features in the [issue tracker](https://github.com/Dark-Fox-PL/disk_kit/issues).

## License

This package is distributed under the MIT License. See [LICENSE](LICENSE).
