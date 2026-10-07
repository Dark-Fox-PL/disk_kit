import 'dart:async';

import 'package:disk_kit/disk_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() => runApp(const MyApp());

/// A manual test harness for the public DiskKit API.
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'DiskKit example',
        theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
        home: const DiskKitExample(),
      );
}

class DiskKitExample extends StatefulWidget {
  const DiskKitExample({super.key});

  @override
  State<DiskKitExample> createState() => _DiskKitExampleState();
}

class _DiskKitExampleState extends State<DiskKitExample> {
  final _kit = const DiskKit();
  final _relativePath = TextEditingController();
  final _localPath = TextEditingController();
  final _volumeName = TextEditingController();
  final _confirmation = TextEditingController();
  late final StreamSubscription<List<DiskInfo>> _subscription;
  List<DiskInfo> _disks = [];
  String? _error;
  bool _loading = true;
  bool _showInternal = false;
  bool _showDetails = false;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _subscription = _kit.watchDisks().listen(
      (disks) {
        if (!mounted) return;
        setState(() {
          _disks = disks;
          _loading = false;
          _error = null;
        });
      },
      onError: (Object error) {
        if (!mounted) return;
        setState(() {
          _error = error.toString();
          _loading = false;
        });
      },
    );
  }

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    _relativePath.dispose();
    _localPath.dispose();
    _volumeName.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final disks = await _kit.getDisks();
      if (mounted) {
        setState(() {
          _disks = disks;
          _loading = false;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _run(String label, Future<void> Function() operation) async {
    setState(() => _running = true);
    try {
      await operation();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$label completed')));
      }
    } catch (error) {
      final message = error is PlatformException
          ? '${error.code}: ${error.message}'
          : error.toString();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            duration: const Duration(seconds: 8),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _running = false);
        await _refresh();
      }
    }
  }

  Future<void> _copy(DiskInfo disk, {required bool fromDisk}) async {
    final relative = _relativePath..clear();
    final local = _localPath..clear();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(fromDisk ? 'Copy from ${disk.id}' : 'Copy to ${disk.id}'),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Mounted at ${disk.volumePath}\nThe destination must not exist. Parent directories must exist.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: relative,
                decoration: const InputDecoration(
                  labelText: 'Relative path inside the volume',
                  hintText: 'Documents/report.pdf',
                ),
              ),
              TextField(
                controller: local,
                decoration: InputDecoration(
                  labelText: fromDisk
                      ? 'Absolute destination path on this Mac'
                      : 'Absolute source path on this Mac',
                  hintText: '/Users/you/Desktop/report.pdf',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Copy'),
          ),
        ],
      ),
    );
    final relativePath = relative.text;
    final localPath = local.text;
    if (confirmed != true || !mounted) return;
    await _run(
      'Copy',
      () => fromDisk
          ? _kit.copyFromDisk(
              disk.id,
              relativePath: relativePath,
              destinationPath: localPath,
            )
          : _kit.copyToDisk(
              disk.id,
              sourcePath: localPath,
              relativePath: relativePath,
            ),
    );
  }

  Future<void> _format(DiskInfo disk) async {
    final name = _volumeName..text = 'DISKKIT';
    final confirmation = _confirmation..clear();
    var fs = DiskFileSystem.exFat;
    var scheme = DiskPartitionScheme.gpt;
    final whole = disk.isWholeDisk == true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text('Erase ${whole ? 'entire disk' : 'volume'} ${disk.id}'),
          content: SizedBox(
            width: 500,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  whole
                      ? 'All partitions and their data will be deleted.'
                      : 'All data on this volume will be deleted.',
                ),
                DropdownButton<DiskFileSystem>(
                  value: fs,
                  isExpanded: true,
                  items: DiskFileSystem.values
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text(value.name),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => update(() {
                    fs = value!;
                    if (fs == DiskFileSystem.apfs) {
                      scheme = DiskPartitionScheme.gpt;
                    }
                  }),
                ),
                if (whole)
                  DropdownButton<DiskPartitionScheme>(
                    value: scheme,
                    isExpanded: true,
                    items: DiskPartitionScheme.values
                        .where(
                          (value) =>
                              fs != DiskFileSystem.apfs ||
                              value == DiskPartitionScheme.gpt,
                        )
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(value.name.toUpperCase()),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => update(() => scheme = value!),
                  ),
                TextField(
                  controller: name,
                  decoration: const InputDecoration(
                    labelText: 'New volume name',
                  ),
                ),
                TextField(
                  controller: confirmation,
                  onChanged: (_) => update(() {}),
                  decoration: InputDecoration(
                    labelText: 'Type ERASE ${disk.id} to confirm',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: confirmation.text == 'ERASE ${disk.id}'
                  ? () => Navigator.pop(context, true)
                  : null,
              child: const Text('Erase and format'),
            ),
          ],
        ),
      ),
    );
    final volumeName = name.text;
    if (confirmed != true || !mounted) return;
    await _run(
      'Format',
      () => whole
          ? _kit.formatDisk(
              disk.id,
              fileSystem: fs,
              volumeName: volumeName,
              partitionScheme: scheme,
            )
          : _kit.formatVolume(disk.id, fileSystem: fs, volumeName: volumeName),
    );
  }

  bool _isSystemPartition(DiskInfo disk) {
    final content = disk.mediaContent?.toLowerCase();
    return content == 'efi' ||
        content == 'c12a7328-f81f-11d2-ba4b-00a0c93ec93b';
  }

  String _size(int? bytes) {
    if (bytes == null) return 'Unknown size';
    for (final unit in [
      (1000000000000, 'TB'),
      (1000000000, 'GB'),
      (1000000, 'MB')
    ]) {
      if (bytes >= unit.$1) {
        return '${(bytes / unit.$1).toStringAsFixed(1)} ${unit.$2}';
      }
    }
    return '$bytes bytes';
  }

  String _fileSystem(DiskInfo disk) => switch (disk.fileSystem) {
        'exfat' => 'exFAT',
        'msdos' => 'FAT',
        'apfs' => 'APFS',
        'hfs' => 'HFS+',
        final value => value ?? 'No filesystem',
      };

  Widget _volume(DiskInfo disk) {
    final system = _isSystemPartition(disk);
    final external = disk.isInternal == false;
    return Padding(
      key: ValueKey('volume-${disk.id}'),
      padding: const EdgeInsets.only(top: 16, left: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(system ? Icons.settings : Icons.folder_outlined, size: 20),
          const SizedBox(width: 8),
          Expanded(
              child: Text(disk.volumeName ?? disk.name ?? 'Unnamed volume',
                  style: Theme.of(context).textTheme.titleSmall)),
        ]),
        Text(
            '${_fileSystem(disk)} · ${_size(disk.sizeBytes)} · ${system ? 'System partition' : disk.isMounted ? 'Mounted' : 'Unmounted'}'),
        if (disk.volumePath != null) SelectableText(disk.volumePath!),
        if (_showDetails)
          SelectableText('${disk.id} · ${disk.devicePath}\n'
              'Partition type: ${disk.mediaContent ?? 'Unknown'}\n'
              'UUID: ${disk.volumeUuid ?? disk.mediaUuid ?? 'Unknown'}'),
        if (external && !system) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (!disk.isMounted && disk.isMountable == true)
              OutlinedButton(
                  onPressed: _running
                      ? null
                      : () => _run('Mount', () => _kit.mount(disk.id)),
                  child: const Text('Mount')),
            if (disk.isMounted) ...[
              OutlinedButton(
                  onPressed:
                      _running ? null : () => _copy(disk, fromDisk: true),
                  child: const Text('Copy from disk')),
              OutlinedButton(
                  onPressed:
                      _running ? null : () => _copy(disk, fromDisk: false),
                  child: const Text('Copy to disk')),
              OutlinedButton(
                  onPressed: _running
                      ? null
                      : () => _run('Unmount', () => _kit.unmount(disk.id)),
                  child: const Text('Unmount')),
            ],
            if (disk.isWholeDisk == false)
              OutlinedButton(
                  onPressed: _running ? null : () => _format(disk),
                  child: const Text('Format volume…')),
          ]),
        ],
      ]),
    );
  }

  Widget _deviceCard(String id, List<DiskInfo> entries) {
    final whole = entries
        .where((disk) => disk.id == id && disk.isWholeDisk == true)
        .firstOrNull;
    final volumes = entries
        .where((disk) =>
            disk != whole || disk.isMountable == true || disk.isMounted)
        .where((disk) => _showDetails || !_isSystemPartition(disk))
        .toList();
    return Card(
      key: ValueKey('device-$id'),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.storage),
                const SizedBox(width: 12),
                Expanded(
                    child: Text(
                        whole?.name ?? whole?.model ?? 'Storage device ($id)',
                        style: Theme.of(context).textTheme.titleMedium)),
              ]),
              if (whole != null) ...[
                Text(
                    '${_size(whole.sizeBytes)} · ${whole.busProtocol ?? 'Unknown connection'}'),
                if (_showDetails)
                  SelectableText(
                      '${whole.id} · ${whole.devicePath}\nUUID: ${whole.mediaUuid ?? 'Unknown'}'),
                if (whole.isInternal == false) ...[
                  const SizedBox(height: 12),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    OutlinedButton(
                        onPressed: _running
                            ? null
                            : () => _run('Unmount disk',
                                () => _kit.unmount(whole.id, wholeDisk: true)),
                        child: const Text('Unmount all volumes')),
                    OutlinedButton(
                        onPressed: _running
                            ? null
                            : () => _run('Eject', () => _kit.eject(whole.id)),
                        child: const Text('Eject')),
                    FilledButton(
                        onPressed: _running ? null : () => _format(whole),
                        child: const Text('Format disk…')),
                  ]),
                ],
              ],
              if (volumes.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Divider(),
                ...volumes.map(_volume),
              ] else
                const Padding(
                    padding: EdgeInsets.only(top: 16),
                    child: Text('No data volumes.')),
            ],
          )),
    );
  }

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<DiskInfo>>{};
    for (final disk in _disks) {
      final id = disk.wholeDiskId ?? disk.id;
      (groups[id] ??= []).add(disk);
    }
    final visible = groups.entries
        .where((group) =>
            _showInternal ||
            group.value.any((disk) => disk.isInternal == false))
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('DiskKit • macOS'), actions: [
        TextButton(
            onPressed: _running ? null : _refresh,
            child: const Text('Refresh')),
      ]),
      body: Column(children: [
        SwitchListTile(
            title: const Text('Show internal and unknown disks'),
            value: _showInternal,
            onChanged: (value) => setState(() => _showInternal = value)),
        SwitchListTile(
            title: const Text('Show details and system partitions'),
            value: _showDetails,
            onChanged: (value) => setState(() => _showDetails = value)),
        if (_running) const LinearProgressIndicator(),
        if (_error != null)
          Padding(padding: const EdgeInsets.all(16), child: Text(_error!)),
        if (_loading) const CircularProgressIndicator(),
        if (!_loading && visible.isEmpty)
          const Padding(
              padding: EdgeInsets.all(24),
              child: Text('No external disks. Connect a USB drive.')),
        Expanded(
            child: ListView.builder(
                itemCount: visible.length,
                itemBuilder: (context, index) =>
                    _deviceCard(visible[index].key, visible[index].value))),
      ]),
    );
  }
}
