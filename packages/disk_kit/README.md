# DiskKit

A federated Flutter plugin for communicating with storage devices. The initial implementation supports macOS 12 or later. Windows and Linux implementations are planned for future releases.

DiskKit 1.0 provides disk operations and installation-media preparation. The packages are maintained under the [darkfox.pl publisher](https://pub.dev/publishers/darkfox.pl).

## Features

- Discover disks, partitions, and volumes, including those already connected.
- Read BSD identifiers, volume names, mount points, filesystem kinds, sizes, UUIDs, and device properties when available.
- Subscribe to complete disk snapshots after discovery, removal, or description changes.
- Mount, unmount, unmount all volumes on a disk, eject, and rename volumes.
- Copy files and directories from a mounted volume or onto it.
- Write uncompressed IMG / USB-compatible hybrid ISO images, with optional read-back verification.
- Create Windows UEFI installers from ISO, including oversized WIM splitting through caller-installed wimlib.
- Create macOS installation media from a complete Apple installer app.
- Format an external volume or an entire external disk as exFAT, FAT32, APFS, or HFS+, including case-sensitive APFS and journaled/non-journaled HFS+ variants. Whole-disk formatting supports GPT or MBR; both APFS variants require GPT.

## Requirements

- Flutter 3.27 or later and Dart 3.6 or later.
- macOS 12 or later, with Xcode installed for development.
- An application running outside App Sandbox for this initial implementation. The included example disables App Sandbox in both debug and release entitlements.

Raw-image writing and macOS installer preparation can request administrator authorization through system dialogs (`allowElevation: true`, the default). DiskKit never collects passwords and does not install a persistent privileged helper. Raw disk access can additionally require the host app to have Files and Folders / Full Disk Access permission in macOS Privacy & Security settings, even after administrator authorization. DiskKit cannot grant that permission; restart the app after changing it. See [Apple’s file access documentation](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox). Other operations retain the application’s current privileges. macOS permissions, disk ownership, files in use, and filesystem compatibility can cause failures.

## Installation

```sh
flutter pub add disk_kit
```

Or add the package to your app's `pubspec.yaml`:

```yaml
dependencies:
  disk_kit: ^1.1.0
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

Traversal outside the volume is rejected, including paths that resolve through a symlink to outside it. Symlinks inside copied directories are preserved. Copying between filesystems may fail for unsupported names, large files, symlinks, or metadata. A failed copy can leave partial destination data. These ordinary file-copy methods have no progress reporting, cancellation, checksum verification, merging, or overwriting. Media operations below have their own progress and verification options.

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

Supported formatting options:

| `DiskFileSystem` | Filesystem | Case-sensitive | Journaled | Whole-disk partition scheme |
| --- | --- | --- | --- | --- |
| `exFat` | exFAT | No | No | GPT or MBR |
| `fat32` | FAT32 | No | No | GPT or MBR |
| `apfs` | APFS | No | Not applicable | GPT |
| `apfsCaseSensitive` | APFS | Yes | Not applicable | GPT |
| `hfsPlus` | HFS+ | No | Yes | GPT or MBR |
| `hfsPlusNonJournaled` | HFS+ | No | No | GPT or MBR |
| `hfsPlusCaseSensitive` | HFS+ | Yes | No | GPT or MBR |
| `hfsPlusCaseSensitiveJournaled` | HFS+ | Yes | Yes | GPT or MBR |

`DiskFileSystem.requiresGpt` identifies the two APFS choices. Case-sensitive
filesystems treat names such as `File.txt` and `file.txt` as different files.
Encrypted formatting is not exposed by this API.

Select `DiskFileSystem.hfsPlus` for journaled, case-insensitive **HFS+ (Mac OS Extended, Journaled)**:

```dart
await kit.formatDisk(
  wholeDisk.id,
  fileSystem: DiskFileSystem.hfsPlus,
  volumeName: 'MAC_USB',
  partitionScheme: DiskPartitionScheme.gpt,
);
```

This erases the entire selected external disk. Use `formatVolume` with the same
filesystem option to format a single volume while keeping its partition table.

An exFAT label is limited to 15 UTF-16 units. The initial FAT32 label validation accepts 1–11 uppercase ASCII letters, digits, underscores, or spaces. Other format and size restrictions are enforced by macOS.

## Optional macOS filesystem extensions

[`disk_kit_macos_extensions`](https://github.com/Dark-Fox-PL/disk_kit/tree/main/packages/disk_kit_macos_extensions)
is a separate optional package. **Add and import it explicitly** to use additional
filesystem tools; the core DiskKit packages do not depend on it.

Its initial 0.1.0 implementation discovers caller-supplied or separately installed
macOS builds of `mkntfs` and `mke2fs` for NTFS and ext2/ext3/ext4 formatting of
existing external physical data partitions. It reports formatter availability
separately from access to mounted volumes. Btrfs formatting remains unavailable.
The extension does not bundle or install tools or drivers, repartition disks,
or elevate privileges. Device permissions and compatible third-party filesystem
support are still required. See its README for setup, API, and limitations.

Version 1.1.0 of the core package continues to format only the native filesystems
listed above. Additional filesystem support is provided through the extension's
separate API.

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

## Images and installation media

All three operations below erase **every partition and file** on an external whole disk. Confirm deletion in your application and select a freshly discovered `DiskInfo` with `isWholeDisk == true`, `isInternal == false`, and `isWritable == true`. Keep the source and required tools on another disk. There is no cancellation, automatic backup, or rollback; failures can leave partially written media.

| Method | Source | Prepared media |
| --- | --- | --- |
| `writeImage` | Uncompressed `.img` or hybrid `.iso` | Exact image bytes, including its partition layout; suitable for Ubuntu hybrid ISOs. |
| `createWindowsInstaller` | Windows setup `.iso` | MBR + FAT32, files copied for **UEFI** boot. Legacy BIOS is unsupported. |
| `createMacOSInstaller` | Full Apple `Install macOS … .app` | GPT + journaled HFS+, then Apple's `createinstallmedia`. ISO/DMG containers are not accepted. |

```dart
void reportProgress(MediaOperationProgress progress) {
  print('${progress.diskId}: ${progress.stage.name} ${progress.fraction}');
}

// The application has already obtained explicit permission to erase wholeDisk.
await kit.writeImage(
  wholeDisk.id,
  imagePath: '/Users/you/Downloads/ubuntu.iso',
  verify: true,
  onProgress: reportProgress,
);

// Alternative operation, also destructive:
await kit.createWindowsInstaller(
  wholeDisk.id,
  isoPath: '/Users/you/Downloads/windows.iso',
  // Optional; otherwise checks the usual Apple Silicon / Intel Homebrew paths.
  wimlibPath: '/opt/homebrew/bin/wimlib-imagex',
  onProgress: reportProgress,
);

// Alternative operation, also destructive:
await kit.createMacOSInstaller(
  wholeDisk.id,
  installerAppPath: '/Applications/Install macOS Sequoia.app',
  onProgress: reportProgress,
);
```

These are alternatives, not a sequence to run on the same USB drive. Rediscover target IDs between separate operations; partition IDs and mount points can change.

### Raw images / Ubuntu

`writeImage` writes to the raw device, rather than storing the image as a file. Images must fit the disk and have a size divisible by 512 bytes. ISO preflight requires an MBR partition signature or GPT header and rejects ordinary optical-only ISOs before unmounting. This structural check does not guarantee bootability. Ubuntu publishes USB-compatible hybrid ISOs; choose an architecture supported by the destination computer. See [Ubuntu's USB guide](https://documentation.ubuntu.com/desktop/en/latest/how-to/create-a-bootable-usb-stick/).

Disk Arbitration unmounts all volumes without force, claims the disk, and blocks mounting during writing. Writing and read-back use native file descriptors with device identity checked again after authorization. When necessary, `authopen` obtains read/write access to the existing raw device and transfers only that descriptor to the app over a Unix socket. No privileged raw writer continues after the app closes. `allowElevation: false` uses current raw-device privileges. `verify: true` compares the image-length destination bytes; trailing disk capacity is not verified or securely erased. Source authenticity and publisher checksums are the application's responsibility. Disconnect/reconnect the drive after writing if macOS has not refreshed the new partition layout; macOS cannot mount every Linux filesystem.

### Windows

A genuine Windows setup ISO must contain `sources/boot.wim`, installation WIM/ESD/SWM files, and a recognized EFI bootloader. The plugin mounts the ISO read-only, checks FAT32 filename and size compatibility, then copies into a freshly formatted MBR/FAT32 volume. Target boot architecture and Secure Boot trust depend on the chosen ISO and destination firmware. See [Microsoft's USB preparation guide](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/install-windows-from-a-usb-flash-drive?view=windows-11).

FAT32's maximum file size is 4,294,967,295 bytes. Oversized `sources/install.wim` is split into `install.swm`, `install2.swm`, etc. using **wimlib-imagex**, which the consuming application/user must install or supply; DiskKit does not download it. Typical developer setup: `brew install wimlib`. Custom `wimlibPath` executables are run with the application's privileges, never as administrator. Splitting happens **before disk erasure** and requires temporary free space on the Mac. A WIM resource too large to split below FAT32's limit is rejected. Oversized ESD and other oversized files are rejected before erasure.

Verification compares all copied files byte-for-byte. For a split WIM it additionally runs `wimlib-imagex verify` against the temporary parts before erasure, then compares each copied part. This verifies data, not a real boot or Windows installation. See [wimlib](https://github.com/ebiggers/wimlib).

### macOS

Download a complete compatible installer from Apple. DiskKit checks the Apple signatures of the installer and its `createinstallmedia` executable; the elevated path repeats these checks after authorization and before erasure. A cancelled administrator dialog does not start formatting. Apple's tool controls installer validation and copying. It may still reject an incomplete installer or incompatible host after preparation has started. No separate byte-for-byte verification is exposed for this mode. See [Apple's installer guide](https://support.apple.com/en-ie/101578).

### Progress

`onProgress` receives `MediaOperationProgress` until the returned `Future<void>` completes. `stage` is a `MediaOperationStage`; `bytesCompleted` and `totalBytes` are nullable. `fraction` describes the **current stage**, not the whole workflow. Show an indeterminate indicator when it is null. Raw writing and read-back verification report byte counts. WIM splitting, authorization, formatting, and Apple's tool have indeterminate stages. Windows file copying and verification report byte counts. A callback error is reported to Flutter without interrupting the native operation. Handle the future's exception to display failure; successful operations end with `completed`.

## Native dependency managers

Supports CocoaPods and Swift Package Manager on macOS. See the [macOS implementation guide](https://github.com/Dark-Fox-PL/disk_kit/blob/main/packages/disk_kit_macos/README.md) for integration details.

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
| `protected_disk` | A destructive operation targeted internal, unknown, or unsupported virtual media. |
| `volume_not_mounted` | A copy request does not have a mounted volume and both paths. |
| `invalid_path` | A path is invalid or escapes the permitted volume root. |
| `destination_exists` | The copy destination already exists. |
| `operation_failed` | Disk Arbitration rejected a mount, unmount, eject, or rename request. |
| `format_failed` | `diskutil` returned a nonzero exit status. |
| `unsupported_image` | Source type, disk layout, installer signature, or Windows ISO contents are unsupported. |
| `image_too_large` | Installation files and filesystem overhead do not fit. |
| `source_on_target` | The source or a supplied tool is on the disk being erased. |
| `source_changed` | The source changed during preparation or writing. |
| `target_changed` | The original device was detached or replaced. |
| `permission_denied` | Raw access was denied by macOS privacy/permissions, or elevation is disabled without adequate privileges. |
| `authorization_cancelled` | The system administrator dialog was cancelled. |
| `dependency_missing` | Required wimlib-imagex is unavailable. |
| `split_failed` | WIM splitting failed or a part exceeds FAT32's limit. |
| `verification_failed` | Read-back comparison or split-WIM integrity verification failed. |
| `media_failed` | A media preparation tool failed; inspect message and details. |
| `io_failed` | A filesystem operation or process launch failed. |

Disk Arbitration errors include `operation`, `diskId`, and native `status`. Formatting failures include `exitCode`. Filesystem errors include their NSError `domain` and `status`. Unsupported platforms throw `UnsupportedError`; invalid BSD names throw `ArgumentError` before reaching native code.

## Example and manual testing

The interactive example is in `packages/disk_kit/example` in the [GitHub repository](https://github.com/Dark-Fox-PL/disk_kit/tree/main/packages/disk_kit/example). It uses the public `disk_kit` API.

After cloning the repository, run from the workspace root:

```sh
flutter pub get
cd packages/disk_kit/example
flutter run -d macos
```

The example displays connected external devices and exposes all operations. See the [example guide](https://github.com/Dark-Fox-PL/disk_kit/blob/main/packages/disk_kit/example/README.md) for a copy → format → restore test.

Source: [GitHub](https://github.com/Dark-Fox-PL/disk_kit). Bugs and proposals: [issues](https://github.com/Dark-Fox-PL/disk_kit/issues).

## Validation of 1.0.0

Unit tests, both example widget suites, and native discovery integration checks
pass with CocoaPods and Swift Package Manager on Flutter 3.47.5. An explicitly
authorized physical USB test passed raw writing and read-back comparison of a
16 MiB synthetic image, Windows MBR/FAT32 preparation from a synthetic ISO,
file verification, and restoration to a mounted exFAT volume. The fixture does
not contain an operating system; this is not a boot test. Genuine Windows WIM
splitting and Apple's full installer still require separate end-to-end tests
with those sources and compatible hardware.

## License

Distributed under the [MIT License](LICENSE). Copyright (c) 2026 ByFox.
