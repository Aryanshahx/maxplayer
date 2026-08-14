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

/// v31 Cleaner - a real device cleaner:
///  * SCAN: one tap (or open) measures every cache kind the app can free.
///  * GRAPHS: a device-storage bar and a reclaimable-space donut with a
///    colour-matched legend.
///  * CLEAN: one "Clean cache" button frees all caches at once; AI models
///    (downloads) sit on their own row with a warning dialog.
///  * Below: LARGEST videos and DUPLICATE copies - deletion is permanent
///    and always asks first. Your videos are never touched by cache
///    cleaning.
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
  DeviceStorage? _storage;
  bool _scanning = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Scan as soon as the sheet opens - the numbers should never be stale.
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
    setState(() {
      _report = report;
      _deviceCache = deviceCache;
      _storage = storage;
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
      }
      // The decoded-image memory cache holds file thumbnails - dropping it
      // makes the freed space (and the graphs) show up at once.
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

  /// The big button: every cache kind in one go (AI models excluded -
  /// they are downloads, cleared from their own row).
  Future<void> _cleanAllCache() async {
    if (_busy || _cacheTotal <= 0) return;
    setState(() => _busy = true);
    var freed = 0;
    try {
      freed += await NativeBridge.clearStorage('thumbs'); // incl. strips
      freed += await NativeBridge.clearStorage('temp');
      freed += await _clearDeviceThumbCache();
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
    } finally {
      await _scan();
      if (mounted) setState(() => _busy = false);
    }
    _snack(
      freed > 0
          ? 'Cleaned all caches - freed ${formatFileSize(freed)}'
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
              height: MediaQuery.of(sheetContext).size.height * 0.5,
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
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '${remaining.length} identical copies - keep one, '
                        'delete the rest',
                        style: TextStyle(
                          color: themeState.accent,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
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
                        : ListView(
                            children: [
                              for (final t in remaining)
                                ListTile(
                                  dense: true,
                                  leading: Icon(
                                    Icons.movie_outlined,
                                    color: themeState.accent,
                                  ),
                                  title: Text(
                                    t.path,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11.5,
                                    ),
                                  ),
                                  trailing: IconButton(
                                    tooltip: 'Delete this copy',
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      color: Colors.redAccent,
                                      size: 20,
                                    ),
                                    onPressed: () async {
                                      await _confirmDelete(
                                          t, () => setSheetState(() {}));
                                    },
                                  ),
                                ),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final accent = themeState.accent;
    final grand = _grandTotal;
    final largest = widget.library.largestVideos(n: 8);
    final dupes = widget.library.duplicateGroups;

    Widget section(String title) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 2),
          child: Text(
            title,
            style: TextStyle(
              color: accent,
              fontSize: 13.5,
              fontWeight: FontWeight.bold,
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
    }) {
      return ListTile(
        dense: true,
        leading:
            Icon(icon, color: Color(cleanerKindColors[kind] ?? 0xFF9E9E9E)),
        title: Text(
          title,
          style: const TextStyle(color: Colors.white, fontSize: 14),
        ),
        subtitle: Text(
          note,
          style: const TextStyle(color: Colors.white38, fontSize: 11.5),
        ),
        trailing: TextButton(
          onPressed: bytes > 0 && !_busy ? onClear : null,
          child: Text(
            bytes > 0 ? 'Clear ${formatFileSize(bytes)}' : 'Empty',
          ),
        ),
      );
    }

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.82,
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
            // Header: headline + scan button.
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Cleaner',
                          style: TextStyle(
                            color: accent,
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          _scanning
                              ? 'Scanning caches...'
                              : grand > 0
                                  ? '${formatFileSize(grand)} reclaimable'
                                  : 'Nothing to reclaim - all clean',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Scan again',
                    onPressed: _scanning || _busy ? null : _scan,
                    icon: _scanning
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: accent,
                            ),
                          )
                        : Icon(Icons.refresh, color: accent),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 14),
                children: [
                  // ---- Graph 1: device storage bar ----------------------
                  if (_storage != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.sd_storage_outlined,
                                    color: accent, size: 18),
                                const SizedBox(width: 8),
                                const Expanded(
                                  child: Text(
                                    'Device storage',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                Text(
                                  '${formatFileSize(_storage!.free)} free '
                                  'of ${formatFileSize(_storage!.total)}',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 11.5,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              height: 10,
                              width: double.infinity,
                              child: CustomPaint(
                                painter: _StorageBarPainter(
                                  usedFraction: _storage!.usedFraction,
                                  fillColor: accent,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  // ---- Graph 2: reclaimable donut + legend --------------
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 120,
                            height: 120,
                            child: CustomPaint(
                              painter: _DonutPainter(_segments),
                              child: Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      _scanning
                                          ? '...'
                                          : grand > 0
                                              ? formatFileSize(grand)
                                              : 'Clean',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const Text(
                                      'reclaimable',
                                      style: TextStyle(
                                        color: Colors.white38,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: _scanning
                                ? const Text(
                                    'Measuring every cache...',
                                    style: TextStyle(
                                      color: Colors.white38,
                                      fontSize: 12,
                                    ),
                                  )
                                : _segments.isEmpty
                                    ? const Text(
                                        'Every cache is empty - nothing '
                                        'to free right now.',
                                        style: TextStyle(
                                          color: Colors.white38,
                                          fontSize: 12,
                                        ),
                                      )
                                    : Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          for (final s in _segments)
                                            Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      vertical: 2),
                                              child: Row(
                                                children: [
                                                  Container(
                                                    width: 9,
                                                    height: 9,
                                                    decoration: BoxDecoration(
                                                      color:
                                                          Color(s.colorValue),
                                                      shape: BoxShape.circle,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Expanded(
                                                    child: Text(
                                                      s.label,
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                        color: Colors.white70,
                                                        fontSize: 11.5,
                                                      ),
                                                    ),
                                                  ),
                                                  Text(
                                                    formatFileSize(s.bytes),
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 11.5,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                        ],
                                      ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // ---- Clean all button ---------------------------------
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed:
                            _cacheTotal > 0 && !_busy ? _cleanAllCache : null,
                        icon: Icon(
                          _busy
                              ? Icons.hourglass_top
                              : Icons.cleaning_services_outlined,
                        ),
                        label: Text(
                          _cacheTotal > 0
                              ? 'Clean cache - free '
                                  '${formatFileSize(_cacheTotal)}'
                              : 'Cache is clean',
                        ),
                      ),
                    ),
                  ),
                  // ---- Per-kind cache rows ------------------------------
                  section('All caches - one tap each'),
                  cacheRow(
                    kind: 'thumbs',
                    icon: Icons.image_outlined,
                    title: 'App thumbnails & previews',
                    note: 'Rebuild automatically as you browse and play',
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
                    icon: Icons.cleaning_services_outlined,
                    title: 'Device gallery cache (.thumbnails)',
                    note: 'Android rebuilds it on its own - safe to clear',
                    bytes: _deviceCache,
                    onClear: () => _clearKind('device', 'Device gallery cache'),
                  ),
                  cacheRow(
                    kind: 'models',
                    icon: Icons.psychology_outlined,
                    title: 'AI subtitle models',
                    note: 'Downloads again only when you generate subtitles',
                    bytes: _models,
                    onClear: _clearModels,
                  ),
                  // ---- Largest videos ------------------------------------
                  if (largest.isNotEmpty) ...[
                    section('Largest videos - tap to delete'),
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
                    section('Duplicate videos - same size & duration'),
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
                        trailing: const Text(
                          'open',
                          style: TextStyle(
                            color: Colors.white38,
                            fontSize: 12,
                          ),
                        ),
                        onTap: () => _showDuplicateGroup(g),
                      ),
                  ],
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 10, 20, 0),
                    child: Text(
                      'Video deletion asks first and is permanent. '
                      'Cache cleaning never touches your videos.',
                      style: TextStyle(
                        color: Colors.white38,
                        fontSize: 11.5,
                      ),
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
