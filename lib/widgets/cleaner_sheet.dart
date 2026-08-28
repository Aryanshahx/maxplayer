import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/video_track.dart';
import '../services/native_bridge.dart';
import '../state/media_player_state.dart';
import '../state/theme_state.dart';
import '../state/video_library_state.dart';
import '../utils/cleaner_stats.dart';
import '../utils/formatters.dart';

/// v31/v72 Cleaner - CCleaner-style full storage cleaner & optimizer:
///  * SCAN: measures app caches, preview thumbnails, temp AI residue, gallery cache & empty folders.
///  * GRAPHS: device-storage bar and reclaimable-space donut with colour-matched legend.
///  * ONE-TAP DEEP CLEAN: frees all caches, temp leftovers, and empty folders in 1 tap.
///  * EMPTY FOLDERS SWEEPER: finds and removes abandoned empty directories.
///  * DUPLICATE CLEANER: 1-tap "Keep 1st, delete all copies" batch action.
///  * LARGEST & OLD VIDEOS: identifies storage hogs and seldom-played media.
class CleanerSheet extends StatefulWidget {
  final MediaPlayerState player;
  final VideoLibraryState library;

  const CleanerSheet({
    super.key,
    required this.player,
    required this.library,
  });

  static Future<void> show(
    BuildContext context, {
    required MediaPlayerState player,
    required VideoLibraryState library,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1a1a24),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => CleanerSheet(player: player, library: library),
    );
  }

  @override
  State<CleanerSheet> createState() => _CleanerSheetState();
}

class _CleanerSheetState extends State<CleanerSheet> {
  Map<String, int> _report = const {};
  int _deviceCache = 0;
  int _emptyFoldersCount = 0;
  DeviceStorage? _storage;
  bool _scanning = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _scan();
  }

  int get _thumbs => (_report['thumbs'] ?? 0) + (_report['strips'] ?? 0);
  int get _temp => _report['temp'] ?? 0;
  int get _models => _report['models'] ?? 0;

  int get _cacheTotal => cleanerCacheTotal(
        thumbs: _report['thumbs'] ?? 0,
        strips: _report['strips'] ?? 0,
        temp: _temp,
        deviceCache: _deviceCache,
      );

  int get _grandTotal => _cacheTotal + _models;

  List<CleanerSegment> get _segments => cleanerSegments(
        thumbs: _report['thumbs'] ?? 0,
        strips: _report['strips'] ?? 0,
        temp: _temp,
        models: _models,
        deviceCache: _deviceCache,
      );

  Future<void> _scan() async {
    setState(() => _scanning = true);
    final report = await NativeBridge.storageReport();
    if (!mounted) return;
    final deviceCache = await _deviceThumbCacheSize();
    if (!mounted) return;
    final storage = await NativeBridge.storageTotals();
    if (!mounted) return;
    final emptyCount = await _countEmptyFolders();
    if (!mounted) return;
    setState(() {
      _report = report;
      _deviceCache = deviceCache;
      _storage = storage;
      _emptyFoldersCount = emptyCount;
      _scanning = false;
    });
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Clear one cache kind, refresh the graphs, say how much was freed.
  Future<void> _clearKind(String kind, String name) async {
    if (_busy) return;
    setState(() => _busy = true);
    var freed = 0;
    try {
      switch (kind) {
        case 'thumbs':
        case 'temp':
          freed = await NativeBridge.clearStorage(kind);
          break;
        case 'device':
          freed = await _clearDeviceThumbCache();
          break;
        case 'empty_folders':
          final deleted = await _cleanEmptyFolders();
          _snack(deleted > 0 ? 'Removed $deleted empty folders' : 'No empty folders found');
          return;
      }
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
    } finally {
      await _scan();
      if (mounted) setState(() => _busy = false);
    }
    _snack(
      freed > 0
          ? '$name cleaned - freed ${formatFileSize(freed)}'
          : '$name is already clean',
    );
  }

  /// Big Button: every cache kind and empty folders in one go.
  Future<void> _cleanAllCache() async {
    if (_busy || _cacheTotal <= 0) return;
    setState(() => _busy = true);
    var freed = 0;
    try {
      freed += await NativeBridge.clearStorage('thumbs');
      freed += await NativeBridge.clearStorage('temp');
      freed += await _clearDeviceThumbCache();
      await _cleanEmptyFolders();
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
    } finally {
      await _scan();
      if (mounted) setState(() => _busy = false);
    }
    _snack(
      freed > 0
          ? 'Deep Clean completed - freed ${formatFileSize(freed)}'
          : 'Caches are already clean',
    );
  }

  /// AI models need mobile data to come back, so they get a warning first.
  Future<void> _clearModels() async {
    if (_busy) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a24),
        title: const Text(
          'Delete the AI models?',
          style: TextStyle(color: Colors.white, fontSize: 17),
        ),
        content: Text(
          'This frees ${formatFileSize(_models)}, but AI subtitle '
          'generation downloads the model again (mobile data may be used).',
          style: const TextStyle(
              color: Colors.white70, fontSize: 13, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.redAccent.shade700,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    setState(() => _busy = true);
    final freed = await NativeBridge.clearStorage('models');
    await _scan();
    if (mounted) setState(() => _busy = false);
    _snack('AI models deleted - freed ${formatFileSize(freed)}');
  }

  Future<void> _deleteVideo(VideoTrack t) async {
    try {
      await File(t.path).delete();
      await NativeBridge.scanFile(t.path);
      widget.player.removeHistoryEntry(t.path);
      widget.library.removeVideo(t.path);
    } catch (_) {
      _snack('Could not delete the file');
    }
  }

  Future<void> _confirmDelete(VideoTrack t, void Function() refresh) async {
    final size = formatFileSize(t.sizeBytes);
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a24),
        title: const Text(
          'Delete this video?',
          style: TextStyle(color: Colors.white, fontSize: 17),
        ),
        content: Text(
          '"${t.title}" ($size) is deleted from the device storage - '
          'this cannot be undone.',
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
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.redAccent.shade700,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (yes == true) {
      await _deleteVideo(t);
      refresh();
    }
  }

  Future<void> _showDuplicateGroup(List<VideoTrack> group) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1a1a24),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          final remaining =
              group.where((t) => File(t.path).existsSync()).toList();
          return SafeArea(
            child: SizedBox(
              height: MediaQuery.of(sheetContext).size.height * 0.55,
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            '${remaining.length} identical copies',
                            style: TextStyle(
                              color: themeState.accent,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (remaining.length > 1)
                          FilledButton.tonal(
                            style: FilledButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: () async {
                              // Keep the 1st one, delete the rest
                              for (var i = 1; i < remaining.length; i++) {
                                await _deleteVideo(remaining[i]);
                              }
                              setSheetState(() {});
                              setState(() {});
                              _snack('Kept 1 copy and cleaned ${remaining.length - 1} duplicates');
                            },
                            child: const Text('Auto-clean dupes'),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: remaining.length < 2
                        ? const Center(
                            child: Text(
                              'One copy left - nothing more to clean.',
                              style: TextStyle(color: Colors.white54),
                            ),
                          )
                        : ListView.builder(
                            itemCount: remaining.length,
                            itemBuilder: (context, i) {
                              final t = remaining[i];
                              return ListTile(
                                leading: Icon(
                                  i == 0
                                      ? Icons.check_circle_outline
                                      : Icons.copy,
                                  color: i == 0
                                      ? themeState.accent
                                      : Colors.white38,
                                ),
                                title: Text(
                                  t.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                  ),
                                ),
                                subtitle: Text(
                                  '${i == 0 ? "Original copy" : "Duplicate"}  ·  ${t.folderName}',
                                  style: const TextStyle(
                                    color: Colors.white38,
                                    fontSize: 12,
                                  ),
                                ),
                                trailing: IconButton(
                                  tooltip: 'Delete this copy',
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    color: Colors.redAccent,
                                  ),
                                  onPressed: () async {
                                    await _confirmDelete(t, () {
                                      setSheetState(() {});
                                      setState(() {});
                                    });
                                  },
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Scans for empty leftover directories on storage.
  Future<int> _countEmptyFolders() async {
    var count = 0;
    try {
      const roots = ['/storage/emulated/0/DCIM', '/storage/emulated/0/Movies', '/storage/emulated/0/Download'];
      for (final r in roots) {
        final d = Directory(r);
        if (!d.existsSync()) continue;
        await for (final e in d.list(recursive: false, followLinks: false)) {
          if (e is Directory && !e.path.contains('/Android')) {
            try {
              final list = e.listSync();
              if (list.isEmpty) count++;
            } catch (_) {}
          }
        }
      }
    } catch (_) {}
    return count;
  }

  /// Cleans empty leftover directories.
  Future<int> _cleanEmptyFolders() async {
    var deleted = 0;
    try {
      const roots = ['/storage/emulated/0/DCIM', '/storage/emulated/0/Movies', '/storage/emulated/0/Download'];
      for (final r in roots) {
        final d = Directory(r);
        if (!d.existsSync()) continue;
        await for (final e in d.list(recursive: false, followLinks: false)) {
          if (e is Directory && !e.path.contains('/Android')) {
            try {
              final list = e.listSync();
              if (list.isEmpty) {
                e.deleteSync();
                deleted++;
              }
            } catch (_) {}
          }
        }
      }
    } catch (_) {}
    return deleted;
  }

  @override
  Widget build(BuildContext context) {
    final accent = themeState.accent;
    final s = _storage;
    final dupes = widget.library.duplicateGroups;
    final largest = widget.library.largestVideos(n: 6);

    Widget section(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
          child: Text(
            text.toUpperCase(),
            style: TextStyle(
              color: accent,
              fontSize: 11.5,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.1,
            ),
          ),
        );

    Widget cacheRow({
      required String kind,
      required IconData icon,
      required String title,
      required String note,
      required int bytes,
      required VoidCallback onClear,
    }) =>
        ListTile(
          dense: true,
          leading: Icon(icon, color: Colors.white70),
          title: Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          subtitle: Text(
            '$note  ·  ${formatFileSize(bytes)}',
            style: const TextStyle(color: Colors.white38, fontSize: 11.5),
          ),
          trailing: TextButton(
            onPressed: bytes > 0 && !_busy ? onClear : null,
            child: Text(
              bytes > 0 ? 'Clear' : 'Clean',
              style: TextStyle(
                color: bytes > 0 ? accent : Colors.white24,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        );

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.9,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  // ---- Header: Device Storage overview --------------------
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
                    child: Row(
                      children: [
                        Icon(Icons.cleaning_services_outlined, color: accent),
                        const SizedBox(width: 10),
                        const Text(
                          'Cleaner & Optimizer',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        if (_scanning)
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else
                          IconButton(
                            icon: const Icon(Icons.refresh, color: Colors.white54),
                            onPressed: _scan,
                          ),
                      ],
                    ),
                  ),
                  if (s != null) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                      child: Row(
                        children: [
                          Text(
                            'Used ${formatFileSize(s.used)} of ${formatFileSize(s.total)}',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${(s.usedFraction * 100).toStringAsFixed(0)}% full',
                            style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: CustomPaint(
                        size: const Size(double.infinity, 8),
                        painter: _StorageBarPainter(
                          usedFraction: s.usedFraction,
                          fillColor: accent,
                        ),
                      ),
                    ),
                  ],
                  // ---- Donut chart + Reclaimable total -------------------
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 80,
                          height: 80,
                          child: CustomPaint(
                            painter: _DonutPainter(_segments),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                formatFileSize(_grandTotal),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 2),
                              const Text(
                                'Reclaimable space on device',
                                style: TextStyle(
                                  color: Colors.white54,
                                  fontSize: 12.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // ---- One-Tap Deep Clean Button -------------------------
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: accent,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed:
                            _cacheTotal > 0 && !_busy ? _cleanAllCache : null,
                        icon: Icon(
                          _busy
                              ? Icons.hourglass_top
                              : Icons.bolt,
                        ),
                        label: Text(
                          _cacheTotal > 0
                              ? 'One-Tap Deep Clean - Free '
                                  '${formatFileSize(_cacheTotal)}'
                              : 'System is fully optimized',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ),
                  // ---- Per-kind cache rows ------------------------------
                  section('Caches & Leftovers'),
                  cacheRow(
                    kind: 'thumbs',
                    icon: Icons.image_outlined,
                    title: 'App thumbnails & previews',
                    note: 'Rebuild automatically as you browse',
                    bytes: _thumbs,
                    onClear: () =>
                        _clearKind('thumbs', 'App thumbnails & previews'),
                  ),
                  cacheRow(
                    kind: 'temp',
                    icon: Icons.mic_none_outlined,
                    title: 'Temporary AI files',
                    note: 'Leftovers from subtitle generation',
                    bytes: _temp,
                    onClear: () => _clearKind('temp', 'Temporary AI files'),
                  ),
                  cacheRow(
                    kind: 'device',
                    icon: Icons.photo_library_outlined,
                    title: 'Device gallery cache (.thumbnails)',
                    note: 'Android rebuilds on its own - safe to clear',
                    bytes: _deviceCache,
                    onClear: () => _clearKind('device', 'Device gallery cache'),
                  ),
                  cacheRow(
                    kind: 'empty_folders',
                    icon: Icons.folder_delete_outlined,
                    title: 'Empty leftover folders',
                    note: '$_emptyFoldersCount empty directories found',
                    bytes: 0,
                    onClear: () => _clearKind('empty_folders', 'Empty folders'),
                  ),
                  cacheRow(
                    kind: 'models',
                    icon: Icons.psychology_outlined,
                    title: 'AI subtitle models',
                    note: 'Downloads again only when generating subtitles',
                    bytes: _models,
                    onClear: _clearModels,
                  ),
                  // ---- Largest videos ------------------------------------
                  if (largest.isNotEmpty) ...[
                    section('Largest storage hogs - tap to delete'),
                    for (final t in largest)
                      ListTile(
                        dense: true,
                        leading: Icon(
                          Icons.video_file_outlined,
                          color: accent,
                        ),
                        title: Text(
                          t.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(
                          '${formatFileSize(t.sizeBytes)}  ·  '
                          '${t.folderName}',
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 11.5,
                          ),
                        ),
                        trailing: IconButton(
                          tooltip: 'Delete this video',
                          icon: const Icon(
                            Icons.delete_outline,
                            color: Colors.redAccent,
                            size: 20,
                          ),
                          onPressed: () =>
                              _confirmDelete(t, () => setState(() {})),
                        ),
                      ),
                  ],
                  // ---- Duplicate videos ----------------------------------
                  if (dupes.isNotEmpty) ...[
                    section('Duplicate video copies (same size & duration)'),
                    for (final g in dupes.take(6))
                      ListTile(
                        dense: true,
                        leading: Icon(
                          Icons.copy_all_outlined,
                          color: accent,
                        ),
                        title: Text(
                          g.first.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(
                          '${g.length} copies  ·  '
                          '${formatFileSize(g.first.sizeBytes)} each',
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 11.5,
                          ),
                        ),
                        trailing: Text(
                          'Review (${g.length})',
                          style: TextStyle(
                            color: accent,
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        onTap: () => _showDuplicateGroup(g),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Donut graph of the reclaimable kinds. Empty graph = one faint ring.
class _DonutPainter extends CustomPainter {
  final List<CleanerSegment> segments;

  const _DonutPainter(this.segments);

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 18.0;
    final center = (Offset.zero & size).center;
    final radius = math.min(size.width, size.height) / 2 - stroke / 2;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    final total = segments.fold<int>(0, (a, s) => a + s.bytes);
    if (total <= 0) {
      paint.color = const Color(0x1FFFFFFF);
      canvas.drawCircle(center, radius, paint);
      return;
    }
    final arcRect = Rect.fromCircle(center: center, radius: radius);
    var start = -math.pi / 2;
    for (final s in segments) {
      final sweep = (s.bytes / total) * 2 * math.pi;
      paint.color = Color(s.colorValue);
      canvas.drawArc(arcRect, start, sweep, false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) => old.segments != segments;
}

/// Device-storage usage bar (used vs free).
class _StorageBarPainter extends CustomPainter {
  final double usedFraction;
  final Color fillColor;

  const _StorageBarPainter({
    required this.usedFraction,
    required this.fillColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const radius = Radius.circular(5);
    final track = RRect.fromRectAndRadius(Offset.zero & size, radius);
    canvas.drawRRect(track, Paint()..color = const Color(0x1FFFFFFF));
    final f = usedFraction.clamp(0.0, 1.0);
    if (f > 0) {
      final fill = RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.width * f, size.height),
        radius,
      );
      canvas.drawRRect(fill, Paint()..color = fillColor);
    }
  }

  @override
  bool shouldRepaint(_StorageBarPainter old) =>
      old.usedFraction != usedFraction || old.fillColor != fillColor;
}

// ---------------------------------------------------------------------------
// System gallery thumbnail cache (safe to clear - Android simply rebuilds
// it when a gallery app is opened again).
// ---------------------------------------------------------------------------

const List<String> _deviceThumbDirs = [
  '/storage/emulated/0/DCIM/.thumbnails',
  '/storage/emulated/0/.thumbnails',
];

Future<int> _pathSizeBytes(String path) async {
  var total = 0;
  try {
    final dir = Directory(path);
    if (!dir.existsSync()) return 0;
    await for (final e in dir.list(recursive: true, followLinks: false)) {
      if (e is File) {
        try {
          total += await e.length();
        } catch (_) {}
      }
    }
  } catch (_) {}
  return total;
}

Future<int> _deviceThumbCacheSize() async {
  var total = 0;
  for (final p in _deviceThumbDirs) {
    total += await _pathSizeBytes(p);
  }
  return total;
}

/// Deletes the CONTENTS of the gallery-cache folders (the folders
/// themselves stay). Returns freed bytes.
Future<int> _clearDeviceThumbCache() async {
  var freed = 0;
  for (final p in _deviceThumbDirs) {
    try {
      final dir = Directory(p);
      if (!dir.existsSync()) continue;
      await for (final e in dir.list(followLinks: false)) {
        try {
          if (e is File) {
            final len = await e.length();
            await e.delete();
            freed += len;
          } else if (e is Directory) {
            final size = await _pathSizeBytes(e.path);
            await e.delete(recursive: true);
            freed += size;
          }
        } catch (_) {}
      }
    } catch (_) {}
  }
  return freed;
}
