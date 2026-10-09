import 'package:disk_kit/disk_kit.dart';
import 'package:disk_kit_platform_interface/disk_kit_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

class FakePlatform extends DiskKitPlatform {
  final calls = <List<Object?>>[];
  bool? lastCopyParallel;
  static const disk = DiskInfo(id: 'disk4', devicePath: '/dev/disk4');
  @override
  Future<List<DiskInfo>> getDisks() async => [disk];
  @override
  Stream<List<DiskInfo>> watchDisks() => Stream.value([disk]);
  @override
  Future<DiskInfo> mount(String diskId) async {
    calls.add(['mount', diskId]);
    return DiskInfo(
        id: diskId, devicePath: '/dev/$diskId', volumePath: '/Volumes/USB');
  }

  @override
  Future<DiskInfo> unmount(String diskId, {bool wholeDisk = false}) async {
    calls.add(['unmount', diskId, wholeDisk]);
    return DiskInfo(id: diskId, devicePath: '/dev/$diskId');
  }

  @override
  Future<void> eject(String diskId) async {
    calls.add(['eject', diskId]);
  }

  @override
  Future<DiskInfo> renameVolume(String diskId,
      {required String volumeName}) async {
    calls.add(['renameVolume', diskId, volumeName]);
    return DiskInfo(
        id: diskId, devicePath: '/dev/$diskId', volumeName: volumeName);
  }

  @override
  Future<void> copyFromDisk(String diskId,
      {required String relativePath,
      required String destinationPath,
      bool parallel = true,
      FileCopyProgressCallback? onProgress}) async {
    lastCopyParallel = parallel;
    onProgress?.call(
        const FileCopyProgress(path: 'a.txt', bytes: 12, completed: true));
    calls.add(['copyFromDisk', diskId, relativePath, destinationPath]);
  }

  @override
  Future<void> copyToDisk(String diskId,
      {required String sourcePath,
      required String relativePath,
      bool parallel = true,
      FileCopyProgressCallback? onProgress}) async {
    calls.add(['copyToDisk', diskId, sourcePath, relativePath]);
  }

  @override
  Future<void> formatVolume(String diskId,
      {required DiskFileSystem fileSystem, required String volumeName}) async {
    calls.add(['formatVolume', diskId, fileSystem, volumeName]);
  }

  @override
  Future<void> formatDisk(String diskId,
      {required DiskFileSystem fileSystem,
      required String volumeName,
      DiskPartitionScheme partitionScheme = DiskPartitionScheme.gpt}) async {
    calls.add(['formatDisk', diskId, fileSystem, volumeName, partitionScheme]);
  }

  @override
  Future<void> writeImage(String diskId,
      {required String imagePath,
      bool verify = true,
      bool allowElevation = true,
      MediaProgressCallback? onProgress}) async {
    calls.add(['writeImage', diskId, imagePath, verify, allowElevation]);
    onProgress?.call(MediaOperationProgress(
        diskId: diskId,
        stage: MediaOperationStage.writing,
        bytesCompleted: 512,
        totalBytes: 1024));
  }

  @override
  Future<void> createWindowsInstaller(String diskId,
      {required String isoPath,
      String? wimlibPath,
      bool verify = true,
      MediaProgressCallback? onProgress}) async {
    calls.add(['createWindowsInstaller', diskId, isoPath, wimlibPath, verify]);
  }

  @override
  Future<void> createMacOSInstaller(String diskId,
      {required String installerAppPath,
      bool allowElevation = true,
      MediaProgressCallback? onProgress}) async {
    calls.add(
        ['createMacOSInstaller', diskId, installerAppPath, allowElevation]);
  }
}

void main() {
  final original = DiskKitPlatform.instance;
  late FakePlatform platform;
  setUp(() {
    platform = FakePlatform();
    DiskKitPlatform.instance = platform;
  });
  tearDown(() => DiskKitPlatform.instance = original);

  test('public API forwards installer options and measurable progress',
      () async {
    const kit = DiskKit();
    final updates = <MediaOperationProgress>[];
    await kit.writeImage('disk4',
        imagePath: '/tmp/ubuntu.iso',
        verify: false,
        allowElevation: false,
        onProgress: updates.add);
    await kit.createWindowsInstaller('disk4',
        isoPath: '/tmp/windows.iso',
        wimlibPath: '/opt/homebrew/bin/wimlib-imagex',
        verify: false);
    await kit.createMacOSInstaller('disk4',
        installerAppPath: '/Applications/Install macOS.app',
        allowElevation: false);
    expect(platform.calls, [
      ['writeImage', 'disk4', '/tmp/ubuntu.iso', false, false],
      [
        'createWindowsInstaller',
        'disk4',
        '/tmp/windows.iso',
        '/opt/homebrew/bin/wimlib-imagex',
        false
      ],
      [
        'createMacOSInstaller',
        'disk4',
        '/Applications/Install macOS.app',
        false
      ],
    ]);
    expect(updates.single.fraction, 0.5);
    expect(
        const MediaOperationProgress(
                diskId: 'disk4', stage: MediaOperationStage.authorizing)
            .fraction,
        isNull);
  });

  test('public API forwards the parallel copy preference and file progress',
      () async {
    final updates = <FileCopyProgress>[];
    await const DiskKit().copyFromDisk('disk4s1',
        relativePath: 'a.txt',
        destinationPath: '/tmp/a.txt',
        parallel: false,
        onProgress: updates.add);
    expect(platform.lastCopyParallel, isFalse);
    expect(updates.single.bytes, 12);
    await const DiskKit().copyFromDisk('disk4s1',
        relativePath: 'a.txt', destinationPath: '/tmp/a.txt');
    expect(platform.lastCopyParallel, isTrue);
  });

  test('public API exposes discovery and snapshots', () async {
    const kit = DiskKit();
    expect((await kit.getDisks()).single.id, 'disk4');
    expect((await kit.watchDisks().first).single.id, 'disk4');
  });

  test('public API returns descriptions for volume operations', () async {
    const DiskKit kit = DiskKit();
    final DiskInfo mounted = await kit.mount('disk4s1');
    final DiskInfo unmounted = await kit.unmount(mounted.id);
    final DiskInfo renamed =
        await kit.renameVolume(unmounted.id, volumeName: 'NEW_USB');
    expect(mounted.isMounted, isTrue);
    expect(unmounted.isMounted, isFalse);
    expect(renamed.volumeName, 'NEW_USB');
  });

  test('public API forwards targets and operation options', () async {
    const kit = DiskKit();
    await kit.mount('disk4s1');
    await kit.unmount('disk4', wholeDisk: true);
    await kit.eject('disk4');
    await kit.renameVolume('disk4s1', volumeName: 'NEW_USB');
    await kit.copyFromDisk('disk4s1',
        relativePath: 'a', destinationPath: '/tmp/b');
    await kit.copyToDisk('disk4s1', sourcePath: '/tmp/b', relativePath: 'a');
    await kit.formatVolume('disk4s1',
        fileSystem: DiskFileSystem.exFat, volumeName: 'USB');
    await kit.formatDisk('disk4',
        fileSystem: DiskFileSystem.fat32,
        volumeName: 'USB',
        partitionScheme: DiskPartitionScheme.mbr);
    expect(platform.calls, [
      ['mount', 'disk4s1'],
      ['unmount', 'disk4', true],
      ['eject', 'disk4'],
      ['renameVolume', 'disk4s1', 'NEW_USB'],
      ['copyFromDisk', 'disk4s1', 'a', '/tmp/b'],
      ['copyToDisk', 'disk4s1', '/tmp/b', 'a'],
      ['formatVolume', 'disk4s1', DiskFileSystem.exFat, 'USB'],
      [
        'formatDisk',
        'disk4',
        DiskFileSystem.fat32,
        'USB',
        DiskPartitionScheme.mbr
      ],
    ]);
  });
}
