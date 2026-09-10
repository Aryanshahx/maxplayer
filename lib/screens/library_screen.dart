import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../theme.dart';
import '../utils/crash_log.dart';
import '../utils/format.dart';
import 'player_screen.dart';

/// Video library: scans device videos via MediaStore (photo_manager),
/// permission-gated, glass grid. Never auto-plays (non-negotiable #7).
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  static const _pageSize = 60;

  bool _loading = true;
  bool _denied = false;
  final List<AssetEntity> _videos = [];
  AssetPathEntity? _allPath;
  int _page = 0;
  bool _exhausted = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _denied = false;
    });
    try {
      final ps = await PhotoManager.requestPermissionExtend();
      if (!ps.isAuth && !ps.hasAccess) {
        CrashLog.crumb('library.permission_denied');
        setState(() {
          _loading = false;
          _denied = true;
        });
        return;
      }
      final paths = await PhotoManager.getAssetPathList(
        type: RequestType.video,
        onlyAll: true,
      );
      if (paths.isEmpty) {
        setState(() => _loading = false);
        return;
      }
      _allPath = paths.first;
      _page = 0;
      _videos.clear();
      _exhausted = false;
      await _loadMore();
      CrashLog.crumb('library.scanned', {'count': _videos.length});
    } catch (e) {
      CrashLog.error('library.scan_failed', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not scan videos on this device')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    final path = _allPath;
    if (path == null || _exhausted) return;
    final batch = await path.getAssetListPaged(page: _page, size: _pageSize);
    if (batch.length < _pageSize) _exhausted = true;
    _page++;
    _videos.addAll(batch.where((a) => a.type == AssetType.video));
    if (mounted) setState(() {});
  }

  Future<void> _openVideo(AssetEntity asset) async {
    CrashLog.crumb('library.tap', {'id': asset.id, 'title': asset.title});
    // Guarded preflight (non-negotiable #2): a tap must play or say why.
    try {
      final file = await asset.file;
      if (!mounted) return;
      if (file == null || !file.existsSync()) {
        throw StateError('video file unavailable: ${asset.title}');
      }
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PlayerScreen(
            path: file.path,
            title: asset.title ?? 'Video',
          ),
        ),
      );
    } catch (e) {
      CrashLog.error('library.open_failed', e, {'id': asset.id});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open this video')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MaxPlayer'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _load,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.accent),
      );
    }
    if (_denied) {
      return _CenteredHint(
        icon: Icons.lock_outline_rounded,
        title: 'Permission needed',
        message: 'MaxPlayer needs access to your videos to show the library.',
        actionLabel: 'Grant access',
        onAction: _load,
      );
    }
    if (_videos.isEmpty) {
      return _CenteredHint(
        icon: Icons.video_library_outlined,
        title: 'No videos found',
        message: 'Videos on this device will appear here.',
        actionLabel: 'Rescan',
        onAction: _load,
      );
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.pixels > n.metrics.maxScrollExtent - 600) _loadMore();
        return false;
      },
      child: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 14,
          crossAxisSpacing: 14,
          childAspectRatio: 0.78,
        ),
        itemCount: _videos.length,
        itemBuilder: (context, i) =>
            _VideoCard(asset: _videos[i], onTap: () => _openVideo(_videos[i])),
      ),
    );
  }
}

class _VideoCard extends StatelessWidget {
  const _VideoCard({required this.asset, required this.onTap});

  final AssetEntity asset;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  FutureBuilder<Uint8List?>(
                    future: asset.thumbnailDataWithSize(
                      const ThumbnailSize(480, 480),
                    ),
                    builder: (context, snap) {
                      final bytes = snap.data;
                      if (bytes == null) {
                        return const ColoredBox(color: AppColors.surfaceAlt);
                      }
                      return Image.memory(bytes, fit: BoxFit.cover);
                    },
                  ),
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        formatDuration(Duration(seconds: asset.duration)),
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.textPrimary),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    asset.title ?? 'Untitled',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${asset.modifiedDateTime.year}-'
                    '${asset.modifiedDateTime.month.toString().padLeft(2, '0')}-'
                    '${asset.modifiedDateTime.day.toString().padLeft(2, '0')}',
                    style: const TextStyle(
                        fontSize: 11.5, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CenteredHint extends StatelessWidget {
  const _CenteredHint({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 52, color: AppColors.textSecondary),
            const SizedBox(height: 16),
            Text(title,
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 8),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 20),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accent,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: onAction,
              child: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}
