import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../theme.dart';
import '../utils/local_store.dart';
import '../widgets/video_grid.dart';

/// Watch history: last 25 opened videos, newest first.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _store = LocalStore();
  List<RecentItem> _items = [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final items = await _store.recent();
    if (mounted) setState(() => _items = items);
  }

  String _when(int ts) {
    final d = DateTime.fromMillisecondsSinceEpoch(ts);
    final now = DateTime.now();
    final diff = now.difference(d);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        actions: [
          if (_items.isNotEmpty)
            IconButton(
              tooltip: 'Clear history',
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: () async {
                await _store.clearRecent();
                _reload();
              },
            ),
        ],
      ),
      body: _items.isEmpty
          ? const Center(
              child: Text('Nothing watched yet.',
                  style: TextStyle(color: AppColors.textSecondary)))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final item = _items[i];
                return Card(
                  clipBehavior: Clip.antiAlias,
                  child: ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    leading: _HistoryThumb(id: item.id),
                    title: Text(item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            const TextStyle(color: AppColors.textPrimary)),
                    subtitle: Text(_when(item.ts),
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 12)),
                    trailing: const Icon(Icons.play_circle_outline_rounded,
                        color: AppColors.accent),
                    onTap: () async {
                      final asset = await AssetEntity.fromId(item.id);
                      if (asset == null) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content:
                                      Text('This video no longer exists')));
                        }
                        return;
                      }
                      if (context.mounted) {
                        await VideoGrid.openVideo(context, asset, store: _store);
                      }
                      _reload();
                    },
                  ),
                );
              },
            ),
    );
  }
}

class _HistoryThumb extends StatelessWidget {
  const _HistoryThumb({required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 64,
        height: 44,
        child: FutureBuilder<AssetEntity?>(
          future: AssetEntity.fromId(id),
          builder: (context, snap) {
            final a = snap.data;
            if (a == null) {
              return const ColoredBox(color: AppColors.surfaceAlt);
            }
            return FutureBuilder<Uint8List?>(
              future:
                  a.thumbnailDataWithSize(const ThumbnailSize(160, 110)),
              builder: (context, t) => t.data == null
                  ? const ColoredBox(color: AppColors.surfaceAlt)
                  : Image.memory(t.data!, fit: BoxFit.cover),
            );
          },
        ),
      ),
    );
  }
}
