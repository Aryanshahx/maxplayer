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

/// Mirrors the web app's useVideoLibrary hook, simplified to a single flow:
/// request storage permission, then scan all of internal storage for videos.
/// No folder picker - file_picker's Android implementation proved
/// incompatible with the current AGP 9 / Kotlin 2.3 / Flutter 3.44 toolchain.
class VideoLibraryState extends ChangeNotifier {
  List<VideoTrack> _videos = [];
  bool isScanning = false;
  ScanProgress scanProgress = const ScanProgress();
  String? folderName;
  bool permissionDenied = false;

  String searchQuery = '';
  SortMode sortMode = SortMode.name;
  bool sortAscending = true;

  static const String _internalStorageRoot = '/storage/emulated/0/';

  /// Folders under internal storage that are never worth scanning for videos
  /// (app-private caches, thumbnails, etc) - skipping these keeps the
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

  /// Requests "All files access", then scans the whole of internal storage
  /// for videos. Call this again any time to retry after a denial.
  Future<void> scanAllStorage() async {
    permissionDenied = false;
    notifyListeners();

    final status = await Permission.manageExternalStorage.request();
    if (!status.isGranted) {
      permissionDenied = true;
      notifyListeners();
      return;
    }

    folderName = 'Internal storage';
    await _scanDirectory(_internalStorageRoot);
  }

  Future<void> rescan() => scanAllStorage();

  Future<void> _scanDirectory(String dirPath) async {
    isScanning = true;
    _videos = [];
    scanProgress = const ScanProgress();
    notifyListeners();

    final dir = Directory(dirPath);
    final foundFiles = <File>[];
    await for (final entity in _listVideosSkippingJunk(dir)) {
      foundFiles.add(entity);
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
