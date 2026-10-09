# disk_kit_macos

macOS implementation of the federated DiskKit Flutter plugin. Applications should depend on and import `disk_kit`; this package registers automatically.

The plugin uses Disk Arbitration for descriptions, notifications, mounting, unmounting, and ejecting. IOKit enumerates existing IOMedia objects for initial discovery. `FileManager` copies files on a background queue, with up to four file workers per copy by default (`parallel: false` uses one). Independent disks can operate concurrently; the containing disk stays exclusively leased until every worker finishes, including on failure. Directory metadata is applied after descendants and nested symlinks are preserved. `/usr/sbin/diskutil` performs formatting using explicit process arguments without a shell.

Formatting supports exFAT, FAT32, both case-sensitive and case-insensitive APFS, and all four combinations of HFS+ case sensitivity and journaling. Both APFS variants require GPT for whole-disk formatting.

Requires macOS 12+, Flutter 3.27+, and Dart 3.6+. The plugin requires an application outside App Sandbox. Raw image writing and macOS installer preparation can request administrator authorization through system dialogs; other operations use the host privileges. No persistent privileged helper is installed. Formatting is limited to media identified as external. Operating system restrictions are returned as structured errors.

The native and Dart method/event channels are `eu.byfox.disk_kit/methods` and `eu.byfox.disk_kit/disks`. Native requests targeting the same containing whole disk are rejected while another DiskKit operation on it is pending.

Copy events are sent as `fileCopyProgress` on the method channel, correlated
by an operation ID. `FileCopyProgress.path` is the absolute source path and
`bytes` is the file size. `completed: false` announces the start and does not
count those bytes as copied; `completed: true` reports a successful file copy.
The entire operation can still fail on another file or directory metadata, so
always await its future. There is no chunk progress, in-flight cancellation,
merging, overwriting or checksum verification. Partial output is retained on
failure. Callback errors are reported through Flutter without interrupting
native copying. Version 1.2.0 requires platform interface 2.0.0.

See the [public API guide](https://github.com/Dark-Fox-PL/disk_kit/blob/main/packages/disk_kit/README.md) and the [example testing guide](https://github.com/Dark-Fox-PL/disk_kit/blob/main/packages/disk_kit_macos/example/README.md).

## Installation media

`writeImage` writes uncompressed IMG/hybrid ISO to a raw external whole disk, unmounting and claiming it through Disk Arbitration. A mount approval callback blocks remounting while it writes. Raw writing and read-back verification stream through native file descriptors. When access requires authorization, Authorization Services and `authopen` transfer only an existing device descriptor over a Unix socket. There is no separate privileged raw writer. Fresh IOKit registry IDs identify the current attachment.

`createWindowsInstaller` mounts ISO read-only through `hdiutil`, preflights the file tree, optionally splits an oversized installation WIM with caller-installed `wimlib-imagex`, and copies to MBR/FAT32 for UEFI. Ordinary copies are verified byte-for-byte when requested. Legacy BIOS and oversized ESD are unsupported.

`createMacOSInstaller` requires a full Apple installer app, verifies Apple signatures, and uses `createinstallmedia` with administrator authorization through AppleScript. Its phase telemetry uses an exclusively created root-owned temporary directory. It does not accept macOS ISO/DMG containers. The authorization prompt precedes formatting. Apple's tool has indeterminate progress and controls validation.

Progress is sent as `mediaProgress` callbacks on the existing method channel, correlated by an operation ID. No password is passed through Dart. See the public API guide for supported sources and limitations.

## Development

Run `flutter pub get` from the workspace root. Native filesystem tests can be run independently with `sh tool/test_macos.sh`; they only use temporary files and validate formatting arguments without launching a format operation.

[Source and issues](https://github.com/Dark-Fox-PL/disk_kit). Distributed under the [MIT License](LICENSE).

Publisher: [darkfox.pl](https://pub.dev/publishers/darkfox.pl).

## Native dependency managers

The package supports CocoaPods and Swift Package Manager. Its SwiftPM product is `disk-kit-macos`; the target imports `FlutterFramework` and links Disk Arbitration, IOKit, and Security. Current SwiftPM builds and native channel tests were verified using Flutter 3.47.5. CocoaPods remains available for applications using older supported Flutter versions.

The manifest follows the [official Flutter plugin guide](https://docs.flutter.dev/packages-and-plugins/swift-package-manager/for-plugin-authors). Flutter generates the `FlutterFramework` dependency while integrating the consuming application; running `swift build` directly inside the published plugin is not the application integration test.
