import 'dart:async';

import 'package:disk_kit_macos/disk_kit_macos_method_channel.dart';
import 'package:disk_kit_platform_interface/disk_kit_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const methods = MethodChannel('eu.byfox.disk_kit/methods');
  const events = MethodChannel('eu.byfox.disk_kit/disks');
  const fixture = [
    {
      'id': 'disk4s1',
      'devicePath': '/dev/disk4s1',
      'fileSystem': 'exfat',
      'sizeBytes': 8000000000,
      'volumePath': '/Volumes/USB'
    }
  ];
  late MethodChannelDiskKitMacos platform;
  final calls = <MethodCall>[];

  setUp(() {
    platform = MethodChannelDiskKitMacos();
    calls.clear();
    messenger.setMockMethodCallHandler(methods, (call) async {
      calls.add(call);
      if (call.method == 'getDisks') return fixture;
      if (['mount', 'unmount', 'renameVolume'].contains(call.method)) {
        final args = Map<String, Object?>.from(call.arguments as Map);
        return {
          'id': args['diskId'],
          'devicePath': '/dev/${args['diskId']}',
          if (call.method == 'mount') 'volumePath': '/Volumes/USB',
          if (call.method == 'renameVolume') 'volumeName': args['volumeName'],
        };
      }
      return null;
    });
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(methods, null);
    messenger.setMockMethodCallHandler(events, null);
  });

  test('decodes a snapshot and returns an immutable list', () async {
    final disks = await platform.getDisks();
    expect(disks.single.sizeBytes, 8000000000);
    expect(disks.single.isMounted, isTrue);
    expect(() => disks.clear(), throwsUnsupportedError);
  });

  test('serializes image and installer operations with safe defaults',
      () async {
    await platform.writeImage('disk4', imagePath: '/tmp/ubuntu.iso');
    await platform.createWindowsInstaller('disk4',
        isoPath: '/tmp/windows.iso', wimlibPath: '/tmp/wimlib');
    await platform.createMacOSInstaller('disk4',
        installerAppPath: '/Applications/Install macOS.app',
        allowElevation: false);
    expect(calls.map((call) => call.method),
        ['writeImage', 'createWindowsInstaller', 'createMacOSInstaller']);
    final raw = Map<String, Object?>.from(calls[0].arguments as Map);
    expect(raw['diskId'], 'disk4');
    expect(raw['verify'], isTrue);
    expect(raw['allowElevation'], isTrue);
    expect(raw['imagePath'], '/tmp/ubuntu.iso');
    expect(raw['operationId'], isA<String>());
    expect((calls[1].arguments as Map)['wimlibPath'], '/tmp/wimlib');
    expect((calls[2].arguments as Map)['allowElevation'], isFalse);
  });

  test('native progress reaches only the operation callback', () async {
    messenger.setMockMethodCallHandler(methods, (call) async {
      final args = Map<Object?, Object?>.from(call.arguments as Map);
      // ignore: deprecated_member_use
      await messenger.handlePlatformMessage(
          methods.name,
          const StandardMethodCodec()
              .encodeMethodCall(MethodCall('mediaProgress', {
            'operationId': args['operationId'],
            'diskId': args['diskId'],
            'stage': 'writing',
            'bytesCompleted': 512,
            'totalBytes': 1024,
          })),
          (_) {});
      return null;
    });
    final updates = <MediaOperationProgress>[];
    await platform.writeImage('disk4',
        imagePath: '/tmp/image.img', onProgress: updates.add);
    expect(updates.single.stage, MediaOperationStage.writing);
    expect(updates.single.fraction, 0.5);
  });

  test('copy options and file events reach only the active callback', () async {
    final updates = <FileCopyProgress>[];
    String? operationId;
    Future<void> emit(String id) async {
      // ignore: deprecated_member_use
      await messenger.handlePlatformMessage(
          methods.name,
          const StandardMethodCodec()
              .encodeMethodCall(MethodCall('fileCopyProgress', {
            'operationId': id,
            'path': '/Volumes/USB/a.txt',
            'bytes': 12,
            'completed': true,
          })),
          (_) {});
    }

    messenger.setMockMethodCallHandler(methods, (call) async {
      final args = call.arguments as Map;
      expect(args['parallel'], isFalse);
      operationId = args['operationId'] as String;
      await emit('other-operation');
      await emit(operationId!);
      return null;
    });
    await platform.copyFromDisk('disk4s1',
        relativePath: 'a.txt',
        destinationPath: '/tmp/a.txt',
        parallel: false,
        onProgress: updates.add);
    expect(updates.single.path, '/Volumes/USB/a.txt');
    expect(updates.single.bytes, 12);
    expect(updates.single.completed, isTrue);
    await emit(operationId!);
    expect(updates.length, 1,
        reason: 'Callbacks are removed when the future finishes');
  });

  test('serializes all operation arguments', () async {
    await platform.mount('disk4s1');
    await platform.unmount('disk4', wholeDisk: true);
    await platform.eject('disk4');
    await platform.copyFromDisk('disk4s1',
        relativePath: 'a', destinationPath: '/tmp/b');
    await platform.copyToDisk('disk4s1',
        sourcePath: '/tmp/b', relativePath: 'a');
    await platform.formatVolume('disk4s1',
        fileSystem: DiskFileSystem.exFat, volumeName: 'USB');
    await platform.formatDisk('disk4',
        fileSystem: DiskFileSystem.fat32,
        volumeName: 'USB',
        partitionScheme: DiskPartitionScheme.mbr);
    expect(calls.map((call) => call.method), [
      'mount',
      'unmount',
      'eject',
      'copyFromDisk',
      'copyToDisk',
      'formatVolume',
      'formatDisk'
    ]);
    expect(calls[1].arguments, {'diskId': 'disk4', 'wholeDisk': true});
    expect(calls[3].arguments, {
      'diskId': 'disk4s1',
      'relativePath': 'a',
      'localPath': '/tmp/b',
      'parallel': true,
      'operationId': isA<String>()
    });
    expect(calls[4].arguments, {
      'diskId': 'disk4s1',
      'relativePath': 'a',
      'localPath': '/tmp/b',
      'parallel': true,
      'operationId': isA<String>()
    });
    expect(calls[5].arguments,
        {'diskId': 'disk4s1', 'fileSystem': 'exFat', 'volumeName': 'USB'});
    expect(calls[6].arguments, {
      'diskId': 'disk4',
      'fileSystem': 'fat32',
      'volumeName': 'USB',
      'partitionScheme': 'mbr'
    });
  });

  test('mount and unmount return the actual target description', () async {
    final DiskInfo mounted = await platform.mount('disk4s1');
    expect(mounted.id, 'disk4s1');
    expect(mounted.isMounted, isTrue);
    final DiskInfo unmounted = await platform.unmount('disk4s1');
    expect(unmounted.id, 'disk4s1');
    expect(unmounted.isMounted, isFalse);
    final DiskInfo whole = await platform.unmount('disk4', wholeDisk: true);
    expect(whole.id, 'disk4');
  });

  test('serializes volume rename requests', () async {
    final DiskInfo renamed =
        await platform.renameVolume('disk4s1', volumeName: 'NEW_USB');
    expect(renamed.id, 'disk4s1');
    expect(renamed.volumeName, 'NEW_USB');
    expect(calls.single.method, 'renameVolume');
    expect(
        calls.single.arguments, {'diskId': 'disk4s1', 'volumeName': 'NEW_USB'});
  });

  test('invalid identifiers never reach native code', () async {
    for (final id in ['', '/dev/disk4', 'disk4;rm -rf /', 'disk']) {
      await expectLater(platform.eject(id), throwsArgumentError);
    }
    expect(calls, isEmpty);
  });

  test('preserves structured native errors', () async {
    messenger.setMockMethodCallHandler(
        methods,
        (_) async => throw PlatformException(
            code: 'disk_busy', message: 'Busy', details: {'status': 16}));
    await expectLater(
        platform.unmount('disk4s1'),
        throwsA(isA<PlatformException>()
            .having((e) => e.code, 'code', 'disk_busy')
            .having((e) => e.details, 'details', {'status': 16})));
  });

  test('malformed snapshots fail rather than appearing empty', () async {
    messenger.setMockMethodCallHandler(methods, (_) async => null);
    await expectLater(platform.getDisks(), throwsFormatException);
  });

  test('shares an event subscription and cancels when last listener leaves',
      () async {
    final listen = Completer<void>();
    final cancel = Completer<void>();
    messenger.setMockMethodCallHandler(events, (call) async {
      if (call.method == 'listen') listen.complete();
      if (call.method == 'cancel') cancel.complete();
      return null;
    });
    final first = Completer<List<DiskInfo>>();
    final second = Completer<List<DiskInfo>>();
    final stream = platform.watchDisks();
    expect(stream.isBroadcast, isTrue);
    expect(identical(stream, platform.watchDisks()), isTrue);
    final a = stream.listen(first.complete);
    final b = stream.listen(second.complete);
    await listen.future;
    await messenger.handlePlatformMessage(events.name,
        const StandardMethodCodec().encodeSuccessEnvelope(fixture), null);
    expect((await first.future).single.id, 'disk4s1');
    expect((await second.future).single.id, 'disk4s1');
    await a.cancel();
    expect(cancel.isCompleted, isFalse);
    await b.cancel();
    await cancel.future;
  });
}
