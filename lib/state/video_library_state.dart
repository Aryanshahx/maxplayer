import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path/path.dart' as p;

import '../models/video_track.dart';
import '../services/native_bridge.dart';
import '../utils/formatters.dart';

class ScanProgress {
  final int found;
  final int processed;
  final int total;
  const ScanProgress({this.found = 0, this.processed = 0, this.total = 0});
}

/// One section in the library when grouping is enabled.
class VideoGroup {
  final String title;
  final List<VideoTrack> videos;
  const VideoGroup(this.title, this.videos);
}

/// Parses an enum value from its persisted name, falling back to [fallback].
T _parseEnum<T extends Enum>(List<T> values, String? name, T fallback) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  return fallback;
}

/// v40: normalizes the native storage-root list (internal + SD card) for
/// the scanner: trims, strips trailing slashes, drops blanks/duplicates
/// and guarantees at least the internal root. Top-level + pure so the
/// widget test can pin the behavior.
List<String> normalizeStorageRoots(List<String> raw) {
  final seen = <String>{};
  final out = <String>[];
  for (final r in raw) {
    var p = r.trim();
    while (p.endsWith('/') && p.length > 1) {
      p = p.substring(0, p.length - 1);
    }
    if (p.isEmpty || p == '/') continue;
    if (seen.add(p)) out.add(p);
  }
  if (out.isEmpty) out.add('/storage/emulated/0');
  return out;
}

/// Mirrors the web app's useVideoLibrary hook, simplified to a single flow:
/// request storage permission, then scan EVERY mounted storage volume for
/// videos - internal storage AND any SD card (v40; before, only
/// "/storage/emulated/0/" was walked, so SD-card videos never appeared).
/// No folder picker - file_picker's Android implementation proved
/// incompatible with the current AGP 9 / Kotlin 2.3 / Flutter 3.44 toolchain.
///
/// Also owns all VLC-style display settings (view mode, favourites, grouping,
/// playback action, sorting) and persists them through [NativeBridge].
class VideoLibraryState extends ChangeNotifier {
  List<VideoTrack> _videos = [];
  bool isScanning = false;
  ScanProgress scanProgress = const ScanProgress();
  String? folderName;
  bool permissionDenied = false;

  String searchQuery = '';
  SortMode sortMode = SortMode.name;
  bool sortAscending = true;

  /// v28: the Folders quick-tile restricts the list to ONE folder.
  /// Session-only (never persisted) so a leftover filter can never hide
  /// someone's videos after an app restart.
  String? folderFilter;

  // --- VLC-style display settings (persisted) ---
  ViewMode viewMode = ViewMode.grid;
  GroupMode groupMode = GroupMode.none;
  PlaybackAction playbackAction = PlaybackAction.all;
  bool favoritesOnly = false;
  Set<String> _favoritePaths = {};

  bool _disposed = false;

  /// Folders under a storage volume that are never worth scanning for videos
  /// (app-private caches, thumbnails, etc) - skipping these keeps the
  /// whole-device scan fast and avoids permission-denied noise.
  static const List<String> _skipDirNames = [
    'Android', // app-private data/obb, largely inaccessible + irrelevant anyway
    '.thumbnails',
    '.trashed',
    'cache',
  ];

  VideoLibraryState() {
    _loadSettings();
  }

  // ---------------------------------------------------------------------------
  // Derived views
  // ---------------------------------------------------------------------------

  List<VideoTrack> get videos {
    final filtered = _videos.where((v) {
      if (folderFilter != null && v.folderName != folderFilter) return false;
      if (favoritesOnly && !_favoritePaths.contains(v.path)) return false;
      if (searchQuery.isEmpty) return true;
      return v.title.toLowerCase().contains(searchQuery.toLowerCase());
    }).toList();

    filtered.sort(_compareTracks);
    return filtered;
  }

  /// [videos] split into groups per [groupMode]. With [GroupMode.none] this
  /// returns a single unnamed group - the UI can always render [groups].
  List<VideoGroup> get groups {
    final visible = videos;
    if (groupMode == GroupMode.none) {
      return [VideoGroup('', visible)];
    }
    final byKey = <String, List<VideoTrack>>{};
    for (final v in visible) {
      final key = groupMode == GroupMode.folder ? v.folderName : _nameKey(v.title);
      byKey.putIfAbsent(key, () => []).add(v);
    }
    final keys = byKey.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return [for (final k in keys) VideoGroup(k, byKey[k]!)];
  }

  int get allVideosCount => _videos.length;
  int get favoriteCount => _favoritePaths.length;
  bool isFavorite(VideoTrack track) => _favoritePaths.contains(track.path);

  /// v40: the UNFILTERED scanned list. The [videos] getter applies
  /// search/favorites/folder filters, which must never hide videos from a
  /// picker (Playlists sheet "add videos").
  List<VideoTrack> get allVideos => List.unmodifiable(_videos);

  /// v40: exact-path lookup in the scanned list (Playlists resolve their
  /// saved paths here first, gaining durations/thumbnails for free).
  VideoTrack? findByPath(String path) {
    for (final v in _videos) {
      if (v.path == path) return v;
    }
    return null;
  }

  int _compareTracks(VideoTrack a, VideoTrack b) {
    int cmp;
    switch (sortMode) {
      case SortMode.name:
        cmp = a.title.toLowerCase().compareTo(b.title.toLowerCase());
        break;
      case SortMode.date:
        cmp = (a.lastModifiedMs ?? 0).compareTo(b.lastModifiedMs ?? 0);
        break;
      case SortMode.size:
        cmp = (a.sizeBytes ?? 0).compareTo(b.sizeBytes ?? 0);
        break;
      case SortMode.length:
        // Videos with unknown duration always sink to the bottom,
        // whichever direction is active.
        final av = a.duration?.inMilliseconds;
        final bv = b.duration?.inMilliseconds;
        if (av == null && bv == null) {
          cmp = 0;
        } else if (av == null) {
          return 1;
        } else if (bv == null) {
          return -1;
        } else {
          cmp = av.compareTo(bv);
        }
        break;
    }
    return sortAscending ? cmp : -cmp;
  }

  /// First A-Z/0-9 character of the title, '#' otherwise (VLC-style buckets).
  static String _nameKey(String title) {
    if (title.isEmpty) return '#';
    final c = title[0].toUpperCase();
    return RegExp(r'[A-Z0-9]').hasMatch(c) ? c : '#';
  }

  // ---------------------------------------------------------------------------
  // Settings mutators (persisted)
  // ---------------------------------------------------------------------------

  void setSearchQuery(String q) {
    searchQuery = q;
    notifyListeners();
  }

  void setSortMode(SortMode m) {
    sortMode = m;
    _persist();
    notifyListeners();
  }

  void toggleSortDirection() {
    sortAscending = !sortAscending;
    _persist();
    notifyListeners();
  }

  /// One-shot setter used by the display-settings sheet - selecting e.g.
  /// "A → Z" fixes both the mode and the direction, like in VLC.
  void setSort(SortMode mode, bool ascending) {
    sortMode = mode;
    sortAscending = ascending;
    _persist();
    notifyListeners();
  }

  void setViewMode(ViewMode mode) {
    viewMode = mode;
    _persist();
    notifyListeners();
  }

  void setGroupMode(GroupMode mode) {
    groupMode = mode;
    _persist();
    notifyListeners();
  }

  void setPlaybackAction(PlaybackAction action) {
    playbackAction = action;
    _persist();
    notifyListeners();
  }

  void setFavoritesOnly(bool value) {
    favoritesOnly = value;
    _persist();
    notifyListeners();
  }

  /// v28 Folders tile: show only one folder (null = everything again).
  void setFolderFilter(String? folder) {
    folderFilter = folder;
    notifyListeners();
  }

  /// v28: every folder containing videos -> how many, name-sorted.
  Map<String, int> get folderCounts {
    final counts = <String, int>{};
    for (final v in _videos) {
      counts[v.folderName] = (counts[v.folderName] ?? 0) + 1;
    }
    final keys = counts.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return {for (final k in keys) k: counts[k]!};
  }

  /// v29 Cleaner: the [n] largest videos, biggest first (big files eat
  /// storage fastest, so the cleaner surfaces them).
  List<VideoTrack> largestVideos({int n = 10}) {
    final withSize = _videos.where((v) => (v.sizeBytes ?? 0) > 0).toList()
      ..sort((a, b) => (b.sizeBytes ?? 0).compareTo(a.sizeBytes ?? 0));
    return withSize.take(n).toList();
  }

  /// v29 Cleaner: probable duplicates - videos with the SAME byte size
  /// AND the SAME duration (two independent signals; hashing whole files
  /// would make the cleaner crawl). Groups with 2+ copies, biggest first.
  List<List<VideoTrack>> get duplicateGroups {
    final bySig = <String, List<VideoTrack>>{};
    for (final v in _videos) {
      final size = v.sizeBytes ?? 0;
      if (size <= 0) continue;
      final dur = v.duration?.inMilliseconds ?? 0;
      bySig.putIfAbsent('$size|$dur', () => []).add(v);
    }
    final groups = bySig.values.where((g) => g.length > 1).toList();
    groups.sort((a, b) =>
        (b.first.sizeBytes ?? 0).compareTo(a.first.sizeBytes ?? 0));
    return groups;
  }

  /// v29: drop one entry in place (the Cleaner deletes files; a rescan
  /// would rebuild everything and lose the scroll position).
  void removeVideo(String path) {
    _videos.removeWhere((v) => v.path == path);
    notifyListeners();
  }

  void toggleFavorite(VideoTrack track) {
    if (!_favoritePaths.remove(track.path)) {
      _favoritePaths.add(track.path);
    }
    _persist();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Persistence (native SharedPreferences via MethodChannel)
  // ---------------------------------------------------------------------------

  Future<void> _loadSettings() async {
    final s = await NativeBridge.loadSettings();
    if (_disposed) return;
    viewMode = _parseEnum(ViewMode.values, s['viewMode'], viewMode);
    groupMode = _parseEnum(GroupMode.values, s['groupMode'], groupMode);
    playbackAction =
        _parseEnum(PlaybackAction.values, s['playbackAction'], playbackAction);
    sortMode = _parseEnum(SortMode.values, s['sortMode'], sortMode);
    sortAscending = s['sortAscending'] != 'false'; // default true
    favoritesOnly = s['favoritesOnly'] == 'true';
    _favoritePaths = (s['favorites'] ?? '')
        .split(',')
        .where((e) => e.isNotEmpty)
        .toSet();
    notifyListeners();
  }

  void _persist() {
    NativeBridge.saveSetting('viewMode', viewMode.name);
    NativeBridge.saveSetting('groupMode', groupMode.name);
    NativeBridge.saveSetting('playbackAction', playbackAction.name);
    NativeBridge.saveSetting('sortMode', sortMode.name);
    NativeBridge.saveSetting('sortAscending', '$sortAscending');
    NativeBridge.saveSetting('favoritesOnly', '$favoritesOnly');
    NativeBridge.saveSetting('favorites', _favoritePaths.join(','));
  }

  // ---------------------------------------------------------------------------
  // Scanning
  // ---------------------------------------------------------------------------

  /// Requests "All files access" (Android 11+) or the classic Storage
  /// runtime permission (Android 10 and older), then scans the whole of
  /// internal storage for videos. Call again any time to retry after a
  /// denial.
  Future<void> scanAllStorage() async {
    if (isScanning) return;
    permissionDenied = false;
    notifyListeners();
    unawaited(NativeBridge.crumb('scan_start'));

    PermissionStatus status;
    try {
      status = await Permission.manageExternalStorage.request();
    } catch (_) {
      // v37: some skins/builds (Tecno/Infinix/MIUI, Go editions) lack the
      // "All files access" settings screen entirely, and the request can
      // blow up instead of returning 'denied'. Never die at app start:
      // fall back to the existing denied-state UI with a retry button.
      unawaited(NativeBridge.crumb('scan_permission_threw'));
      permissionDenied = true;
      notifyListeners();
      return;
    }
    if (!status.isGranted && (await NativeBridge.sdkInt()) < 30) {
      // v38: Android 10 and older (API < 30) have no "All files access" at
      // all - the request above resolves to denied FOREVER there (the real
      // API 27 log: scan_start twice, never scan_granted, even after the
      // user granted Storage manually). The classic Storage runtime
      // permission is the correct ask on those versions.
      unawaited(NativeBridge.crumb('scan_legacy_perm'));
      status = await Permission.storage.request();
    }
    if (!status.isGranted) {
      permissionDenied = true;
      notifyListeners();
      return;
    }

    unawaited(NativeBridge.crumb('scan_granted'));
    folderName = 'Device storage';
    // v40: scan EVERY mounted storage volume (internal + SD card, e.g.
    // "/storage/1C4B-9A2F"). The old code walked only
    // "/storage/emulated/0/", so videos on SD cards never appeared
    // ("does not show external storage added on phone like sd cards").
    await _scanDirectories(
      normalizeStorageRoots(await NativeBridge.storageRoots()),
    );
  }

  Future<void> rescan() => scanAllStorage();

  /// v22: swap in a thumbnail the PLAYER captured with mpv (Android's
  /// metadata engine can't decode some 4K/HDR files, whose tiles stayed
  /// grey). Updates the list in place - no rescan needed.
  void setThumbnail(String videoPath, String thumbPath) {
    var hit = false;
    for (var i = 0; i < _videos.length; i++) {
      if (_videos[i].path == videoPath) {
        _videos[i] = _videos[i].copyWith(thumbnailPath: thumbPath);
        hit = true;
      }
    }
    if (hit) notifyListeners();
  }

  /// v40: walks every storage-volume root in [roots] (internal + SD card).
  /// The same file can surface twice (e.g. an SD card that is ALSO mounted
  /// under "/storage/emulated/0/..." on some phones) - [seenPaths] dedupes.
  Future<void> _scanDirectories(List<String> roots) async {
    isScanning = true;
    _videos = [];
    scanProgress = const ScanProgress();
    notifyListeners();

    final foundFiles = <File>[];
    final seenPaths = <String>{};
    for (final root in roots) {
      await for (final entity
          in _listVideosSkippingJunk(Directory(root))) {
        if (seenPaths.add(entity.path)) foundFiles.add(entity);
      }
    }

    scanProgress =
        ScanProgress(found: foundFiles.length, total: foundFiles.length);
    notifyListeners();

    final allVideos = <VideoTrack>[];
    // Process in small batches so the UI can show progress incrementally.
    const batchSize = 8;
    for (var i = 0; i < foundFiles.length; i += batchSize) {
      final batch = foundFiles.skip(i).take(batchSize);
      final tracks = await Future.wait(batch.map((f) => _buildTrack(f.path)));
      allVideos.addAll(tracks.whereType<VideoTrack>());
      _videos = [...allVideos];
      scanProgress = ScanProgress(
        found: foundFiles.length,
        processed: (i + batchSize).clamp(0, foundFiles.length),
        total: foundFiles.length,
      );
      notifyListeners();
    }

    isScanning = false;
    notifyListeners();
  }

  /// Recursively lists video files under [dir], skipping subfolders named in
  /// [_skipDirNames] and silently ignoring individual permission-denied
  /// entries (common under /storage/emulated/0/Android on newer Android).
  Stream<File> _listVideosSkippingJunk(Directory dir) async* {
    List<FileSystemEntity> entries;
    try {
      entries = await dir.list(followLinks: false).toList();
    } catch (_) {
      return; // can't read this directory (permission denied etc) - skip it
    }

    for (final entity in entries) {
      final name = p.basename(entity.path);
      if (entity is Directory) {
        if (_skipDirNames.contains(name)) continue;
        yield* _listVideosSkippingJunk(entity);
      } else if (entity is File && isVideoFile(entity.path)) {
        yield entity;
      }
    }
  }

  Future<VideoTrack?> _buildTrack(String path) async {
    try {
      final file = File(path);
      final stat = await file.stat();
      // Duration + thumbnail come from native MediaMetadataRetriever code
      // (replaces the AGP-incompatible video_thumbnail plugin). Thumbnails
      // are cached on disk natively, so this is cheap on repeat scans.
      final meta = await NativeBridge.fetchMetadata(path);
      return VideoTrack(
        id: '$path-${stat.modified.millisecondsSinceEpoch}',
        title: p.basenameWithoutExtension(path),
        path: path,
        thumbnailPath: meta.thumbnailPath,
        duration: meta.duration,
        sizeBytes: stat.size,
        lastModifiedMs: stat.modified.millisecondsSinceEpoch,
        width: meta.width,
        height: meta.height,
      );
    } catch (e) {
      debugPrint('Failed to read $path: $e');
      return null;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// Test hook - swaps the scanned list without touching the filesystem.
  @visibleForTesting
  void debugSetVideos(List<VideoTrack> videos) {
    _videos = videos;
    notifyListeners();
  }
}
