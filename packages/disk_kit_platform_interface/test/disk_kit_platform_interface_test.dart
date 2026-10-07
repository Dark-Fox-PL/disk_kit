import 'package:disk_kit_platform_interface/disk_kit_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

class UnsupportedPlatform extends DiskKitPlatform {}

void main() {
  test('decodes optional properties without inventing missing values', () {
    final disk = DiskInfo.fromMap({
      'id': 'disk4s1',
      'devicePath': '/dev/disk4s1',
      'wholeDiskId': 'disk4',
      'volumePath': '/Volumes/USB',
      'sizeBytes': 4294967297,
      'fileSystem': 'exfat',
      'mediaContent': 'Microsoft Basic Data',
      'isInternal': false,
    });
    expect(disk.isMounted, isTrue);
    expect(disk.sizeBytes, 4294967297);
    expect(disk.isInternal, isFalse);
    expect(disk.isRemovable, isNull);
    expect(disk.wholeDiskId, 'disk4');
    expect(disk.mediaContent, 'Microsoft Basic Data');
    expect(
        DiskInfo.fromMap({'id': 'disk4', 'devicePath': '/dev/disk4'}).isMounted,
        isFalse);
  });

  test('decodes media progress and clamps stage fractions', () {
    final progress = MediaOperationProgress.fromMap({
      'diskId': 'disk4',
      'stage': 'verifying',
      'bytesCompleted': 4096,
      'totalBytes': 8192,
    });
    expect(progress.stage, MediaOperationStage.verifying);
    expect(progress.fraction, 0.5);
    expect(
        const MediaOperationProgress(
                diskId: 'disk4',
                stage: MediaOperationStage.writing,
                bytesCompleted: 100,
                totalBytes: 50)
            .fraction,
        1.0);
    expect(
        const MediaOperationProgress(
                diskId: 'disk4',
                stage: MediaOperationStage.writing,
                bytesCompleted: 0,
                totalBytes: 0)
            .fraction,
        isNull);
  });

  test('rejects missing identifiers', () {
    expect(() => DiskInfo.fromMap({}), throwsFormatException);
  });

  test('unsupported platform reports failure for every operation', () async {
    final platform = UnsupportedPlatform();
    await expectLater(platform.writeImage('disk4', imagePath: '/tmp/a.img'),
        throwsUnsupportedError);
    await expectLater(
        platform.createWindowsInstaller('disk4', isoPath: '/tmp/a.iso'),
        throwsUnsupportedError);
    await expectLater(
        platform.createMacOSInstaller('disk4',
            installerAppPath: '/Applications/a.app'),
        throwsUnsupportedError);
    await expectLater(platform.getDisks(), throwsUnsupportedError);
    await expectLater(
        platform.watchDisks(), emitsError(isA<UnsupportedError>()));
    await expectLater(platform.mount('disk4'), throwsUnsupportedError);
    await expectLater(platform.unmount('disk4'), throwsUnsupportedError);
    await expectLater(platform.eject('disk4'), throwsUnsupportedError);
    await expectLater(platform.renameVolume('disk4s1', volumeName: 'USB'),
        throwsUnsupportedError);
    await expectLater(
        platform.copyFromDisk('disk4',
            relativePath: 'a', destinationPath: '/tmp/b'),
        throwsUnsupportedError);
    await expectLater(
        platform.copyToDisk('disk4', sourcePath: '/tmp/a', relativePath: 'b'),
        throwsUnsupportedError);
    await expectLater(
        platform.formatVolume('disk4',
            fileSystem: DiskFileSystem.exFat, volumeName: 'USB'),
        throwsUnsupportedError);
    await expectLater(
        platform.formatDisk('disk4',
            fileSystem: DiskFileSystem.exFat, volumeName: 'USB'),
        throwsUnsupportedError);
  });
}
