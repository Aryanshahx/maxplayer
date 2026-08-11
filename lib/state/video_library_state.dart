import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
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
class VideoLibraryState extends ChangeNotifier {
  List<VideoTrack> _videos = [];
  bool isScanning = false;
  ScanProgress scanProgress = const ScanProgress();
  String? folderName;
  String? _folderPath;

  String searchQuery = '';
  SortMode sortMode = SortMode.name;
  bool sortAscending = true;

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

  /// Opens Android's folder picker (SAF) and recursively scans for videos.
  Future<void> pickFolderAndScan() async {
    final dirPath = await FilePicker.platform.getDirectoryPath();
    if (dirPath == null) return; // user cancelled
    _folderPath = dirPath;
    folderName = p.basename(dirPath);
    await _scanDirectory(dirPath);
  }

  Future<void> rescan() async {
    if (_folderPath != null) {
      await _scanDirectory(_folderPath!);
    }
  }

  /// Lets the user multi-select individual video files (fallback when
  /// folder scanning isn't convenient, mirrors the web app's drag/drop + file picker).
  Future<void> addFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.video,
    );
    if (result == null || result.files.isEmpty) return;

    isScanning = true;
    scanProgress = ScanProgress(total: result.files.length);
    notifyListeners();

    final newVideos = <VideoTrack>[];
    for (final f in result.files) {
      final path = f.path;
      if (path == null) continue;
      final track = await _buildTrack(path);
      if (track != null) newVideos.add(track);
      scanProgress = ScanProgress(
        found: result.files.length,
        processed: newVideos.length,
        total: result.files.length,
      );
      notifyListeners();
    }

    _videos = [..._videos, ...newVideos];
    folderName ??= 'My Videos';
    isScanning = false;
    notifyListeners();
  }

  Future<void> _scanDirectory(String dirPath) async {
    isScanning = true;
    _videos = [];
    scanProgress = const ScanProgress();
    notifyListeners();

    final dir = Directory(dirPath);
    final foundFiles = <File>[];
    try {
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is File && isVideoFile(entity.path)) {
          foundFiles.add(entity);
        }
      }
    } catch (e) {
      debugPrint('Folder scan failed: $e');
    }

    scanProgress = ScanProgress(found: foundFiles.length, total: foundFiles.length);
    notifyListeners();

    final allVideos = <VideoTrack>[];
    // Process in small batches so the UI can show progress incrementally.
    const batchSize = 4;
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

  Future<VideoTrack?> _buildTrack(String path) async {
    try {
      final file = File(path);
      final stat = await file.stat();
      return VideoTrack(
        id: '$path-${stat.modified.millisecondsSinceEpoch}',
        title: p.basenameWithoutExtension(path),
        path: path,
        // Thumbnail generation removed for now - the `video_thumbnail`
        // plugin's Android build config is incompatible with current AGP
        // (missing namespace declaration). VideoTile already falls back to
        // a placeholder icon when thumbnailPath is null.
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
