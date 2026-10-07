import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'disk_kit_macos_platform_interface.dart';

/// An implementation of [DiskKitMacosPlatform] that uses method channels.
class MethodChannelDiskKitMacos extends DiskKitMacosPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('disk_kit_macos');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }
}
