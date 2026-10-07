## Unreleased

- Show readable filesystem names in both examples, including HFS+ (Mac OS Extended, Journaled).
- Add an explicit HFS+ formatting example to the README; the existing API remains unchanged.

## 1.0.1

- Simplify the README section on CocoaPods and Swift Package Manager and link to the macOS implementation guide for details.

## 1.0.0

- Add raw IMG / USB-compatible hybrid ISO writing with optional read-back verification.
- Add Windows UEFI installation media preparation, including preflight FAT32 checks and optional oversized WIM splitting with caller-installed wimlib.
- Add macOS installation media preparation from an Apple-signed installer app.
- Add typed media stages and progress callbacks; allow system administrator authorization for raw writing and macOS installers.
- Update both examples, documentation, and explicit opt-in media tests.
- Require the matching 1.0.0 federated implementation and platform interface.

## 0.0.2

* Add a runnable macOS example to the public package, including widget and integration tests.
* Document the library and link installation and example instructions from the README.
* Exclude local dependency overrides and generated build artifacts from publication.

## 0.0.1

* Initial experimental macOS API: discovery, snapshots, mounting, unmounting, ejecting, file/directory copies, and external disk/volume formatting.

* Add volume renaming and typed DiskInfo results for mount, unmount, and rename operations.
