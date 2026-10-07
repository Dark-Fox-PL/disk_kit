import 'package:disk_kit_platform_interface/disk_kit_platform_interface.dart';
import 'package:flutter/services.dart';

/// macOS transport using method and event channels.
class MethodChannelDiskKitMacos extends DiskKitPlatform {
  final MethodChannel methodChannel = const MethodChannel(
    'eu.byfox.disk_kit/methods',
  );
  final EventChannel eventChannel =
      const EventChannel('eu.byfox.disk_kit/disks');
  Stream<List<DiskInfo>>? _disks;

  @override
  Future<List<DiskInfo>> getDisks() async =>
      _decode(await methodChannel.invokeMethod<Object?>('getDisks'));

  @override
  Stream<List<DiskInfo>> watchDisks() =>
      _disks ??= eventChannel.receiveBroadcastStream().map(_decode);

  @override
  Future<void> mount(String diskId) => _operate('mount', diskId);

  @override
  Future<void> unmount(String diskId, {bool wholeDisk = false}) =>
      _operate('unmount', diskId, wholeDisk: wholeDisk);

  @override
  Future<void> eject(String diskId) => _operate('eject', diskId);

  @override
  Future<void> copyFromDisk(
    String diskId, {
    required String relativePath,
    required String destinationPath,
  }) =>
      _operate('copyFromDisk', diskId, arguments: {
        'relativePath': relativePath,
        'localPath': destinationPath,
      });

  @override
  Future<void> copyToDisk(
    String diskId, {
    required String sourcePath,
    required String relativePath,
  }) =>
      _operate('copyToDisk', diskId, arguments: {
        'relativePath': relativePath,
        'localPath': sourcePath,
      });

  @override
  Future<void> formatVolume(
    String diskId, {
    required DiskFileSystem fileSystem,
    required String volumeName,
  }) =>
      _operate('formatVolume', diskId, arguments: {
        'fileSystem': fileSystem.name,
        'volumeName': volumeName,
      });

  @override
  Future<void> formatDisk(
    String diskId, {
    required DiskFileSystem fileSystem,
    required String volumeName,
    DiskPartitionScheme partitionScheme = DiskPartitionScheme.gpt,
  }) =>
      _operate('formatDisk', diskId, arguments: {
        'fileSystem': fileSystem.name,
        'volumeName': volumeName,
        'partitionScheme': partitionScheme.name,
      });

  Future<void> _operate(
    String method,
    String diskId, {
    bool? wholeDisk,
    Map<String, Object?> arguments = const {},
  }) async {
    if (!RegExp(r'^disk[0-9]+(?:s[0-9]+)*$').hasMatch(diskId)) {
      throw ArgumentError.value(diskId, 'diskId', 'Expected a macOS BSD name.');
    }
    await methodChannel.invokeMethod<void>(method, {
      'diskId': diskId,
      if (wholeDisk != null) 'wholeDisk': wholeDisk,
      ...arguments,
    });
  }

  List<DiskInfo> _decode(Object? value) {
    if (value is! List) {
      throw const FormatException('Expected a list of DiskInfo maps.');
    }
    return List.unmodifiable(
      value.map((item) {
        if (item is! Map) {
          throw const FormatException('Expected a DiskInfo map.');
        }
        return DiskInfo.fromMap(Map<Object?, Object?>.from(item));
      }),
    );
  }
}
