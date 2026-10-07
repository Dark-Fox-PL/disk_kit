# DiskKit

A federated Flutter plugin for communicating with storage devices through native platform APIs. The initial implementation targets macOS 12+. Windows and Linux implementations are planned for future releases.

The plugin supports discovery, device properties, live notifications, mounting, unmounting, ejecting, copying files and directories in both directions, and formatting external disks or volumes. This is an experimental implementation; it has not been published on pub.dev yet.

## Workspace

- [`disk_kit`](packages/disk_kit): public Dart API and endorsed platform implementation.
- [`disk_kit_platform_interface`](packages/disk_kit_platform_interface): shared contract and models.
- [`disk_kit_macos`](packages/disk_kit_macos): Disk Arbitration, IOKit, FileManager, and diskutil implementation.

Requires Flutter 3.27+, Dart 3.6+, and Xcode for macOS development. The initial implementation runs outside App Sandbox. It does not elevate privileges.

## Try it

```sh
flutter pub get
cd packages/disk_kit_macos/example
flutter run -d macos
```

Connect a USB drive and use the example to inspect devices and test operations. See the [API documentation](packages/disk_kit/README.md) and [manual testing guide](packages/disk_kit_macos/example/README.md), including copying data off a USB drive, formatting it, and copying the data back.

## Checks

From the workspace root:

```sh
flutter analyze
flutter test packages/disk_kit/test packages/disk_kit_platform_interface/test packages/disk_kit_macos/test
sh tool/test_macos.sh
```

The example guide includes widget and native integration test commands. The ordinary checks do not format disks. A separate destructive integration test requires an explicit target and erase flag.

## License

Copyright (c) 2026 ByFox. Distributed under the [MIT License](LICENSE).
