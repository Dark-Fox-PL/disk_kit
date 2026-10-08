/// Optional filesystem tools for DiskKit on macOS.
///
/// Add this package explicitly; it does not replace DiskKit's platform plugin.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Additional filesystems handled independently of DiskKit's native formats.
enum MacosExtensionFileSystem {
  /// NTFS, formatted with a macOS build of mkntfs.
  ntfs,

  /// ext2, formatted with a macOS build of mke2fs.
  ext2,

  /// ext3, formatted with a macOS build of mke2fs.
  ext3,

  /// ext4, formatted with a macOS build of mke2fs.
  ext4,

  /// Reserved for future support; formatting is currently unavailable.
  btrfs,
}

/// Whether an operation is available, unavailable, or has not been determined.
enum MacosCapabilityStatus {
  /// The necessary tool was found and answered its version probe.
  available,

  /// The operation is unsupported or its tool is missing or unusable.
  unavailable,

  /// Availability cannot be inferred; inspect an actual mounted volume.
  unknown,
}

/// Trusted macOS executables supplied by an application or installed by its user.
///
/// Paths must be absolute. Null enables discovery in standard Homebrew paths.
/// These executables run with the application's privileges. No tools or drivers
/// are downloaded, installed, or bundled by this package.
class MacosExtensionTools {
  /// Configures optional formatter paths.
  const MacosExtensionTools({this.mkntfsPath, this.mke2fsPath});

  /// Absolute path to mkntfs from NTFS-3G.
  final String? mkntfsPath;

  /// Absolute path to mke2fs from e2fsprogs.
  final String? mke2fsPath;

  Map<String, Object?> _toMap() => {
        'mkntfsPath': mkntfsPath,
        'mke2fsPath': mke2fsPath,
      };
}

/// Formatter availability for one filesystem; distinct from volume access.
class MacosFileSystemCapabilities {
  MacosFileSystemCapabilities._(Map<Object?, Object?> map)
      : fileSystem = MacosExtensionFileSystem.values
            .byName(map['fileSystem']! as String),
        formatting =
            MacosCapabilityStatus.values.byName(map['formatting']! as String),
        toolPath = map['toolPath'] as String?,
        toolVersion = map['toolVersion'] as String?,
        reason = map['reason']! as String;

  /// Filesystem described by this result.
  final MacosExtensionFileSystem fileSystem;

  /// A runnable tool enables formatting attempts; target permissions and
  /// compatibility are checked separately and can still prevent formatting.
  final MacosCapabilityStatus formatting;

  /// Reading cannot be inferred from a formatter; use getVolumeAccess instead.
  MacosCapabilityStatus get reading => MacosCapabilityStatus.unknown;

  /// Writing cannot be inferred from a formatter; use getVolumeAccess instead.
  MacosCapabilityStatus get writing => MacosCapabilityStatus.unknown;

  /// Resolved executable path; null when no usable tool was found.
  final String? toolPath;

  /// Bounded version output; null when no usable tool was found.
  final String? toolVersion;

  /// Explanation of availability or the missing prerequisite.
  final String reason;
}

/// Access to the root of an actual volume under the host application's privileges.
///
/// This does not verify every file or bypass macOS privacy restrictions.
class MacosVolumeAccess {
  MacosVolumeAccess._(Map<Object?, Object?> map)
      : diskId = map['diskId']! as String,
        fileSystem = map['fileSystem'] as String?,
        mountPath = map['mountPath'] as String?,
        canRead = map['canRead'] as bool?,
        canWrite = map['canWrite'] as bool?;

  /// Current BSD identifier of the inspected volume.
  final String diskId;

  /// Native filesystem kind; null when macOS does not recognize it.
  final String? fileSystem;

  /// Actual mount point; null when unmounted.
  final String? mountPath;

  /// Whether the mounted root is readable; null when unmounted.
  final bool? canRead;

  /// Whether the mounted root is writable and the mount permits writing;
  /// null when unmounted. A true value does not guarantee every copy succeeds.
  final bool? canWrite;
}

/// An external partition validated for a possible destructive operation.
///
/// The native token binds it to the current attachment for five minutes and is
/// consumed by a formatting attempt. Prepare a fresh target before retrying.
class MacosFormatTarget {
  MacosFormatTarget._(Map<Object?, Object?> map)
      : diskId = map['diskId']! as String,
        wholeDiskId = map['wholeDiskId']! as String,
        _token = map['token']! as String;

  /// Partition to format; all data on this partition will be lost.
  final String diskId;

  /// Containing physical disk, used to serialize operations in this extension.
  final String wholeDiskId;
  final String _token;
}

/// Explicitly opted-in macOS filesystem extensions for DiskKit.
///
/// Uses a separate channel and preserves DiskKit's registered implementation.
/// Callers must serialize disk operations across the core and this extension.
class DiskKitMacosExtensions {
  /// Creates a handle using trusted tools or standard Homebrew discovery paths.
  const DiskKitMacosExtensions({this.tools = const MacosExtensionTools()});

  /// Executable discovery configuration.
  final MacosExtensionTools tools;

  static const _channel = MethodChannel('eu.byfox.disk_kit/extensions');

  void _checkPlatform() {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.macOS) {
      throw UnsupportedError('DiskKit macOS extensions require macOS.');
    }
  }

  /// Probes tools without accessing a disk or requesting authorization.
  ///
  /// Version probes execute the configured trusted binaries. The result is a
  /// snapshot, not a guarantee that a later formatting operation will succeed.
  Future<List<MacosFileSystemCapabilities>> getCapabilities() async {
    _checkPlatform();
    final values = await _channel.invokeListMethod<Object?>(
        'getCapabilities', tools._toMap());
    return List.unmodifiable(values!.map((value) =>
        MacosFileSystemCapabilities._(value! as Map<Object?, Object?>)));
  }

  /// Inspects current mount access; installs no driver and writes no files.
  Future<MacosVolumeAccess> getVolumeAccess(String diskId) async {
    _checkPlatform();
    final value = await _channel.invokeMapMethod<Object?, Object?>(
        'getVolumeAccess', {'diskId': diskId});
    return MacosVolumeAccess._(value!);
  }

  /// Validates an external physical partition without changing its contents.
  ///
  /// Whole disks, disk images, internal or unknown devices, EFI/system
  /// partitions, and synthesized volumes are rejected. Show confirmation for
  /// this target to the user, then pass it to formatVolume.
  Future<MacosFormatTarget> prepareFormat(String diskId) async {
    _checkPlatform();
    final value = await _channel
        .invokeMapMethod<Object?, Object?>('prepareFormat', {'diskId': diskId});
    return MacosFormatTarget._(value!);
  }

  /// Erases an existing external partition using a trusted formatter.
  ///
  /// Requires explicit caller confirmation. Unmounts all volumes on its disk
  /// without force, claims it through Disk Arbitration, and checks attachment
  /// identity before execution. No repartitioning or automatic remount occurs.
  /// Requires a Microsoft Basic Data/NTFS partition type for NTFS, or a Linux
  /// Filesystem partition type for ext. Metadata is preserved; prepare the layout
  /// separately. APFS/CoreStorage/container partitions are not supported.
  ///
  /// No elevation is implemented: insufficient device permissions produce
  /// permission_denied before unmounting. A failed formatter can leave the
  /// partition unusable; this API provides no rollback or cancellation.
  Future<void> formatVolume(
    MacosFormatTarget target, {
    required MacosExtensionFileSystem fileSystem,
    required String volumeName,
  }) async {
    _checkPlatform();
    await _channel.invokeMethod<void>('formatVolume', {
      ...tools._toMap(),
      'token': target._token,
      'fileSystem': fileSystem.name,
      'volumeName': volumeName,
    });
  }
}
