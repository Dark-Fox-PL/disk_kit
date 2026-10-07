/// Native disk discovery, notifications, copying, formatting, and volume operations.
///
/// Use [DiskKit] to access the registered platform implementation. [DiskInfo]
/// describes disks and volumes returned by discovery and completed operations.
library;

import 'package:disk_kit_platform_interface/disk_kit_platform_interface.dart';

export 'package:disk_kit_platform_interface/disk_kit_platform_interface.dart'
    show DiskInfo, DiskFileSystem, DiskPartitionScheme;

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
/// DiskKit does not elevate privileges or implement an automatic backup workflow.
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
  /// `io_failed`. There is no progress, cancellation, or checksum verification.
  Future<void> copyFromDisk(
    String diskId, {
    required String relativePath,
    required String destinationPath,
  }) =>
      DiskKitPlatform.instance.copyFromDisk(
        diskId,
        relativePath: relativePath,
        destinationPath: destinationPath,
      );

  /// Copy an absolute local file/directory into a mounted volume.
  /// [relativePath] names the new item inside the volume. No merge or overwrite
  /// is performed; the destination parent directory must already exist.
  /// [diskId] must identify a mounted volume, and [sourcePath] must be absolute.
  /// Symlinks inside copied directories are preserved. Unsupported metadata,
  /// insufficient space, permissions, or filename restrictions can cause
  /// `io_failed`; failed copies can leave partial data. The same path restrictions
  /// and absence of progress/cancellation as [copyFromDisk] apply.
  Future<void> copyToDisk(
    String diskId, {
    required String sourcePath,
    required String relativePath,
  }) =>
      DiskKitPlatform.instance.copyToDisk(
        diskId,
        sourcePath: sourcePath,
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
  /// All data on every partition is lost. APFS requires GPT.
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
}
