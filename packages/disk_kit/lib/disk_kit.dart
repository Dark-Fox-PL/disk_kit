import 'package:disk_kit_platform_interface/disk_kit_platform_interface.dart';

export 'package:disk_kit_platform_interface/disk_kit_platform_interface.dart'
    show DiskInfo, DiskFileSystem, DiskPartitionScheme;

/// Communicates with the operating system's disk management APIs.
class DiskKit {
  const DiskKit();

  /// Snapshot of devices, partitions, and volumes currently visible to the OS.
  Future<List<DiskInfo>> getDisks() => DiskKitPlatform.instance.getDisks();

  /// Full snapshots after discovery, removal, or a disk description change.
  ///
  /// The first subscription receives an initial snapshot. Additional listeners
  /// joining an active broadcast stream receive subsequent updates.
  Stream<List<DiskInfo>> watchDisks() => DiskKitPlatform.instance.watchDisks();

  /// Mount a volume at the operating system's default mount point.
  Future<void> mount(String diskId) => DiskKitPlatform.instance.mount(diskId);

  /// Unmount a volume, or all volumes on its containing disk with [wholeDisk].
  /// No force is used. Completion means the OS has completed the request.
  Future<void> unmount(String diskId, {bool wholeDisk = false}) =>
      DiskKitPlatform.instance.unmount(diskId, wholeDisk: wholeDisk);

  /// Eject the containing whole disk. Unmount its volumes first.
  Future<void> eject(String diskId) => DiskKitPlatform.instance.eject(diskId);

  /// Copy a file or directory from a mounted volume to an absolute local path.
  /// The destination must not exist; its parent directory must exist.
  /// Directory copies are recursive. Symlinks within directories are preserved.
  /// A failed copy may leave partial files at the destination.
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
