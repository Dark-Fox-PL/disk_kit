# disk_kit_platform_interface

Shared contract and data models for the federated DiskKit Flutter plugin. Applications should use `disk_kit`; platform implementation packages extend `DiskKitPlatform` and install their implementation in `DiskKitPlatform.instance`.

The contract covers disk snapshots, live notifications, mounting, unmounting, ejecting, renaming volumes, copying files in both directions, and formatting volumes or whole disks. `DiskInfo` represents devices, partitions, and volumes. Unknown native properties remain nullable. `DiskFileSystem` and `DiskPartitionScheme` describe formatting options.

The default implementation reports `UnsupportedError`. Future Windows and Linux packages can implement the contract independently of the macOS transport.

See the [public API guide](https://github.com/Dark-Fox-PL/disk_kit/blob/main/packages/disk_kit/README.md). Run `flutter pub get` from the workspace root before development.

[Source and issues](https://github.com/Dark-Fox-PL/disk_kit). Distributed under the [MIT License](LICENSE).

Publisher: [darkfox.pl](https://pub.dev/publishers/darkfox.pl).

## Installation media contract

The interface includes `writeImage`, `createWindowsInstaller`, and `createMacOSInstaller`, each returning `Future<void>`. Optional `MediaProgressCallback` receives typed `MediaOperationProgress` with a `MediaOperationStage` and nullable stage byte counters. Existing platform implementations inherit unsupported defaults for these methods. Callers must confirm whole-disk erasure; boot compatibility depends on the source and destination computer.

## Copy contract and migration to 2.0.0

`copyFromDisk` and `copyToDisk` return `Future<void>` and now accept optional
named `bool parallel = true` and `FileCopyProgressCallback? onProgress`.
This is a breaking signature change for platform implementations and mocks
that override these methods; add both named parameters even if a platform
cannot yet implement parallel copying or progress.

`FileCopyProgress` contains the absolute source `path`, file-size `bytes`, and
`completed`. Start events (`completed: false`) must not be counted as copied
bytes. A completion event reports one successful file copy, not success of the
entire operation; callers must await the future. Callbacks can arrive out of
order across files under parallel I/O. These events provide no chunk progress,
in-flight cancellation or checksum verification. Partial destinations must be
retained on failure; no merge or overwrite is allowed.

The macOS implementation defaults to at most four workers per copy. Disabling
parallel I/O limits it to one worker while leaving the future asynchronous.
Existing application calls through the public `disk_kit` API remain valid.
