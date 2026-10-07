import 'dart:io';

import 'package:disk_kit/disk_kit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Destructive test: requires both an explicit target name and an erase flag.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.shouldPropagateDevicePointerEvents = false;
  const kit = DiskKit();
  const targetName = String.fromEnvironment('DISK_KIT_TEST_VOLUME_NAME');
  const erase = bool.fromEnvironment('DISK_KIT_ERASE_TEST_DRIVE');

  Future<DiskInfo> waitForVolume(String wholeId, String name, String fs) async {
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(deadline)) {
      final matches = (await kit.getDisks())
          .where((disk) =>
              disk.wholeDiskId == wholeId &&
              disk.volumeName == name &&
              disk.fileSystem == fs &&
              disk.isMounted &&
              disk.isInternal == false)
          .toList();
      if (matches.length == 1) return matches.single;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    throw StateError('The formatted volume did not appear: $name ($fs).');
  }

  testWidgets('external copy, FAT32 volume format, exFAT disk format, restore',
      (tester) async {
    final disks = await kit.getDisks();
    final matches = disks
        .where((disk) =>
            disk.volumeName == targetName &&
            disk.isMounted &&
            disk.isInternal == false)
        .toList();
    expect(matches, hasLength(1),
        reason: 'Must identify exactly one mounted external target.');
    final original = matches.single;
    final whole = disks.singleWhere((disk) => disk.id == original.wholeDiskId);
    expect(whole.isWholeDisk, isTrue);
    expect(whole.isInternal, isFalse);
    expect(whole.busProtocol, 'USB');
    // ignore: avoid_print
    print(
        'ERASE authorized target: name=$targetName, volume=${original.id}, whole=${whole.id}, size=${whole.sizeBytes}, vendor=${whole.vendor}, model=${whole.model}');

    final temporary = await Directory.systemTemp.createTemp('disk-kit-format-');
    final source = await Directory('${temporary.path}/source/nested')
        .create(recursive: true);
    final sourceDirectory = source.parent;
    const text = 'DiskKit: copy, FAT32, exFAT, restore';
    final bytes = List<int>.generate(1024 * 1024, (index) => index % 251);
    await File('${sourceDirectory.path}/hello.txt').writeAsString(text);
    await File('${source.path}/data.bin').writeAsBytes(bytes);
    final relative = 'DiskKitTest-${DateTime.now().microsecondsSinceEpoch}';
    final backup = '${temporary.path}/backup';

    Future<void> verifyRestored(DiskInfo volume) async {
      await kit.copyToDisk(volume.id,
          sourcePath: backup, relativePath: relative);
      final restored = Directory('${volume.volumePath}/$relative');
      expect(await File('${restored.path}/hello.txt').readAsString(), text);
      expect(await File('${restored.path}/nested/data.bin').readAsBytes(),
          orderedEquals(bytes));
      // Delete only this test's generated fixture.
      await restored.delete(recursive: true);
    }

    try {
      await kit.copyToDisk(original.id,
          sourcePath: sourceDirectory.path, relativePath: relative);
      await kit.copyFromDisk(original.id,
          relativePath: relative, destinationPath: backup);
      expect(await File('$backup/hello.txt').readAsString(), text);
      expect(await File('$backup/nested/data.bin').readAsBytes(),
          orderedEquals(bytes));

      // These calls deliberately erase user data on the authorized target.
      await kit.formatVolume(original.id,
          fileSystem: DiskFileSystem.fat32, volumeName: 'DISKKITTEST');
      final fat = await waitForVolume(whole.id, 'DISKKITTEST', 'msdos');
      await verifyRestored(fat);
      // ignore: avoid_print
      print('FAT32 formatVolume and verified restore passed on ${fat.id}.');

      await kit.formatDisk(whole.id,
          fileSystem: DiskFileSystem.exFat, volumeName: targetName);
      final exFat = await waitForVolume(whole.id, targetName, 'exfat');
      await verifyRestored(exFat);
      // ignore: avoid_print
      print(
          'exFAT formatDisk and verified restore passed on ${exFat.id}; final name=$targetName.');
    } finally {
      await temporary.delete(recursive: true);
    }
  },
      skip: !erase || targetName.isEmpty,
      timeout: const Timeout(Duration(minutes: 5)));
}
