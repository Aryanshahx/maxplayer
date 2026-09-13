import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../screens/player_screen.dart';
import '../state/private_vault.dart';
import '../theme.dart';
import '../utils/badges.dart';
import '../utils/crash_log.dart';
import '../utils/format.dart';
import '../utils/local_store.dart';
import '../utils/resume.dart';
import '../utils/settings.dart';
import '../utils/storage_permission.dart';

/// Shared video card grid + compact list used by Home, Folders, Playlists,
/// Private Space and History. Responsive: column count adapts to width.
class VideoGrid extends StatefulWidget {
  const VideoGrid({
    super.key,
    required this.videos,
    required this.onChanged,
    this.onOpen,
    this.listMode = false,
    this.controller,
  });

  final List<AssetEntity> videos;
  final VoidCallback onChanged;
  final void Function(AssetEntity asset)? onOpen;

  /// Compact rows instead of visual cards (Display Settings → List View).
  final bool listMode;

  /// Optional scroll controller so the home screen can drive the
  /// hide-on-scroll quick tiles from this grid's offset.
  final ScrollController? controller;

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

  @override
  void initState() {
    super.initState();
    _loadFlags();
  }

  Future<void> _loadFlags() async {
    final favs = await _store.favorites();
    if (mounted) {
      setState(() {
        _favs = favs;
      });
    }
  }

  Future<void> _toggleFav(AssetEntity a) async {
    await _store.toggleFavorite(a.id);
    await _loadFlags();
    widget.onChanged();
  }

  Future<void> _togglePrivate(AssetEntity a) async {
    // Old-app parity: "Move to Private folder" really moves the FILE into
    // the app-private vault (it disappears from Gallery + MediaStore), so
    // the whole device is the source of truth — not an id flag.
    if (!await ensureStorageAccess()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Private folder needs storage permission: allow it, then '
            'long-press the video again',
          ),
        ),
      );
      return;
    }
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a24),
        title: const Text('Move to Private folder?',
            style: TextStyle(color: Colors.white, fontSize: 17)),
        content: Text(
          '"${a.title ?? 'This video'}" moves into the app\'s private folder '
          '- invisible to Gallery and file managers, visible here only after '
          'your PIN.\n\nWarning: uninstalling the app deletes hidden videos.',
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 13,
            height: 1.45,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.lock_outline, size: 16),
            label: const Text('Hide'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final file = await a.file;
      final path = file?.path;
      if (path == null || path.isEmpty) {
        throw const FileSystemException('Video file not found');
      }
      await PrivateVault().hide(path);
      await _store.scrubId(a.id);
      CrashLog.crumb('video.hidden', {'id': a.id});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Moved to Private folder')),
        );
      }
    } catch (e) {
      CrashLog.error('video.hide_failed', e, {'id': a.id});
      if (mounted) {
        final why = e
            .toString()
            .replaceAll('FileSystemException: ', '')
            .replaceAll('Exception: ', '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not hide: $why')),
        );
      }
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
              foregroundColor: Colors.white,
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
            _sheetAction(Icons.drive_file_rename_outline_rounded, 'Rename', () {
              Navigator.of(context).pop();
              _rename(a);
            }),
            _sheetAction(Icons.lock_outline_rounded, 'Move to Private folder',
                () {
              Navigator.of(context).pop();
              _togglePrivate(a);
            }),
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

  /// Renames the video's file on disk (same best-effort rename as the
  /// player). The resume point (keyed by path) migrates with it so
  /// "continue watching" keeps working. Refresh after so the grid shows
  /// the new name.
  Future<void> _rename(AssetEntity a) async {
    try {
      final file = await a.file;
      final path = file?.path;
      if (file == null || path == null || path.isEmpty || !file.existsSync()) {
        throw const FileSystemException('Video file not found');
      }
      final oldName = a.title ?? path.split('/').last;
      final dot = oldName.lastIndexOf('.');
      final ext =
          (dot > 0 && dot < oldName.length - 1) ? oldName.substring(dot) : '';
      final base = dot > 0 ? oldName.substring(0, dot) : oldName;
      final ctrl = TextEditingController(text: base);
      if (!mounted) return;
      final newBase = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppColors.border),
          ),
          title: const Text('Rename video',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 17)),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: const InputDecoration(
              hintText: 'New name',
              hintStyle: TextStyle(color: AppColors.textSecondary),
            ),
            onSubmitted: (v) => Navigator.of(context).pop(v.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel',
                  style: TextStyle(color: AppColors.textSecondary)),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: AppColors.onAccent,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => Navigator.of(context).pop(ctrl.text.trim()),
              child: const Text('Rename'),
            ),
          ],
        ),
      );
      if (newBase == null || newBase.isEmpty || newBase == base) return;
      final newName = '$newBase$ext';
      final targetPath = '${file.parent.path}${Platform.pathSeparator}$newName';
      final target = File(targetPath);
      if (target.existsSync()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('A file with that name exists')));
        }
        return;
      }
      final resume = ResumeStore();
      final saved = await resume.readMs(path);
      await file.rename(targetPath);
      if (saved != null) {
        await resume.writeMs(targetPath, saved);
        await resume.clear(path);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Renamed to "$newName"')));
      }
      resumeProgressCache.remove(a.id);
      widget.onChanged();
    } catch (e) {
      CrashLog.error('grid.rename_failed', e, {'id': a.id});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Rename failed - the file may be protected or in use')),
        );
      }
    }
  }

  Future<void> _open(AssetEntity a) async {
    if (widget.onOpen != null) {
      widget.onOpen!(a);
    } else {
      await VideoGrid.openVideo(context, a, store: _store, queue: widget.videos);
    }
    // Watched-progress bars must reflect the position the player just
    // saved — drop the memoized fractions so the next build re-reads them.
    resumeProgressCache.clear();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (widget.listMode) {
          return ListView.separated(
            controller: widget.controller,
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
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
        // Old-player grid geometry: maxCrossAxisExtent 200, 8px gaps,
        // 1.18 child aspect ratio.
        return GridView.builder(
          controller: widget.controller,
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 200,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.18,
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

/// Memoized watched-progress fractions (0..1) for the playbar overlay,
/// keyed by asset id. 0 = nothing watched (or finished — the bar hides).
final Map<String, Future<double>> resumeProgressCache = {};

Future<double> resumeProgress(AssetEntity asset) =>
    resumeProgressCache.putIfAbsent(asset.id, () async {
      try {
        final file = await asset.file;
        final path = file?.path;
        if (path == null || path.isEmpty) return 0;
        final saved = await ResumeStore().readMs(path);
        if (saved == null || saved <= 0) return 0;
        final durMs = asset.duration * 1000;
        if (durMs <= 0) return 0;
        // Finished videos (within the end margin) show no partial bar.
        if (isFinishedMs(saved, durMs)) return 0;
        return (saved / durMs).clamp(0.0, 1.0);
      } catch (_) {
        return 0;
      }
    });

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
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${qualityBadge(asset.width, asset.height)} · ${formatDuration(Duration(seconds: asset.duration))}',
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 11.5),
            ),
            const SizedBox(height: 5),
            SizedBox(
              width: 120,
              height: 3,
              child: FutureBuilder<double>(
                future: resumeProgress(asset),
                builder: (context, snap) {
                  final frac = (snap.data ?? 0).clamp(0.0, 1.0);
                  if (frac <= 0) return const SizedBox.shrink();
                  return Stack(
                    children: [
                      Container(
                          color: Colors.white.withValues(alpha: 0.18)),
                      FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: frac,
                        child: Container(color: AppColors.accent),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
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
    // Old-player tile: 16:9 thumbnail with quality badge (top-left),
    // favourite toggle (top-right) and duration pill (bottom-right), then
    // title + file size.
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  FutureBuilder<Uint8List?>(
                    future: videoThumb(asset, const ThumbnailSize(480, 480)),
                    builder: (context, snap) =>
                        snap.hasError || snap.data == null
                            ? const _ThumbFallback()
                            : Image.memory(snap.data!,
                                fit: BoxFit.cover, gaplessPlayback: true),
                  ),
                  // Quality badge (e.g. "1080p"), top-left like VLC.
                  Positioned(
                    top: 4,
                    left: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        qualityBadge(asset.width, asset.height),
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  // Favourite toggle.
                  Positioned(
                    top: 4,
                    right: 4,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: onToggleFav,
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isFav ? Icons.favorite : Icons.favorite_border,
                          size: 15,
                          color: isFav ? AppColors.accent : Colors.white70,
                        ),
                      ),
                    ),
                  ),
                  // Duration pill.
                  Positioned(
                    right: 6,
                    bottom: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        formatDuration(Duration(seconds: asset.duration)),
                        style: const TextStyle(
                            fontSize: 11, color: Colors.white),
                      ),
                    ),
                  ),
                  // Watched-progress playbar (resume position per path).
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: FutureBuilder<double>(
                      future: resumeProgress(asset),
                      builder: (context, snap) {
                        final frac = (snap.data ?? 0).clamp(0.0, 1.0);
                        if (frac <= 0) return const SizedBox.shrink();
                        return SizedBox(
                          height: 3,
                          child: Stack(
                            children: [
                              Container(
                                  color: Colors.white.withValues(alpha: 0.25)),
                              FractionallySizedBox(
                                alignment: Alignment.centerLeft,
                                widthFactor: frac,
                                child: Container(color: AppColors.accent),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    asset.title ?? 'Untitled',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white),
                  ),
                  const SizedBox(height: 2),
                  FutureBuilder<int>(
                    future: videoSize(asset),
                    builder: (context, snap) => Text(
                      snap.hasData && snap.data! > 0
                          ? formatBytes(snap.data!)
                          : ' ',
                      style: TextStyle(
                          fontSize: 11,
                          color: Colors.white.withValues(alpha: 0.5)),
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
