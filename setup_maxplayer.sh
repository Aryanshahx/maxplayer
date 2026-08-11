#!/usr/bin/env bash
# Run this from inside your Flutter project root (e.g. ~/IdeaProjects/maxplayer).
# It creates/overwrites pubspec.yaml, lib/, test/widget_test.dart, and drops the
# Android manifest snippet + codemagic.yaml alongside your project.
set -e

mkdir -p lib/models lib/state lib/screens lib/widgets lib/utils test

cat > 'pubspec.yaml' << 'MAXPLAYER_EOF'
name: maxplayer
description: "Max Player - a local video library & player."
publish_to: 'none'
version: 1.0.0+1

environment:
  sdk: '>=3.3.0 <4.0.0'

dependencies:
  flutter:
    sdk: flutter
  cupertino_icons: ^1.0.8

  # Playback engine (libmpv/ffmpeg backed) - handles mp4/webm/mkv/avi/wmv/flv/ts/vob/etc
  # which ExoPlayer (video_player plugin) does not reliably support.
  media_kit: ^1.1.11
  media_kit_video: ^1.2.5
  media_kit_libs_android_video: ^1.3.6

  # Folder scanning via a manually-entered path + broad storage permission,
  # instead of file_picker's native SAF dialog (file_picker's Android side has
  # proven incompatible with current AGP/Kotlin toolchains as of this writing).
  permission_handler: ^11.3.1

  path: ^1.9.0
  intl: ^0.19.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^4.0.0

flutter:
  uses-material-design: true
MAXPLAYER_EOF

cat > 'codemagic.yaml' << 'MAXPLAYER_EOF'
workflows:
  android-apk:
    name: Max Player - Android APK
    max_build_duration: 60
    environment:
      flutter: stable
      # No android_signing block yet - this ships a debug-signed APK, which is
      # fine for sideloading and testing. Add an android_signing entry here
      # later once you've created a keystore and registered it in
      # Codemagic > Team settings > Code signing identities, for a real release build.
    scripts:
      - name: Clean build (avoid stale plugin registration after dependency upgrades)
        script: flutter clean
      - name: Get Flutter packages
        script: flutter pub get
      - name: Build APK (release)
        script: flutter build apk --release
    artifacts:
      - build/app/outputs/flutter-apk/*.apk
    publishing:
      email:
        recipients:
          - your-email@example.com
        notify:
          success: true
          failure: true
MAXPLAYER_EOF

cat > 'android_manifest_snippet.xml' << 'MAXPLAYER_EOF'
<!--
  Add these INSIDE the <manifest> tag of android/app/src/main/AndroidManifest.xml,
  above the <application> tag. If your manifest's root <manifest> tag doesn't
  already declare xmlns:tools="http://schemas.android.com/tools", add that
  attribute too (needed for the tools:ignore line below).
-->

<!-- Android 13+ granular media permission -->
<uses-permission android:name="android.permission.READ_MEDIA_VIDEO" />

<!-- Android 12 and below -->
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"
    android:maxSdkVersion="32" />

<!--
  Required for scanning arbitrary user-entered folder paths (not just
  MediaStore-indexed locations). This is the "All files access" permission -
  the user grants it manually in Settings > Apps > Max Player > Permissions,
  which permission_handler's request() call will deep-link to.
  Fine for a personal sideloaded APK; would need Play Store justification
  for a public release.
-->
<uses-permission android:name="android.permission.MANAGE_EXTERNAL_STORAGE"
    tools:ignore="ScopedStorage" />

<!--
  NOTE: arbitrary folder scanning (outside MediaStore-indexed locations)
  requires MANAGE_EXTERNAL_STORAGE below, since it's not going through a
  media-store-aware picker.
-->

<!-- Also set the visible app name (inside <application ...>): -->
<!-- android:label="Max Player" -->
MAXPLAYER_EOF

cat > 'test/widget_test.dart' << 'MAXPLAYER_EOF'
import 'package:flutter_test/flutter_test.dart';

import 'package:maxplayer/main.dart';

void main() {
  testWidgets('Max Player launches to the library screen', (WidgetTester tester) async {
    await tester.pumpWidget(const MaxPlayerApp());

    // The library screen's app bar title should be visible on launch.
    expect(find.text('Max Player'), findsOneWidget);
  });
}
MAXPLAYER_EOF

cat > 'lib/main.dart' << 'MAXPLAYER_EOF'
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'state/media_player_state.dart';
import 'state/video_library_state.dart';
import 'screens/library_screen.dart';

void main() {
  // Must be called before any media_kit Player is created.
  MediaKit.ensureInitialized();
  runApp(const MaxPlayerApp());
}

class MaxPlayerApp extends StatefulWidget {
  const MaxPlayerApp({super.key});

  @override
  State<MaxPlayerApp> createState() => _MaxPlayerAppState();
}

class _MaxPlayerAppState extends State<MaxPlayerApp> {
  final library = VideoLibraryState();
  final player = MediaPlayerState();

  @override
  void dispose() {
    player.dispose();
    library.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Max Player',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0a0a0f),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFA855F7),
          brightness: Brightness.dark,
        ),
      ),
      home: LibraryScreen(library: library, player: player),
    );
  }
}
MAXPLAYER_EOF

cat > 'lib/models/video_track.dart' << 'MAXPLAYER_EOF'
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

enum SortMode { name, date, size }
MAXPLAYER_EOF

cat > 'lib/utils/formatters.dart' << 'MAXPLAYER_EOF'
String formatFileSize(int? bytes) {
  if (bytes == null) return '';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

String formatDuration(Duration? d) {
  if (d == null) return '--:--';
  final totalSeconds = d.inSeconds;
  final h = totalSeconds ~/ 3600;
  final m = (totalSeconds % 3600) ~/ 60;
  final s = totalSeconds % 60;
  if (h > 0) {
    return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
  return '$m:${s.toString().padLeft(2, '0')}';
}

const List<String> videoExtensions = [
  '.mp4', '.webm', '.mkv', '.avi', '.mov', '.wmv', '.flv', '.m4v',
  '.3gp', '.ogv', '.ts', '.mts', '.m2ts', '.vob',
];

bool isVideoFile(String name) {
  final lower = name.toLowerCase();
  return videoExtensions.any((ext) => lower.endsWith(ext));
}
MAXPLAYER_EOF

cat > 'lib/state/video_library_state.dart' << 'MAXPLAYER_EOF'
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
MAXPLAYER_EOF

cat > 'lib/state/media_player_state.dart' << 'MAXPLAYER_EOF'
import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart' hide VideoTrack;

import '../models/video_track.dart';

/// Mirrors the web app's useMediaPlayer hook, backed by media_kit's Player.
class MediaPlayerState extends ChangeNotifier {
  final Player player = Player();

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

cat > 'lib/widgets/video_tile.dart' << 'MAXPLAYER_EOF'
import 'dart:io';
import 'package:flutter/material.dart';
import '../models/video_track.dart';
import '../utils/formatters.dart';

class VideoTile extends StatelessWidget {
  final VideoTrack track;
  final VoidCallback onTap;

  const VideoTile({super.key, required this.track, required this.onTap});

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
                    Image.file(File(track.thumbnailPath!), fit: BoxFit.cover)
                  else
                    Container(
                      color: Colors.black45,
                      child: const Icon(Icons.movie_outlined, size: 32, color: Colors.white24),
                    ),
                  if (track.duration != null)
                    Positioned(
                      right: 6,
                      bottom: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          formatDuration(track.duration),
                          style: const TextStyle(fontSize: 11, color: Colors.white),
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
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    formatFileSize(track.sizeBytes),
                    style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.5)),
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
MAXPLAYER_EOF

cat > 'lib/widgets/progress_bar.dart' << 'MAXPLAYER_EOF'
import 'package:flutter/material.dart';
import '../utils/formatters.dart';

class VideoProgressBar extends StatefulWidget {
  final Duration position;
  final Duration duration;
  final ValueChanged<Duration> onSeek;

  const VideoProgressBar({
    super.key,
    required this.position,
    required this.duration,
    required this.onSeek,
  });

  @override
  State<VideoProgressBar> createState() => _VideoProgressBarState();
}

class _VideoProgressBarState extends State<VideoProgressBar> {
  double? _dragValue; // 0..1 while user is dragging

  @override
  Widget build(BuildContext context) {
    final totalMs = widget.duration.inMilliseconds.clamp(1, 1 << 62);
    final value = _dragValue ?? (widget.position.inMilliseconds / totalMs).clamp(0.0, 1.0);

    return Row(
      children: [
        Text(formatDuration(widget.position), style: _timeStyle),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              activeTrackColor: const Color(0xFFA855F7),
              inactiveTrackColor: Colors.white.withValues(alpha: 0.15),
              thumbColor: const Color(0xFFA855F7),
            ),
            child: Slider(
              value: value,
              onChanged: (v) => setState(() => _dragValue = v),
              onChangeEnd: (v) {
                widget.onSeek(Duration(milliseconds: (v * totalMs).round()));
                setState(() => _dragValue = null);
              },
            ),
          ),
        ),
        Text(formatDuration(widget.duration), style: _timeStyle),
      ],
    );
  }

  static const _timeStyle = TextStyle(fontSize: 12, color: Colors.white70);
}
MAXPLAYER_EOF

cat > 'lib/widgets/playlist_panel.dart' << 'MAXPLAYER_EOF'
import 'package:flutter/material.dart';
import '../models/video_track.dart';
import '../utils/formatters.dart';

class PlaylistPanel extends StatelessWidget {
  final List<VideoTrack> playlist;
  final int currentIndex;
  final ValueChanged<int> onPlay;
  final ValueChanged<int> onRemove;

  const PlaylistPanel({
    super.key,
    required this.playlist,
    required this.currentIndex,
    required this.onPlay,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    if (playlist.isEmpty) {
      return const Center(
        child: Text('Queue is empty', style: TextStyle(color: Colors.white38)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: playlist.length,
      itemBuilder: (context, i) {
        final track = playlist[i];
        final active = i == currentIndex;
        return ListTile(
          dense: true,
          onTap: () => onPlay(i),
          tileColor: active ? Colors.white.withValues(alpha: 0.08) : null,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          leading: Icon(
            active ? Icons.equalizer : Icons.play_arrow,
            size: 18,
            color: active ? const Color(0xFFA855F7) : Colors.white38,
          ),
          title: Text(
            track.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              color: active ? Colors.white : Colors.white70,
              fontWeight: active ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
          subtitle: Text(formatFileSize(track.sizeBytes),
              style: const TextStyle(fontSize: 11, color: Colors.white38)),
          trailing: IconButton(
            icon: const Icon(Icons.close, size: 16, color: Colors.white38),
            onPressed: () => onRemove(i),
          ),
        );
      },
    );
  }
}
MAXPLAYER_EOF

cat > 'lib/widgets/player_controls_overlay.dart' << 'MAXPLAYER_EOF'
import 'package:flutter/material.dart' hide RepeatMode;
import '../models/video_track.dart';
import '../state/media_player_state.dart';
import 'progress_bar.dart';

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
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
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
          Row(
            children: [
              _iconBtn(
                icon: player.isShuffled ? Icons.shuffle_on_outlined : Icons.shuffle,
                active: player.isShuffled,
                onTap: player.toggleShuffle,
              ),
              _iconBtn(icon: Icons.skip_previous, onTap: player.prevTrack),
              _iconBtn(
                icon: player.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                size: 40,
                onTap: player.togglePlay,
              ),
              _iconBtn(icon: Icons.skip_next, onTap: player.nextTrack),
              _iconBtn(
                icon: switch (player.repeatMode) {
                  RepeatMode.none => Icons.repeat,
                  RepeatMode.all => Icons.repeat_on_outlined,
                  RepeatMode.one => Icons.repeat_one_on_outlined,
                },
                active: player.repeatMode != RepeatMode.none,
                onTap: player.toggleRepeat,
              ),
              const Spacer(),
              _iconBtn(
                icon: player.isMuted || player.volume == 0 ? Icons.volume_off : Icons.volume_up,
                onTap: player.toggleMute,
              ),
              SizedBox(
                width: 70,
                child: Slider(
                  value: player.isMuted ? 0 : player.volume,
                  onChanged: player.setVolume,
                  activeColor: Colors.white70,
                  inactiveColor: Colors.white24,
                ),
              ),
              PopupMenuButton<double>(
                initialValue: player.playbackRate,
                color: const Color(0xFF1a1a24),
                onSelected: player.setPlaybackRate,
                itemBuilder: (context) => [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
                    .map((r) => PopupMenuItem(
                          value: r,
                          child: Text('${r}x', style: const TextStyle(color: Colors.white)),
                        ))
                    .toList(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text('${player.playbackRate}x',
                      style: const TextStyle(color: Colors.white70, fontSize: 12)),
                ),
              ),
              _iconBtn(icon: Icons.queue_music, onTap: onToggleQueue),
              _iconBtn(
                icon: isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                onTap: onToggleFullscreen,
              ),
            ],
          ),
        ],
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
      icon: Icon(icon, size: size, color: active ? const Color(0xFFA855F7) : Colors.white),
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
    // the first time this screen opens - no folder picker needed.
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
    final all = widget.library.videos;
    final idx = all.indexWhere((v) => v.id == track.id);
    widget.player.setPlaylistAndPlay(all, idx >= 0 ? idx : 0);
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PlayerScreen(player: widget.player)),
    );
  }

  Future<void> _showFolderDialog() async {
    final controller = TextEditingController(
      text: VideoLibraryState.suggestedFolders.first,
    );
    final path = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a24),
        title: const Text('Scan a folder', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Folder path',
                labelStyle: TextStyle(color: Colors.white54),
              ),
            ),
            const SizedBox(height: 12),
            const Text('Quick picks:', style: TextStyle(color: Colors.white38, fontSize: 12)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: VideoLibraryState.suggestedFolders.map((folder) {
                return ActionChip(
                  label: Text(folder, style: const TextStyle(fontSize: 11)),
                  onPressed: () => controller.text = folder,
                  backgroundColor: Colors.white.withValues(alpha: 0.08),
                  labelStyle: const TextStyle(color: Colors.white70),
                );
              }).toList(),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Scan'),
          ),
        ],
      ),
    );
    if (path != null && path.isNotEmpty) {
      await widget.library.scanFolder(path);
    }
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
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        ),
        actions: [
          IconButton(
            tooltip: 'Scan a specific folder instead',
            icon: const Icon(Icons.folder_open),
            onPressed: _showFolderDialog,
          ),
          if (lib.folderName != null)
            IconButton(
              tooltip: 'Rescan',
              icon: const Icon(Icons.refresh),
              onPressed: lib.rescan,
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
          if (lib.permissionError != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Container(
                padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                ),
                child: Text(
                  lib.permissionError!,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12),
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
          Expanded(
            child: lib.videos.isEmpty
                ? _EmptyState(
                    isScanning: lib.isScanning,
                    onGrantAccess: () => lib.scanAllStorage(),
                    onPickFolder: _showFolderDialog,
                  )
                : GridView.builder(
                    padding: const EdgeInsets.all(12),
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 220,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.82,
                    ),
                    itemCount: lib.videos.length,
                    itemBuilder: (context, i) {
                      final track = lib.videos[i];
                      return VideoTile(track: track, onTap: () => _playVideo(track));
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool isScanning;
  final VoidCallback onGrantAccess;
  final VoidCallback onPickFolder;

  const _EmptyState({
    required this.isScanning,
    required this.onGrantAccess,
    required this.onPickFolder,
  });

  @override
  Widget build(BuildContext context) {
    if (isScanning) {
      // Auto-scan is already in progress (shown via the progress bar above) -
      // no need for a duplicate empty-state message.
      return const SizedBox.shrink();
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.video_library_outlined, size: 48, color: Colors.white24),
          const SizedBox(height: 12),
          const Text('No videos yet', style: TextStyle(color: Colors.white54, fontSize: 16)),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onGrantAccess,
            icon: const Icon(Icons.folder_open),
            label: const Text('Grant access & scan device'),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: onPickFolder,
            icon: const Icon(Icons.create_new_folder_outlined, size: 18),
            label: const Text('Or scan a specific folder'),
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
  late final VideoController _controller;
  bool _controlsVisible = true;
  bool _isFullscreen = false;
  bool _showQueue = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoController(widget.player.player);
    widget.player.addListener(_onChange);
  }

  @override
  void dispose() {
    widget.player.removeListener(_onChange);
    if (_isFullscreen) _exitFullscreen();
    super.dispose();
  }

  void _onChange() => setState(() {});

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
                title: Text(player.currentTrack?.title ?? 'Max Player',
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
        body: SafeArea(
          top: !_isFullscreen,
          bottom: false,
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _controlsVisible = !_controlsVisible),
                  onDoubleTap: _toggleFullscreen,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Center(
                        child: player.currentTrack != null
                            ? Video(controller: _controller, controls: NoVideoControls)
                            : const Text('No video loaded', style: TextStyle(color: Colors.white38)),
                      ),
                      if (player.isLoading)
                        const Center(child: CircularProgressIndicator(color: Color(0xFFA855F7))),
                      if (_controlsVisible)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: PlayerControlsOverlay(
                            player: player,
                            isFullscreen: _isFullscreen,
                            onToggleFullscreen: _toggleFullscreen,
                            onToggleQueue: () => setState(() => _showQueue = !_showQueue),
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
                    child: PlaylistPanel(
                      playlist: player.playlist,
                      currentIndex: player.currentIndex,
                      onPlay: player.playTrack,
                      onRemove: player.removeFromPlaylist,
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

echo "Done."
