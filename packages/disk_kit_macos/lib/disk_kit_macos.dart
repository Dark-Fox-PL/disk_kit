
import 'disk_kit_macos_platform_interface.dart';

class DiskKitMacos {
  Future<String?> getPlatformVersion() {
    return DiskKitMacosPlatform.instance.getPlatformVersion();
  }
}
