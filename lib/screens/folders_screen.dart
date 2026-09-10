import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../theme.dart';
import '../utils/crash_log.dart';
import '../utils/local_store.dart';
import '../widgets/video_grid.dart';

/// Folders: every storage folder containing videos, with counts.
class FoldersScreen extends StatefulWidget {
  const FoldersScreen({super.key});

  @override
  State<FoldersScreen> createState() => _FoldersScreenState();
}

class _FoldersScreenState extends State<FoldersScreen> {
  List<AssetPathEntity> _paths = [];
  Map<String, int> _counts = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final paths = await PhotoManager.getAssetPathList(
          type: RequestType.video, hasAll: false);
      final counts = <String, int>{};
      for (final p in paths) {
        counts[p.id] = await p.assetCountAsync;
      }
      if (mounted) {
        setState(() {
          _paths = paths;
          _counts = counts;
        });
      }
      CrashLog.crumb('folders.scanned', {'count': paths.length});
    } catch (e) {
      CrashLog.error('folders.scan_failed', e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Folders')),
      body: _paths.isEmpty
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.accent))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _paths.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final p = _paths[i];
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.folder_rounded,
                        color: AppColors.accent, size: 30),
                    title: Text(p.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            const TextStyle(color: AppColors.textPrimary)),
                    subtitle: Text('${_counts[p.id] ?? 0} videos',
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 12)),
                    trailing: const Icon(Icons.chevron_right_rounded,
                        color: AppColors.textSecondary),
                    onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => FolderVideosScreen(path: p))),
                  ),
                );
              },
            ),
    );
  }
}

class FolderVideosScreen extends StatefulWidget {
  const FolderVideosScreen({super.key, required this.path});

  final AssetPathEntity path;

  @override
  State<FolderVideosScreen> createState() => _FolderVideosScreenState();
}

class _FolderVideosScreenState extends State<FolderVideosScreen> {
  static const _pageSize = 60;
  final List<AssetEntity> _videos = [];
  int _page = 0;
  bool _exhausted = false;
  Set<String> _priv = {};

  @override
  void initState() {
    super.initState();
    _loadMore();
    LocalStore().privateIds().then((s) {
      if (mounted) setState(() => _priv = s);
    });
  }

  Future<void> _loadMore() async {
    if (_exhausted) return;
    final batch =
        await widget.path.getAssetListPaged(page: _page, size: _pageSize);
    if (batch.length < _pageSize) _exhausted = true;
    _page++;
    _videos.addAll(batch.where((a) => a.type == AssetType.video));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final visible = _videos.where((a) => !_priv.contains(a.id)).toList();
    return Scaffold(
      appBar: AppBar(title: Text(widget.path.name)),
      body: visible.isEmpty
          ? const Center(
              child: Text('Empty folder',
                  style: TextStyle(color: AppColors.textSecondary)))
          : NotificationListener<ScrollNotification>(
              onNotification: (n) {
                if (n.metrics.pixels > n.metrics.maxScrollExtent - 600) {
                  _loadMore();
                }
                return false;
              },
              child: VideoGrid(
                videos: visible,
                onChanged: () async {
                  final s = await LocalStore().privateIds();
                  if (mounted) setState(() => _priv = s);
                },
              ),
            ),
    );
  }
}
