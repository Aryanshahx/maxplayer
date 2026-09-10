import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../theme.dart';
import '../utils/format.dart';
import '../utils/local_store.dart';

/// Statistics — local library numbers. All computed on-device.
class StatisticsScreen extends StatefulWidget {
  const StatisticsScreen({super.key});

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> {
  Map<String, Object>? _stats;

  @override
  void initState() {
    super.initState();
    _compute();
  }

  Future<void> _compute() async {
    var videos = 0;
    var seconds = 0;
    try {
      final paths = await PhotoManager.getAssetPathList(
          type: RequestType.video, onlyAll: true);
      if (paths.isNotEmpty) {
        final all = paths.first;
        videos = await all.assetCountAsync;
        const pageSize = 200;
        for (var page = 0;; page++) {
          final batch =
              await all.getAssetListPaged(page: page, size: pageSize);
          if (batch.isEmpty) break;
          for (final a in batch) {
            if (a.type == AssetType.video) seconds += a.duration;
          }
          if (batch.length < pageSize) break;
        }
      }
    } catch (_) {/* stats are best-effort */}

    final store = LocalStore();
    final favs = (await store.favorites()).length;
    final priv = (await store.privateIds()).length;
    final playlists = await store.playlists();
    final playlistItems =
        playlists.values.fold<int>(0, (sum, v) => sum + v.length);
    final recent = (await store.recent()).length;

    if (mounted) {
      setState(() {
        _stats = {
          'Videos on device': videos,
          'Total runtime': formatDuration(Duration(seconds: seconds)),
          'Favourites': favs,
          'In Private Space': priv,
          'Playlists': playlists.length,
          'Items in playlists': playlistItems,
          'History entries': recent,
          'App version': '0.8.0+9',
          'Engine': 'MPV (libmpv + FFmpeg)',
        };
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Statistics')),
      body: _stats == null
          ? Center(child: CircularProgressIndicator(color: AppColors.accent))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _stats!.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final k = _stats!.keys.elementAt(i);
                return Card(
                  child: ListTile(
                    title: Text(k,
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 13)),
                    trailing: Text('${_stats![k]}',
                        style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w700)),
                  ),
                );
              },
            ),
    );
  }
}
