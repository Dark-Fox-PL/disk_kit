/// A storage device, partition, or volume reported by the operating system.
///
/// On macOS [id] is a BSD name, such as `disk4` or `disk4s1`. It can change or
/// be reused after removal; refresh the list before performing an operation.
/// Missing native properties are represented by null, rather than inferred.
class DiskInfo {
  /// Creates an immutable description. Leave unknown native properties null.
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

  /// Native media name; may differ from the user-visible volume label.
  final String? name;

  /// Filesystem volume label, when the OS recognizes one.
  final String? volumeName;

  /// Mount point; null when the volume is not mounted.
  final String? volumePath;

  /// Native filesystem kind, for example `exfat`, `msdos`, or `apfs` on macOS.
  final String? fileSystem;

  /// Native media content or partition type, such as `EFI` on macOS.
  final String? mediaContent;

  /// Capacity of this media object in bytes, not available free space.
  /// For a partition, this is the partition size rather than the whole disk size.
  final int? sizeBytes;

  /// Native connection type, such as `USB`, `PCI-Express`, or `Disk Image`.
  final String? busProtocol;

  /// Device vendor reported by the operating system.
  final String? vendor;

  /// Device model reported by the operating system.
  final String? model;

  /// Filesystem volume UUID, when available. Formatting can replace it.
  final String? volumeUuid;

  /// Media or partition UUID, when available. Repartitioning can replace it.
  final String? mediaUuid;

  /// Whether this entry represents a whole disk rather than one of its slices.
  final bool? isWholeDisk;

  /// Whether the OS identifies the device as internal.
  /// A false value identifies external media; null means unknown.
  final bool? isInternal;

  /// Whether the media itself is removable according to the OS.
  /// An external USB device is not necessarily reported as removable.
  final bool? isRemovable;

  /// Whether the OS reports the media as ejectable.
  /// This does not guarantee that an eject request will succeed.
  final bool? isEjectable;

  /// Whether the media is writable; this does not imply filesystem access.
  final bool? isWritable;

  /// Whether the OS recognizes a mountable filesystem on this entry.
  /// This is independent of whether it is currently mounted.
  final bool? isMountable;

  /// Whether the current description contains a mount point.
  bool get isMounted => volumePath != null;

  /// Decodes the shared platform-channel representation.
  ///
  /// [map] must contain String values for `id` and `devicePath`; absent optional
  /// keys remain null. Throws [FormatException] when required identifiers are
  /// missing, or [TypeError] when an optional property has the wrong type.
  /// Platform implementation packages use this factory to decode native data.
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
