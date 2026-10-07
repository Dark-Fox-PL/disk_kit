/// Filesystems supported by the initial macOS implementation.
enum DiskFileSystem { exFat, fat32, apfs, hfsPlus }

/// Partition table to create when formatting an entire disk.
enum DiskPartitionScheme { gpt, mbr }
