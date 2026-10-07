## 1.0.0

- Add raw IMG / USB-compatible hybrid ISO writing with optional read-back verification.
- Add Windows UEFI installation media preparation, including preflight FAT32 checks and optional oversized WIM splitting with caller-installed wimlib.
- Add macOS installation media preparation from an Apple-signed installer app.
- Add typed media stages and progress callbacks; allow system administrator authorization for raw writing and macOS installers.
- Update both examples, documentation, and explicit opt-in media tests.
- Require platform interface 1.0.0 and link Security with CocoaPods and SwiftPM.

## 0.0.1

* Implement Disk Arbitration discovery callbacks and volume operations, with IOKit initial enumeration.
* Add native file/directory copies and external formatting through diskutil.
* Add automatic Dart registration, native errors, and a public API example for macOS 12+.

* Add volume renaming and typed DiskInfo results for mount, unmount, and rename operations.
