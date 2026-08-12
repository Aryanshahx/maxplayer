import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart' hide VideoTrack;
import 'package:path/path.dart' as p;

import 'models/video_track.dart';
import 'screens/library_screen.dart';
import 'screens/player_screen.dart';
import 'services/native_bridge.dart';
import 'state/media_player_state.dart';
import 'state/theme_state.dart';
import 'state/video_library_state.dart';

// Global keys so a native "Open with" callback can navigate + snackbar from
// anywhere, without a BuildContext of its own.
final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<ScaffoldMessengerState> _messengerKey =
    GlobalKey<ScaffoldMessengerState>();

void main() {
  // Must be called before any media_kit Player is created.
  MediaKit.ensureInitialized();
  // Follow the phone's own rotation everywhere; the player's lock button
  // temporarily restricts it (and restores on exit).
  SystemChrome.setPreferredOrientations(DeviceOrientation.values);
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
  void initState() {
    super.initState();
    // App-wide accent color (persisted).
    themeState.load();
    // "Open with Max Player" from other apps: warm delivery ...
    NativeBridge.configureCallbacks(
      onOpenVideo: _openExternalVideo,
      onOpenVideoFailed: _externalOpenFailed,
    );
    // ... and the cold-start case (app launched BY a VIEW intent).
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final initial = await NativeBridge.getInitialOpenVideo();
      final path = initial['path'];
      final failed = initial['failed'];
      if (path != null) {
        _openExternalVideo(path);
      } else if (failed != null) {
        _externalOpenFailed(failed);
      }
    });
  }

  /// Plays a video that another app sent us. Local files arrive as real
  /// filesystem paths (resolved natively); http/rtsp-style links are treated
  /// as network streams and handed to libmpv directly.
  Future<void> _openExternalVideo(String path) async {
    const streamSchemes = {'http', 'https', 'rtsp', 'rtmp', 'mms'};
    final uri = Uri.tryParse(path);
    if (uri != null && streamSchemes.contains(uri.scheme.toLowerCase())) {
      final title =
          uri.pathSegments.isNotEmpty && uri.pathSegments.last.isNotEmpty
              ? Uri.decodeComponent(uri.pathSegments.last)
              : uri.host;
      await player.playStream(path, title);
      _navigateToPlayer();
      return;
    }
    try {
      await File(path).stat();
    } catch (_) {
      _externalOpenFailed(path);
      return;
    }
    final meta = await NativeBridge.fetchMetadata(path);
    final track = VideoTrack(
      id: path,
      title: p.basenameWithoutExtension(path),
      path: path,
      thumbnailPath: meta.thumbnailPath,
      duration: meta.duration,
      width: meta.width,
      height: meta.height,
    );
    await player.setPlaylistAndPlay([track], 0);
    _navigateToPlayer();
  }

  /// Jump straight into the player, replacing an already-open one.
  void _navigateToPlayer() {
    final nav = _navigatorKey.currentState;
    if (nav == null) return;
    nav.popUntil((route) => route.isFirst);
    nav.push(MaterialPageRoute(builder: (_) => PlayerScreen(player: player)));
  }

  void _externalOpenFailed(String target) {
    _messengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text("Can't open '${p.basename(target)}' - "
            'the file may be unavailable or storage access is off'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  void dispose() {
    player.dispose();
    library.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild the whole app when the accent color changes.
    return AnimatedBuilder(
      animation: themeState,
      builder: (context, _) {
        return MaterialApp(
          navigatorKey: _navigatorKey,
          scaffoldMessengerKey: _messengerKey,
          title: 'Max Player',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            scaffoldBackgroundColor: const Color(0xFF0a0a0f),
            colorScheme: ColorScheme.fromSeed(
              seedColor: themeState.accent,
              brightness: Brightness.dark,
            ),
          ),
          home: LibraryScreen(library: library, player: player),
        );
      },
    );
  }
}
