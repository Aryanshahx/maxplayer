import 'package:flutter/foundation.dart';
import '../models/video_model.dart';
import '../services/video_scanner_service.dart';
import '../services/native_bridge.dart';

class VideoProvider with ChangeNotifier {
  List<VideoModel> _videos = [];
  bool _isLoading = false;
  bool _isInitialized = false;

  List<VideoModel> get videos => _videos;
  bool get isLoading => _isLoading;
  bool get isInitialized => _isInitialized;

  Future<void> loadVideos({bool forceReload = false}) async {
    if (_isLoading) return;
    if (_isInitialized && !forceReload) {
      await _refreshThumbnails();
      return;
    }

    _isLoading = true;
    notifyListeners();

    try {
      _videos = await VideoScannerService.scanAllVideos();
      _isInitialized = true;
      
      final paths = _videos.map((v) => v.path).toList();
      NativeBridge.preloadThumbnails(paths);
    } catch (e) {
      debugPrint('Error loading videos: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _refreshThumbnails() async {
    for (var video in _videos) {
      final thumbPath = await NativeBridge.getThumbnail(video.path);
      if (thumbPath != null && thumbPath != video.thumbnailPath) {
        video.thumbnailPath = thumbPath;
      }
    }
    notifyListeners();
  }

  Future<void> refreshVideos() async {
    await loadVideos(forceReload: true);
  }

  void clearVideos() {
    _videos.clear();
    _isInitialized = false;
    notifyListeners();
  }
}
