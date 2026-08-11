#!/usr/bin/env bash
# =============================================================================
# Max Player update: player fixes + audio/subtitle track selection
# Run from your flutter project root, e.g.:  cd ~/IdeaProjects/maxplayer
#
# Fixes: controls overflow error (two slim rows), fullscreen flicker,
# stacked VideoControllers. Removes volume slider (mute button stays).
# Adds: audio track + subtitle track pickers (media_kit native streams).
# INCLUDES everything from the previous update too - safe to run on the
# repo whether or not update_maxplayer.sh was already applied.
# Verified: flutter analyze = no issues, flutter test = 12/12 passed.
# =============================================================================
set -e

mkdir -p lib/models lib/state lib/screens lib/widgets lib/services test android/app/src/main/kotlin/com/example/maxplayer

cat > 'android/app/src/main/kotlin/com/example/maxplayer/MainActivity.kt' << 'MAXPLAYER_EOF'
package com.example.maxplayer

import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.security.MessageDigest
import java.util.concurrent.Executors

/**
 * Native bridge for Max Player. One MethodChannel ("maxplayer/native") exposes:
 *
 *  - getMetadata(path): video duration + a cached JPEG thumbnail, extracted with
 *    Android's own MediaMetadataRetriever. We use this instead of the
 *    `video_thumbnail` plugin, which proved incompatible with the
 *    AGP 9 / Kotlin 2.3 toolchain. No third-party plugin = no AAR conflicts.
 *
 *  - settingsGetAll / settingsPut: tiny key/value store backed by Android
 *    SharedPreferences, so no extra Dart plugin is needed either.
 *
 * Metadata extraction runs on a background executor; results are posted back
 * on the main thread as required by MethodChannel.
 */
class MainActivity : FlutterActivity() {
    private val channelName = "maxplayer/native"
    private val executor = Executors.newFixedThreadPool(4)
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getMetadata" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrEmpty()) {
                            result.error("bad_args", "path argument is required", null)
                        } else {
                            executor.execute {
                                val data = extractMetadata(path)
                                mainHandler.post { result.success(data) }
                            }
                        }
                    }
                    "settingsGetAll" -> {
                        val prefs = getSharedPreferences("maxplayer_settings", MODE_PRIVATE)
                        val map = HashMap<String, String>()
                        for ((k, v) in prefs.all) {
                            if (v is String) map[k] = v
                        }
                        result.success(map)
                    }
                    "settingsPut" -> {
                        val key = call.argument<String>("key")
                        val value = call.argument<String>("value")
                        if (key == null || value == null) {
                            result.error("bad_args", "key and value are required", null)
                        } else {
                            getSharedPreferences("maxplayer_settings", MODE_PRIVATE)
                                .edit().putString(key, value).apply()
                            result.success(true)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Extracts duration (ms) + dimensions and writes a thumbnail JPEG into the
     * app cache dir. Thumbnails are cached per video path and re-used while the
     * source file's mtime is older than the cached image, so rescanning the
     * library does NOT regenerate them every launch.
     */
    private fun extractMetadata(path: String): HashMap<String, Any?> {
        val out = HashMap<String, Any?>()
        out["thumbnailPath"] = null
        out["durationMs"] = null
        out["width"] = null
        out["height"] = null

        val videoFile = File(path)
        if (!videoFile.exists()) return out

        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(path)
            val durationMs =
                retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull()
            out["durationMs"] = durationMs
            out["width"] =
                retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull()
            out["height"] =
                retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull()

            val thumbsDir = File(cacheDir, "thumbs").apply { mkdirs() }
            val thumbFile = File(thumbsDir, md5(path) + ".jpg")

            val cacheValid =
                thumbFile.exists() && thumbFile.length() > 0 &&
                    thumbFile.lastModified() >= videoFile.lastModified()

            if (cacheValid) {
                out["thumbnailPath"] = thumbFile.absolutePath
            } else {
                // Grab a frame ~1s in (or the very first frame for tiny clips).
                val seekUs = if (durationMs != null && durationMs in 0..1500) 0L else 1_000_000L
                val frame =
                    retriever.getFrameAtTime(seekUs, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                if (frame != null) {
                    val scaled = scaleToWidth(frame, 320)
                    FileOutputStream(thumbFile).use { fos ->
                        scaled.compress(Bitmap.CompressFormat.JPEG, 82, fos)
                    }
                    if (scaled !== frame) scaled.recycle()
                    frame.recycle()
                    out["thumbnailPath"] = thumbFile.absolutePath
                } else {
                    thumbFile.delete() // don't keep a stale/broken cache entry
                }
            }
        } catch (e: Exception) {
            // Unparseable / inaccessible file -> return nulls, Dart side shows
            // the generic placeholder icon.
        } finally {
            try {
                retriever.release()
            } catch (_: Exception) {
            }
        }
        return out
    }

    private fun scaleToWidth(src: Bitmap, targetWidth: Int): Bitmap {
        if (src.width <= targetWidth) return src
        val targetHeight =
            (src.height * (targetWidth.toFloat() / src.width)).toInt().coerceAtLeast(1)
        return Bitmap.createScaledBitmap(src, targetWidth, targetHeight, true)
    }

    private fun md5(s: String): String {
        val digest = MessageDigest.getInstance("MD5").digest(s.toByteArray(Charsets.UTF_8))
        return digest.joinToString("") { "%02x".format(it) }
    }

    override fun onDestroy() {
        executor.shutdown()
        super.onDestroy()
    }
}
MAXPLAYER_EOF

cat > 'lib/services/native_bridge.dart' << 'MAXPLAYER_EOF'
import 'package:flutter/services.dart';

/// Result of a native metadata extraction for one video file.
class VideoMetadata {
  final Duration? duration;
  final String? thumbnailPath;
  final int? width;
  final int? height;

  const VideoMetadata({
    this.duration,
    this.thumbnailPath,
    this.width,
    this.height,
  });
}

/// Bridge to the Android native code in `MainActivity.kt` over a single
/// MethodChannel ("maxplayer/native"):
///
///  - [fetchMetadata]: duration + cached JPEG thumbnail per video. This
///    replaces the `video_thumbnail` plugin, which was incompatible with the
///    AGP 9 / Kotlin 2.3 toolchain — the native side has no external deps.
///  - [loadSettings] / [saveSetting]: a tiny key/value store backed by
///    Android SharedPreferences, avoiding another plugin dependency.
///
/// EVERY call is guarded: where the channel doesn't exist (unit tests,
/// desktop platforms), calls fail silently and return empty values.
class NativeBridge {
  static const MethodChannel _channel = MethodChannel('maxplayer/native');

  static Future<VideoMetadata> fetchMetadata(String path) async {
    try {
      final Map<Object?, Object?>? res =
          await _channel.invokeMethod<Map<Object?, Object?>>(
        'getMetadata',
        {'path': path},
      );
      if (res == null) return const VideoMetadata();
      final durationMs = res['durationMs'];
      final width = res['width'];
      final height = res['height'];
      return VideoMetadata(
        duration: durationMs is int ? Duration(milliseconds: durationMs) : null,
        thumbnailPath: res['thumbnailPath'] as String?,
        width: width is int ? width : null,
        height: height is int ? height : null,
      );
    } catch (_) {
      return const VideoMetadata();
    }
  }

  static Future<Map<String, String>> loadSettings() async {
    try {
      final Map<Object?, Object?>? res =
          await _channel.invokeMethod<Map<Object?, Object?>>('settingsGetAll');
      if (res == null) return <String, String>{};
      return res.map((k, v) => MapEntry('$k', '$v'));
    } catch (_) {
      return <String, String>{};
    }
  }

  static Future<void> saveSetting(String key, String value) async {
    try {
      await _channel.invokeMethod('settingsPut', {'key': key, 'value': value});
    } catch (_) {
      // Ignore - settings persistence is best-effort.
    }
  }
}
MAXPLAYER_EOF

cat > 'lib/models/video_track.dart' << 'MAXPLAYER_EOF'
import 'package:path/path.dart' as p;

/// Mirrors the web app's VideoTrack type, adapted for local files on Android.
class VideoTrack {
  final String id;
  final String title;
  final String path; // absolute filesystem path (was `src` blob URL on web)
  final String? thumbnailPath; // cached jpg path, generated on scan
  final Duration? duration;
  final int? sizeBytes;
  final int? lastModifiedMs;

  const VideoTrack({
    required this.id,
    required this.title,
    required this.path,
    this.thumbnailPath,
    this.duration,
    this.sizeBytes,
    this.lastModifiedMs,
  });

  /// Name of the folder containing this video (used by "Group by folder").
  String get folderName {
    final dir = p.dirname(path);
    final base = p.basename(dir);
    return base.isEmpty ? dir : base;
  }

  VideoTrack copyWith({
    String? thumbnailPath,
    Duration? duration,
  }) {
    return VideoTrack(
      id: id,
      title: title,
      path: path,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      duration: duration ?? this.duration,
      sizeBytes: sizeBytes,
      lastModifiedMs: lastModifiedMs,
    );
  }
}

enum RepeatMode { none, one, all }

enum SortMode { name, date, size, length }

enum ViewMode { grid, list }

enum GroupMode { none, name, folder }

/// What tapping a video does: queue every visible video, or just that file.
enum PlaybackAction { all, single }
MAXPLAYER_EOF

cat > 'lib/state/video_library_state.dart' << 'MAXPLAYER_EOF'
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

/// Mirrors the web app's useVideoLibrary hook, simplified to a single flow:
/// request storage permission, then scan all of internal storage for videos.
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

  // --- VLC-style display settings (persisted) ---
  ViewMode viewMode = ViewMode.grid;
  GroupMode groupMode = GroupMode.none;
  PlaybackAction playbackAction = PlaybackAction.all;
  bool favoritesOnly = false;
  Set<String> _favoritePaths = {};

  bool _disposed = false;

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

  VideoLibraryState() {
    _loadSettings();
  }

  // ---------------------------------------------------------------------------
  // Derived views
  // ---------------------------------------------------------------------------

  List<VideoTrack> get videos {
    final filtered = _videos.where((v) {
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

  /// Requests "All files access", then scans the whole of internal storage
  /// for videos. Call this again any time to retry after a denial.
  Future<void> scanAllStorage() async {
    if (isScanning) return;
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
MAXPLAYER_EOF

cat > 'lib/state/media_player_state.dart' << 'MAXPLAYER_EOF'
import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart' hide VideoTrack;
import 'package:media_kit_video/media_kit_video.dart';

import '../models/video_track.dart';

/// Mirrors the web app's useMediaPlayer hook, backed by media_kit's Player.
class MediaPlayerState extends ChangeNotifier {
  final Player player = Player();

  /// ONE video controller for the app's lifetime, created lazily.
  /// PlayerScreen used to construct a new VideoController on every visit and
  /// (with media_kit_video 1.3.x having no public dispose) those stacked up
  /// on the same player - one source of the fullscreen glitches.
  late final VideoController videoController = VideoController(player);

  List<VideoTrack> playlist = [];
  int currentIndex = 0;
  bool isPlaying = false;
  Duration position = Duration.zero;
  Duration duration = Duration.zero;
  double volume = 0.75; // 0..1
  bool isMuted = false;
  double playbackRate = 1.0;
  RepeatMode repeatMode = RepeatMode.none;
  bool isShuffled = false;
  bool isLoading = false;
  List<int> _shuffledOrder = [];

  // Available tracks of the currently loaded media (populated from streams).
  List<AudioTrack> audioTracks = [];
  List<SubtitleTrack> subtitleTracks = [];
  AudioTrack? currentAudioTrack;
  SubtitleTrack? currentSubtitleTrack;

  VideoTrack? get currentTrack =>
      playlist.isNotEmpty && currentIndex < playlist.length ? playlist[currentIndex] : null;

  final _rand = Random();
  late final List<StreamSubscription> _subs;

  MediaPlayerState() {
    _subs = [
      player.stream.playing.listen((v) {
        isPlaying = v;
        notifyListeners();
      }),
      player.stream.position.listen((v) {
        position = v;
        notifyListeners();
      }),
      player.stream.duration.listen((v) {
        duration = v;
        notifyListeners();
      }),
      player.stream.buffering.listen((v) {
        isLoading = v;
        notifyListeners();
      }),
      player.stream.completed.listen((completed) {
        if (completed) _handleEnded();
      }),
      // Repopulates whenever a new media is opened.
      player.stream.tracks.listen((t) {
        audioTracks = t.audio;
        subtitleTracks = t.subtitle;
        notifyListeners();
      }),
      player.stream.track.listen((t) {
        currentAudioTrack = t.audio;
        currentSubtitleTrack = t.subtitle;
        notifyListeners();
      }),
    ];
    player.setVolume(volume * 100);
  }

  List<int> _generateShuffledOrder(int length, int currentIdx) {
    final indices = List.generate(length, (i) => i)..remove(currentIdx);
    indices.shuffle(_rand);
    return [currentIdx, ...indices];
  }

  int _getNextIndex({required bool forward}) {
    if (playlist.isEmpty) return 0;
    if (isShuffled && _shuffledOrder.isNotEmpty) {
      final pos = _shuffledOrder.indexOf(currentIndex);
      final len = _shuffledOrder.length;
      return forward
          ? _shuffledOrder[(pos + 1) % len]
          : _shuffledOrder[(pos - 1 + len) % len];
    }
    final len = playlist.length;
    return forward ? (currentIndex + 1) % len : (currentIndex - 1 + len) % len;
  }

  /// Replace the whole queue and start playing at [startIndex].
  Future<void> setPlaylistAndPlay(List<VideoTrack> videos, [int startIndex = 0]) async {
    playlist = videos;
    currentIndex = startIndex.clamp(0, videos.isEmpty ? 0 : videos.length - 1);
    notifyListeners();
    await _loadCurrent(autoplay: true);
  }

  Future<void> playTrack(int index) async {
    if (index < 0 || index >= playlist.length) return;
    currentIndex = index;
    notifyListeners();
    await _loadCurrent(autoplay: true);
  }

  Future<void> _loadCurrent({required bool autoplay}) async {
    final track = currentTrack;
    if (track == null) return;
    await player.open(Media(track.path), play: autoplay);
    await player.setRate(playbackRate);
  }

  Future<void> togglePlay() async {
    if (isPlaying) {
      await player.pause();
    } else {
      await player.play();
    }
  }

  Future<void> pause() => player.pause();

  Future<void> seek(Duration to) => player.seek(to);

  Future<void> setVolume(double v) async {
    volume = v.clamp(0.0, 1.0);
    if (volume > 0) isMuted = false;
    await player.setVolume(isMuted ? 0 : volume * 100);
    notifyListeners();
  }

  Future<void> toggleMute() async {
    isMuted = !isMuted;
    await player.setVolume(isMuted ? 0 : volume * 100);
    notifyListeners();
  }

  Future<void> setPlaybackRate(double rate) async {
    playbackRate = rate;
    await player.setRate(rate);
    notifyListeners();
  }

  /// Switch to a different audio track (e.g. Hindi / English in dual-audio
  /// files). Pass an entry of [audioTracks].
  void selectAudioTrack(AudioTrack track) => player.setAudioTrack(track);

  /// Switch subtitle track; pass SubtitleTrack.no() to turn subtitles off.
  void selectSubtitleTrack(SubtitleTrack track) =>
      player.setSubtitleTrack(track);

  /// True when a real subtitle track (not "no"/off) is currently active.
  bool get subtitlesActive =>
      currentSubtitleTrack != null && currentSubtitleTrack!.id != 'no';

  Future<void> nextTrack() async {
    if (playlist.length <= 1) return;
    await playTrack(_getNextIndex(forward: true));
  }

  Future<void> prevTrack() async {
    if (position.inSeconds > 3) {
      await seek(Duration.zero);
      return;
    }
    if (playlist.length <= 1) return;
    await playTrack(_getNextIndex(forward: false));
  }

  void toggleRepeat() {
    repeatMode = switch (repeatMode) {
      RepeatMode.none => RepeatMode.all,
      RepeatMode.all => RepeatMode.one,
      RepeatMode.one => RepeatMode.none,
    };
    notifyListeners();
  }

  void toggleShuffle() {
    isShuffled = !isShuffled;
    if (isShuffled) {
      _shuffledOrder = _generateShuffledOrder(playlist.length, currentIndex);
    }
    notifyListeners();
  }

  Future<void> removeFromPlaylist(int index) async {
    final wasCurrent = index == currentIndex;
    playlist = [...playlist]..removeAt(index);
    if (playlist.isEmpty) {
      currentIndex = 0;
      await player.stop();
    } else if (wasCurrent) {
      currentIndex = currentIndex.clamp(0, playlist.length - 1);
      await _loadCurrent(autoplay: false);
    } else if (index < currentIndex) {
      currentIndex -= 1;
    }
    notifyListeners();
  }

  Future<void> _handleEnded() async {
    if (repeatMode == RepeatMode.one) {
      await player.seek(Duration.zero);
      await player.play();
    } else if (repeatMode == RepeatMode.all || currentIndex < playlist.length - 1) {
      await nextTrack();
    }
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    player.dispose();
    super.dispose();
  }
}
MAXPLAYER_EOF

cat > 'lib/widgets/display_settings_sheet.dart' << 'MAXPLAYER_EOF'
import 'package:flutter/material.dart';
import '../models/video_track.dart';
import '../state/video_library_state.dart';

/// VLC-style "Display settings" sheet: list/grid toggle, favourites filter,
/// grouping, playback action and grouped sort options with direction choices.
class DisplaySettingsSheet extends StatelessWidget {
  final VideoLibraryState library;

  const DisplaySettingsSheet({super.key, required this.library});

  static const Color _accent = Color(0xFFA855F7);
  static const Color _surface = Color(0xFF1a1a24);

  static Future<void> show(BuildContext context, VideoLibraryState library) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DisplaySettingsSheet(library: library),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Rebuilds whenever the library notifies, so checkmarks update in place.
    return AnimatedBuilder(
      animation: library,
      builder: (context, _) {
        final lib = library;
        return SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 10),
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 14, 20, 4),
                  child: Text(
                    'Display settings',
                    style: TextStyle(
                      color: _accent,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                _SwitchRow(
                  icon: Icons.view_list_outlined,
                  label: 'Display in list',
                  value: lib.viewMode == ViewMode.list,
                  onChanged: (v) =>
                      lib.setViewMode(v ? ViewMode.list : ViewMode.grid),
                ),
                _CheckRow(
                  icon: Icons.favorite_border,
                  label: 'Show only favourites',
                  value: lib.favoritesOnly,
                  onChanged: (v) => lib.setFavoritesOnly(v ?? false),
                ),
                _DropdownRow<GroupMode>(
                  icon: Icons.collections_outlined,
                  label: 'Group videos',
                  value: lib.groupMode,
                  entries: const {
                    GroupMode.none: "Don't group",
                    GroupMode.name: 'Group by name',
                    GroupMode.folder: 'Group by folder',
                  },
                  onChanged: (m) => lib.setGroupMode(m ?? GroupMode.none),
                ),
                _DropdownRow<PlaybackAction>(
                  icon: Icons.play_arrow,
                  label: 'Playback action',
                  subtitle: 'When tapping a video',
                  value: lib.playbackAction,
                  entries: const {
                    PlaybackAction.all: 'Play all (queue)',
                    PlaybackAction.single: 'Play single video',
                  },
                  onChanged: (a) =>
                      lib.setPlaybackAction(a ?? PlaybackAction.all),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 16, 20, 4),
                  child: Text(
                    'Sort by...',
                    style: TextStyle(
                      color: _accent,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                _SortGroup(
                  icon: Icons.sort_by_alpha,
                  title: 'Name',
                  mode: SortMode.name,
                  options: const ['A → Z', 'Z → A'],
                  library: lib,
                ),
                _SortGroup(
                  icon: Icons.timer_outlined,
                  title: 'Length',
                  mode: SortMode.length,
                  options: const ['Shortest first', 'Longest first'],
                  library: lib,
                ),
                _SortGroup(
                  icon: Icons.history,
                  title: 'Recently added',
                  mode: SortMode.date,
                  // lastModified ascending = oldest files first
                  options: const ['Oldest first', 'Newest first'],
                  library: lib,
                ),
                _SortGroup(
                  icon: Icons.sd_storage_outlined,
                  title: 'Size',
                  mode: SortMode.size,
                  options: const ['Smallest first', 'Largest first'],
                  library: lib,
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Icon(icon, color: Colors.white70, size: 22),
          const SizedBox(width: 16),
          Expanded(
            child: Text(label,
                style:
                    const TextStyle(color: Colors.white, fontSize: 15)),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: DisplaySettingsSheet._accent,
          ),
        ],
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool?> onChanged;

  const _CheckRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(
          children: [
            Icon(icon, color: Colors.white70, size: 22),
            const SizedBox(width: 16),
            Expanded(
              child: Text(label,
                  style:
                      const TextStyle(color: Colors.white, fontSize: 15)),
            ),
            Checkbox(
              value: value,
              onChanged: onChanged,
              activeColor: DisplaySettingsSheet._accent,
              checkColor: Colors.white,
              side: const BorderSide(color: Colors.white38),
            ),
          ],
        ),
      ),
    );
  }
}

class _DropdownRow<T> extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final T value;
  final Map<T, String> entries;
  final ValueChanged<T?> onChanged;

  const _DropdownRow({
    required this.icon,
    required this.label,
    this.subtitle,
    required this.value,
    required this.entries,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Icon(icon, color: Colors.white70, size: 22),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 15)),
                if (subtitle != null)
                  Text(subtitle!,
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 12)),
              ],
            ),
          ),
          DropdownButton<T>(
            value: value,
            dropdownColor: const Color(0xFF26262f),
            underline: const SizedBox.shrink(),
            style: const TextStyle(color: Colors.white70, fontSize: 14),
            items: [
              for (final e in entries.entries)
                DropdownMenuItem(value: e.key, child: Text(e.value)),
            ],
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

/// One VLC-style sort block: title on the left, its two direction options on
/// the right, purple checkmark on the active option. Option 0 is ascending,
/// option 1 is descending.
class _SortGroup extends StatelessWidget {
  final IconData icon;
  final String title;
  final SortMode mode;
  final List<String> options;
  final VideoLibraryState library;

  const _SortGroup({
    required this.icon,
    required this.title,
    required this.mode,
    required this.options,
    required this.library,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Icon(icon, color: Colors.white70, size: 22),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(title,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 15)),
            ),
          ),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < options.length; i++)
                  _SortOption(
                    label: options[i],
                    active: library.sortMode == mode &&
                        library.sortAscending == (i == 0),
                    onTap: () => library.setSort(mode, i == 0),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SortOption extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _SortOption({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  color:
                      active ? DisplaySettingsSheet._accent : Colors.white70,
                  fontWeight: active ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
            SizedBox(
              width: 22,
              child: active
                  ? const Icon(Icons.check,
                      size: 18, color: DisplaySettingsSheet._accent)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
MAXPLAYER_EOF

cat > 'lib/widgets/track_selection_sheet.dart' << 'MAXPLAYER_EOF'
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart' hide VideoTrack;

import '../state/media_player_state.dart';

/// Bottom sheet listing the current media's audio or subtitle tracks, with a
/// check on the active one. Opened from the player controls.
class TrackSelectionSheet extends StatelessWidget {
  final MediaPlayerState player;
  final bool isSubtitle;

  const TrackSelectionSheet({
    super.key,
    required this.player,
    required this.isSubtitle,
  });

  static const Color _accent = Color(0xFFA855F7);
  static const Color _surface = Color(0xFF1a1a24);

  static Future<void> show(
    BuildContext context,
    MediaPlayerState player, {
    required bool isSubtitle,
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: _surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) =>
          TrackSelectionSheet(player: player, isSubtitle: isSubtitle),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
            child: Text(
              isSubtitle ? 'Subtitles' : 'Audio track',
              style: const TextStyle(
                color: _accent,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Flexible(
            child: isSubtitle ? _subtitleList(context) : _audioList(context),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _audioList(BuildContext context) {
    // Dedupe by id - some containers list an entry twice.
    final tracks = <String, AudioTrack>{};
    for (final t in player.audioTracks) {
      if (t.id == 'no') continue;
      tracks[t.id] = t;
    }
    final list = tracks.values.toList();
    if (list.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Text('No audio tracks found',
            style: TextStyle(color: Colors.white38)),
      );
    }
    return ListView(
      shrinkWrap: true,
      children: [
        for (var i = 0; i < list.length; i++)
          _TrackTile(
            label: _audioLabel(list[i], i),
            detail: list[i].language,
            selected: player.currentAudioTrack?.id == list[i].id,
            onTap: () {
              player.selectAudioTrack(list[i]);
              Navigator.of(context).pop();
            },
          ),
      ],
    );
  }

  Widget _subtitleList(BuildContext context) {
    // "no" is the explicit OFF entry; dedupe the rest by id.
    final tracks = <String, SubtitleTrack>{};
    for (final t in player.subtitleTracks) {
      if (t.id == 'no') continue;
      tracks[t.id] = t;
    }
    final list = [SubtitleTrack.no(), ...tracks.values];
    return ListView(
      shrinkWrap: true,
      children: [
        for (var i = 0; i < list.length; i++)
          _TrackTile(
            label: _subtitleLabel(list[i], i),
            detail: list[i].language ?? list[i].codec,
            selected: player.currentSubtitleTrack?.id == list[i].id,
            onTap: () {
              player.selectSubtitleTrack(list[i]);
              Navigator.of(context).pop();
            },
          ),
      ],
    );
  }

  String _audioLabel(AudioTrack t, int index) {
    if (t.id == 'auto') return 'Auto';
    final title = t.title?.trim() ?? '';
    if (title.isNotEmpty) return title;
    return t.language?.toUpperCase() ?? 'Audio ${index + 1}';
  }

  String _subtitleLabel(SubtitleTrack t, int index) {
    if (t.id == 'no') return 'Off';
    if (t.id == 'auto') return 'Auto';
    final title = t.title?.trim() ?? '';
    if (title.isNotEmpty) return title;
    return t.language?.toUpperCase() ?? 'Subtitle $index';
  }
}

class _TrackTile extends StatelessWidget {
  final String label;
  final String? detail;
  final bool selected;
  final VoidCallback onTap;

  const _TrackTile({
    required this.label,
    required this.detail,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      onTap: onTap,
      leading: SizedBox(
        width: 24,
        child: selected
            ? const Icon(Icons.check,
                size: 18, color: TrackSelectionSheet._accent)
            : null,
      ),
      title: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: selected ? Colors.white : Colors.white70,
          fontSize: 15,
          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      subtitle: (detail != null && detail!.isNotEmpty)
          ? Text(detail!,
              style: const TextStyle(color: Colors.white38, fontSize: 12))
          : null,
    );
  }
}
MAXPLAYER_EOF

cat > 'lib/widgets/video_tile.dart' << 'MAXPLAYER_EOF'
import 'dart:io';
import 'package:flutter/material.dart';
import '../models/video_track.dart';
import '../utils/formatters.dart';

class VideoTile extends StatelessWidget {
  final VideoTrack track;
  final bool isFavorite;
  final VoidCallback onTap;
  final VoidCallback onFavorite;

  const VideoTile({
    super.key,
    required this.track,
    required this.isFavorite,
    required this.onTap,
    required this.onFavorite,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
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
                  if (track.thumbnailPath != null)
                    Image.file(
                      File(track.thumbnailPath!),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const _Placeholder(),
                    )
                  else
                    const _Placeholder(),
                  // Favourite toggle
                  Positioned(
                    top: 4,
                    right: 4,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: onFavorite,
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isFavorite ? Icons.favorite : Icons.favorite_border,
                          size: 15,
                          color: isFavorite
                              ? const Color(0xFFA855F7)
                              : Colors.white70,
                        ),
                      ),
                    ),
                  ),
                  // Duration pill
                  if (track.duration != null)
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
                          formatDuration(track.duration),
                          style: const TextStyle(
                              fontSize: 11, color: Colors.white),
                        ),
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
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    formatFileSize(track.sizeBytes),
                    style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.5)),
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

class _Placeholder extends StatelessWidget {
  const _Placeholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black45,
      child: const Center(
        child: Icon(Icons.movie_outlined, size: 32, color: Colors.white24),
      ),
    );
  }
}
MAXPLAYER_EOF

cat > 'lib/widgets/video_list_item.dart' << 'MAXPLAYER_EOF'
import 'dart:io';
import 'package:flutter/material.dart';
import '../models/video_track.dart';
import '../utils/formatters.dart';

/// List-mode row for the library (see "Display in list" in the settings
/// sheet): small thumbnail, title, size + duration, and a favourite toggle.
class VideoListItem extends StatelessWidget {
  final VideoTrack track;
  final bool isFavorite;
  final VoidCallback onTap;
  final VoidCallback onFavorite;

  const VideoListItem({
    super.key,
    required this.track,
    required this.isFavorite,
    required this.onTap,
    required this.onFavorite,
  });

  @override
  Widget build(BuildContext context) {
    final duration = formatDuration(track.duration);
    final size = formatFileSize(track.sizeBytes);
    final subtitle =
        duration == '--:--' ? size : '$duration${size.isEmpty ? '' : '  ·  $size'}';

    return ListTile(
      onTap: onTap,
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 96,
          height: 54,
          child: _Thumb(track: track),
        ),
      ),
      title: Text(
        track.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
            fontSize: 14, color: Colors.white, fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(fontSize: 12, color: Colors.white38),
      ),
      trailing: IconButton(
        icon: Icon(
          isFavorite ? Icons.favorite : Icons.favorite_border,
          size: 20,
          color: isFavorite ? const Color(0xFFA855F7) : Colors.white38,
        ),
        onPressed: onFavorite,
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  final VideoTrack track;
  const _Thumb({required this.track});

  @override
  Widget build(BuildContext context) {
    if (track.thumbnailPath != null) {
      return Image.file(
        File(track.thumbnailPath!),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const _Placeholder(),
      );
    }
    return const _Placeholder();
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF12121a),
      child: const Center(
        child: Icon(Icons.movie_outlined, size: 22, color: Colors.white24),
      ),
    );
  }
}
MAXPLAYER_EOF

cat > 'lib/widgets/player_controls_overlay.dart' << 'MAXPLAYER_EOF'
import 'package:flutter/material.dart' hide RepeatMode;
import '../models/video_track.dart' show RepeatMode;
import '../state/media_player_state.dart';
import 'progress_bar.dart';
import 'track_selection_sheet.dart';

/// Controls drawn on top of the video. Two slim rows are used instead of one
/// long row - the previous single-row layout needed ~540dp and overflowed
/// (black/yellow error stripes) on portrait phones.
///
/// This widget rebuilds itself via [AnimatedBuilder] on every player tick,
/// so the parent screen does NOT rebuild (which kept recreating the video
/// surface and caused fullscreen flicker).
class PlayerControlsOverlay extends StatelessWidget {
  final MediaPlayerState player;
  final bool isFullscreen;
  final VoidCallback onToggleFullscreen;
  final VoidCallback onToggleQueue;

  const PlayerControlsOverlay({
    super.key,
    required this.player,
    required this.isFullscreen,
    required this.onToggleFullscreen,
    required this.onToggleQueue,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: player,
      builder: (context, _) {
        return Container(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, Colors.black.withValues(alpha: 0.85)],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              VideoProgressBar(
                position: player.position,
                duration: player.duration,
                onSeek: player.seek,
              ),
              // Row 1: transport (shuffle - prev - play - next - repeat)
              Row(
                children: [
                  _iconBtn(
                    icon: player.isShuffled
                        ? Icons.shuffle_on_outlined
                        : Icons.shuffle,
                    active: player.isShuffled,
                    onTap: player.toggleShuffle,
                  ),
                  const Spacer(),
                  _iconBtn(icon: Icons.skip_previous, onTap: player.prevTrack),
                  _iconBtn(
                    icon: player.isPlaying
                        ? Icons.pause_circle_filled
                        : Icons.play_circle_filled,
                    size: 40,
                    onTap: player.togglePlay,
                  ),
                  _iconBtn(icon: Icons.skip_next, onTap: player.nextTrack),
                  const Spacer(),
                  _iconBtn(
                    icon: switch (player.repeatMode) {
                      RepeatMode.none => Icons.repeat,
                      RepeatMode.all => Icons.repeat_on_outlined,
                      RepeatMode.one => Icons.repeat_one_on_outlined,
                    },
                    active: player.repeatMode != RepeatMode.none,
                    onTap: player.toggleRepeat,
                  ),
                ],
              ),
              // Row 2: options (mute - speed - audio - subtitles | queue - fullscreen)
              Row(
                children: [
                  _iconBtn(
                    icon: player.isMuted || player.volume == 0
                        ? Icons.volume_off
                        : Icons.volume_up,
                    onTap: player.toggleMute,
                  ),
                  _speedMenu(),
                  _iconBtn(
                    icon: Icons.audiotrack_outlined,
                    // Highlight when the file actually offers multiple tracks.
                    active: player.audioTracks.length > 1,
                    onTap: () => TrackSelectionSheet.show(
                      context,
                      player,
                      isSubtitle: false,
                    ),
                  ),
                  _iconBtn(
                    icon: player.subtitlesActive
                        ? Icons.subtitles
                        : Icons.subtitles_outlined,
                    active: player.subtitlesActive,
                    onTap: () => TrackSelectionSheet.show(
                      context,
                      player,
                      isSubtitle: true,
                    ),
                  ),
                  const Spacer(),
                  _iconBtn(icon: Icons.queue_music, onTap: onToggleQueue),
                  _iconBtn(
                    icon: isFullscreen
                        ? Icons.fullscreen_exit
                        : Icons.fullscreen,
                    onTap: onToggleFullscreen,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _speedMenu() {
    return PopupMenuButton<double>(
      initialValue: player.playbackRate,
      color: const Color(0xFF1a1a24),
      onSelected: player.setPlaybackRate,
      itemBuilder: (context) => [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
          .map((r) => PopupMenuItem(
                value: r,
                child: Text('${r}x',
                    style: const TextStyle(color: Colors.white)),
              ))
          .toList(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        child: Text('${player.playbackRate}x',
            style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ),
    );
  }

  Widget _iconBtn({
    required IconData icon,
    required VoidCallback onTap,
    bool active = false,
    double size = 24,
  }) {
    return IconButton(
      icon: Icon(icon,
          size: size, color: active ? const Color(0xFFA855F7) : Colors.white),
      onPressed: onTap,
    );
  }
}
MAXPLAYER_EOF

cat > 'lib/screens/library_screen.dart' << 'MAXPLAYER_EOF'
import 'package:flutter/material.dart';
import '../models/video_track.dart';
import '../state/media_player_state.dart';
import '../state/video_library_state.dart';
import '../widgets/display_settings_sheet.dart';
import '../widgets/video_list_item.dart';
import '../widgets/video_tile.dart';
import 'player_screen.dart';

class LibraryScreen extends StatefulWidget {
  final VideoLibraryState library;
  final MediaPlayerState player;

  const LibraryScreen({super.key, required this.library, required this.player});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  @override
  void initState() {
    super.initState();
    widget.library.addListener(_onChange);
    // Automatically ask for storage permission and scan the whole device
    // the first time this screen opens.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.library.folderName == null && !widget.library.isScanning) {
        widget.library.scanAllStorage();
      }
    });
  }

  @override
  void dispose() {
    widget.library.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() => setState(() {});

  void _playVideo(VideoTrack track) {
    final lib = widget.library;
    if (lib.playbackAction == PlaybackAction.single) {
      // Queue only the tapped file.
      widget.player.setPlaylistAndPlay([track], 0);
    } else {
      // Queue every visible video, starting at the tapped one.
      final all = lib.videos;
      final idx = all.indexWhere((v) => v.id == track.id);
      widget.player.setPlaylistAndPlay(all, idx >= 0 ? idx : 0);
    }
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PlayerScreen(player: widget.player)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lib = widget.library;
    return Scaffold(
      backgroundColor: const Color(0xFF0a0a0f),
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: 0.3),
        elevation: 0,
        title: ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [Color(0xFFA78BFA), Color(0xFF8B5CF6), Color(0xFF22D3EE)],
          ).createShader(bounds),
          child: const Text('Max Player',
              style:
                  TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        ),
        actions: [
          if (lib.folderName != null)
            IconButton(
              tooltip: 'Rescan',
              icon: const Icon(Icons.refresh),
              onPressed: lib.rescan,
            ),
          IconButton(
            tooltip: 'Display settings',
            icon: const Icon(Icons.tune),
            onPressed: () => DisplaySettingsSheet.show(context, lib),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              onChanged: lib.setSearchQuery,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search ${lib.allVideosCount} videos...',
                hintStyle: const TextStyle(color: Colors.white38),
                prefixIcon: const Icon(Icons.search, color: Colors.white38),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.05),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          if (lib.isScanning)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(
                children: [
                  LinearProgressIndicator(
                    value: lib.scanProgress.total > 0
                        ? lib.scanProgress.processed / lib.scanProgress.total
                        : null,
                    color: const Color(0xFFA855F7),
                    backgroundColor: Colors.white10,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Scanning ${lib.scanProgress.processed}/${lib.scanProgress.total}',
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                  const SizedBox(height: 6),
                ],
              ),
            ),
          Expanded(child: _buildBody(lib)),
        ],
      ),
    );
  }

  Widget _buildBody(VideoLibraryState lib) {
    // Single evaluation - the getter filters+sorts, so compute once per build.
    final groups = lib.groups;
    final visibleCount =
        groups.fold<int>(0, (sum, g) => sum + g.videos.length);

    if (visibleCount == 0) {
      return _EmptyState(
        isScanning: lib.isScanning,
        permissionDenied: lib.permissionDenied,
        favoritesOnly: lib.favoritesOnly,
        onGrantAccess: lib.scanAllStorage,
      );
    }

    return CustomScrollView(
      slivers: [
        for (final group in groups) ...[
          if (lib.groupMode != GroupMode.none)
            SliverToBoxAdapter(
              child: _GroupHeader(
                title: group.title,
                count: group.videos.length,
              ),
            ),
          if (lib.viewMode == ViewMode.grid)
            SliverPadding(
              padding: const EdgeInsets.all(12),
              sliver: SliverGrid(
                gridDelegate:
                    const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 220,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.82,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, i) {
                    final track = group.videos[i];
                    return VideoTile(
                      track: track,
                      isFavorite: lib.isFavorite(track),
                      onTap: () => _playVideo(track),
                      onFavorite: () => lib.toggleFavorite(track),
                    );
                  },
                  childCount: group.videos.length,
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) {
                    final track = group.videos[i];
                    return VideoListItem(
                      track: track,
                      isFavorite: lib.isFavorite(track),
                      onTap: () => _playVideo(track),
                      onFavorite: () => lib.toggleFavorite(track),
                    );
                  },
                  childCount: group.videos.length,
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _GroupHeader extends StatelessWidget {
  final String title;
  final int count;

  const _GroupHeader({required this.title, required this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
      child: Text(
        '$title  ·  $count',
        style: const TextStyle(
          color: Colors.white54,
          fontSize: 13,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool isScanning;
  final bool permissionDenied;
  final bool favoritesOnly;
  final VoidCallback onGrantAccess;

  const _EmptyState({
    required this.isScanning,
    required this.permissionDenied,
    required this.favoritesOnly,
    required this.onGrantAccess,
  });

  @override
  Widget build(BuildContext context) {
    if (isScanning) {
      // Progress bar above already shows scan status - avoid a duplicate message.
      return const SizedBox.shrink();
    }

    // Library loaded, but the favourites filter hides everything.
    if (favoritesOnly && !permissionDenied) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.favorite_border, size: 48, color: Colors.white24),
            SizedBox(height: 12),
            Text(
              'No favourites yet.\nTap the heart on any video to add it here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54, fontSize: 16),
            ),
          ],
        ),
      );
    }

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.video_library_outlined,
              size: 48, color: Colors.white24),
          const SizedBox(height: 12),
          Text(
            permissionDenied
                ? 'Max Player needs storage access to find your videos'
                : 'No videos yet',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white54, fontSize: 16),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onGrantAccess,
            icon: const Icon(Icons.folder_open),
            label: Text(permissionDenied ? 'Try again' : 'Scan device'),
          ),
        ],
      ),
    );
  }
}
MAXPLAYER_EOF

cat > 'lib/screens/player_screen.dart' << 'MAXPLAYER_EOF'
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../state/media_player_state.dart';
import '../widgets/player_controls_overlay.dart';
import '../widgets/playlist_panel.dart';

class PlayerScreen extends StatefulWidget {
  final MediaPlayerState player;

  const PlayerScreen({super.key, required this.player});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  // Shared, app-lifetime controller owned by MediaPlayerState (this media_kit
  // version has no VideoController.dispose, so per-visit controllers leaked
  // and glitched the player).
  late final VideoController _controller = widget.player.videoController;
  bool _controlsVisible = true;
  bool _isFullscreen = false;
  bool _showQueue = false;

  // NOTE: no addListener/setState here. Rebuilding the whole screen on
  // every position tick re-created the video surface each time and made
  // fullscreen toggling flicker. Ticking parts (overlay, spinner, queue,
  // title) listen to the player themselves via AnimatedBuilder.

  @override
  void dispose() {
    if (_isFullscreen) _exitFullscreen();
    super.dispose();
  }

  void _toggleFullscreen() {
    setState(() => _isFullscreen = !_isFullscreen);
    if (_isFullscreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      _exitFullscreen();
    }
  }

  void _exitFullscreen() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
  }

  @override
  Widget build(BuildContext context) {
    final player = widget.player;

    return PopScope(
      canPop: !_isFullscreen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _isFullscreen) _toggleFullscreen();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: _isFullscreen
            ? null
            : AppBar(
                backgroundColor: Colors.black,
                title: AnimatedBuilder(
                  animation: player,
                  builder: (context, _) => Text(
                    player.currentTrack?.title ?? 'Max Player',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
        body: SafeArea(
          top: !_isFullscreen,
          // Lift controls above the gesture/nav bar in landscape fullscreen.
          bottom: true,
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () =>
                      setState(() => _controlsVisible = !_controlsVisible),
                  onDoubleTap: _toggleFullscreen,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Center(
                        child: player.currentTrack != null
                            ? RepaintBoundary(
                                child: Video(
                                  controller: _controller,
                                  controls: NoVideoControls,
                                ),
                              )
                            : const Text('No video loaded',
                                style: TextStyle(color: Colors.white38)),
                      ),
                      // Buffering spinner - follows the player stream only.
                      Positioned.fill(
                        child: AnimatedBuilder(
                          animation: player,
                          builder: (context, _) => player.isLoading
                              ? const Center(
                                  child: CircularProgressIndicator(
                                      color: Color(0xFFA855F7)),
                                )
                              : const SizedBox.shrink(),
                        ),
                      ),
                      if (_controlsVisible)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: PlayerControlsOverlay(
                            player: player,
                            isFullscreen: _isFullscreen,
                            onToggleFullscreen: _toggleFullscreen,
                            onToggleQueue: () =>
                                setState(() => _showQueue = !_showQueue),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (_showQueue && !_isFullscreen)
                SizedBox(
                  width: 280,
                  child: Container(
                    color: const Color(0xFF12121a),
                    child: AnimatedBuilder(
                      animation: player,
                      builder: (context, _) => PlaylistPanel(
                        playlist: player.playlist,
                        currentIndex: player.currentIndex,
                        onPlay: player.playTrack,
                        onRemove: player.removeFromPlaylist,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
MAXPLAYER_EOF

cat > 'test/widget_test.dart' << 'MAXPLAYER_EOF'
import 'package:flutter_test/flutter_test.dart';

import 'package:maxplayer/models/video_track.dart';
import 'package:maxplayer/state/video_library_state.dart';
import 'package:maxplayer/utils/formatters.dart';

// Pure unit tests - no platform channels involved. (NativeBridge calls in
// VideoLibraryState are guarded and return defaults when no channel exists,
// so these tests run fine in the Dart VM.)
//
// A full-app pump test was removed: it constructed the real media_kit Player
// and fired a storage-permission request, both of which need a device.
// Re-add a widget test once the states can be injected/faked.

VideoTrack _track(
  String name, {
  Duration? duration,
  int? size,
  int? modified,
  String dir = '/storage/emulated/0/Movies',
}) {
  final path = '$dir/$name.mp4';
  return VideoTrack(
    id: path,
    title: name,
    path: path,
    duration: duration,
    sizeBytes: size,
    lastModifiedMs: modified,
  );
}

VideoLibraryState _libraryWith(List<VideoTrack> videos) {
  final lib = VideoLibraryState();
  lib.debugSetVideos(videos);
  addTearDown(lib.dispose);
  return lib;
}

void main() {
  group('formatters', () {
    test('formats file sizes', () {
      expect(formatFileSize(null), '');
      expect(formatFileSize(512), '512 B');
      expect(formatFileSize(2048), '2.0 KB');
      expect(formatFileSize(5 * 1024 * 1024), '5.0 MB');
      expect(formatFileSize(3 * 1024 * 1024 * 1024), '3.00 GB');
    });

    test('formats durations', () {
      expect(formatDuration(null), '--:--');
      expect(formatDuration(const Duration(seconds: 65)), '1:05');
      expect(formatDuration(const Duration(hours: 1, minutes: 2, seconds: 3)),
          '1:02:03');
    });

    test('detects video extensions case-insensitively', () {
      expect(isVideoFile('clip.MKV'), isTrue);
      expect(isVideoFile('movie.mp4'), isTrue);
      expect(isVideoFile('notes.txt'), isFalse);
    });
  });

  group('library sorting', () {
    final videos = [
      _track('banana', size: 300, modified: 100, duration: const Duration(minutes: 3)),
      _track('apple', size: 100, modified: 300, duration: const Duration(minutes: 1)),
      _track('cherry', size: 200, modified: 200),
    ];

    test('name A->Z and Z->A', () {
      final lib = _libraryWith(videos);
      lib.setSort(SortMode.name, true);
      expect(lib.videos.map((v) => v.title), ['apple', 'banana', 'cherry']);
      lib.setSort(SortMode.name, false);
      expect(lib.videos.map((v) => v.title), ['cherry', 'banana', 'apple']);
    });

    test('length shortest first, unknown duration sinks to the end', () {
      final lib = _libraryWith(videos);
      lib.setSort(SortMode.length, true);
      expect(lib.videos.map((v) => v.title), ['apple', 'banana', 'cherry']);
      // longest first, but the unknown one still ends up last
      lib.setSort(SortMode.length, false);
      expect(lib.videos.map((v) => v.title), ['banana', 'apple', 'cherry']);
    });

    test('recently added: newest first', () {
      final lib = _libraryWith(videos);
      lib.setSort(SortMode.date, false);
      expect(lib.videos.map((v) => v.title), ['apple', 'cherry', 'banana']);
    });

    test('size smallest first', () {
      final lib = _libraryWith(videos);
      lib.setSort(SortMode.size, true);
      expect(lib.videos.map((v) => v.title), ['apple', 'cherry', 'banana']);
    });
  });

  group('library filtering & favourites', () {
    final videos = [
      _track('cat video'),
      _track('dog video'),
      _track('cat fails'),
    ];

    test('search filters by title', () {
      final lib = _libraryWith(videos);
      lib.setSearchQuery('cat');
      expect(lib.videos.length, 2);
      lib.setSearchQuery('dog');
      expect(lib.videos.map((v) => v.title), ['dog video']);
    });

    test('favourites-only shows only hearted videos', () {
      final lib = _libraryWith(videos);
      lib.toggleFavorite(videos[1]);
      expect(lib.isFavorite(videos[1]), isTrue);
      lib.setFavoritesOnly(true);
      expect(lib.videos.map((v) => v.title), ['dog video']);
      lib.toggleFavorite(videos[1]);
      expect(lib.videos, isEmpty);
    });
  });

  group('grouping', () {
    test('group by name buckets titles by first letter', () {
      final lib = _libraryWith([
        _track('Banana'),
        _track('apple'),
        _track('avocado'),
        _track('123 intro'),
      ]);
      lib.setGroupMode(GroupMode.name);
      final groups = lib.groups;
      expect(groups.map((g) => g.title), ['1', 'A', 'B']);
      expect(groups[1].videos.length, 2); // apple + avocado under A
    });

    test('group by folder uses the parent directory name', () {
      final lib = _libraryWith([
        _track('one', dir: '/storage/emulated/0/Movies'),
        _track('two', dir: '/storage/emulated/0/Download'),
      ]);
      lib.setGroupMode(GroupMode.folder);
      expect(lib.groups.map((g) => g.title), ['Download', 'Movies']);
    });

    test('no grouping yields a single unnamed group', () {
      final lib = _libraryWith([_track('x')]);
      lib.setGroupMode(GroupMode.none);
      expect(lib.groups.length, 1);
      expect(lib.groups.single.title, '');
    });
  });
}
MAXPLAYER_EOF

echo "Update applied. Now run:"
echo "  git add -A && git commit -m \"Fix player overflow/fullscreen glitches, add audio+subtitle track selection\" && git push
