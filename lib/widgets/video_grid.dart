import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../screens/player_screen.dart';
import '../theme.dart';
import '../utils/badges.dart';
import '../utils/crash_log.dart';
import '../utils/format.dart';
import '../utils/local_store.dart';
import '../utils/resume.dart';
import '../utils/settings.dart';

/// Shared video card grid + compact list used by Home, Folders, Playlists,
/// Private Space and History. Responsive: column count adapts to width.
class VideoGrid extends StatefulWidget {
  const VideoGrid({
    super.key,
    required this.videos,
    required this.onChanged,
    this.onOpen,
    this.listMode = false,
  });

  final List<AssetEntity> videos;
  final VoidCallback onChanged;
  final void Function(AssetEntity asset)? onOpen;

  /// Compact rows instead of visual cards (Display Settings → List View).
  final bool listMode;

  /// Guarded open used everywhere a video starts (non-negotiable #2).
  /// Records history, hands off the queue when "Queue All" is enabled.
  static Future<void> openVideo(BuildContext context, AssetEntity asset,
      {LocalStore? store, List<AssetEntity>? queue}) async {
    CrashLog.crumb('video.tap', {'id': asset.id, 'title': asset.title});
    try {
      final file = await asset.file;
      if (!context.mounted) return;
      if (file == null || !file.existsSync()) {
        throw StateError('video file unavailable: ${asset.title}');
      }
      unawaited((store ?? LocalStore()).addRecent(RecentItem(
        id: asset.id,
        title: asset.title ?? 'Video',
        path: file.path,
        ts: DateTime.now().millisecondsSinceEpoch,
      )));
      List<String> queueIds = const [];
      var start = 0;
      if (AppSettings.instance.queueAll &&
          queue != null &&
          queue.isNotEmpty) {
        queueIds = queue.map((e) => e.id).toList();
        start = queueIds.indexOf(asset.id);
        if (start < 0) start = 0;
      }
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PlayerScreen(
            path: file.path,
            title: asset.title ?? 'Video',
            queueIds: queueIds,
            queueStart: start,
            meta: {
              'File': file.path,
              'Size': formatBytes(file.lengthSync()),
              'Resolution':
                  '${asset.width} × ${asset.height} (${qualityBadge(asset.width, asset.height)})',
              'Duration (MediaStore)':
                  formatDuration(Duration(seconds: asset.duration)),
              if (asset.mimeType != null) 'MIME': asset.mimeType!,
            },
          ),
        ),
      );
    } catch (e) {
      CrashLog.error('video.open_failed', e, {'id': asset.id});
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open this video')),
        );
      }
    }
  }

  /// Delete with system consent (MediaStore delete dialog on Android 11+),
  /// then scrub the id from every local store + resume point.
  static Future<bool> deleteWithConsent(AssetEntity asset,
      {LocalStore? store, ResumeStore? resumeStore}) async {
    CrashLog.crumb('video.delete_request', {'id': asset.id});
    try {
      final path = (await asset.file)?.path;
      final deleted = await PhotoManager.editor.deleteWithIds([asset.id]);
      final ok = deleted.isNotEmpty;
      if (ok) {
        await (store ?? LocalStore()).scrubId(asset.id);
        if (path != null) await (resumeStore ?? ResumeStore()).clear(path);
        CrashLog.crumb('video.deleted', {'id': asset.id});
      }
      return ok;
    } catch (e) {
      CrashLog.error('video.delete_failed', e, {'id': asset.id});
      return false;
    }
  }

  @override
  State<VideoGrid> createState() => _VideoGridState();
}

class _VideoGridState extends State<VideoGrid> {
  final _store = LocalStore();
  Set<String> _favs = {};
  Set<String> _priv = {};

  @override
  void initState() {
    super.initState();
    _loadFlags();
  }

  Future<void> _loadFlags() async {
    final favs = await _store.favorites();
    final priv = await _store.privateIds();
    if (mounted) {
      setState(() {
        _favs = favs;
        _priv = priv;
      });
    }
  }

  Future<void> _toggleFav(AssetEntity a) async {
    await _store.toggleFavorite(a.id);
    await _loadFlags();
    widget.onChanged();
  }

  Future<void> _togglePrivate(AssetEntity a) async {
    final nowPrivate = await _store.togglePrivate(a.id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(nowPrivate
            ? 'Moved to Private Space'
            : 'Removed from Private Space'),
      ));
    }
    await _loadFlags();
    widget.onChanged();
  }

  Future<void> _confirmDelete(AssetEntity a) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.border),
        ),
        title: const Text('Delete video?',
            style: TextStyle(color: AppColors.textPrimary, fontSize: 17)),
        content: Text(
          '"${a.title ?? 'This video'}" will be deleted from your device. '
          'Android will ask you to confirm.',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.danger,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    final ok = await VideoGrid.deleteWithConsent(a, store: _store);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ok ? 'Deleted' : 'Delete cancelled or failed'),
      ));
    }
    widget.onChanged();
  }

  Future<void> _addToPlaylist(AssetEntity a) async {
    final pls = await _store.playlists();
    if (!mounted) return;
    if (pls.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text('No playlists yet — create one from the Playlists tile')));
      return;
    }
    final chosen = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Add to playlist',
                  style: TextStyle(
                      color: AppColors.accent,
                      fontSize: 16,
                      fontWeight: FontWeight.w700)),
            ),
            for (final name in pls.keys)
              ListTile(
                leading: Icon(Icons.playlist_play_rounded,
                    color: AppColors.accent),
                title: Text(name,
                    style: const TextStyle(color: AppColors.textPrimary)),
                trailing: Icon(
                  pls[name]!.contains(a.id)
                      ? Icons.check_circle_rounded
                      : Icons.add_circle_outline_rounded,
                  color: pls[name]!.contains(a.id)
                      ? AppColors.accent
                      : AppColors.textSecondary,
                ),
                onTap: () => Navigator.of(context).pop(name),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (chosen == null) return;
    final added = await _store.toggleInPlaylist(chosen, a.id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text(added ? 'Added to "$chosen"' : 'Removed from "$chosen"')));
    }
    widget.onChanged();
  }

  Future<void> _properties(AssetEntity a) async {
    final file = await a.file;
    final size = file != null && file.existsSync() ? file.lengthSync() : 0;
    final latlng = await a.latlngAsync();
    String fmtDate(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    final ext = (a.title ?? '').contains('.')
        ? a.title!.split('.').last.toUpperCase()
        : 'MP4/MKV';
    final mp = (a.width * a.height / 1e6);
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.border),
        ),
        title: Text(a.title ?? 'Video',
            style:
                const TextStyle(color: AppColors.textPrimary, fontSize: 15)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _prop('Resolution',
                  '${a.width} × ${a.height} (${qualityBadge(a.width, a.height)})'),
              _prop('Megapixels', '${mp.toStringAsFixed(1)} MP/video-frame'),
              _prop('Duration',
                  formatDuration(Duration(seconds: a.duration))),
              _prop('Format', ext),
              if (a.mimeType != null) _prop('MIME', a.mimeType!),
              _prop('Size', formatBytes(size)),
              if (size > 0 && a.duration > 0)
                _prop('Average bit rate',
                    '${((size * 8) / a.duration / 1000).toStringAsFixed(0)} kbit/s'),
              _prop('Location on device',
                  file?.path ?? a.relativePath ?? 'unknown'),
              _prop('Created', fmtDate(a.createDateTime)),
              _prop('Modified', fmtDate(a.modifiedDateTime)),
              if (latlng != null)
                _prop('GPS', '${latlng.latitude}, ${latlng.longitude}'),
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  'Codec / frame-rate / track details: open the video and '
                  'tap the (i) button — the player reads them live from MPV.',
                  style: TextStyle(
                      color: AppColors.textSecondary, fontSize: 11.5,
                      height: 1.4),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Close', style: TextStyle(color: AppColors.accent)),
          ),
        ],
      ),
    );
  }

  Widget _prop(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text('$k:  $v',
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 13)),
      );

  void _showActions(AssetEntity a) {
    final isPriv = _priv.contains(a.id);
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(14),
              child: Text(a.title ?? 'Video',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700)),
            ),
            _sheetAction(Icons.playlist_add_rounded, 'Add to playlist', () {
              Navigator.of(context).pop();
              _addToPlaylist(a);
            }),
            _sheetAction(
              isPriv ? Icons.lock_open_rounded : Icons.lock_outline_rounded,
              isPriv ? 'Remove from Private Space' : 'Move to Private Space',
              () {
                Navigator.of(context).pop();
                _togglePrivate(a);
              },
            ),
            _sheetAction(Icons.info_outline_rounded, 'Properties', () {
              Navigator.of(context).pop();
              unawaited(_properties(a));
            }),
            _sheetAction(Icons.delete_outline_rounded, 'Delete', () {
              Navigator.of(context).pop();
              _confirmDelete(a);
            }, danger: true),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  ListTile _sheetAction(IconData icon, String label, VoidCallback onTap,
          {bool danger = false}) =>
      ListTile(
        leading:
            Icon(icon, color: danger ? AppColors.danger : AppColors.accent),
        title: Text(label,
            style: TextStyle(
                color: danger ? AppColors.danger : AppColors.textPrimary)),
        onTap: onTap,
      );

  void _open(AssetEntity a) => (widget.onOpen ??
      (x) => VideoGrid.openVideo(context, x,
          store: _store, queue: widget.videos))(a);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Responsive: ~190dp per column — phones 2, tablets/foldables 4-6.
        final cols = (constraints.maxWidth / 190).floor().clamp(2, 6);
        if (widget.listMode) {
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: widget.videos.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final a = widget.videos[i];
              return _VideoRow(
                asset: a,
                isFav: _favs.contains(a.id),
                onTap: () => _open(a),
                onLongPress: () => _showActions(a),
                onToggleFav: () => _toggleFav(a),
              );
            },
          );
        }
        return GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            mainAxisSpacing: 14,
            crossAxisSpacing: 14,
            childAspectRatio: 0.78,
          ),
          itemCount: widget.videos.length,
          itemBuilder: (context, i) {
            final a = widget.videos[i];
            return _VideoCard(
              asset: a,
              isFav: _favs.contains(a.id),
              onTap: () => _open(a),
              onLongPress: () => _showActions(a),
              onToggleFav: () => _toggleFav(a),
            );
          },
        );
      },
    );
  }
}

/// Static async size cache shared by cards and rows.
final Map<String, Future<int>> videoSizeCache = {};

Future<int> videoSize(AssetEntity asset) => videoSizeCache.putIfAbsent(
    asset.id, () async => (await asset.file)?.length() ?? 0);

/// Memoized thumbnail futures — MediaStore gets asked ONCE per asset, and
/// a failed sized render falls back to an unscaled decode before giving
/// up (common on huge 4K/HEVC files and some SD cards).
final Map<String, Future<Uint8List?>> videoThumbCache = {};

Future<Uint8List?> videoThumb(AssetEntity asset, ThumbnailSize size) =>
    videoThumbCache.putIfAbsent('${asset.id}@${size.width}', () async {
      try {
        final t = await asset.thumbnailDataWithSize(size);
        if (t != null) return t;
      } catch (_) {/* fall through */}
      try {
        return await asset.thumbnailDataWithOption(
          ThumbnailOption(
              size: size, format: ThumbnailFormat.jpeg, quality: 90),
        );
      } catch (_) {
        return null;
      }
    });

class _VideoRow extends StatelessWidget {
  const _VideoRow({
    required this.asset,
    required this.isFav,
    required this.onTap,
    required this.onLongPress,
    required this.onToggleFav,
  });

  final AssetEntity asset;
  final bool isFav;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onToggleFav;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: onTap,
        onLongPress: onLongPress,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: 72,
            height: 48,
            child: FutureBuilder<Uint8List?>(
              future: videoThumb(asset, const ThumbnailSize(160, 110)),
              builder: (context, t) => t.hasError || t.data == null
                  ? const _ThumbFallback()
                  : Image.memory(t.data!, fit: BoxFit.cover),
            ),
          ),
        ),
        title: Text(asset.title ?? 'Untitled',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style:
                const TextStyle(color: AppColors.textPrimary, fontSize: 14)),
        subtitle: Text(
          '${qualityBadge(asset.width, asset.height)} · ${formatDuration(Duration(seconds: asset.duration))}',
          style:
              const TextStyle(color: AppColors.textSecondary, fontSize: 11.5),
        ),
        trailing: IconButton(
          icon: Icon(
            isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            color: isFav ? AppColors.danger : AppColors.textSecondary,
            size: 20,
          ),
          onPressed: onToggleFav,
        ),
      ),
    );
  }
}

class _VideoCard extends StatelessWidget {
  const _VideoCard({
    required this.asset,
    required this.isFav,
    required this.onTap,
    required this.onLongPress,
    required this.onToggleFav,
  });

  final AssetEntity asset;
  final bool isFav;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onToggleFav;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  FutureBuilder<Uint8List?>(
                    future: videoThumb(asset, const ThumbnailSize(480, 480)),
                    builder: (context, snap) =>
                        snap.hasError || snap.data == null
                            ? const _ThumbFallback()
                            : Image.memory(snap.data!, fit: BoxFit.cover, gaplessPlayback: true),
                  ),
                  Positioned(
                    left: 8,
                    top: 8,
                    child: _Pill(
                      text: qualityBadge(asset.width, asset.height),
                      color: Colors.black.withValues(alpha: 0.65),
                      textColor: AppColors.textPrimary,
                    ),
                  ),
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: _Pill(
                      text: formatDuration(Duration(seconds: asset.duration)),
                      color: Colors.black.withValues(alpha: 0.65),
                      textColor: AppColors.textPrimary,
                    ),
                  ),
                  Positioned(
                    right: 4,
                    top: 4,
                    child: IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: Icon(
                        isFav
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        color: isFav ? AppColors.danger : Colors.white,
                        size: 20,
                      ),
                      onPressed: onToggleFav,
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
                        color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 3),
                  FutureBuilder<int>(
                    future: videoSize(asset),
                    builder: (context, snap) => Text(
                      snap.hasData && snap.data! > 0
                          ? formatBytes(snap.data!)
                          : ' ',
                      style: const TextStyle(
                          fontSize: 11.5, color: AppColors.textSecondary),
                    ),
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

class _Pill extends StatelessWidget {
  const _Pill(
      {required this.text, required this.color, required this.textColor});

  final String text;
  final Color color;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration:
          BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
      child: Text(text,
          style: TextStyle(
              fontSize: 11, color: textColor, fontWeight: FontWeight.w600)),
    );
  }
}


/// Shown when MediaStore can't render a thumbnail (huge 4K/HEVC files).
class _ThumbFallback extends StatelessWidget {
  const _ThumbFallback();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: AppColors.surfaceAlt,
      child: Center(
        child: Icon(Icons.videocam_outlined,
            color: AppColors.textSecondary, size: 34),
      ),
    );
  }
}
