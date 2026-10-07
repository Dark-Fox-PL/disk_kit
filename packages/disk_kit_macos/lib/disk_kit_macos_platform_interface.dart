import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'disk_kit_macos_method_channel.dart';

abstract class DiskKitMacosPlatform extends PlatformInterface {
  /// Constructs a DiskKitMacosPlatform.
  DiskKitMacosPlatform() : super(token: _token);

  static final Object _token = Object();

  static DiskKitMacosPlatform _instance = MethodChannelDiskKitMacos();

  /// The default instance of [DiskKitMacosPlatform] to use.
  ///
  /// Defaults to [MethodChannelDiskKitMacos].
  static DiskKitMacosPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [DiskKitMacosPlatform] when
  /// they register themselves.
  static set instance(DiskKitMacosPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
