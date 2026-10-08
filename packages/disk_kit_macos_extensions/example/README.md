# DiskKit macOS extensions example

This Flutter macOS application explicitly depends on both `disk_kit` and
`disk_kit_macos_extensions`. It displays formatter availability and actual
read/write access to the roots of external volumes. Refresh after attaching a
disk or installing tools. It never formats, unmounts, or writes to a disk.

From the repository root:

```sh
flutter pub get
cd packages/disk_kit_macos_extensions/example
flutter run -d macos
```

No third-party tools are required to run the screen: absent tools are displayed
as unavailable. To use application-supplied tools, configure `MacosExtensionTools`
in `lib/main.dart` with absolute paths to trusted macOS executables.

Local dependency overrides are excluded from the published archive. The package
README documents the separate destructive formatting API and its limitations.
