import 'package:disk_kit_platform_interface/disk_kit_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

/// macOS transport using method and event channels.
class MethodChannelDiskKitMacos extends DiskKitPlatform {
  /// Creates a transport for the registered macOS native plugin.
  MethodChannelDiskKitMacos();

  bool _progressHandlerInstalled = false;
  void _installProgressHandler() {
    if (_progressHandlerInstalled) return;
    _progressHandlerInstalled = true;
    methodChannel.setMethodCallHandler((call) async {
      if (call.method != 'mediaProgress') return;
      final data = Map<Object?, Object?>.from(call.arguments as Map);
      final callback = _progress[data['operationId']];
      if (callback != null) {
        try {
          callback(MediaOperationProgress.fromMap(data));
        } catch (error, stack) {
          FlutterError.reportError(FlutterErrorDetails(
            exception: error,
            stack: stack,
            library: 'disk_kit_macos',
            context:
                ErrorDescription('while reporting media operation progress'),
          ));
        }
      }
    });
  }

  final _progress = <String, MediaProgressCallback>{};
  static int _nextOperation = 0;

  /// Native request channel. Errors are propagated as [PlatformException].
  final MethodChannel methodChannel = const MethodChannel(
    'eu.byfox.disk_kit/methods',
  );

  /// Native disk snapshot channel, shared by all stream listeners.
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
  Future<DiskInfo> mount(String diskId) =>
      _operate<Object?>('mount', diskId).then(_decodeDisk);

  @override
  Future<DiskInfo> unmount(String diskId, {bool wholeDisk = false}) =>
      _operate<Object?>('unmount', diskId, wholeDisk: wholeDisk)
          .then(_decodeDisk);

  @override
  Future<void> eject(String diskId) => _operate<void>('eject', diskId);

  @override
  Future<DiskInfo> renameVolume(String diskId, {required String volumeName}) =>
      _operate<Object?>('renameVolume', diskId,
          arguments: {'volumeName': volumeName}).then(_decodeDisk);

  @override
  Future<void> copyFromDisk(
    String diskId, {
    required String relativePath,
    required String destinationPath,
  }) =>
      _operate<void>('copyFromDisk', diskId, arguments: {
        'relativePath': relativePath,
        'localPath': destinationPath,
      });

  @override
  Future<void> copyToDisk(
    String diskId, {
    required String sourcePath,
    required String relativePath,
  }) =>
      _operate<void>('copyToDisk', diskId, arguments: {
        'relativePath': relativePath,
        'localPath': sourcePath,
      });

  @override
  Future<void> formatVolume(
    String diskId, {
    required DiskFileSystem fileSystem,
    required String volumeName,
  }) =>
      _operate<void>('formatVolume', diskId, arguments: {
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
      _operate<void>('formatDisk', diskId, arguments: {
        'fileSystem': fileSystem.name,
        'volumeName': volumeName,
        'partitionScheme': partitionScheme.name,
      });

  @override
  Future<void> writeImage(
    String diskId, {
    required String imagePath,
    bool verify = true,
    bool allowElevation = true,
    MediaProgressCallback? onProgress,
  }) =>
      _mediaOperation(
          'writeImage',
          diskId,
          {
            'imagePath': imagePath,
            'verify': verify,
            'allowElevation': allowElevation,
          },
          onProgress);

  @override
  Future<void> createWindowsInstaller(
    String diskId, {
    required String isoPath,
    String? wimlibPath,
    bool verify = true,
    MediaProgressCallback? onProgress,
  }) =>
      _mediaOperation(
          'createWindowsInstaller',
          diskId,
          {
            'isoPath': isoPath,
            if (wimlibPath != null) 'wimlibPath': wimlibPath,
            'verify': verify,
          },
          onProgress);

  @override
  Future<void> createMacOSInstaller(
    String diskId, {
    required String installerAppPath,
    bool allowElevation = true,
    MediaProgressCallback? onProgress,
  }) =>
      _mediaOperation(
          'createMacOSInstaller',
          diskId,
          {
            'installerAppPath': installerAppPath,
            'allowElevation': allowElevation,
          },
          onProgress);

  Future<void> _mediaOperation(String method, String diskId,
      Map<String, Object?> arguments, MediaProgressCallback? callback) async {
    _installProgressHandler();
    final operationId =
        '${DateTime.now().microsecondsSinceEpoch}-${_nextOperation++}';
    if (callback != null) _progress[operationId] = callback;
    try {
      await _operate<void>(method, diskId, arguments: {
        ...arguments,
        'operationId': operationId,
      });
    } finally {
      _progress.remove(operationId);
    }
  }

  Future<T?> _operate<T>(
    String method,
    String diskId, {
    bool? wholeDisk,
    Map<String, Object?> arguments = const {},
  }) async {
    if (!RegExp(r'^disk[0-9]+(?:s[0-9]+)*$').hasMatch(diskId)) {
      throw ArgumentError.value(diskId, 'diskId', 'Expected a macOS BSD name.');
    }
    return methodChannel.invokeMethod<T>(method, {
      'diskId': diskId,
      if (wholeDisk != null) 'wholeDisk': wholeDisk,
      ...arguments,
    });
  }

  DiskInfo _decodeDisk(Object? value) {
    if (value is! Map) {
      throw const FormatException('Expected a DiskInfo map.');
    }
    return DiskInfo.fromMap(Map<Object?, Object?>.from(value));
  }

  List<DiskInfo> _decode(Object? value) {
    if (value is! List) {
      throw const FormatException('Expected a list of DiskInfo maps.');
    }
    return List.unmodifiable(
      value.map(_decodeDisk),
    );
  }
}
