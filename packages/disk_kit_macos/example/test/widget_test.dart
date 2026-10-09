import 'package:disk_kit_platform_interface/disk_kit_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:disk_kit_macos_example/main.dart';

class FakePlatform extends DiskKitPlatform {
  final disks = [
    const DiskInfo(
      id: 'disk4',
      devicePath: '/dev/disk4',
      wholeDiskId: 'disk4',
      name: 'USB drive',
      isWritable: true,
      sizeBytes: 64000000000,
      busProtocol: 'USB',
      isInternal: false,
      isWholeDisk: true,
    ),
    const DiskInfo(
      id: 'disk4s1',
      devicePath: '/dev/disk4s1',
      wholeDiskId: 'disk4',
      volumeName: 'EFI',
      fileSystem: 'msdos',
      mediaContent: 'EFI',
      isInternal: false,
      isWholeDisk: false,
    ),
    const DiskInfo(
      id: 'disk4s2',
      devicePath: '/dev/disk4s2',
      wholeDiskId: 'disk4',
      volumeName: 'USB',
      volumePath: '/Volumes/USB',
      isInternal: false,
      isWholeDisk: false,
    ),
    const DiskInfo(
      id: 'disk0',
      devicePath: '/dev/disk0',
      name: 'Internal',
      isInternal: true,
      isWholeDisk: true,
    ),
  ];
  List<String>? copied;
  bool formatted = false;
  String? formattedDisk;
  List<String>? renamed;
  List<Object?>? media;
  @override
  Future<void> writeImage(String diskId,
      {required String imagePath,
      bool verify = true,
      bool allowElevation = true,
      MediaProgressCallback? onProgress}) async {
    media = ['raw', diskId, imagePath, verify, allowElevation];
    onProgress?.call(MediaOperationProgress(
        diskId: diskId, stage: MediaOperationStage.completed));
  }

  @override
  Future<void> createWindowsInstaller(String diskId,
      {required String isoPath,
      String? wimlibPath,
      bool verify = true,
      MediaProgressCallback? onProgress}) async {
    media = ['windows', diskId, isoPath, wimlibPath, verify];
  }

  @override
  Future<void> createMacOSInstaller(String diskId,
      {required String installerAppPath,
      bool allowElevation = true,
      MediaProgressCallback? onProgress}) async {
    media = ['macos', diskId, installerAppPath, allowElevation];
  }

  @override
  Stream<List<DiskInfo>> watchDisks() => Stream.value(disks);
  @override
  Future<List<DiskInfo>> getDisks() async => disks;
  @override
  Future<void> copyFromDisk(
    String diskId, {
    required String relativePath,
    required String destinationPath,
    bool parallel = true,
    FileCopyProgressCallback? onProgress,
  }) async {
    copied = [diskId, relativePath, destinationPath];
  }

  @override
  Future<DiskInfo> renameVolume(String diskId,
      {required String volumeName}) async {
    renamed = [diskId, volumeName];
    return DiskInfo(
        id: diskId, devicePath: '/dev/$diskId', volumeName: volumeName);
  }

  @override
  Future<void> formatVolume(
    String diskId, {
    required DiskFileSystem fileSystem,
    required String volumeName,
  }) async {
    formatted = true;
  }

  @override
  Future<void> formatDisk(
    String diskId, {
    required DiskFileSystem fileSystem,
    required String volumeName,
    DiskPartitionScheme partitionScheme = DiskPartitionScheme.gpt,
  }) async {
    formattedDisk = diskId;
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

  for (final mode in ['raw', 'windows', 'macos']) {
    testWidgets(
        '$mode media dialog requires erasure confirmation and forwards options',
        (tester) async {
      await tester.pumpWidget(const MyApp());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Write image / installer…'));
      await tester.pumpAndSettle();
      if (mode != 'raw') {
        await tester.tap(find.byType(DropdownButton<String>));
        await tester.pumpAndSettle();
        await tester.tap(find
            .text(mode == 'windows'
                ? 'Windows ISO → UEFI installer'
                : 'Install macOS .app → Mac installer')
            .last);
        await tester.pumpAndSettle();
      }
      final source = mode == 'macos'
          ? '/Applications/Install macOS.app'
          : '/tmp/installer.iso';
      await tester.enterText(find.byType(TextField).first, source);
      if (mode == 'windows') {
        await tester.enterText(find.byType(TextField).at(1), '/tmp/wimlib');
      }
      final write = find.widgetWithText(FilledButton, 'Erase and write');
      expect(tester.widget<FilledButton>(write).onPressed, isNull);
      await tester.ensureVisible(find.byType(TextField).last);
      await tester.enterText(find.byType(TextField).last, 'ERASE disk4');
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(write).onPressed, isNotNull);
      await tester.tap(write);
      await tester.pumpAndSettle();
      expect(
          platform.media,
          mode == 'raw'
              ? ['raw', 'disk4', source, true, true]
              : mode == 'windows'
                  ? ['windows', 'disk4', source, '/tmp/wimlib', true]
                  : ['macos', 'disk4', source, true]);
    });
  }

  testWidgets('renders external disks and hides internal disks by default', (
    tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();
    expect(find.byType(Card), findsOneWidget);
    expect(find.text('USB drive'), findsOneWidget);
    expect(find.text('USB'), findsOneWidget);
    expect(find.text('EFI'), findsNothing);
    expect(find.text('Internal'), findsNothing);
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    expect(find.text('Internal'), findsOneWidget);
  });

  testWidgets('details reveal EFI inside the same device card', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('volume-disk4s1')), findsNothing);
    await tester.tap(find.byType(Switch).at(1));
    await tester.pumpAndSettle();
    expect(find.byType(Card), findsOneWidget);
    final device = find.byKey(const ValueKey('device-disk4'));
    expect(find.descendant(of: device, matching: find.text('EFI')),
        findsOneWidget);
    expect(find.descendant(of: device, matching: find.text('USB')),
        findsOneWidget);
    // EFI stays read-only in the example; data-volume operations remain available.
    final efi = find.byKey(const ValueKey('volume-disk4s1'));
    expect(find.descendant(of: efi, matching: find.byType(OutlinedButton)),
        findsNothing);
  });

  testWidgets('rename dialog forwards the volume ID and new name',
      (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename…'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'NEW_USB');
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    expect(platform.renamed, ['disk4s2', 'NEW_USB']);
    expect(platform.formatted, isFalse);
    expect(platform.formattedDisk, isNull);
  });

  testWidgets('copy dialog forwards both paths', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy from disk'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'Documents');
    await tester.enterText(find.byType(TextField).at(1), '/tmp/backup');
    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();
    expect(platform.copied, ['disk4s2', 'Documents', '/tmp/backup']);
  });

  testWidgets('formatting requires explicit target confirmation', (
    tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Format volume…'));
    await tester.pumpAndSettle();
    final erase = find.widgetWithText(FilledButton, 'Erase and format');
    expect(tester.widget<FilledButton>(erase).onPressed, isNull);
    await tester.enterText(find.byType(TextField).at(1), 'ERASE disk4s2');
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(erase).onPressed, isNotNull);
    await tester.tap(erase);
    await tester.pumpAndSettle();
    expect(platform.formatted, isTrue);
  });

  testWidgets('device format targets the whole disk rather than its volume',
      (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Format disk…'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(1), 'ERASE disk4');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Erase and format'));
    await tester.pumpAndSettle();
    expect(platform.formattedDisk, 'disk4');
    expect(platform.formatted, isFalse);
  });
}
