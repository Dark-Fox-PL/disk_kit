import 'dart:io';

import 'package:disk_kit/disk_kit.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Explicitly destructive physical-media test. Fixtures are synthetic; passing
/// demonstrates transport, byte verification, and FAT32 preparation, not booting.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.shouldPropagateDevicePointerEvents = false;
  binding.platformDispatcher.onPointerDataPacket = null;
  const kit = DiskKit();
  const volumeName = String.fromEnvironment('DISK_KIT_TEST_VOLUME_NAME');
  const erase = bool.fromEnvironment('DISK_KIT_ERASE_TEST_DRIVE');
  const raw =
      bool.fromEnvironment('DISK_KIT_TEST_RAW_IMAGE', defaultValue: true);

  testWidgets('raw image and Windows UEFI layout on explicitly selected USB',
      (tester) async {
    final disks = await kit.getDisks();
    final volumes = disks
        .where(
            (disk) => disk.volumeName == volumeName && disk.isInternal == false)
        .toList();
    expect(volumes, hasLength(1),
        reason:
            'Expected exactly one external volume named $volumeName; external entries: ${disks.where((d) => d.isInternal == false).map((d) => "${d.id}:${d.volumeName}:${d.volumePath}").join(", ")}');
    final discovered = volumes.single;
    final volume =
        discovered.isMounted ? discovered : await kit.mount(discovered.id);
    final whole = disks.singleWhere(
        (disk) => disk.id == volume.wholeDiskId && disk.isWholeDisk == true);
    expect(whole.busProtocol, 'USB');
    expect(whole.isWritable, isTrue);
    final temporary =
        await Directory.systemTemp.createTemp('disk-kit-media-test-');
    final image = File('${temporary.path}/fixture.img');
    // 16 MiB of deterministic data; no actual OS bootloader is included.
    final data =
        Uint8List.fromList(List.generate(16 * 1024 * 1024, (i) => i % 251));
    await image.writeAsBytes(data, flush: true);
    final optical = File('${temporary.path}/ordinary.iso');
    await optical.writeAsBytes(Uint8List(4096));
    final originalProbe = File(
        '${volume.volumePath}/DiskKit-preflight-${DateTime.now().microsecondsSinceEpoch}.txt');
    await originalProbe.writeAsString('preserved until erasure');
    final updates = <MediaOperationProgress>[];
    void report(MediaOperationProgress progress) {
      if (updates.isEmpty || updates.last.stage != progress.stage) {
        // ignore: avoid_print
        print('Media stage: ${progress.stage.name}');
      }
      updates.add(progress);
    }

    try {
      await expectLater(
          kit.writeImage(whole.id, imagePath: optical.path),
          throwsA(isA<PlatformException>()
              .having((e) => e.code, 'code', 'unsupported_image')));
      expect(await originalProbe.readAsString(), 'preserved until erasure');
      await expectLater(
          kit.createMacOSInstaller(whole.id,
              installerAppPath: '${temporary.path}/missing.app'),
          throwsA(isA<PlatformException>()));
      expect(await originalProbe.readAsString(), 'preserved until erasure');
      final onTarget = File('${volume.volumePath}/DiskKit-source.img');
      await onTarget.writeAsBytes(Uint8List(512));
      await expectLater(
          kit.writeImage(whole.id, imagePath: onTarget.path),
          throwsA(isA<PlatformException>()
              .having((e) => e.code, 'code', 'source_on_target')));
      await onTarget.delete();
      await originalProbe.delete();
      // Explicit opt-in permits the macOS administrator dialog. No credentials
      // are supplied by this test or collected by DiskKit.
      if (raw) {
        await kit.writeImage(whole.id,
            imagePath: image.path, onProgress: report);
        expect(updates.any((p) => p.stage == MediaOperationStage.verifying),
            isTrue);
        expect(updates.last.stage, MediaOperationStage.completed);
      }
      final source =
          await Directory('${temporary.path}/windows-source').create();
      await Directory('${source.path}/sources').create();
      await Directory('${source.path}/efi/boot').create(recursive: true);
      for (final path in [
        'sources/boot.wim',
        'sources/install.wim',
        'efi/boot/bootx64.efi'
      ]) {
        await File('${source.path}/$path').writeAsBytes(data.sublist(0, 8192));
      }
      final isoPath = '${temporary.path}/windows-fixture.iso';
      final hybrid = await Process.run('/usr/bin/hdiutil',
          ['makehybrid', '-iso', '-joliet', '-o', isoPath, source.path]);
      expect(hybrid.exitCode, 0, reason: '${hybrid.stderr}');
      updates.clear();
      await kit.createWindowsInstaller(whole.id,
          isoPath: isoPath, onProgress: report);
      expect(
          updates.any((p) => p.stage == MediaOperationStage.verifying), isTrue);
      expect(updates.last.stage, MediaOperationStage.completed);
      final windows = (await kit.getDisks()).singleWhere((disk) =>
          disk.wholeDiskId == whole.id &&
          disk.volumeName == 'WINDOWS' &&
          disk.isMounted);
      expect(windows.fileSystem, 'msdos');
      for (final path in [
        'sources/boot.wim',
        'sources/install.wim',
        'efi/boot/bootx64.efi'
      ]) {
        expect(await File('${windows.volumePath}/$path').readAsBytes(),
            orderedEquals(data.sublist(0, 8192)));
      }
    } finally {
      // IDs can be reused: refuse restoration if the current target description
      // differs. Keep the USB connected for the entire opt-in test.
      final current =
          (await kit.getDisks()).singleWhere((disk) => disk.id == whole.id);
      expect(current.name, whole.name);
      expect(current.sizeBytes, whole.sizeBytes);
      expect(current.busProtocol, 'USB');
      expect(current.isInternal, isFalse);
      await kit.formatDisk(current.id,
          fileSystem: DiskFileSystem.exFat, volumeName: volumeName);
      final restored = (await kit.getDisks()).singleWhere((disk) =>
          disk.wholeDiskId == current.id && disk.volumeName == volumeName);
      expect(restored.fileSystem, 'exfat');
      expect(restored.isMounted, isTrue);
      await temporary.delete(recursive: true);
    }
  },
      skip: volumeName.isEmpty || !erase,
      timeout: const Timeout(Duration(minutes: 10)));
}
