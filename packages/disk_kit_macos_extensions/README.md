# disk_kit_macos_extensions

Optional macOS filesystem tools for [DiskKit](https://pub.dev/packages/disk_kit).
**Applications must explicitly add this package.** The core DiskKit packages do
not depend on it, and this plugin does not replace their platform implementation.

Version 0.1.0 is an initial tool integration. It does not bundle or install
executables, filesystem drivers, or privileged helpers.

## Installation

```yaml
dependencies:
  disk_kit: ^1.1.0
  disk_kit_macos_extensions: ^0.1.0
```

`disk_kit` automatically includes and registers its endorsed macOS implementation,
`disk_kit_macos`. Applications do not need to list `disk_kit_macos` or
`disk_kit_platform_interface` directly. Only the extension requires an explicit
additional dependency.

Import it separately:

```dart
import 'package:disk_kit/disk_kit.dart';
import 'package:disk_kit_macos_extensions/disk_kit_macos_extensions.dart';
```

Requires macOS 12+, Flutter 3.27+, Dart 3.6+, and a host outside App Sandbox.
CocoaPods and Swift Package Manager are supported.

## Capabilities

| Filesystem         | Formatting backend                     | Reading / writing                                      |
| ------------------ | -------------------------------------- | ------------------------------------------------------ |
| NTFS               | macOS build of `mkntfs` from NTFS-3G   | Depends on the mounted filesystem and installed driver |
| ext2 / ext3 / ext4 | macOS build of `mke2fs` from e2fsprogs | Requires separate filesystem support in macOS          |
| Btrfs              | Unavailable in this release            | No driver supplied                                     |

A formatter creates a filesystem; it does not provide a mount driver.
`getCapabilities()` reports whether a formatter answers its version probe.
Reading and writing remain `unknown` in this report. Use `getVolumeAccess()` to
inspect the mounted root's access under the application's current privileges.
Unmounted volumes report null access values. Root access does not guarantee access
to every file, available space, metadata compatibility, or successful copying.

```dart
const extensions = DiskKitMacosExtensions();
final capabilities = await extensions.getCapabilities();
for (final capability in capabilities) {
  print('${capability.fileSystem.name}: ${capability.formatting.name}');
  print(capability.reason);
}

final disks = await const DiskKit().getDisks();
for (final volume in disks.where((disk) => disk.isWholeDisk == false)) {
  final access = await extensions.getVolumeAccess(volume.id);
  print('${volume.id}: read=${access.canRead}, write=${access.canWrite}');
}
```

## Supplying tools

Provide trusted executables built for the user's macOS architecture, with all
required libraries and configuration files. Null paths enable discovery in
`/opt/homebrew` and `/usr/local`, including their formula `opt` directories;
the plugin does not search an arbitrary shell `PATH`.

```dart
const extensions = DiskKitMacosExtensions(
  tools: MacosExtensionTools(
    mkntfsPath: '/absolute/path/to/mkntfs',
    mke2fsPath: '/absolute/path/to/mke2fs',
  ),
);
```

Version probes execute the configured binaries with `-V`, with a ten-second
deadline and bounded captured output. Discovery does not verify signatures or
make an untrusted executable safe. Missing binaries, architecture mismatches,
and missing dynamic libraries report unavailable tools.

Applications may supply their own builds or ask the user to install tools.
Redistributed tools retain their upstream licenses; the package's MIT license
covers this integration code. See [NTFS-3G](https://github.com/tuxera/ntfs-3g)
and [e2fsprogs](https://github.com/tytso/e2fsprogs) for build and licensing details.
No macFUSE or other driver is installed automatically.

## Formatting an existing partition

**Formatting destroys all files on the selected partition.** Confirm the target
with the user before calling `formatVolume`:

```dart
final target = await extensions.prepareFormat(volume.id);
// Present target.diskId and target.wholeDiskId and obtain explicit confirmation.
// Only after confirmation:
await extensions.formatVolume(
  target,
  fileSystem: MacosExtensionFileSystem.ext4,
  volumeName: 'LINUX_USB',
);
```

The target token expires after five minutes, belongs to this plugin instance,
and is consumed by a formatting attempt. A retry requires a new target. Native
checks bind the partition and containing disk to their current IOKit attachment
identities. Internal or unknown media, whole disks, disk images, synthesized
volumes, containers, EFI, and system partitions are rejected.

Only physical data partitions with compatible type identifiers are accepted:
Microsoft Basic Data or Windows NTFS for NTFS, and Linux Filesystem for ext.
FAT/HFS partition types, containers, and supporting system partitions are rejected.
The partition table and type identifiers are preserved; prepare a compatible
layout separately before using this API.
This API does not convert partition types or create a bootable installer.
NTFS labels allow up to 128 UTF-16 units; ext labels allow up to 16 UTF-8 bytes.
Empty labels, slash, backslash, colon, and NUL are rejected.

Tool and device-access preflight precede unmounting. Formatting unmounts all
volumes on the containing disk without force, claims that disk through Disk
Arbitration, and blocks remounting during the operation. Formatters run with
explicit arguments, without a shell, and closed standard input. NTFS uses a
quick format; ext uses a single `-F` after native target validation. No automatic
remount, driver mounting, rollback, cancellation, or backup is provided. On
failure, a partition may be partially formatted and other volumes may remain
unmounted. The formatter and its dependencies must be stored off the target disk.

**No administrator elevation is implemented in 0.1.0.** The host must already
have read/write access to the device. Otherwise the operation returns
`permission_denied` before unmounting. A detected formatter alone therefore
does not guarantee that a normal desktop application can format a USB drive.
The plugin does not ask for or accept a password.

Serialize operations across DiskKit and this extension in the application.
The extension rejects its own overlapping requests on the same containing disk;
its queue is independent of the core plugin's operation queue.

Once an appropriate driver mounts the volume, use the existing DiskKit mount and
copy APIs when macOS exposes that volume. Formatter availability does not imply
that `DiskKit.mount` or `copyToDisk` will succeed. macOS may require rediscovery
or reconnecting the drive after an external formatter changes its filesystem.

## Errors

Native failures use `PlatformException` with codes including `tool_unavailable`,
`tool_changed`, `unsupported_filesystem`, `protected_disk`, `invalid_target`,
`target_changed`, `disk_not_found`, `permission_denied`, `disk_busy`,
`invalid_arguments`, `invalid_path`, `format_failed`, and `io_failed`.
Other platforms throw `UnsupportedError` from the Dart API.

## Example

The included Flutter application only inspects tools and volume access; it does
not format disks:

```sh
flutter pub get
cd packages/disk_kit_macos_extensions/example
flutter run -d macos
```

Real NTFS/ext formatting and third-party driver interoperability have not yet
been verified on physical media. Tool discovery is not a compatibility certification.

## License

Copyright (c) 2026 ByFox. [MIT](LICENSE).
Publisher: [darkfox.pl](https://pub.dev/publishers/darkfox.pl).
