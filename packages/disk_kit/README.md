# DiskKit

A federated Flutter plugin for communicating with storage devices. The initial implementation supports macOS 12 or later. Windows and Linux implementations are planned for future releases.

DiskKit is an early release. Its public API may evolve. The packages are maintained under the [darkfox.pl publisher](https://pub.dev/publishers/darkfox.pl).

## Features

- Discover disks, partitions, and volumes, including those already connected.
- Read BSD identifiers, volume names, mount points, filesystem kinds, sizes, UUIDs, and device properties when available.
- Subscribe to complete disk snapshots after discovery, removal, or description changes.
- Mount, unmount, unmount all volumes on a disk, eject, and rename volumes.
- Copy files and directories from a mounted volume or onto it.
- Format an external volume or an entire external disk as exFAT, FAT32, APFS, or journaled HFS+. Whole-disk formatting supports GPT or MBR; APFS requires GPT.

## Requirements

- Flutter 3.27 or later and Dart 3.6 or later.
- macOS 12 or later, with Xcode installed for development.
- An application running outside App Sandbox for this initial implementation. The included example disables App Sandbox in both debug and release entitlements.

DiskKit does not elevate privileges or install a privileged helper. macOS permissions, disk ownership, files in use, and filesystem compatibility can cause an operation to fail.

## Installation

```sh
flutter pub add disk_kit
```

Or add the first release to your app's `pubspec.yaml`:

```yaml
dependencies:
  disk_kit: ^0.0.1
```

Import `package:disk_kit/disk_kit.dart`. The macOS implementation is installed and registered automatically; applications do not need to add `disk_kit_macos` or `disk_kit_platform_interface` directly.

For development before publication, clone the [workspace](https://github.com/Dark-Fox-PL/disk_kit) and run the included example. It already resolves the workspace packages locally.

## Discovery and notifications

```dart
import 'dart:async';

import 'package:disk_kit/disk_kit.dart';

const DiskKit kit = DiskKit();
final List<DiskInfo> disks = await kit.getDisks();

final StreamSubscription<List<DiskInfo>> subscription = kit.watchDisks().listen(
  (List<DiskInfo> snapshot) {
    for (final DiskInfo disk in snapshot) {
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
final DiskInfo volume = (await kit.getDisks()).singleWhere(
  (DiskInfo disk) => disk.volumeName == 'TEST_USB' &&
      disk.isMounted && disk.isInternal == false,
);

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

Use a freshly discovered target, such as the `volume` selected above. Resolve the containing whole disk separately when needed:

```dart
final DiskInfo wholeDisk = (await kit.getDisks()).singleWhere(
  (DiskInfo disk) => disk.id == volume.wholeDiskId && disk.isWholeDisk == true,
);

final DiskInfo unmountedVolume = await kit.unmount(volume.id);
final DiskInfo mountedVolume = await kit.mount(unmountedVolume.id);
print(mountedVolume.volumePath);

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

## Renaming a volume

```dart
final DiskInfo renamedVolume = await kit.renameVolume(
  volume.id,
  volumeName: 'NEW_USB',
);
print(renamedVolume.volumeName);
print(renamedVolume.volumePath);
```

Renaming preserves file contents. It accepts the same label rules as formatting. macOS may change the mount point, so use the returned description or refresh the snapshot before accessing files. The change also appears in `watchDisks()`.

`mount`, `unmount`, and `renameVolume` return a `DiskInfo` describing the operated target after completion. `unmount(..., wholeDisk: true)` returns the whole-disk description; subscribe to the snapshot stream to observe its individual volumes. `eject`, copies, and formatting return `Future<void>`.

## Native dependency managers

The macOS package includes both a CocoaPods podspec and a Swift Package Manager manifest. SwiftPM imports `FlutterFramework` and links the system Disk Arbitration and IOKit frameworks. See the [Flutter migration guide](https://docs.flutter.dev/packages-and-plugins/swift-package-manager/for-plugin-authors) for enabling SwiftPM in an application.

## Errors

Native failures arrive as `PlatformException`. Handle its `code`, `message`, and optional native `details`:

| Code | Meaning |
| --- | --- |
| `session_unavailable` | The native Disk Arbitration session could not be created. |
| `discovery_failed` | Native device enumeration failed. |
| `disk_not_found` | The target disappeared or could not be resolved. |
| `disk_busy` | Another DiskKit operation is pending on the same whole disk. |
| `invalid_arguments` | Required arguments, a label, filesystem, or scheme are invalid. |
| `invalid_target` | The operation requires a different kind of disk or volume. |
| `protected_disk` | Formatting was requested for internal or unknown media. |
| `volume_not_mounted` | A copy request does not have a mounted volume and both paths. |
| `invalid_path` | A path is invalid or escapes the permitted volume root. |
| `destination_exists` | The copy destination already exists. |
| `operation_failed` | Disk Arbitration rejected a mount, unmount, eject, or rename request. |
| `format_failed` | `diskutil` returned a nonzero exit status. |
| `io_failed` | A filesystem operation or process launch failed. |

Disk Arbitration errors include `operation`, `diskId`, and native `status`. Formatting failures include `exitCode`. Filesystem errors include their NSError `domain` and `status`. Unsupported platforms throw `UnsupportedError`; invalid BSD names throw `ArgumentError` before reaching native code.

## Example and manual testing

The interactive example is in `packages/disk_kit_macos/example` in the [GitHub repository](https://github.com/Dark-Fox-PL/disk_kit/tree/main/packages/disk_kit_macos/example). It uses the public `disk_kit` API.

After cloning the repository, run from the workspace root:

```sh
flutter pub get
cd packages/disk_kit_macos/example
flutter run -d macos
```

The example displays connected external devices and exposes all operations. See the [example guide](https://github.com/Dark-Fox-PL/disk_kit/blob/main/packages/disk_kit_macos/example/README.md) for a copy → format → restore test.

Source: [GitHub](https://github.com/Dark-Fox-PL/disk_kit). Bugs and proposals: [issues](https://github.com/Dark-Fox-PL/disk_kit/issues).

## License

Distributed under the [MIT License](LICENSE). Copyright (c) 2026 ByFox.
