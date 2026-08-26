import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart' hide VideoTrack;
import 'package:path/path.dart' as p;

import 'models/video_track.dart';
import 'screens/library_screen.dart';
import 'screens/player_screen.dart';
import 'services/native_bridge.dart';
import 'services/notification_service.dart';
import 'services/resume_sync_service.dart';
import 'state/media_player_state.dart';
import 'state/theme_state.dart';
import 'state/video_library_state.dart';
import 'utils/crash_log.dart';

// Global keys so a native "Open with" callback can navigate + snackbar from
// anywhere, without a BuildContext of its own.
final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<ScaffoldMessengerState> _messengerKey =
    GlobalKey<ScaffoldMessengerState>();

void main() {
  // Crash journal: rather than vanishing silently, record any Dart-side
  // error and offer it as a copyable report on the next app launch -
  // "app closed unexpectedly" becomes debuggable without a PC/logcat.
  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();
    // v37: startup breadcrumbs - maxplayer_start.log (also in Android/
    // data/...) shows how far a phone gets before dying.
    unawaited(NativeBridge.crumb('dart_main'));
    // Must be called before any media_kit Player is created.
    MediaKit.ensureInitialized();
    unawaited(NativeBridge.crumb('mediakit_ok'));
    FlutterError.onError = (details) {
      CrashLog.record(
          'flutter', details.exceptionAsString(), details.stack);
      FlutterError.presentError(details);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      CrashLog.record('async', error.toString(), stack);
      return true;
    };
    // Follow the phone's own rotation everywhere; the player's lock button
    // temporarily restricts it (and restores on exit).
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    runApp(const MaxPlayerApp());
  }, (error, stack) {
    CrashLog.record('zone', error.toString(), stack);
  });
}

class MaxPlayerApp extends StatefulWidget {
  const MaxPlayerApp({super.key});

  @override
  State<MaxPlayerApp> createState() => _MaxPlayerAppState();
}

class _MaxPlayerAppState extends State<MaxPlayerApp> {
  final library = VideoLibraryState();

  // v37: created inside initState under a guard - if the playback engine's
  // native library can't load on this device, show a readable error screen
  // instead of dying with "Max Player has stopped" at startup.
  MediaPlayerState? _player;
  Object? _playerError;

  @override
  void initState() {
    super.initState();
    try {
      _player = MediaPlayerState();
      unawaited(NativeBridge.crumb('player_ok'));
    } catch (e) {
      _playerError = e;
      unawaited(NativeBridge.crumb('player_FAIL: $e'));
    }
    // App-wide accent color (persisted).
    themeState.load();
    final mp = _player;
    if (mp != null) {
      // v22: the player's fallback for 4K/HDR thumbnails writes the cached
      // image itself - swap it into the already-built library list so the
      // tile updates without a rescan.
      mp.onThumbnailCaptured =
          (videoPath, thumbPath) => library.setThumbnail(videoPath, thumbPath);
      // v69 C3 / v70 C4: start Wi-Fi resume-sync and Wear OS companion service.
      unawaited(ResumeSyncService.instance.start(mp));
      // "Open with Max Player" from other apps: warm delivery ...
      NativeBridge.configureCallbacks(
        onOpenVideo: _openExternalVideo,
        onOpenVideoFailed: _externalOpenFailed,
        // v62 Phase 1: a notification was tapped while the app was running.
        onNotificationTap: _handleNotificationTap,
        // v67 B1: media notification controls (play/pause, next, prev, stop).
        onMediaAction: (action) {
          final p = _player;
          if (p == null) return;
          switch (action) {
            case 'play_pause':
              p.togglePlay();
              break;
            case 'next':
              p.nextTrack();
              break;
            case 'prev':
              p.previousTrack();
              break;
            case 'stop':
              p.pause();
              unawaited(NativeBridge.cancelNowPlaying());
              break;
          }
        },
        // v70 C4: media notification playbar seek action.
        onMediaSeek: (pos) => _player?.seek(pos),
      );
      // ... and the cold-start cases (app launched BY a VIEW intent or a
      // notification tap).
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final initial = await NativeBridge.getInitialOpenVideo();
        final path = initial['path'];
        final failed = initial['failed'];
        if (path != null) {
          _openExternalVideo(path);
        } else if (failed != null) {
          _externalOpenFailed(failed);
        }
        // Cold start from a notification tap.
        final notifPayload =
            await NativeBridge.getInitialNotificationPayload();
        if (notifPayload != null) {
          _handleNotificationTap(notifPayload);
        }
      });
    }
  }

  /// Plays a video that another app sent us. Local files arrive as real
  /// filesystem paths (resolved natively); http/rtsp-style links are treated
  /// as network streams and handed to libmpv directly.
  Future<void> _openExternalVideo(String path) async {
    final mp = _player;
    if (mp == null) return;
    const streamSchemes = {'http', 'https', 'rtsp', 'rtmp', 'mms'};
    final uri = Uri.tryParse(path);
    if (uri != null && streamSchemes.contains(uri.scheme.toLowerCase())) {
      final title =
          uri.pathSegments.isNotEmpty && uri.pathSegments.last.isNotEmpty
              ? Uri.decodeComponent(uri.pathSegments.last)
              : uri.host;
      await mp.playStream(path, title);
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
    await mp.setPlaylistAndPlay([track], 0);
    _navigateToPlayer();
  }

  /// Jump straight into the player, replacing an already-open one.
  void _navigateToPlayer() {
    final nav = _navigatorKey.currentState;
    final mp = _player;
    if (nav == null || mp == null) return;
    nav.popUntil((route) => route.isFirst);
    nav.push(MaterialPageRoute(builder: (_) => PlayerScreen(player: mp)));
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

  /// v62/v63: a Max Player notification was tapped. Routes the payload as a
  /// deep link: "video:<path>" opens the video in the player (used by
  /// AI-subtitles-ready and Continue watching); "cast:" brings the app to the
  /// foreground for cast controls; "test:..." (About-sheet button) just
  /// confirms delivery.
  void _handleNotificationTap(String payload) {
    final action = NotificationAction.parse(payload);
    switch (action) {
      case VideoNotificationAction(path: final path):
        if (path.isNotEmpty) {
          _openExternalVideo(path);
        }
      case CastNotificationAction():
        // The app is already in the foreground from the tap; the cast
        // controls are where the user left them. Nothing more to do.
        break;
      case TestNotificationAction(tag: final tag):
        _messengerKey.currentState?.showSnackBar(
          SnackBar(
            content: Text('Notification: $tag'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      case UnknownNotificationAction():
        break;
    }
  }

  @override
  void dispose() {
    _player?.dispose();
    library.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mp = _player;
    // Rebuild the whole app when the accent color changes.
    return AnimatedBuilder(
      animation: themeState,
      builder: (context, _) {
        return MaterialApp(
          navigatorKey: _navigatorKey,
          scaffoldMessengerKey: _messengerKey,
          title: 'Max Player',
          debugShowCheckedModeBanner: false,
          // v60 CRASH FIX (his report: "Null check operator used on a null
          // value" in _onUnknownRoute): when Android pushes a route the
          // app does not know (task restore / back stack / plugin intent),
          // pushNamed returned null and Flutter crashed with a null-check.
          // Unknown routes now land on the normal home screen.
          onUnknownRoute: (settings) => MaterialPageRoute(
            builder: (_) => mp == null
                ? _StartupFailureScreen(error: _playerError)
                : LibraryScreen(library: library, player: mp),
          ),
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            scaffoldBackgroundColor: const Color(0xFF0a0a0f),
            colorScheme: ColorScheme.fromSeed(
              seedColor: themeState.accent,
              brightness: Brightness.dark,
            ),
          ),
          home: mp == null
              ? _StartupFailureScreen(error: _playerError)
              : LibraryScreen(library: library, player: mp),
        );
      },
    );
  }
}

/// v37: shown if the playback engine itself failed to initialise (e.g. its
/// native library could not load on this device). Much better than a silent
/// "has stopped": the reason is visible + copyable, and the startup trace
/// file pinpoints the exact stage.
class _StartupFailureScreen extends StatelessWidget {
  final Object? error;

  const _StartupFailureScreen({this.error});

  @override
  Widget build(BuildContext context) {
    final detail = error?.toString() ?? 'unknown error';
    return Scaffold(
      backgroundColor: const Color(0xFF0a0a0f),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline,
                  color: Colors.redAccent, size: 56),
              const SizedBox(height: 16),
              const Text(
                'The video engine failed to start on this phone',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              SelectableText(
                detail,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 20),
              const Text(
                'Please send this text + the file\n'
                'Android/data/com.hypertechlabs.maxplayer/files/maxplayer_start.log\n'
                'to the developer.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white38, fontSize: 12.5),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () =>
                    Clipboard.setData(ClipboardData(text: detail)),
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('Copy error'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
