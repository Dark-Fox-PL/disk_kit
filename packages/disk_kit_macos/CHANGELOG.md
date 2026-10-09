## 1.2.0

- Copy directories with at most four concurrent file workers by default; `parallel: false` uses one worker. Run independent disk operations on a concurrent background queue while preserving per-disk exclusion.
- Report file start/completion through operation-correlated `fileCopyProgress` method-channel events; remove callbacks when the operation future finishes.
- Drain active workers before returning errors, retain partial output, preserve nested symlinks, and apply directory metadata after descendants.
- Reject existing copy destinations, including dangling symlinks. Copies still never merge or overwrite and have no chunk progress, in-flight cancellation or checksum verification.
- Require platform interface 2.0.0; extend native, transport and public example tests without formatting real disks.

## 1.1.0

- Map the additional APFS/HFS+ variants to native diskutil formats and reject MBR for both APFS variants.
- Require platform interface 1.1.0 and update the example format selector.

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
