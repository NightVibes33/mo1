import 'package:dope/core/services/storage_diagnostics_service.dart';
import 'package:dope/features/status_bar/widgets/status_bar.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class StorageDiagnosticsScreen extends ConsumerStatefulWidget {
  const StorageDiagnosticsScreen({super.key});

  @override
  ConsumerState<StorageDiagnosticsScreen> createState() => _StorageDiagnosticsScreenState();
}

class _StorageDiagnosticsScreenState extends ConsumerState<StorageDiagnosticsScreen> {
  late Future<StorageDiagnosticsSnapshot> _future;

  @override
  void initState() {
    super.initState();
    _future = ref.read(storageDiagnosticsServiceProvider).snapshot();
  }

  void _refresh() {
    setState(() {
      _future = ref.read(storageDiagnosticsServiceProvider).snapshot();
    });
  }

  Future<void> _clearEqCache() async {
    await ref.read(storageDiagnosticsServiceProvider).clearNativeEqCache();
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      child: Column(
        children: [
          const StatusBar(title: 'Storage'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: CupertinoButton(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    onPressed: _refresh,
                    child: const Text('Refresh'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: CupertinoButton(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    onPressed: _clearEqCache,
                    child: const Text('Clear EQ Cache'),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<StorageDiagnosticsSnapshot>(
              future: _future,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CupertinoActivityIndicator());
                }
                final data = snapshot.data!;
                return ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: data.entries.length + 1,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return _StorageRow(
                        title: 'Total Tracked Storage',
                        value: formatBytes(data.totalBytes),
                        subtitle: 'App-managed music, artwork, logs, and caches.',
                      );
                    }
                    final entry = data.entries[index - 1];
                    return _StorageRow(
                      title: entry.label,
                      value: entry.displaySize,
                      subtitle: entry.path,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _StorageRow extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;

  const _StorageRow({required this.title, required this.value, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: CupertinoColors.systemGrey6.resolveFrom(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: CupertinoColors.separator.resolveFrom(context)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 4),
              Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }
}
