## 0.1.0

- Introduce an explicitly opted-in macOS plugin alongside the core DiskKit implementation.
- Discover caller-supplied or Homebrew-installed mkntfs and mke2fs using bounded version probes.
- Report formatting capabilities independently from reading and writing; inspect access to mounted volume roots.
- Add attachment-bound, expiring format targets and external partition formatting for NTFS and ext2/ext3/ext4.
- Unmount without force, claim disks through Disk Arbitration, block remounting during formatting, and reject internal, virtual, container, and system targets.
- Keep Btrfs formatting explicitly unavailable. Do not bundle, install, elevate, or mount third-party filesystem tools or drivers.
- Include CocoaPods and Swift Package Manager integration and a read-only example.
