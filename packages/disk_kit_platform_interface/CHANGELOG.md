## 1.0.0

- Add raw IMG / USB-compatible hybrid ISO writing with optional read-back verification.
- Add Windows UEFI installation media preparation, including preflight FAT32 checks and optional oversized WIM splitting with caller-installed wimlib.
- Add macOS installation media preparation from an Apple-signed installer app.
- Add typed media stages and progress callbacks; allow system administrator authorization for raw writing and macOS installers.
- Update both examples, documentation, and explicit opt-in media tests.
- Keep unsupported defaults for platform implementations that do not support media preparation.

## 0.0.1

* Introduce the shared DiskKitPlatform contract, DiskInfo model, filesystem options, and partition schemes.

* Add volume renaming and typed DiskInfo results for mount, unmount, and rename operations.
