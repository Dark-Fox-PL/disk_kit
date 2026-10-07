import 'package:disk_kit_platform_interface/disk_kit_platform_interface.dart';

import 'disk_kit_macos_method_channel.dart';

/// Automatically registered macOS implementation of DiskKit.
class DiskKitMacos extends MethodChannelDiskKitMacos {
  /// Installs this implementation in the shared platform interface.
  /// Flutter invokes this automatically when registering macOS plugins.
  static void registerWith() {
    DiskKitPlatform.instance = DiskKitMacos();
  }
}
