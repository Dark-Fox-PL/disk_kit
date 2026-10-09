/// Native disk discovery, volume operations, copying, formatting, and installation media.
///
/// Use [DiskKit] to access the registered platform implementation. [DiskInfo]
/// describes disks and volumes returned by discovery and completed operations.
library;

import 'package:disk_kit_platform_interface/disk_kit_platform_interface.dart';

export 'package:disk_kit_platform_interface/disk_kit_platform_interface.dart'
    show
        FileCopyProgress,
        FileCopyProgressCallback,
        DiskInfo,
        DiskFileSystem,
        DiskPartitionScheme,
        MediaOperationStage,
        MediaOperationProgress,
        MediaProgressCallback;

/// Communicates with the operating system's disk management APIs.
///
/// macOS 12+ is the initial supported platform. The native plugin registers
/// automatically. Unsupported platforms report [UnsupportedError].
///
/// Native failures complete the returned future with a `PlatformException`.
/// Its `code` identifies the failure and `details` can include the native status.
/// Invalid macOS BSD names report [ArgumentError]. IDs come from [getDisks];
/// they are attachment-specific and can be reused after a device is removed.
///
/// Media operations may request administrator authorization on macOS.
/// DiskKit does not implement an automatic backup workflow.
/// Callers confirm destructive operations and cancel their stream subscriptions.
class DiskKit {
  /// Creates a stateless handle to the registered platform implementation.
  const DiskKit();

  /// Returns an immutable snapshot of visible devices, partitions, and volumes.
  ///
  /// Includes internal media and system partitions. Filter or group results
  /// using [DiskInfo.isInternal], [DiskInfo.wholeDiskId], and
  /// [DiskInfo.mediaContent]. Properties missing from the OS description are null.
  /// Fails with `session_unavailable` or `discovery_failed` on native discovery errors.
  Future<List<DiskInfo>> getDisks() => DiskKitPlatform.instance.getDisks();

  /// Full snapshots after discovery, removal, or a disk description change.
  ///
  /// The first subscription receives an initial snapshot. Additional listeners
  /// joining an active broadcast stream receive subsequent updates. After the
  /// last listener cancels, the next subscription receives a new initial snapshot.
  /// Snapshots can repeat and operations may cause intermediate snapshots.
  /// Cancel the subscription when its consumer is disposed; listen for errors.
  Stream<List<DiskInfo>> watchDisks() => DiskKitPlatform.instance.watchDisks();

  /// Mounts the volume identified by [diskId] at the OS default mount point.
  ///
  /// Returns the mounted volume description after Disk Arbitration completes.
  /// Native permissions,
  /// unsupported filesystems, or an already mounted volume can cause
  /// `operation_failed`. Read the resulting mount point from a fresh snapshot.
  Future<DiskInfo> mount(String diskId) =>
      DiskKitPlatform.instance.mount(diskId);

  /// Unmount a volume, or all volumes on its containing disk with [wholeDisk].
  /// Returns the target description after the OS has completed the request.
  /// With [wholeDisk] true, the target is the containing whole disk; use the
  /// disk snapshot stream to observe the states of all its volumes.
  /// No force is used.
  /// [diskId] identifies the volume; with [wholeDisk], macOS resolves its containing
  /// whole disk and unmounts all its volumes. Busy files can cause `operation_failed`.
  /// An unmounted volume remains discoverable and can be mounted again.
  Future<DiskInfo> unmount(String diskId, {bool wholeDisk = false}) =>
      DiskKitPlatform.instance.unmount(diskId, wholeDisk: wholeDisk);

  /// Ejects the whole disk containing [diskId]. Unmount its volumes first.
  ///
  /// The target can be a whole disk or one of its volumes. A successful eject
  /// removes it from discovery. It may need to be physically reconnected.
  /// OS restrictions or mounted volumes can cause `operation_failed`.
  Future<void> eject(String diskId) => DiskKitPlatform.instance.eject(diskId);

  /// Renames a filesystem volume without formatting it or changing file contents.
  ///
  /// [diskId] identifies a recognized volume, and [volumeName] is its new label.
  /// The label follows the same filesystem-specific rules as [formatVolume].
  /// macOS can change its mount point; obtain the new [DiskInfo.volumePath] from
  /// the returned [DiskInfo], [getDisks], or [watchDisks] after completion.
  /// The OS may reject a rename due
  /// to permissions or volume state (`operation_failed`). Whole disks without
  /// a recognized filesystem are rejected with `invalid_target`.
  Future<DiskInfo> renameVolume(String diskId, {required String volumeName}) =>
      DiskKitPlatform.instance.renameVolume(diskId, volumeName: volumeName);

  /// Copy a file or directory from a mounted volume to an absolute local path.
  /// The destination must not exist; its parent directory must exist.
  /// Directory copies are recursive. Symlinks within directories are preserved.
  /// A failed copy may leave partial files at the destination.
  /// [diskId] must identify a mounted volume. [relativePath] is inside its root;
  /// `.` selects the root itself. [destinationPath] must be an absolute local path.
  /// Volume traversal outside the mount point is rejected with `invalid_path`.
  /// Other failures include `volume_not_mounted`, `destination_exists`, and
  /// `io_failed`. File events report paths and completed file sizes, not chunk progress.
  /// [parallel] defaults to true and permits up to four concurrent file copies.
  /// There is no cancellation or checksum verification.
  Future<void> copyFromDisk(
    String diskId, {
    required String relativePath,
    required String destinationPath,
    bool parallel = true,
    FileCopyProgressCallback? onProgress,
  }) =>
      DiskKitPlatform.instance.copyFromDisk(
        diskId,
        relativePath: relativePath,
        destinationPath: destinationPath,
        parallel: parallel,
        onProgress: onProgress,
      );

  /// Copy an absolute local file/directory into a mounted volume.
  /// [relativePath] names the new item inside the volume. No merge or overwrite
  /// is performed; the destination parent directory must already exist.
  /// [diskId] must identify a mounted volume, and [sourcePath] must be absolute.
  /// Symlinks inside copied directories are preserved. Unsupported metadata,
  /// insufficient space, permissions, or filename restrictions can cause
  /// `io_failed`; failed copies can leave partial data. The same path restrictions
  /// and cancellation limitations as [copyFromDisk] apply.
  Future<void> copyToDisk(
    String diskId, {
    required String sourcePath,
    bool parallel = true,
    FileCopyProgressCallback? onProgress,
    required String relativePath,
  }) =>
      DiskKitPlatform.instance.copyToDisk(
        diskId,
        sourcePath: sourcePath,
        parallel: parallel,
        onProgress: onProgress,
        relativePath: relativePath,
      );

  /// Erase an external partition or volume and create a new filesystem.
  /// All data on that target is lost. The containing partition table is kept.
  /// OS permissions and filesystem compatibility still apply.
  /// [diskId] must identify a partition or volume, not a whole disk.
  /// [fileSystem] selects the new filesystem and [volumeName] its label.
  /// exFAT labels accept up to 15 UTF-16 units. FAT labels accept 1–11 uppercase
  /// ASCII letters, digits, underscores, or spaces. Other labels accept up to
  /// 255 UTF-16 units; `/`, `:`, backslash, and NUL are rejected for every label.
  /// Internal or unknown devices fail with `protected_disk`; incorrect targets
  /// with `invalid_target`; invalid labels with `invalid_arguments`; `diskutil`
  /// failures with `format_failed`. Callers must confirm data deletion beforehand.
  Future<void> formatVolume(
    String diskId, {
    required DiskFileSystem fileSystem,
    required String volumeName,
  }) =>
      DiskKitPlatform.instance.formatVolume(
        diskId,
        fileSystem: fileSystem,
        volumeName: volumeName,
      );

  /// Erase an external whole disk, replacing all partitions with one volume.
  /// All data on every partition is lost. Both APFS variants require GPT.
  /// Refresh disk identifiers before calling; identifiers can be reused.
  /// [diskId] must identify a whole disk. [partitionScheme] defaults to GPT and
  /// [fileSystem] and [volumeName] follow the rules documented on [formatVolume].
  /// All existing partitions are replaced by a layout containing one data volume;
  /// macOS may also create supporting system partitions such as EFI.
  /// After completion, rediscover the volume IDs and mount points. Callers must
  /// confirm deletion of all partitions before calling this method.
  Future<void> formatDisk(
    String diskId, {
    required DiskFileSystem fileSystem,
    required String volumeName,
    DiskPartitionScheme partitionScheme = DiskPartitionScheme.gpt,
  }) =>
      DiskKitPlatform.instance.formatDisk(
        diskId,
        fileSystem: fileSystem,
        volumeName: volumeName,
        partitionScheme: partitionScheme,
      );

  /// Writes an uncompressed IMG or USB-compatible hybrid ISO to an external
  /// whole disk, replacing its partition table and all data.
  ///
  /// Use [createWindowsInstaller] for ordinary Windows ISOs and
  /// [createMacOSInstaller] for Apple's installers. Raw writing does not turn
  /// an arbitrary ISO into bootable media. Compressed images and container DMGs
  /// are not supported. The image must fit on the target and be stored elsewhere.
  /// [verify] defaults to true and compares the image-length destination bytes.
  /// [allowElevation] permits a macOS administrator prompt; false uses current
  /// privileges. [onProgress] reports stages and bytes where measurable.
  /// Confirm erasure first and refresh the target ID. Failed operations can
  /// leave unusable media. There is no cancellation or automatic rollback.
  Future<void> writeImage(
    String diskId, {
    required String imagePath,
    bool verify = true,
    bool allowElevation = true,
    MediaProgressCallback? onProgress,
  }) =>
      DiskKitPlatform.instance.writeImage(diskId,
          imagePath: imagePath,
          verify: verify,
          allowElevation: allowElevation,
          onProgress: onProgress);

  /// Creates Windows installation media for UEFI from a local Windows ISO.
  ///
  /// Erases all partitions on an external whole disk, creates MBR/FAT32, and
  /// copies the ISO contents. Legacy BIOS boot is not configured. The ISO must
  /// contain a supported EFI bootloader and sources/boot.wim. Files over FAT32's
  /// limit are rejected except sources/install.wim, which is split into SWMs.
  /// Install wimlib-imagex separately for splitting; [wimlibPath] can supply an
  /// absolute executable path. Missing tools are detected before erasure.
  /// Oversized install.esd is unsupported. [verify] compares copied files and
  /// verifies the split WIM with wimlib. Firmware, Secure Boot trust, and CPU
  /// compatibility depend on the chosen ISO and target computer.
  /// [onProgress] receives stage updates and copy/verification byte counts.
  Future<void> createWindowsInstaller(
    String diskId, {
    required String isoPath,
    String? wimlibPath,
    bool verify = true,
    MediaProgressCallback? onProgress,
  }) =>
      DiskKitPlatform.instance.createWindowsInstaller(diskId,
          isoPath: isoPath,
          wimlibPath: wimlibPath,
          verify: verify,
          onProgress: onProgress);

  /// Creates bootable macOS installation media from a full Apple installer app.
  ///
  /// [installerAppPath] must point to a complete Install macOS .app containing
  /// an Apple-signed createinstallmedia tool; ISO/DMG files are not accepted.
  /// Erases all partitions on the external whole disk and prepares GPT/HFS+.
  /// [allowElevation] permits the macOS administrator prompt required by Apple's
  /// tool. With false, the host must already have adequate privileges.
  /// Apple's tool validates its installer and controls progress; [onProgress]
  /// reports indeterminate stages. The installer version must support the host
  /// and destination Mac. A failed operation can leave partially prepared media.
  Future<void> createMacOSInstaller(
    String diskId, {
    required String installerAppPath,
    bool allowElevation = true,
    MediaProgressCallback? onProgress,
  }) =>
      DiskKitPlatform.instance.createMacOSInstaller(diskId,
          installerAppPath: installerAppPath,
          allowElevation: allowElevation,
          onProgress: onProgress);
}
