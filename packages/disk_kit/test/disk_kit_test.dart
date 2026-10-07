import 'package:disk_kit/disk_kit.dart';
import 'package:disk_kit_platform_interface/disk_kit_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

class FakePlatform extends DiskKitPlatform {
  final calls = <List<Object?>>[];
  static const disk = DiskInfo(id: 'disk4', devicePath: '/dev/disk4');
  @override
  Future<List<DiskInfo>> getDisks() async => [disk];
  @override
  Stream<List<DiskInfo>> watchDisks() => Stream.value([disk]);
  @override
  Future<void> mount(String diskId) async {
    calls.add(['mount', diskId]);
  }

  @override
  Future<void> unmount(String diskId, {bool wholeDisk = false}) async {
    calls.add(['unmount', diskId, wholeDisk]);
  }

  @override
  Future<void> eject(String diskId) async {
    calls.add(['eject', diskId]);
  }

  @override
  Future<void> copyFromDisk(String diskId,
      {required String relativePath, required String destinationPath}) async {
    calls.add(['copyFromDisk', diskId, relativePath, destinationPath]);
  }

  @override
  Future<void> copyToDisk(String diskId,
      {required String sourcePath, required String relativePath}) async {
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
}

void main() {
  final original = DiskKitPlatform.instance;
  late FakePlatform platform;
  setUp(() {
    platform = FakePlatform();
    DiskKitPlatform.instance = platform;
  });
  tearDown(() => DiskKitPlatform.instance = original);

  test('public API exposes discovery and snapshots', () async {
    const kit = DiskKit();
    expect((await kit.getDisks()).single.id, 'disk4');
    expect((await kit.watchDisks().first).single.id, 'disk4');
  });

  test('public API forwards targets and operation options', () async {
    const kit = DiskKit();
    await kit.mount('disk4s1');
    await kit.unmount('disk4', wholeDisk: true);
    await kit.eject('disk4');
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
