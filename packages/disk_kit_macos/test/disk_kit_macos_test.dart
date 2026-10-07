import 'package:flutter_test/flutter_test.dart';
import 'package:disk_kit_macos/disk_kit_macos.dart';
import 'package:disk_kit_macos/disk_kit_macos_platform_interface.dart';
import 'package:disk_kit_macos/disk_kit_macos_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockDiskKitMacosPlatform
    with MockPlatformInterfaceMixin
    implements DiskKitMacosPlatform {
  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final DiskKitMacosPlatform initialPlatform = DiskKitMacosPlatform.instance;

  test('$MethodChannelDiskKitMacos is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelDiskKitMacos>());
  });

  test('getPlatformVersion', () async {
    DiskKitMacos diskKitMacosPlugin = DiskKitMacos();
    MockDiskKitMacosPlatform fakePlatform = MockDiskKitMacosPlatform();
    DiskKitMacosPlatform.instance = fakePlatform;

    expect(await diskKitMacosPlugin.getPlatformVersion(), '42');
  });
}
