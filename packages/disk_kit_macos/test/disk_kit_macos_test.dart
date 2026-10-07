import 'package:disk_kit_macos/disk_kit_macos.dart';
import 'package:disk_kit_platform_interface/disk_kit_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Dart registration installs the shared platform implementation', () {
    final original = DiskKitPlatform.instance;
    addTearDown(() => DiskKitPlatform.instance = original);
    DiskKitMacos.registerWith();
    expect(DiskKitPlatform.instance, isA<DiskKitMacos>());
  });
}
