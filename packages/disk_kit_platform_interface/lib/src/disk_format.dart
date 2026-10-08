/// Filesystems accepted by the macOS formatting implementation.
///
/// Support also depends on the target's layout, capacity, and OS permissions.
/// These options are not a guarantee that every volume can be converted in place.
enum DiskFileSystem {
  /// exFAT. The label is limited to 15 UTF-16 code units on macOS.
  exFat,

  /// FAT32. The initial label validation accepts 1–11 uppercase ASCII letters,
  /// digits, underscores, or spaces. Filesystem size restrictions still apply.
  fat32,

  /// Apple File System. Whole-disk formatting requires GPT.
  apfs,

  /// Journaled, case-insensitive Mac OS Extended (HFS+).
  hfsPlus,

  /// Case-sensitive Apple File System. Whole-disk formatting requires GPT.
  apfsCaseSensitive,

  /// Non-journaled, case-insensitive Mac OS Extended (HFS+).
  hfsPlusNonJournaled,

  /// Non-journaled, case-sensitive Mac OS Extended (HFS+).
  hfsPlusCaseSensitive,

  /// Journaled, case-sensitive Mac OS Extended (HFS+).
  hfsPlusCaseSensitiveJournaled;

  /// Whether whole-disk formatting on macOS requires a GUID Partition Table.
  bool get requiresGpt => this == apfs || this == apfsCaseSensitive;
}

/// Partition table created when formatting an entire disk.
///
/// Volume-only formatting preserves the existing partition table.
enum DiskPartitionScheme {
  /// GUID Partition Table; the default and the required scheme for both APFS variants.
  gpt,

  /// Master Boot Record; supported for compatible FAT32, exFAT, and HFS+ targets.
  mbr,
}
