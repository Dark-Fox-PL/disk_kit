import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:disk_kit_macos/disk_kit_macos_method_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MethodChannelDiskKitMacos platform = MethodChannelDiskKitMacos();
  const MethodChannel channel = MethodChannel('disk_kit_macos');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
          return '42';
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('getPlatformVersion', () async {
    expect(await platform.getPlatformVersion(), '42');
  });
}
