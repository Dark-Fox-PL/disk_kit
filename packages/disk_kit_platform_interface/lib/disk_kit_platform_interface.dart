import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'src/file_copy_progress.dart';
export 'src/file_copy_progress.dart';

import 'src/disk_info.dart';
import 'src/disk_format.dart';
import 'src/media_operation_progress.dart';

export 'src/disk_info.dart';
export 'src/disk_format.dart';
export 'src/media_operation_progress.dart';

/// Contract implemented by DiskKit's platform packages.
///
/// Extend this class and install the implementation with [instance]. Extending
/// permits future methods to receive default unsupported behavior. Unimplemented
/// methods report [UnsupportedError]. Platform packages expose native errors as
/// `PlatformException`; callers must also handle invalid arguments and IDs.
abstract class DiskKitPlatform extends PlatformInterface {
  /// Creates an implementation with the token used to verify registration.
  DiskKitPlatform() : super(token: _token);

  static final Object _token = Object();
  static DiskKitPlatform _instance = _UnsupportedDiskKitPlatform();

  /// The registered implementation; defaults to unsupported behavior.
  static DiskKitPlatform get instance => _instance;

  /// Registers a platform implementation and verifies its platform token.
  static set instance(DiskKitPlatform platform) {
    PlatformInterface.verifyToken(platform, _token);
    _instance = platform;
  }

  /// Returns a snapshot including devices, partitions, and volumes.
  /// Implementations preserve unknown metadata as null and return immutable lists.
  Future<List<DiskInfo>> getDisks() async => throw _unsupported();

  /// A broadcast stream with an initial snapshot and subsequent snapshots.
  ///
  /// A new listener on an already active broadcast stream receives future
  /// updates. The first listener after cancellation starts a new subscription.
  Stream<List<DiskInfo>> watchDisks() => Stream.error(_unsupported());

  /// Mounts the volume identified by [diskId] at the default OS mount point.
  /// Returns the volume description after the native operation finishes.
  Future<DiskInfo> mount(String diskId) async => throw _unsupported();

  /// Unmount a volume, or all volumes on its whole disk if [wholeDisk] is true.
  /// Returns the unmounted volume, or the whole disk when [wholeDisk] is true.
  /// Query the snapshot stream for individual volume states after a whole-disk
  /// request. Active files can cause rejection; no force is used.
  Future<DiskInfo> unmount(String diskId, {bool wholeDisk = false}) async =>
      throw _unsupported();

  /// Eject the whole disk containing [diskId]. Unmount its volumes first.
  Future<void> eject(String diskId) async => throw _unsupported();

  /// Changes the filesystem volume label to [volumeName], preserving file data.
  /// Returns the updated volume description, including its current mount point.
  /// Implementations validate filesystem label rules and notify observers of
  /// description changes, including any change to the mount point.
  Future<DiskInfo> renameVolume(String diskId,
          {required String volumeName}) async =>
      throw _unsupported();

  /// Recursively copies a file or directory from a mounted [diskId].
  /// [relativePath] is inside the volume; [destinationPath] is absolute and must
  /// not exist. Its parent must exist. Reject traversal out of the volume.
  /// A failed copy can leave partial data; no overwrite or merge is performed.
  Future<void> copyFromDisk(
    String diskId, {
    required String relativePath,
    required String destinationPath,
    bool parallel = true,
    FileCopyProgressCallback? onProgress,
  }) async =>
      throw _unsupported();

  /// Copies an absolute [sourcePath] to [relativePath] inside mounted [diskId].
  /// The destination must not exist and its parent directory must exist.
  /// Preserves nested symlinks; reject destinations escaping the volume root.
  /// A failed copy can leave partial data; no overwrite or merge is performed.
  Future<void> copyToDisk(
    String diskId, {
    required String sourcePath,
    bool parallel = true,
    FileCopyProgressCallback? onProgress,
    required String relativePath,
  }) async =>
      throw _unsupported();

  /// Destructively replaces the filesystem on the volume identified by [diskId].
  /// Preserve its partition table. [fileSystem] and [volumeName] specify the
  /// replacement. The macOS implementation requires positively external media;
  /// native permissions and filesystem/layout restrictions still apply.
  Future<void> formatVolume(
    String diskId, {
    required DiskFileSystem fileSystem,
    required String volumeName,
  }) async =>
      throw _unsupported();

  /// Destructively replaces all partitions on the whole disk [diskId].
  /// Create a data volume named [volumeName] with [fileSystem] using
  /// [partitionScheme]. The OS may create additional system partitions.
  /// macOS requires external media and GPT for both APFS variants; callers confirm deletion.
  Future<void> formatDisk(
    String diskId, {
    required DiskFileSystem fileSystem,
    required String volumeName,
    DiskPartitionScheme partitionScheme = DiskPartitionScheme.gpt,
  }) async =>
      throw _unsupported();

  /// Writes an uncompressed raw IMG or USB-compatible hybrid ISO to a whole disk.
  /// Erases the disk layout. Ordinary Windows/macOS installer ISOs need their
  /// dedicated installer methods instead. Verification reads back image bytes.
  /// macOS can request administrator authorization when [allowElevation] is true.
  Future<void> writeImage(
    String diskId, {
    required String imagePath,
    bool verify = true,
    bool allowElevation = true,
    MediaProgressCallback? onProgress,
  }) async =>
      throw _unsupported();

  /// Erases a whole disk and copies a Windows ISO into a FAT32 UEFI layout.
  /// Oversized install.wim needs a caller-installed wimlib-imagex executable;
  /// [wimlibPath] overrides the usual Homebrew locations. No legacy BIOS setup.
  /// [verify] compares copied files and checks split WIM integrity.
  Future<void> createWindowsInstaller(
    String diskId, {
    required String isoPath,
    String? wimlibPath,
    bool verify = true,
    MediaProgressCallback? onProgress,
  }) async =>
      throw _unsupported();

  /// Erases a whole disk and runs an Apple-signed installer's createinstallmedia.
  /// [installerAppPath] names a complete Install macOS .app, not an ISO or DMG.
  /// macOS can request administrator authorization when [allowElevation] is true.
  /// Apple's tool controls copying and validation; byte counters are unavailable.
  Future<void> createMacOSInstaller(
    String diskId, {
    required String installerAppPath,
    bool allowElevation = true,
    MediaProgressCallback? onProgress,
  }) async =>
      throw _unsupported();

  UnsupportedError _unsupported() =>
      UnsupportedError('DiskKit is not supported on this platform.');
}

class _UnsupportedDiskKitPlatform extends DiskKitPlatform {}
