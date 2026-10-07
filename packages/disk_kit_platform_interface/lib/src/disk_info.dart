/// A storage device, partition, or volume reported by the operating system.
///
/// On macOS [id] is a BSD name, such as `disk4` or `disk4s1`. It can change or
/// be reused after removal; refresh the list before performing an operation.
/// Missing native properties are represented by null, rather than inferred.
class DiskInfo {
  const DiskInfo({
    required this.id,
    required this.devicePath,
    this.wholeDiskId,
    this.name,
    this.volumeName,
    this.volumePath,
    this.fileSystem,
    this.mediaContent,
    this.sizeBytes,
    this.busProtocol,
    this.vendor,
    this.model,
    this.volumeUuid,
    this.mediaUuid,
    this.isWholeDisk,
    this.isInternal,
    this.isRemovable,
    this.isEjectable,
    this.isWritable,
    this.isMountable,
  });

  /// Identifier to pass to DiskKit operations; not a persistent identity.
  final String id;

  /// Native device node, for example `/dev/disk4s1` on macOS.
  final String devicePath;

  /// The containing whole disk, when available (also reported for whole disks).
  final String? wholeDiskId;
  final String? name;
  final String? volumeName;

  /// Mount point; null when the volume is not mounted.
  final String? volumePath;

  /// Native filesystem kind, for example `exfat`, `msdos`, or `apfs` on macOS.
  final String? fileSystem;

  /// Native media content or partition type, such as `EFI` on macOS.
  final String? mediaContent;
  final int? sizeBytes;
  final String? busProtocol;
  final String? vendor;
  final String? model;
  final String? volumeUuid;
  final String? mediaUuid;
  final bool? isWholeDisk;
  final bool? isInternal;
  final bool? isRemovable;
  final bool? isEjectable;

  /// Whether the media is writable; this does not imply filesystem access.
  final bool? isWritable;
  final bool? isMountable;

  bool get isMounted => volumePath != null;

  /// Decode the shared platform-channel representation.
  factory DiskInfo.fromMap(Map<Object?, Object?> map) {
    if (map['id'] is! String || map['devicePath'] is! String) {
      throw const FormatException(
          'DiskInfo requires id and devicePath strings.');
    }
    return DiskInfo(
      id: map['id']! as String,
      devicePath: map['devicePath']! as String,
      wholeDiskId: map['wholeDiskId'] as String?,
      name: map['name'] as String?,
      volumeName: map['volumeName'] as String?,
      volumePath: map['volumePath'] as String?,
      fileSystem: map['fileSystem'] as String?,
      mediaContent: map['mediaContent'] as String?,
      sizeBytes: map['sizeBytes'] as int?,
      busProtocol: map['busProtocol'] as String?,
      vendor: map['vendor'] as String?,
      model: map['model'] as String?,
      volumeUuid: map['volumeUuid'] as String?,
      mediaUuid: map['mediaUuid'] as String?,
      isWholeDisk: map['isWholeDisk'] as bool?,
      isInternal: map['isInternal'] as bool?,
      isRemovable: map['isRemovable'] as bool?,
      isEjectable: map['isEjectable'] as bool?,
      isWritable: map['isWritable'] as bool?,
      isMountable: map['isMountable'] as bool?,
    );
  }
}
