import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path/path.dart' as p;

import '../models/video_track.dart';
import '../utils/formatters.dart';

class ScanProgress {
  final int found;
  final int processed;
  final int total;
  const ScanProgress({this.found = 0, this.processed = 0, this.total = 0});
}

/// Mirrors the web app's useVideoLibrary hook.
///
/// Folder access is done via a manually-entered path + broad storage
/// permission rather than a native folder-picker plugin - file_picker's
/// Android implementation has proven incompatible with the current
/// AGP 9 / Kotlin 2.3 / Flutter 3.44 toolchain combination (missing/renamed
/// native class at build time across every 8.x-11.x version tried).
class VideoLibraryState extends ChangeNotifier {
  List<VideoTrack> _videos = [];
  bool isScanning = false;
  ScanProgress scanProgress = const ScanProgress();
  String? folderName;
  String? _folderPath;
  String? permissionError;

  String searchQuery = '';
  SortMode sortMode = SortMode.name;
  bool sortAscending = true;

  /// Common Android video folders, offered as quick-pick suggestions in the UI.
  static const List<String> suggestedFolders = [
    '/storage/emulated/0/Movies',
    '/storage/emulated/0/DCIM/Camera',
    '/storage/emulated/0/Download',
    '/storage/emulated/0/',
  ];

  static const String _internalStorageRoot = '/storage/emulated/0/';

  /// Folders under internal storage that are never worth scanning for videos
  /// (app-private caches, thumbnails, etc) - skipping these keeps a
  /// whole-device scan fast and avoids permission-denied noise.
  static const List<String> _skipDirNames = [
    'Android', // app-private data/obb, largely inaccessible + irrelevant anyway
    '.thumbnails',
    '.trashed',
    'cache',
  ];

  List<VideoTrack> get videos {
    final filtered = _videos.where((v) {
      if (searchQuery.isEmpty) return true;
      return v.title.toLowerCase().contains(searchQuery.toLowerCase());
    }).toList();

    filtered.sort((a, b) {
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
      }
      return sortAscending ? cmp : -cmp;
    });
    return filtered;
  }

  int get allVideosCount => _videos.length;

  void setSearchQuery(String q) {
    searchQuery = q;
    notifyListeners();
  }

  void setSortMode(SortMode m) {
    sortMode = m;
    notifyListeners();
  }

  void toggleSortDirection() {
    sortAscending = !sortAscending;
    notifyListeners();
  }

  /// Requests "All files access" (needed to read arbitrary folders outside
  /// the media-store-scoped directories on Android 11+), then scans [dirPath].
  Future<void> scanFolder(String dirPath) async {
    if (!await _ensurePermission()) return;

    _folderPath = dirPath;
    folderName = p.basename(dirPath.endsWith('/')
        ? dirPath.substring(0, dirPath.length - 1)
        : dirPath);
    if (folderName!.isEmpty) folderName = 'Internal storage';
    await _scanDirectory(dirPath);
  }

  /// Requests storage permission, then scans the whole of internal storage
  /// for videos in one go - no folder selection needed.
  Future<void> scanAllStorage() async {
    if (!await _ensurePermission()) return;

    _folderPath = _internalStorageRoot;
    folderName = 'Internal storage';
    await _scanDirectory(_internalStorageRoot);
  }

  Future<bool> _ensurePermission() async {
    permissionError = null;
    notifyListeners();

    final status = await Permission.manageExternalStorage.request();
    if (!status.isGranted) {
      permissionError =
          'Storage access was not granted. Open Settings > Apps > Max Player > '
          'Permissions and enable "All files access", then try again.';
      notifyListeners();
      return false;
    }
    return true;
  }

  Future<void> rescan() async {
    if (_folderPath != null) {
      await _scanDirectory(_folderPath!);
    }
  }

  Future<void> _scanDirectory(String dirPath) async {
    isScanning = true;
    _videos = [];
    scanProgress = const ScanProgress();
    notifyListeners();

    final dir = Directory(dirPath);
    final foundFiles = <File>[];
    try {
      await for (final entity in _listVideosSkippingJunk(dir)) {
        foundFiles.add(entity);
      }
    } catch (e) {
      debugPrint('Folder scan failed: $e');
      permissionError = 'Could not read that folder: $e';
    }

    scanProgress = ScanProgress(found: foundFiles.length, total: foundFiles.length);
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
      return VideoTrack(
        id: '$path-${stat.modified.millisecondsSinceEpoch}',
        title: p.basenameWithoutExtension(path),
        path: path,
        // No thumbnail generation for now - see README for why.
        thumbnailPath: null,
        sizeBytes: stat.size,
        lastModifiedMs: stat.modified.millisecondsSinceEpoch,
      );
    } catch (e) {
      debugPrint('Failed to read $path: $e');
      return null;
    }
  }
}
