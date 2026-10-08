import 'package:disk_kit/disk_kit.dart';
import 'package:disk_kit_macos_extensions/disk_kit_macos_extensions.dart';
import 'package:flutter/material.dart';

void main() => runApp(const MaterialApp(home: ExtensionsExample()));

/// Shows optional tools and volume access without changing any disk contents.
class ExtensionsExample extends StatefulWidget {
  const ExtensionsExample({super.key});

  @override
  State<ExtensionsExample> createState() => _ExtensionsExampleState();
}

class _ExtensionsExampleState extends State<ExtensionsExample> {
  final _extensions = const DiskKitMacosExtensions();
  late Future<List<Widget>> _snapshot;

  @override
  void initState() {
    super.initState();
    _snapshot = _load();
  }

  Future<List<Widget>> _load() async {
    final capabilities = await _extensions.getCapabilities();
    final disks = await const DiskKit().getDisks();
    final rows = <Widget>[
      const Padding(
        padding: EdgeInsets.all(16),
        child: Text('Read-only example. No disk is formatted. '
            'Formatter availability does not imply filesystem read/write support.'),
      ),
      ...capabilities.map((capability) => ListTile(
            title: Text('${capability.fileSystem.name}: '
                'formatting ${capability.formatting.name}'),
            subtitle: Text('${capability.toolPath ?? capability.reason}\n'
                'Read/write: inspect a mounted volume below'),
          )),
      const Divider(),
    ];
    for (final volume in disks.where(
        (disk) => disk.isInternal == false && disk.isWholeDisk == false)) {
      final access = await _extensions.getVolumeAccess(volume.id);
      rows.add(ListTile(
        title: Text(
            '${volume.id} · ${volume.volumeName ?? volume.name ?? 'Volume'}'),
        subtitle: Text('${access.mountPath ?? 'Unmounted'}\n'
            'Root readable: ${access.canRead ?? 'unknown'} · '
            'Root writable: ${access.canWrite ?? 'unknown'}'),
      ));
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('DiskKit optional extensions'),
          actions: [
            IconButton(
              tooltip: 'Refresh tools and volumes',
              onPressed: () => setState(() => _snapshot = _load()),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: FutureBuilder<List<Widget>>(
          future: _snapshot,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(child: SelectableText('${snapshot.error}'));
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            return ListView(children: snapshot.data!);
          },
        ),
      );
}
