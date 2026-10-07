# DiskKit macOS example

A manual test harness that imports the public `disk_kit` API. Requires macOS 12+, Xcode, and Flutter. The example runs outside App Sandbox so native storage operations and filesystem paths can be exercised.

## Run

From the workspace root:

```sh
flutter pub get
cd packages/disk_kit_macos/example
flutter run -d macos
```

Connect a USB drive. The list should update without pressing Refresh. Each whole disk has one card, with its volumes nested inside. The device header offers actions for the entire disk; each data volume has its own copy, mount, rename, and format actions. EFI system partitions are hidden by default. Enable **Show details and system partitions** to reveal their properties and native identifiers. EFI entries are read-only in this example. Internal and unknown disks are hidden by default and can be shown with their separate toggle; operations remain available only for external media.

## Copy → format → restore

Use a test USB drive whose contents can be erased. This procedure deliberately deletes data during the format step.

1. Create a small directory named `DiskKitTest` on the USB volume, containing a text file and a nested directory.
2. On the mounted volume entry, choose **Copy from disk**. Enter `DiskKitTest` as the relative path and an absolute unused destination on your Mac, for example `/Users/you/Desktop/DiskKitTest-backup`. The parent directory must already exist.
3. Check that the backup contains the original files. You can compare directory contents with `diff -r /Volumes/USB/DiskKitTest /Users/you/Desktop/DiskKitTest-backup`.
4. Choose **Format volume…** inside the card to keep the partition table, or **Format disk…** in the device header to replace all its partitions. Choose `exFat` and a volume name such as `DISKKIT`. Whole-disk formatting also selects GPT or MBR. Type the displayed `ERASE disk…` confirmation and execute.
5. Wait for the list to update. Formatting can replace volume identifiers. Select the new mounted volume rather than reusing an old ID.
6. Choose **Copy to disk**, enter `/Users/you/Desktop/DiskKitTest-backup` as the local source and `DiskKitTest` as the relative destination.
7. Compare the restored directory with the backup. The plugin itself does not perform checksum verification.
8. Test **Unmount**, **Mount**, **Unmount all volumes**, then **Eject**. Eject expects the whole disk's volumes to be unmounted.

Try copying to an existing destination to see `destination_exists`, and opening a file in another application before unmounting to observe how macOS handles a busy volume. macOS may still allow unmounting depending on the other application's file handles.

Local paths are absolute. Paths on the volume are relative. Copying never merges or overwrites. Failed copies may leave partial files; remove those before retrying. Filesystem permissions and compatibility can cause failures.

## Automated checks

From the workspace root:

```sh
flutter analyze
flutter test packages/disk_kit/test packages/disk_kit_platform_interface/test packages/disk_kit_macos/test
sh tool/test_macos.sh
```

From this example directory:

```sh
flutter test test/widget_test.dart
flutter test integration_test/plugin_integration_test.dart -d macos
```

The native filesystem tests use temporary directories and validate formatting arguments. The integration tests exercise discovery, initial snapshots, resubscription, and errors for nonexistent devices. None of these automated checks formats a disk.

To test copying against a particular mounted external volume, explicitly supply its name. Replace `TEST_USB` with the exact mounted volume name on your Mac:

```sh
flutter test integration_test/plugin_integration_test.dart -d macos \
  '--dart-define=DISK_KIT_TEST_VOLUME_NAME=TEST_USB'
```

This creates a unique test directory on that volume, copies text and binary files in both directions, compares their contents, and removes its test directory. Existing data is preserved. Adding `--dart-define=DISK_KIT_TEST_MOUNT_CYCLE=true` also tests an unmount/remount cycle, its returned `DiskInfo` values, and the corresponding stream update. Adding `--dart-define=DISK_KIT_TEST_RENAME=true` tests a rename, verifies the updated metadata and preserved test file, then restores the original label. Close files on that volume before the mount-cycle test.

## Destructive format integration test

The separate formatting test is skipped unless both a target volume name and an explicit erase flag are supplied. It copies a generated fixture off the drive, formats the target volume as FAT32, verifies a restore, formats the entire disk as exFAT with GPT, and verifies another restore. The final volume uses the original name. Existing user files and all original partitions are erased; only the generated test fixture is backed up.

Run this only on a drive whose entire contents may be deleted:

```sh
flutter test integration_test/formatting_integration_test.dart -d macos \
  '--dart-define=DISK_KIT_TEST_VOLUME_NAME=TEST_USB' \
  --dart-define=DISK_KIT_ERASE_TEST_DRIVE=true
```

The test requires exactly one mounted external volume matching the name and a whole device using the USB protocol. It removes its generated files after successful verification. FAT32 and exFAT are exercised on hardware; APFS and HFS+ formatting parameters are covered by native argument-validation tests.

## Rename a volume

Choose **Rename…** on a data volume, enter its new label, and confirm. The displayed name and mount point update from the native snapshots. File contents are preserved. Refresh any filesystem paths you keep after renaming.

## Swift Package Manager verification

The plugin has a SwiftPM manifest as well as its CocoaPods podspec. To test SwiftPM on a recent Flutter SDK without changing your global Flutter configuration, temporarily add the following application setting to this example's `pubspec.yaml`:

```yaml
flutter:
  config:
    enable-swift-package-manager: true
  uses-material-design: true
```

Then run `flutter test integration_test/plugin_integration_test.dart -d macos`. Flutter adds SwiftPM integration to the example's Xcode project. The generated `macos/Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage/Package.swift` should reference the `disk-kit-macos` product. This verifies that the plugin is built through SwiftPM rather than only checking that its manifest exists.

The setting belongs to the application, not to a plugin dependency. Existing CocoaPods integration can remain while testing the SwiftPM plugin. See the [Flutter app migration guide](https://docs.flutter.dev/packages-and-plugins/swift-package-manager/for-app-developers) for the full application migration.

## Local workspace dependencies

The example's normal pubspec depends on the published `disk_kit` package and overrides the macOS implementation with the adjacent plugin directory. In a GitHub checkout, `pubspec_overrides.yaml` also resolves the public package and interface from their workspace directories. This local override file is excluded from the pub.dev archive, so the published example does not depend on sibling packages outside that archive. Run the published example after all three DiskKit packages have been released.
