# disk_kit_platform_interface

Shared Flutter platform interface for DiskKit. Platform implementations use this package to provide a consistent contract to the app-facing `disk_kit` package.

The interface is currently an initial scaffold. Disk discovery, volume details, change notifications, and other operations have not been defined yet.

This package is part of the [DiskKit workspace](https://github.com/Dark-Fox-PL/disk_kit). The initial implementation target is macOS; other platform implementations may be added in future releases.

## Development

From the workspace root, run `flutter pub get` to resolve local workspace packages.

## License

This package is distributed under the MIT License. See [LICENSE](LICENSE).
