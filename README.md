# DiskKit workspace

This repository contains the packages that make up DiskKit, a Flutter plugin project for communicating with storage devices through platform APIs.

The initial target is macOS, using Disk Arbitration. Windows and Linux are possible future platform implementations. The repository currently contains generated package scaffolds; disk discovery and other disk operations are not implemented yet.

## Workspace packages

- [`disk_kit`](packages/disk_kit): app-facing Flutter package.
- [`disk_kit_platform_interface`](packages/disk_kit_platform_interface): shared contract for platform implementations.
- [`disk_kit_macos`](packages/disk_kit_macos): macOS plugin implementation.

## Development

Requires Dart 3.6.0 or later and Flutter 3.27.0 or later. From the repository root, run:

```sh
flutter pub get
```

The macOS plugin's generated example app is in `packages/disk_kit_macos/example`.

## Publication

The packages are intended for publication on pub.dev after their public APIs and documentation are ready. Each package is licensed under MIT.

## License

Copyright (c) 2026 ByFox. Distributed under the [MIT License](LICENSE).
