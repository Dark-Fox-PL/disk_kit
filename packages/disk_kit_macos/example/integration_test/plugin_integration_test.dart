import 'dart:io';
import 'dart:async';

import 'package:disk_kit/disk_kit.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // These tests exercise platform channels, not physical mouse input.
  binding.shouldPropagateDevicePointerEvents = false;
  const kit = DiskKit();
  const testVolumeName = String.fromEnvironment('DISK_KIT_TEST_VOLUME_NAME');
  const testMountCycle = bool.fromEnvironment('DISK_KIT_TEST_MOUNT_CYCLE');
  const testRename = bool.fromEnvironment('DISK_KIT_TEST_RENAME');

  testWidgets('native discovery and initial stream snapshot', (tester) async {
    final disks = await kit.getDisks();
    expect(disks, isNotEmpty);
    expect(disks.map((disk) => disk.id).toSet().length, disks.length);
    for (final disk in disks) {
      expect(disk.devicePath, '/dev/${disk.id}');
    }
    final snapshot = await kit.watchDisks().first.timeout(
          const Duration(seconds: 10),
        );
    expect(snapshot, isNotEmpty);
    // Re-subscribing after cancellation must deliver a fresh initial snapshot.
    final next = await kit.watchDisks().first.timeout(
          const Duration(seconds: 10),
        );
    expect(next, isNotEmpty);
  });

  testWidgets('a nonexistent target returns a structured native error', (
    tester,
  ) async {
    await expectLater(
      kit.mount('disk999999999'),
      throwsA(
        isA<PlatformException>().having(
          (error) => error.code,
          'code',
          'disk_not_found',
        ),
      ),
    );
  });

  testWidgets('copy round trip on an explicitly selected external volume',
      (tester) async {
    final matches = (await kit.getDisks())
        .where((disk) =>
            disk.volumeName == testVolumeName &&
            disk.isMounted &&
            disk.isInternal == false)
        .toList();
    expect(matches, hasLength(1),
        reason: 'Expected one mounted external volume named $testVolumeName.');
    final volume = matches.single;
    final entries = await Directory(volume.volumePath!).list().length;
    // Only device properties and the entry count are logged, not user filenames.
    // ignore: avoid_print
    print(
        'Physical test: ${volume.id}, whole=${volume.wholeDiskId}, fs=${volume.fileSystem}, size=${volume.sizeBytes}, path=${volume.volumePath}, existingEntries=$entries');
    final temporary =
        await Directory.systemTemp.createTemp('disk-kit-round-trip-');
    final relativePath =
        'DiskKit-test-${DateTime.now().microsecondsSinceEpoch}';
    final onVolume = Directory('${volume.volumePath}/$relativePath');
    final source = await Directory('${temporary.path}/source').create();
    await Directory('${source.path}/nested').create();
    await File('${source.path}/hello.txt')
        .writeAsString('DiskKit copy round trip');
    final bytes = List<int>.generate(8192, (index) => index % 256);
    await File('${source.path}/nested/data.bin').writeAsBytes(bytes);
    try {
      await kit.copyToDisk(volume.id,
          sourcePath: source.path, relativePath: relativePath);
      await expectLater(
        kit.copyToDisk(volume.id,
            sourcePath: source.path, relativePath: relativePath),
        throwsA(isA<PlatformException>()
            .having((error) => error.code, 'code', 'destination_exists')),
      );
      final backup = '${temporary.path}/restored';
      await kit.copyFromDisk(volume.id,
          relativePath: relativePath, destinationPath: backup);
      expect(await File('$backup/hello.txt').readAsString(),
          'DiskKit copy round trip');
      expect(await File('$backup/nested/data.bin').readAsBytes(),
          orderedEquals(bytes));
      expect(await File('${source.path}/hello.txt').exists(), isTrue);
    } finally {
      // Remove only the unique test directory created during this test.
      if (await onVolume.exists()) await onVolume.delete(recursive: true);
      await temporary.delete(recursive: true);
    }
  }, skip: testVolumeName.isEmpty);

  testWidgets('unmount and remount an explicitly selected external volume',
      (tester) async {
    final matches = (await kit.getDisks())
        .where((disk) =>
            disk.volumeName == testVolumeName &&
            disk.isMounted &&
            disk.isInternal == false)
        .toList();
    expect(matches, hasLength(1));
    final volume = matches.single;
    final unmounted = Completer<void>();
    final subscription = kit.watchDisks().listen((snapshot) {
      if (!unmounted.isCompleted &&
          snapshot.any((disk) => disk.id == volume.id && !disk.isMounted)) {
        unmounted.complete();
      }
    });
    var didUnmount = false;
    try {
      final DiskInfo target = await kit.unmount(volume.id);
      expect(target.id, volume.id);
      expect(target.isMounted, isFalse);
      didUnmount = true;
      expect(
          (await kit.getDisks())
              .singleWhere((disk) => disk.id == volume.id)
              .isMounted,
          isFalse);
      await unmounted.future.timeout(const Duration(seconds: 10));
    } finally {
      await subscription.cancel();
      if (didUnmount) {
        final DiskInfo mounted = await kit.mount(volume.id);
        expect(mounted.id, volume.id);
        expect(mounted.isMounted, isTrue);
      }
    }
    expect(
        (await kit.getDisks())
            .singleWhere((disk) => disk.id == volume.id)
            .isMounted,
        isTrue);
  }, skip: testVolumeName.isEmpty || !testMountCycle);

  testWidgets('rename preserves data, returns new metadata, and notifies observers', (tester) async {
    final List<DiskInfo> matches = (await kit.getDisks()).where((DiskInfo disk) =>
      disk.volumeName == testVolumeName && disk.isMounted && disk.isInternal == false).toList();
    expect(matches, hasLength(1));
    final DiskInfo original = matches.single;
    final String newName = 'DK${DateTime.now().millisecondsSinceEpoch % 100000000}';
    final String fileName = 'DiskKit-rename-${DateTime.now().microsecondsSinceEpoch}.txt';
    const String content = 'Renaming preserves this test file.';
    await File('${original.volumePath}/$fileName').writeAsString(content);
    final renamedEvent = Completer<DiskInfo>();
    final StreamSubscription<List<DiskInfo>> subscription = kit.watchDisks().listen((List<DiskInfo> snapshot) {
      for (final DiskInfo disk in snapshot) {
        if (disk.id == original.id && disk.volumeName == newName && !renamedEvent.isCompleted) {
          renamedEvent.complete(disk);
        }
      }
    });
    try {
      final DiskInfo renamed = await kit.renameVolume(original.id, volumeName: newName);
      expect(renamed.id, original.id);
      expect(renamed.volumeName, newName);
      expect(renamed.volumeUuid, original.volumeUuid);
      expect(renamed.isMounted, isTrue);
      expect(await File('${renamed.volumePath}/$fileName').readAsString(), content);
      expect((await renamedEvent.future.timeout(const Duration(seconds: 10))).volumeName, newName);
      await expectLater(kit.renameVolume(original.id, volumeName: 'BAD/NAME'),
        throwsA(isA<PlatformException>().having((error) => error.code, 'code', 'invalid_arguments')));
    } finally {
      await subscription.cancel();
      DiskInfo current = (await kit.getDisks()).singleWhere((DiskInfo disk) => disk.id == original.id);
      if (current.volumeName != testVolumeName) {
        current = await kit.renameVolume(current.id, volumeName: testVolumeName);
      }
      expect(current.volumeName, testVolumeName);
      final File fixture = File('${current.volumePath}/$fileName');
      if (await fixture.exists()) await fixture.delete();
    }
  }, skip: testVolumeName.isEmpty || !testRename);

}
