# DiskKit

A federated Flutter plugin for communicating with storage devices. The initial implementation supports macOS 12 or later. Windows and Linux implementations are planned for future releases.

This is an experimental implementation under development; the packages are not published on pub.dev yet.

## Features

- Discover disks, partitions, and volumes, including those already connected.
- Read BSD identifiers, volume names, mount points, filesystem kinds, sizes, UUIDs, and device properties when available.
- Subscribe to complete disk snapshots after discovery, removal, or description changes.
- Mount, unmount, unmount all volumes on a disk, and eject.
- Copy files and directories from a mounted volume or onto it.
- Format an external volume or an entire external disk as exFAT, FAT32, APFS, or journaled HFS+. Whole-disk formatting supports GPT or MBR; APFS requires GPT.

## Requirements

- Flutter 3.27 or later and Dart 3.6 or later.
- macOS 12 or later, with Xcode installed for development.
- An application running outside App Sandbox for this initial implementation. The included example disables App Sandbox in both debug and release entitlements.

DiskKit does not elevate privileges or install a privileged helper. macOS permissions, disk ownership, files in use, and filesystem compatibility can cause an operation to fail.

## Installation during development

Add the local package to a Flutter app:

```yaml
dependencies:
  disk_kit:
    path: /absolute/path/to/disk_kit/packages/disk_kit

dependency_overrides:
  disk_kit_macos:
    path: /absolute/path/to/disk_kit/packages/disk_kit_macos
  disk_kit_platform_interface:
    path: /absolute/path/to/disk_kit/packages/disk_kit_platform_interface
```

Overrides resolve the implementation packages until they are published. The macOS plugin registers automatically; import `disk_kit` in application code.

## Discovery and notifications

```dart
import 'package:disk_kit/disk_kit.dart';

const kit = DiskKit();
final disks = await kit.getDisks();

final subscription = kit.watchDisks().listen(
  (snapshot) {
    for (final disk in snapshot) {
      print('${disk.id}: ${disk.volumeName} at ${disk.volumePath}');
    }
  },
  onError: (Object error) => print(error),
);

// Cancel when the consumer is disposed.
await subscription.cancel();
```

The first listener receives an initial snapshot. Additional listeners joining an active broadcast stream receive future updates. After the last listener cancels, a new subscription receives another initial snapshot. One device can have several entries: a whole disk plus its partitions and volumes.

`DiskInfo` properties are nullable when macOS does not provide them. The native `msdos` filesystem kind does not identify the exact FAT variant. An external USB disk is not necessarily marked removable; use `isInternal == false` to select explicitly external media.

On macOS IDs are BSD names such as `disk4` and `disk4s1`. They can change or be reused after removal. Refresh and identify the intended device before operating on it; UUID properties can help when available.

## Copying

Select a mounted volume from discovery, then use its ID:

```dart
await kit.copyFromDisk(
  volume.id,
  relativePath: 'Documents',
  destinationPath: '/Users/you/Desktop/Documents-backup',
);

await kit.copyToDisk(
  volume.id,
  sourcePath: '/Users/you/Desktop/Documents-backup',
  relativePath: 'Documents-restored',
);
```

Local paths must be absolute; volume paths must be relative to the volume's mount point. The destination must not exist and its parent directory must exist. Directory copies are recursive. `.` selects the volume root; protected system metadata may prevent copying an entire root. Prefer explicitly selected user directories.

Traversal outside the volume is rejected, including paths that resolve through a symlink to outside it. Symlinks inside copied directories are preserved. Copying between filesystems may fail for unsupported names, large files, symlinks, or metadata. A failed copy can leave partial destination data. The first version has no progress reporting, cancellation, checksum verification, merging, or overwriting.

## Mounting and formatting

```dart
await kit.unmount(volume.id);
await kit.mount(volume.id);

// Destructive: erases only this target volume's data.
await kit.formatVolume(
  volume.id,
  fileSystem: DiskFileSystem.exFat,
  volumeName: 'DISKKIT',
);

// Destructive: erases every partition and creates one new volume.
await kit.formatDisk(
  wholeDisk.id,
  fileSystem: DiskFileSystem.exFat,
  volumeName: 'DISKKIT',
  partitionScheme: DiskPartitionScheme.gpt,
);

await kit.unmount(wholeDisk.id, wholeDisk: true);
await kit.eject(wholeDisk.id);
```

Formatting is restricted to media positively identified by macOS as external. `formatVolume` requires a partition or volume; `formatDisk` requires a whole disk. APFS containers have additional system constraints; `diskutil` can reject volume-level conversions. Formatting delegates unmounting to `diskutil`; mount and unmount requests do not use force. Callers must confirm destructive operations with their users. DiskKit does not automatically back up or restore files.

An exFAT label is limited to 15 UTF-16 units. The initial FAT32 label validation accepts 1–11 uppercase ASCII letters, digits, underscores, or spaces. Other format and size restrictions are enforced by macOS.

## Errors

Native failures arrive as `PlatformException`, with codes such as `disk_not_found`, `disk_busy`, `operation_failed`, `volume_not_mounted`, `destination_exists`, `invalid_path`, `invalid_target`, `protected_disk`, `format_failed`, or `io_failed`. Details include the native status or `diskutil` exit code when available. Unsupported platforms throw `UnsupportedError`; invalid BSD names throw `ArgumentError` before reaching native code.

## Manual testing

From the workspace root:

```sh
flutter pub get
cd packages/disk_kit_macos/example
flutter run -d macos
```

The example displays connected external devices and exposes all operations. See the [example guide](../disk_kit_macos/example/README.md) for a copy → format → restore test.

Source: [GitHub](https://github.com/Dark-Fox-PL/disk_kit). Bugs and proposals: [issues](https://github.com/Dark-Fox-PL/disk_kit/issues).

## License

Distributed under the [MIT License](LICENSE). Copyright (c) 2026 ByFox.
