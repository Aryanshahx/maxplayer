import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../theme.dart';
import '../utils/format.dart';
import '../utils/local_store.dart';
import '../utils/resume.dart';
import '../widgets/video_grid.dart';

/// Watch history — most recently opened videos first, each with its saved
/// progress (old-app look: 96×54 thumbnail, time-ago + position bar, per-row
/// remove, "clear" confirm). Tapping resumes where you left off.
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

  Future<void> _confirmClear() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.border),
        ),
        title: const Text('Clear history?',
            style: TextStyle(color: AppColors.textPrimary)),
        content: const Text(
          'This also resets the saved resume position of every video.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: AppColors.onAccent,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    await _store.clearRecent();
    await ResumeStore().clearAll(); // old-app rule: clear = reset resume too
    _reload();
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
              onPressed: _confirmClear,
            ),
        ],
      ),
      body: _items.isEmpty
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.history, size: 48, color: Colors.white24),
                  SizedBox(height: 12),
                  Text(
                    'Nothing watched yet.\nVideos you open will show up here.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 16),
                  ),
                ],
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _items.length,
              separatorBuilder: (_, _) => const Divider(
                height: 1,
                indent: 120,
                color: AppColors.border,
              ),
              itemBuilder: (context, i) => _HistoryTile(
                item: _items[i],
                store: _store,
                onChanged: _reload,
              ),
            ),
    );
  }
}

class _HistoryTile extends StatefulWidget {
  const _HistoryTile({
    required this.item,
    required this.store,
    required this.onChanged,
  });

  final RecentItem item;
  final LocalStore store;
  final VoidCallback onChanged;

  @override
  State<_HistoryTile> createState() => _HistoryTileState();
}

class _HistoryTileState extends State<_HistoryTile> {
  late final Future<_HistoryDetail?> _detail = _resolve(widget.item);

  static Future<_HistoryDetail?> _resolve(RecentItem item) async {
    try {
      final asset = await AssetEntity.fromId(item.id);
      final posMs = (await ResumeStore().readMs(item.path)) ?? 0;
      final durMs = (asset?.duration ?? 0) * 1000;
      return _HistoryDetail(asset: asset, posMs: posMs, durMs: durMs);
    } catch (_) {
      return null;
    }
  }

  void _open() async {
    final asset = await AssetEntity.fromId(widget.item.id);
    if (asset == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('This video no longer exists')));
      }
      return;
    }
    if (mounted) {
      await VideoGrid.openVideo(context, asset, store: widget.store);
    }
    widget.onChanged();
  }

  Future<void> _remove() async {
    await widget.store.removeRecentByPath(widget.item.path);
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_HistoryDetail?>(
      future: _detail,
      builder: (context, snap) {
        final d = snap.data;
        final missing = snap.connectionState == ConnectionState.done && d == null;
        final posLabel = formatDuration(
            Duration(milliseconds: (d?.posMs ?? 0).clamp(0, 1 << 40)));
        final totalLabel = formatDuration(
            Duration(milliseconds: (d?.durMs ?? 0).clamp(0, 1 << 40)));
        final hasProgress =
            d != null && d.durMs > 0 && d.posMs > 0 && d.posMs < d.durMs;
        final frac = hasProgress ? (d.posMs / d.durMs).clamp(0.0, 1.0) : 0.0;
        return ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 96,
              height: 54,
              child: d?.asset == null
                  ? const _ThumbPlaceholder()
                  : FutureBuilder<Uint8List?>(
                      future: videoThumb(
                          d!.asset!, const ThumbnailSize(480, 480)),
                      builder: (context, t) => t.data == null
                          ? const _ThumbPlaceholder()
                          : Image.memory(t.data!,
                              fit: BoxFit.cover, gaplessPlayback: true),
                    ),
            ),
          ),
          title: Text(
            widget.item.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: 14,
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w500),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 2),
              Text(
                missing
                    ? '${timeAgo(widget.item.ts)}  ·  no longer on device'
                    : hasProgress
                        ? '${timeAgo(widget.item.ts)}  ·  $posLabel / $totalLabel'
                        : timeAgo(widget.item.ts),
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
              if (hasProgress) ...[
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: frac,
                    minHeight: 3,
                    backgroundColor: Colors.white10,
                    color: AppColors.accent,
                  ),
                ),
              ],
            ],
          ),
          trailing: IconButton(
            icon: const Icon(Icons.close, size: 18, color: AppColors.textSecondary),
            tooltip: 'Remove from history',
            onPressed: _remove,
          ),
          onTap: _open,
        );
      },
    );
  }
}

class _HistoryDetail {
  final AssetEntity? asset;
  final int posMs;
  final int durMs;
  const _HistoryDetail({this.asset, required this.posMs, required this.durMs});
}

class _ThumbPlaceholder extends StatelessWidget {
  const _ThumbPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surfaceAlt,
      child: const Center(
        child: Icon(Icons.movie_outlined, size: 22, color: Colors.white24),
      ),
    );
  }
}

/// Old-app relative time: "Just now", "3m ago", "5h ago", "2d ago", else
/// "12 Sep".
String timeAgo(int msSinceEpoch) {
  if (msSinceEpoch <= 0) return '';
  final dt = DateTime.fromMillisecondsSinceEpoch(msSinceEpoch);
  final diff = DateTime.now().difference(dt);
  if (diff.isNegative || diff.inSeconds < 60) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${dt.day} ${months[dt.month - 1]}';
}
