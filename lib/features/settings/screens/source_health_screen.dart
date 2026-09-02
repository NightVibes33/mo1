import 'package:dopi/core/services/source_health_service.dart';
import 'package:dopi/features/status_bar/widgets/status_bar.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SourceHealthScreen extends ConsumerWidget {
  const SourceHealthScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(sourceHealthProvider);
    return CupertinoPageScaffold(
      child: Column(
        children: [
          const StatusBar(title: 'Source Health'),
          Expanded(
            child: snapshot.when(
              loading: () => const Center(child: CupertinoActivityIndicator()),
              error: (error, _) => Center(child: Text('Source health failed: $error')),
              data: (data) => ListView.builder(
                padding: const EdgeInsets.all(8),
                itemCount: data.items.length,
                itemBuilder: (context, index) {
                  final item = data.items[index];
                  return _SourceHealthRow(item: item);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SourceHealthRow extends StatelessWidget {
  final SourceHealthItem item;

  const _SourceHealthRow({required this.item});

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
          child: Row(
            children: [
              Icon(
                item.isHealthy ? CupertinoIcons.check_mark_circled_solid : CupertinoIcons.exclamationmark_triangle_fill,
                color: item.isHealthy ? CupertinoColors.systemGreen : CupertinoColors.systemOrange,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 3),
                    Text(item.status, maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 3),
                    Text(item.detail, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
