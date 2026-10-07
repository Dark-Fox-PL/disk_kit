# disk_kit_platform_interface

Shared contract and data models for the federated DiskKit Flutter plugin. Applications should use `disk_kit`; platform implementation packages extend `DiskKitPlatform` and install their implementation in `DiskKitPlatform.instance`.

The contract covers disk snapshots, live notifications, mounting, unmounting, ejecting, renaming volumes, copying files in both directions, and formatting volumes or whole disks. `DiskInfo` represents devices, partitions, and volumes. Unknown native properties remain nullable. `DiskFileSystem` and `DiskPartitionScheme` describe formatting options.

The default implementation reports `UnsupportedError`. Future Windows and Linux packages can implement the contract independently of the macOS transport.

See the [public API guide](https://github.com/Dark-Fox-PL/disk_kit/blob/main/packages/disk_kit/README.md). Run `flutter pub get` from the workspace root before development.

[Source and issues](https://github.com/Dark-Fox-PL/disk_kit). Distributed under the [MIT License](LICENSE).

Publisher: [darkfox.pl](https://pub.dev/publishers/darkfox.pl).
