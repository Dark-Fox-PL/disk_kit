import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'src/disk_info.dart';
import 'src/disk_format.dart';

export 'src/disk_info.dart';
export 'src/disk_format.dart';

/// Contract implemented by DiskKit's platform packages.
abstract class DiskKitPlatform extends PlatformInterface {
  DiskKitPlatform() : super(token: _token);

  static final Object _token = Object();
  static DiskKitPlatform _instance = _UnsupportedDiskKitPlatform();

  static DiskKitPlatform get instance => _instance;

  static set instance(DiskKitPlatform platform) {
    PlatformInterface.verifyToken(platform, _token);
    _instance = platform;
  }

  Future<List<DiskInfo>> getDisks() async => throw _unsupported();

  /// A broadcast stream with an initial snapshot and subsequent snapshots.
  ///
  /// A new listener on an already active broadcast stream receives future
  /// updates. The first listener after cancellation starts a new subscription.
  Stream<List<DiskInfo>> watchDisks() => Stream.error(_unsupported());

  Future<void> mount(String diskId) async => throw _unsupported();

  /// Unmount a volume, or all volumes on its whole disk if [wholeDisk] is true.
  /// Active files can cause the OS to reject the operation; no force is used.
  Future<void> unmount(String diskId, {bool wholeDisk = false}) async =>
      throw _unsupported();

  /// Eject the whole disk containing [diskId]. Unmount its volumes first.
  Future<void> eject(String diskId) async => throw _unsupported();

  Future<void> copyFromDisk(
    String diskId, {
    required String relativePath,
    required String destinationPath,
  }) async =>
      throw _unsupported();

  Future<void> copyToDisk(
    String diskId, {
    required String sourcePath,
    required String relativePath,
  }) async =>
      throw _unsupported();

  Future<void> formatVolume(
    String diskId, {
    required DiskFileSystem fileSystem,
    required String volumeName,
  }) async =>
      throw _unsupported();

  Future<void> formatDisk(
    String diskId, {
    required DiskFileSystem fileSystem,
    required String volumeName,
    DiskPartitionScheme partitionScheme = DiskPartitionScheme.gpt,
  }) async =>
      throw _unsupported();

  UnsupportedError _unsupported() =>
      UnsupportedError('DiskKit is not supported on this platform.');
}

class _UnsupportedDiskKitPlatform extends DiskKitPlatform {}
