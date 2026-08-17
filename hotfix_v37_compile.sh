#!/usr/bin/env bash
# =============================================================
#  Max Player - v37 COMPATIBILITY RESEARCH ROUND ("all devices")
#  Repo: https://github.com/Aryanshahx/maxplayer   Version: 1.0.0+35
#  Includes ALL of v36/v35/v34/...
#
#  RESEARCH RESULTS THIS ROUND (verified on the real 3.44.9 engine):
#   - The Impeller off-switch IS still honored by the engine we ship
#     (flag + Skia backend both verified inside libflutter.so), and the
#     engine is 64KB-page aligned (safe on new phones). So the crash is
#     NOT the renderer opt-out and NOT new-page-size systems.
#   - NEW suspicion list: media_kit Player creation at start, storage
#     permission flow on Tecno/Infinix/MIUI skins, engine itself.
#  1. STARTUP TRACE: every cold start now writes a stage breadcrumb log:
#       Android/data/com.hypertechlabs.maxplayer/files/maxplayer_start.log
#     Stages: app_create -> activity_create -> channel_ready -> dart_main
#     -> mediakit_ok -> player_ok -> scan_start ... + "CRASH:" line.
#     The file also exists in internal storage. Whatever stage is LAST,
#     that is the component killing the phone. No PC, no logcat, works
#     even if the app never opens once.
#  2. ENGINE GUARD: if the video engine (libmpv) fails to initialise on
#     a device, the app now shows a red error screen with the reason +
#     copy button instead of a silent "has stopped" at startup.
#  3. PERMISSION HARDENED: the all-files-access request is wrapped -
#     skins without that settings screen now get the retry UI, not a
#     dead app.
#  4. Keeps v34-v36 (crash report readable without opening the app),
#     v35 tune-sheet fix, and everything older. 86 tests pass.
#
#  FILES (27) - full-file writes; one script is enough from any state.
#
#  HOW TO USE:
#    cd ~/IdeaProjects/maxplayer
#    nano update_maxplayer_v37.sh   # paste, save, exit
#    bash update_maxplayer_v37.sh   (must print 19 x OK)
#    git add -A && git commit -m "v37: startup trace + engine guard +
#        permission hardening (1.0.0+35)" && git push
# =============================================================
set -e
cd "$HOME/IdeaProjects/maxplayer" || { echo "ERROR: project folder not found"; exit 1; }

if ! grep -q "^name: maxplayer" pubspec.yaml 2>/dev/null; then
  echo "ERROR: This does not look like the maxplayer project folder."
  exit 1
fi
if grep -qF "maxplayer_start.log" android/app/src/main/kotlin/com/hypertechlabs/maxplayer/MaxPlayerApp.kt 2>/dev/null \
  && grep -qF "private fun write(context: Context?" android/app/src/main/kotlin/com/hypertechlabs/maxplayer/MaxPlayerApp.kt 2>/dev/null \
  && grep -qF "version: 1.0.0+35" pubspec.yaml 2>/dev/null; then
  echo "v37 looks already applied. Nothing to do."
  exit 0
fi

echo "==> v37: writing 27 files ..."

mkdir -p "$(dirname 'lib/main.dart')"
cat > 'lib/main.dart' <<'EOF_MARKER_0'
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
EOF_MARKER_0

mkdir -p "$(dirname 'lib/state/theme_state.dart')"
cat > 'lib/state/theme_state.dart' <<'EOF_MARKER_1'
import 'package:flutter/material.dart';

import '../services/native_bridge.dart';

/// App-wide accent color state. A single global instance ([themeState]) is
/// fine here - main.dart rebuilds MaterialApp when it notifies, which
/// refreshes every screen. Widgets read [ThemeState.accent] directly so
/// no InheritedWidget plumbing is needed.
class ThemeState extends ChangeNotifier {
  /// Selectable accent colors (white added in v22).
  static const List<Color> swatches = [
    Color(0xFFA855F7), // purple
    Color(0xFF22D3EE), // cyan
    Color(0xFF34D399), // green
    Color(0xFFFB923C), // orange
    Color(0xFFF472B6), // pink
    Color(0xFF60A5FA), // blue
    Color(0xFFFFFFFF), // white (v22)
  ];

  /// v29: WHITE is the default theme colour (user request). Anyone who
  /// already picked a colour keeps it - the saved choice loads on top.
  static const Color defaultAccent = Color(0xFFFFFFFF);

  static const String _kAccentKey = 'theme.accent';

  Color _accent = defaultAccent;
  Color get accent => _accent;

  /// Text/icon color to paint ON TOP of the accent (light accents like
  /// white need dark ink, the rest use white).
  Color get onAccent => contrastColorFor(_accent);

  Future<void> load() async {
    final s = await NativeBridge.loadSettings();
    final v = int.tryParse(s[_kAccentKey] ?? '');
    if (v != null) {
      final match = swatches.where((c) => c.toARGB32() == v);
      _accent = match.isNotEmpty ? match.first : Color(v);
      notifyListeners();
    }
  }

  void setAccent(Color c) {
    _accent = c;
    notifyListeners();
    NativeBridge.saveSetting(_kAccentKey, '${c.toARGB32()}');
  }
}

/// The one app-wide instance.
final ThemeState themeState = ThemeState();

/// Text/icon color that stays readable ON a [c]-coloured surface. Pure +
/// unit-tested (v22: this is what keeps the speed badge visible on the
/// white accent).
Color contrastColorFor(Color c) {
  final argb = c.toARGB32();
  // Perceived luminance (WCAG-ish), cheap and fine for our swatches.
  final r = (argb >> 16) & 0xFF;
  final g = (argb >> 8) & 0xFF;
  final b = argb & 0xFF;
  final lum = 0.299 * r + 0.587 * g + 0.114 * b;
  return lum > 160 ? const Color(0xFF16161f) : Colors.white;
}
EOF_MARKER_1

mkdir -p "$(dirname 'android/app/src/main/AndroidManifest.xml')"
cat > 'android/app/src/main/AndroidManifest.xml' <<'EOF_MARKER_2'
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:tools="http://schemas.android.com/tools">

    <uses-permission android:name="android.permission.READ_MEDIA_VIDEO" />
    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"
        android:maxSdkVersion="32" />
    <uses-permission android:name="android.permission.MANAGE_EXTERNAL_STORAGE"
        tools:ignore="ScopedStorage" />

    <!-- Network: one-time AI model download + streaming URLs + DLNA cast control -->
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
    <!-- DLNA/UPnP casting: SSDP device discovery needs the multicast lock -->
    <uses-permission android:name="android.permission.CHANGE_WIFI_MULTICAST_STATE" />
    <application
        android:label="Max Player"
        android:name=".MaxPlayerApp"
        android:icon="@mipmap/ic_launcher"
        android:roundIcon="@mipmap/ic_launcher_round">
        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:launchMode="singleTop"
            android:taskAffinity=""
            android:theme="@style/LaunchTheme"
            android:resizeableActivity="true"
            android:supportsPictureInPicture="true"
            android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode"
            android:hardwareAccelerated="true"
            android:windowSoftInputMode="adjustResize">
            <!-- Specifies an Android theme to apply to this Activity as soon as
                 the Android process has started. This theme is visible to the user
                 while the Flutter UI initializes. After that, this theme continues
                 to determine the Window background behind the Flutter UI. -->
            <meta-data
              android:name="io.flutter.embedding.android.NormalTheme"
              android:resource="@style/NormalTheme"
              />

            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>

            <!-- ================= Open with / Share ================= -->
            <!-- "Share -> Max Player" from any gallery, file manager, chat app -->
            <intent-filter>
                <action android:name="android.intent.action.SEND" />
                <category android:name="android.intent.category.DEFAULT" />
                <data android:mimeType="video/*" />
            </intent-filter>

            <!-- Properly typed local videos (galleries, file managers) -->
            <intent-filter>
                <action android:name="android.intent.action.VIEW" />
                <category android:name="android.intent.category.DEFAULT" />
                <data android:scheme="content" android:mimeType="video/*" />
                <data android:scheme="file" android:mimeType="video/*" />
            </intent-filter>

            <!-- Typed video links in browsers -->
            <intent-filter>
                <action android:name="android.intent.action.VIEW" />
                <category android:name="android.intent.category.DEFAULT" />
                <category android:name="android.intent.category.BROWSABLE" />
                <data android:scheme="http" android:mimeType="video/*" />
                <data android:scheme="https" android:mimeType="video/*" />
            </intent-filter>

            <!-- Live streaming protocols -->
            <intent-filter>
                <action android:name="android.intent.action.VIEW" />
                <category android:name="android.intent.category.DEFAULT" />
                <data android:scheme="rtsp" />
                <data android:scheme="rtmp" />
                <data android:scheme="mms" />
            </intent-filter>

            <!-- Untyped URIs (FileProvider & friends): any mime, but the path
                 has a video extension. Lower- and upper-case patterns because
                 Android's pattern matching is case-sensitive. -->
            <intent-filter>
                <action android:name="android.intent.action.VIEW" />
                <category android:name="android.intent.category.DEFAULT" />
                <data android:scheme="file" />
                <data android:scheme="content" />
                <data android:host="*" />
                    <data android:pathPattern=".*\\.mp4" />
                    <data android:pathPattern=".*\\.MP4" />
                    <data android:pathPattern=".*\\.webm" />
                    <data android:pathPattern=".*\\.WEBM" />
                    <data android:pathPattern=".*\\.mkv" />
                    <data android:pathPattern=".*\\.MKV" />
                    <data android:pathPattern=".*\\.avi" />
                    <data android:pathPattern=".*\\.AVI" />
                    <data android:pathPattern=".*\\.mov" />
                    <data android:pathPattern=".*\\.MOV" />
                    <data android:pathPattern=".*\\.wmv" />
                    <data android:pathPattern=".*\\.WMV" />
                    <data android:pathPattern=".*\\.flv" />
                    <data android:pathPattern=".*\\.FLV" />
                    <data android:pathPattern=".*\\.m4v" />
                    <data android:pathPattern=".*\\.M4V" />
                    <data android:pathPattern=".*\\.3gp" />
                    <data android:pathPattern=".*\\.3GP" />
                    <data android:pathPattern=".*\\.3gpp" />
                    <data android:pathPattern=".*\\.3GPP" />
                    <data android:pathPattern=".*\\.ogv" />
                    <data android:pathPattern=".*\\.OGV" />
                    <data android:pathPattern=".*\\.ts" />
                    <data android:pathPattern=".*\\.TS" />
                    <data android:pathPattern=".*\\.mts" />
                    <data android:pathPattern=".*\\.MTS" />
                    <data android:pathPattern=".*\\.m2ts" />
                    <data android:pathPattern=".*\\.M2TS" />
                    <data android:pathPattern=".*\\.vob" />
                    <data android:pathPattern=".*\\.VOB" />
                    <data android:pathPattern=".*\\.mpg" />
                    <data android:pathPattern=".*\\.MPG" />
                    <data android:pathPattern=".*\\.mpeg" />
                    <data android:pathPattern=".*\\.MPEG" />
                    <data android:pathPattern=".*\\.rmvb" />
                    <data android:pathPattern=".*\\.RMVB" />
                    <data android:pathPattern=".*\\.divx" />
                    <data android:pathPattern=".*\\.DIVX" />
                    <data android:pathPattern=".*\\.f4v" />
                    <data android:pathPattern=".*\\.F4V" />
            </intent-filter>

            <!-- Videos wrongly typed as application/octet-stream (common on
                 Xiaomi/Oppo/Vivo/Realme galleries & some file managers). -->
            <intent-filter>
                <action android:name="android.intent.action.VIEW" />
                <category android:name="android.intent.category.DEFAULT" />
                <category android:name="android.intent.category.BROWSABLE" />
                <data android:scheme="file" />
                <data android:scheme="content" />
                <data android:scheme="http" />
                <data android:scheme="https" />
                <data android:host="*" />
                <data android:mimeType="application/octet-stream" />
                    <data android:pathPattern=".*\\.mp4" />
                    <data android:pathPattern=".*\\.MP4" />
                    <data android:pathPattern=".*\\.webm" />
                    <data android:pathPattern=".*\\.WEBM" />
                    <data android:pathPattern=".*\\.mkv" />
                    <data android:pathPattern=".*\\.MKV" />
                    <data android:pathPattern=".*\\.avi" />
                    <data android:pathPattern=".*\\.AVI" />
                    <data android:pathPattern=".*\\.mov" />
                    <data android:pathPattern=".*\\.MOV" />
                    <data android:pathPattern=".*\\.wmv" />
                    <data android:pathPattern=".*\\.WMV" />
                    <data android:pathPattern=".*\\.flv" />
                    <data android:pathPattern=".*\\.FLV" />
                    <data android:pathPattern=".*\\.m4v" />
                    <data android:pathPattern=".*\\.M4V" />
                    <data android:pathPattern=".*\\.3gp" />
                    <data android:pathPattern=".*\\.3GP" />
                    <data android:pathPattern=".*\\.3gpp" />
                    <data android:pathPattern=".*\\.3GPP" />
                    <data android:pathPattern=".*\\.ogv" />
                    <data android:pathPattern=".*\\.OGV" />
                    <data android:pathPattern=".*\\.ts" />
                    <data android:pathPattern=".*\\.TS" />
                    <data android:pathPattern=".*\\.mts" />
                    <data android:pathPattern=".*\\.MTS" />
                    <data android:pathPattern=".*\\.m2ts" />
                    <data android:pathPattern=".*\\.M2TS" />
                    <data android:pathPattern=".*\\.vob" />
                    <data android:pathPattern=".*\\.VOB" />
                    <data android:pathPattern=".*\\.mpg" />
                    <data android:pathPattern=".*\\.MPG" />
                    <data android:pathPattern=".*\\.mpeg" />
                    <data android:pathPattern=".*\\.MPEG" />
                    <data android:pathPattern=".*\\.rmvb" />
                    <data android:pathPattern=".*\\.RMVB" />
                    <data android:pathPattern=".*\\.divx" />
                    <data android:pathPattern=".*\\.DIVX" />
                    <data android:pathPattern=".*\\.f4v" />
                    <data android:pathPattern=".*\\.F4V" />
            </intent-filter>
        </activity>
        <!-- Don't delete the meta-data below.
             This is used by the Flutter tool to generate GeneratedPluginRegistrant.java -->
        <meta-data
            android:name="flutterEmbedding"
            android:value="2" />
        <!-- v33: Force the legacy Skia renderer instead of Impeller.
             Impeller (default since Flutter 3.29) crashes / shows black
             video with libmpv on many older GPUs - older Androids keep
             playing fine through the Skia path. -->
        <meta-data
            android:name="io.flutter.embedding.android.EnableImpeller"
            android:value="false" />
    </application>
    <!-- Required to query activities that can process text, see:
         https://developer.android.com/training/package-visibility and
         https://developer.android.com/reference/android/content/Intent#ACTION_PROCESS_TEXT.

         In particular, this is used by the Flutter engine in io.flutter.plugin.text.ProcessTextPlugin. -->
    <queries>
        <intent>
            <action android:name="android.intent.action.PROCESS_TEXT"/>
            <data android:mimeType="text/plain"/>
        </intent>
    </queries>
</manifest>
EOF_MARKER_2

mkdir -p "$(dirname 'lib/widgets/track_selection_sheet.dart')"
cat > 'lib/widgets/track_selection_sheet.dart' <<'EOF_MARKER_3'
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart' hide VideoTrack;

import '../state/theme_state.dart';
import '../utils/ai_subtitles.dart';

import '../state/media_player_state.dart';

/// v34: how tall the tracks sheet opens, as a fraction of the screen.
/// Pure so tests can pin the behaviour: handle + title is ~110dp, each
/// dense track row ~64dp; clamped to 40%..80% - and the sheet can always
/// be dragged up to 92%, so rows are never clipped on any phone.
double trackSheetInitialSize(int rowCount, double screenHeight) {
  if (screenHeight <= 0) return 0.6;
  final est = 110 + rowCount * 64.0;
  return (est / screenHeight).clamp(0.4, 0.8);
}

/// Bottom sheet listing the current media's audio or subtitle tracks, with a
/// check on the active one. Opened from the player controls.
class TrackSelectionSheet extends StatelessWidget {
  final MediaPlayerState player;
  final bool isSubtitle;
  final ScrollController scrollController;

  const TrackSelectionSheet({
    super.key,
    required this.player,
    required this.isSubtitle,
    required this.scrollController,
  });

  static Color get _accent => themeState.accent;
  static const Color _surface = Color(0xFF1a1a24);

  static Future<void> show(
    BuildContext context,
    MediaPlayerState player, {
    required bool isSubtitle,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        // v34: the old constrained sheet STILL opened half-sized / cut on
        // some small phones. A DraggableScrollableSheet always opens tall
        // enough for the content (sized by real row count) and drags up
        // to 92% of the screen - no clipped rows, ever.
        final rows = isSubtitle
            ? player.subtitleTracks.length + 2 // "Generate with AI" + room
            : player.audioTracks.length;
        final initial = trackSheetInitialSize(
          rows,
          MediaQuery.of(sheetContext).size.height,
        );
        return DraggableScrollableSheet(
          initialChildSize: initial,
          minChildSize: 0.35,
          maxChildSize: 0.92,
          expand: false,
          builder: (_, controller) => TrackSelectionSheet(
            player: player,
            isSubtitle: isSubtitle,
            scrollController: controller,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Column(
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
              style: TextStyle(
                color: _accent,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: ListView(
              controller: scrollController,
              children:
                  isSubtitle ? _subtitleTiles(context) : _audioTiles(context),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  List<Widget> _audioTiles(BuildContext context) {
    // Dedupe by id - some containers list an entry twice.
    final tracks = <String, AudioTrack>{};
    for (final t in player.audioTracks) {
      if (t.id == 'no') continue;
      tracks[t.id] = t;
    }
    final list = tracks.values.toList();
    if (list.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.all(20),
          child: Text(
            'No audio tracks found',
            style: TextStyle(color: Colors.white38),
          ),
        ),
      ];
    }
    return [
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
    ];
  }

  List<Widget> _subtitleTiles(BuildContext context) {
    // "no" is the explicit OFF entry; dedupe the rest by id.
    final tracks = <String, SubtitleTrack>{};
    for (final t in player.subtitleTracks) {
      if (t.id == 'no') continue;
      tracks[t.id] = t;
    }
    final list = [SubtitleTrack.no(), ...tracks.values];
    return [
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
      const Divider(height: 16, color: Colors.white12),
      // Offline AI subtitle generation (whisper.cpp) - free, no internet
      // after the one-time model download.
      ListTile(
        dense: true,
        leading: Icon(Icons.auto_awesome,
            size: 20, color: TrackSelectionSheet._accent),
        title: const Text(
          'Generate with AI ✨',
          style: TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: const Text(
          'Offline & free · the AI writes subtitles for this video',
          style: TextStyle(color: Colors.white38, fontSize: 12),
        ),
        onTap: () {
          final rootCtx = Navigator.of(context, rootNavigator: true).context;
          Navigator.of(context).pop();
          AiSubtitleRunner.start(rootCtx, player);
        },
      ),
    ];
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
            ? Icon(Icons.check, size: 18, color: TrackSelectionSheet._accent)
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
EOF_MARKER_3

mkdir -p "$(dirname 'lib/widgets/player_controls_overlay.dart')"
cat > 'lib/widgets/player_controls_overlay.dart' <<'EOF_MARKER_4'
import 'package:flutter/material.dart';

import '../state/media_player_state.dart';
import '../state/theme_state.dart';
import '../utils/formatters.dart';
import 'progress_bar.dart';
import 'track_selection_sheet.dart';

/// Controls drawn on top of the video - v19 final-polish layout, v26 look:
///
///   [progress bar, with scrub thumbnail preview]
///   row 1:  previous  -  play/pause  -  next            (centered trio)
///   row 2:  mute - speed - Tracks(subs/audio/A-B)
///           ...  queue - fit - rotation lock
///
/// v26: every button follows the picked theme colour, EXCEPT the transport
/// trio (prev/play/next), which stays white and only flashes the accent as
/// a background effect WHILE pressed. The seek bar itself is untouched.
/// The rotation lock moved next to the fit button (user request).
///
/// Removed per the final polish pass: shuffle, repeat, the dedicated
/// +/-10 s buttons (horizontal drag-seek covers them) and the fullscreen
/// button (sensor auto-rotate replaces it); the fit cycle moved to the
/// corner where fullscreen used to sit.
///
/// This widget rebuilds itself via [AnimatedBuilder] on every player tick,
/// so the parent screen does NOT rebuild (which kept recreating the video
/// surface and caused fullscreen flicker).
class PlayerControlsOverlay extends StatelessWidget {
  final MediaPlayerState player;
  final VoidCallback onToggleQueue;

  /// Fired on every control interaction; the screen uses it to restart the
  /// auto-hide countdown.
  final VoidCallback onInteract;

  /// v26: reports seek-bar drag start/end; the screen pauses its auto-hide
  /// countdown while a scrub is in progress (controls faded mid-drag).
  final ValueChanged<bool> onScrubbing;

  /// Cycles the video fit (contain -> cover -> fill).
  final VoidCallback onCycleFit;

  /// Rotation lock toggle (auto-rotate by sensor vs pinned).
  final bool orientationLocked;
  final VoidCallback onToggleOrientationLock;

  const PlayerControlsOverlay({
    super.key,
    required this.player,
    required this.onToggleQueue,
    required this.onInteract,
    required this.onScrubbing,
    required this.onCycleFit,
    required this.orientationLocked,
    required this.onToggleOrientationLock,
    // v25: karaoke toggle moved INTO the tracks sheet (was the ⋮ menu).
    required this.karaokeOn,
    required this.onToggleKaraoke,
  });

  /// v25: karaoke state + toggle, so the tracks sheet can host the switch
  /// next to Subtitles / Audio track / A-B loop.
  final bool karaokeOn;
  final VoidCallback onToggleKaraoke;

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
              colors: [
                Colors.transparent,
                Colors.black.withValues(alpha: 0.85),
              ],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              VideoProgressBar(
                position: player.position,
                duration: player.duration,
                previewThumb: player.scrubThumbPath,
                onSeek: (d) {
                  player.seek(d);
                  onInteract();
                },
                onScrubbing: onScrubbing,
              ),
              // Row 1: previous / play-pause / next - the transport trio.
              // v26: these three STAY white; the theme colour appears only
              // as the press flash behind them (accentPress).
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _iconBtn(
                    icon: Icons.skip_previous,
                    size: 30,
                    accentPress: true,
                    tooltip: 'Previous video',
                    onTap: player.prevTrack,
                  ),
                  const SizedBox(width: 22),
                  _iconBtn(
                    icon: player.isPlaying
                        ? Icons.pause_circle_filled
                        : Icons.play_circle_filled,
                    size: 46,
                    accentPress: true,
                    onTap: player.togglePlay,
                  ),
                  const SizedBox(width: 22),
                  _iconBtn(
                    icon: Icons.skip_next,
                    size: 30,
                    accentPress: true,
                    tooltip: 'Next video',
                    onTap: player.nextTrack,
                  ),
                ],
              ),
              // Row 2 (compact): mute speed tracks | queue fit rotate
              Row(
                children: [
                  _iconBtn(
                    icon: player.isMuted || player.volume == 0
                        ? Icons.volume_off
                        : Icons.volume_up,
                    active: player.isMuted || player.volume == 0,
                    tooltip: 'Mute',
                    onTap: player.toggleMute,
                    compact: true,
                  ),
                  _speedMenu(),
                  _tracksMenu(context),
                  const Spacer(),
                  _iconBtn(
                    icon: Icons.queue_music,
                    tooltip: 'Queue',
                    onTap: onToggleQueue,
                    compact: true,
                  ),
                  _iconBtn(
                    tooltip: 'Fit: contain / cover / fill',
                    icon: Icons.aspect_ratio,
                    onTap: onCycleFit,
                    compact: true,
                  ),
                  // v26: rotation lock moved next to the fit button.
                  _iconBtn(
                    tooltip: orientationLocked
                        ? 'Rotation locked - tap for auto'
                        : 'Auto-rotate - tap to lock',
                    icon: orientationLocked
                        ? Icons.screen_lock_rotation
                        : Icons.screen_rotation,
                    active: orientationLocked,
                    onTap: onToggleOrientationLock,
                    compact: true,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  /// One button opening ONE bottom sheet for everything track-shaped:
  /// subtitles, audio tracks, and the A-B loop (previously three separate
  /// buttons). v20: switched from PopupMenuButton to a bottom sheet - the
  /// popup glitched because this overlay rebuilds on every player tick
  /// while the popup was open.
  Widget _tracksMenu(BuildContext context) {
    final active = player.subtitlesActive ||
        player.audioTracks.length > 1 ||
        player.abLoopActive;
    // v26: theme-coloured like the other row buttons; an "active" chip
    // background marks subtitles/audio/A-B in use.
    return _iconBtn(
      tooltip: 'Subtitles, audio tracks, A-B loop, karaoke',
      icon: Icons.tune,
      active: active,
      compact: true,
      onTap: () => _showTracksSheet(context),
    );
  }

  void _showTracksSheet(BuildContext context) {
    final hasA = player.loopA != null;
    final hasB = player.loopB != null;
    final abSubtitle = hasA && hasB
        ? 'Looping ${formatDuration(player.loopA)} - ${formatDuration(player.loopB)} (tap to clear)'
        : hasA
            ? 'A set at ${formatDuration(player.loopA)} - tap to set B'
            : 'Off - tap to mark point A';
    showModalBottomSheet<void>(
      context: context,
      // v35: THIS is the button that was reported broken ("subtitles,
      // audio tracks, A-B loop, karaoke - not fully opens in phone"):
      // without isScrollControlled a bottom sheet is capped at HALF the
      // screen height, so in landscape (and on small phones) the A-B
      // loop and karaoke rows were clipped with no way to reach them.
      // A DraggableScrollableSheet sizes to content, always scrolls,
      // and drags up to 92% of the screen.
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1a1a24),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: trackSheetInitialSize(
          4, // handle + subtitles + audio + A-B loop + karaoke rows
          MediaQuery.of(sheetContext).size.height,
        ),
        minChildSize: 0.3,
        maxChildSize: 0.92,
        expand: false,
        builder: (_, scrollController) => SafeArea(
          top: false,
          child: ListView(
            controller: scrollController,
            children: [
              const SizedBox(height: 10),
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: Icon(
                  player.subtitlesActive
                      ? Icons.subtitles
                      : Icons.subtitles_outlined,
                  color: Colors.white70,
                ),
                title: Text(
                  player.subtitlesActive ? 'Subtitles (on)' : 'Subtitles',
                  style: const TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  TrackSelectionSheet.show(context, player, isSubtitle: true);
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.audiotrack_outlined,
                  color: Colors.white70,
                ),
                title: Text(
                  player.audioTracks.length > 1
                      ? 'Audio track (${player.audioTracks.length} available)'
                      : 'Audio track',
                  style: const TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  TrackSelectionSheet.show(context, player, isSubtitle: false);
                },
              ),
              ListTile(
                leading: Icon(
                  Icons.repeat_one_outlined,
                  color: player.abLoopActive
                      ? themeState.accent
                      : Colors.white70,
                ),
                title: const Text(
                  'A-B loop',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  abSubtitle,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  final msg = player.tapLoopPoint();
                  ScaffoldMessenger.of(context)
                    ..clearSnackBars()
                    ..showSnackBar(
                      SnackBar(
                        content: Text(msg),
                        duration: const Duration(milliseconds: 1400),
                      ),
                    );
                },
              ),
              ListTile(
                leading: Icon(
                  karaokeOn
                      ? Icons.closed_caption
                      : Icons.closed_caption_off_outlined,
                  color: karaokeOn ? themeState.accent : Colors.white70,
                ),
                title: Text(
                  karaokeOn ? 'Karaoke subtitles (on)' : 'Karaoke subtitles',
                  style: TextStyle(
                      color:
                          karaokeOn ? themeState.accent : Colors.white),
                ),
                subtitle: const Text(
                  'Words light up - other subtitles hide while on',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  onToggleKaraoke();
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _speedMenu() {
    return PopupMenuButton<double>(
      initialValue: player.playbackRate,
      color: const Color(0xFF1a1a24),
      onSelected: (r) {
        player.setPlaybackRate(r);
        onInteract();
      },
      itemBuilder: (context) =>
          const [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0] // v22: up to 3x
              .map((r) => PopupMenuItem(
                    value: r,
                    child: Text('${r}x',
                        style: const TextStyle(color: Colors.white)),
                  ))
              .toList(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
        // v26: the speed label follows the theme colour like the buttons.
        child: Text('${player.playbackRate}x',
            style: TextStyle(color: themeState.accent, fontSize: 11)),
      ),
    );
  }

  Widget _iconBtn({
    required IconData icon,
    required VoidCallback onTap,
    bool active = false,
    double size = 24,
    bool compact = false,
    String? tooltip,

    /// v26: the transport trio (prev/play/next) is the ONLY exception to
    /// the theme-coloured buttons: their icons stay white and the accent
    /// shows purely as the press flash behind the icon.
    bool accentPress = false,
  }) {
    final accent = themeState.accent;
    return IconButton(
      tooltip: tooltip,
      icon: Icon(
        icon,
        size: compact ? 20 : size,
        // v26: every player button follows the picked theme colour
        // (accentPress buttons stay white - they flash it instead).
        color: accentPress ? Colors.white : accent,
      ),
      // Press-only theme colour for the transport trio.
      splashColor: accentPress ? accent.withValues(alpha: 0.45) : null,
      highlightColor: accentPress ? accent.withValues(alpha: 0.28) : null,
      // An "on" state (rotation locked, tracks in use, muted) sits on a
      // translucent accent chip so it reads as active even though every
      // icon is accent-coloured now.
      style: active
          ? ButtonStyle(
              backgroundColor: WidgetStateProperty.all(
                accent.withValues(alpha: 0.22),
              ),
            )
          : null,
      // Compact rows must fit ~7 actions on a 320dp-wide phone.
      constraints:
          compact ? const BoxConstraints.tightFor(width: 34, height: 40) : null,
      padding: compact ? EdgeInsets.zero : null,
      visualDensity: compact ? VisualDensity.compact : null,
      // Every press also restarts the screen's auto-hide countdown.
      onPressed: () {
        onTap();
        onInteract();
      },
    );
  }
}
EOF_MARKER_4

mkdir -p "$(dirname 'lib/state/video_library_state.dart')"
cat > 'lib/state/video_library_state.dart' <<'EOF_MARKER_5'
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

  /// Requests "All files access", then scans the whole of internal storage
  /// for videos. Call this again any time to retry after a denial.
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
    if (!status.isGranted) {
      permissionDenied = true;
      notifyListeners();
      return;
    }

    unawaited(NativeBridge.crumb('scan_granted'));
    folderName = 'Internal storage';
    await _scanDirectory(_internalStorageRoot);
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
EOF_MARKER_5

mkdir -p "$(dirname 'lib/widgets/video_picker_sheet.dart')"
cat > 'lib/widgets/video_picker_sheet.dart' <<'EOF_MARKER_6'
import 'dart:io';

import 'package:flutter/material.dart';

import '../models/video_track.dart';
import '../state/theme_state.dart';
import '../utils/formatters.dart';
import 'fade_in_image.dart';

/// v29: multi-select video picker bottom sheet. Used by the Playlist tile
/// ("build a playlist from selected videos") and the Private folder's "+"
/// button. Returns the selected videos, or null when dismissed without
/// confirming.
class VideoPickerSheet extends StatefulWidget {
  final List<VideoTrack> videos;
  final String title;

  /// Verb on the confirm button ("Play", "Hide", ...).
  final String actionLabel;

  const VideoPickerSheet({
    super.key,
    required this.videos,
    required this.title,
    required this.actionLabel,
  });

  static Future<List<VideoTrack>?> show(
    BuildContext context,
    List<VideoTrack> videos, {
    required String title,
    required String actionLabel,
  }) {
    return showModalBottomSheet<List<VideoTrack>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1a1a24),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SizedBox(
        height: MediaQuery.of(sheetContext).size.height * 0.72,
        child: VideoPickerSheet(
          videos: videos,
          title: title,
          actionLabel: actionLabel,
        ),
      ),
    );
  }

  @override
  State<VideoPickerSheet> createState() => _VideoPickerSheetState();
}

class _VideoPickerSheetState extends State<VideoPickerSheet> {
  final Set<String> _selected = {};

  void _toggle(String path) {
    setState(() {
      if (!_selected.remove(path)) _selected.add(path);
    });
  }

  @override
  Widget build(BuildContext context) {
    final accent = themeState.accent;
    return SafeArea(
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
            padding: const EdgeInsets.fromLTRB(20, 10, 8, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: TextStyle(
                      color: accent,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      if (_selected.length == widget.videos.length) {
                        _selected.clear();
                      } else {
                        _selected
                          ..clear()
                          ..addAll(widget.videos.map((v) => v.path));
                      }
                    });
                  },
                  child: Text(
                    _selected.length == widget.videos.length
                        ? 'Clear all'
                        : 'Select all',
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: widget.videos.isEmpty
                ? const Center(
                    child: Text(
                      'No videos in the library yet - rescan first.',
                      style: TextStyle(color: Colors.white54),
                    ),
                  )
                : ListView.builder(
                    itemCount: widget.videos.length,
                    itemBuilder: (context, i) {
                      final v = widget.videos[i];
                      final selected = _selected.contains(v.path);
                      return InkWell(
                        onTap: () => _toggle(v.path),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 7),
                          child: Row(
                            children: [
                              _PickerThumb(
                                  path: v.thumbnailPath, accent: accent),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      v.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: selected
                                            ? accent
                                            : Colors.white,
                                        fontSize: 13.5,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${formatDuration(v.duration)}  ·  '
                                      '${formatFileSize(v.sizeBytes)}',
                                      style: const TextStyle(
                                          color: Colors.white38,
                                          fontSize: 11.5),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                selected
                                    ? Icons.check_circle
                                    : Icons.circle_outlined,
                                color:
                                    selected ? accent : Colors.white24,
                                size: 22,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          const Divider(height: 1, color: Colors.white12),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
            child: Row(
              children: [
                Text(
                  _selected.isEmpty
                      ? 'Tap videos to select'
                      : '${_selected.length} selected',
                  style: const TextStyle(color: Colors.white54),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: _selected.isEmpty
                      ? null
                      : () {
                          final picked = [
                            for (final v in widget.videos)
                              if (_selected.contains(v.path)) v,
                          ];
                          Navigator.of(context).pop(picked);
                        },
                  child: Text(
                    _selected.isEmpty
                        ? widget.actionLabel
                        : '${widget.actionLabel} (${_selected.length})',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PickerThumb extends StatelessWidget {
  final String? path;
  final Color accent;
  const _PickerThumb({required this.path, required this.accent});

  @override
  Widget build(BuildContext context) {
    final p = path;
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: 46,
        height: 28,
        child: p != null
            ? Image.file(
                File(p),
                fit: BoxFit.cover,
                cacheWidth: 96,
                frameBuilder: fadeInImageFrame,
                errorBuilder: (_, __, ___) => _fallback(),
              )
            : _fallback(),
      ),
    );
  }

  Widget _fallback() => Container(
        color: accent.withValues(alpha: 0.12),
        child: Icon(Icons.movie_outlined, size: 14, color: accent),
      );
}
EOF_MARKER_6

mkdir -p "$(dirname 'lib/state/media_player_state.dart')"
cat > 'lib/state/media_player_state.dart' <<'EOF_MARKER_7'
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:media_kit/media_kit.dart' hide VideoTrack;
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;

import '../models/history_entry.dart';
import '../models/video_track.dart';
import '../services/native_bridge.dart';
import '../utils/formatters.dart';
import '../utils/srt.dart';
import 'player_settings.dart';

/// v30: merge picked videos into the play queue, skipping entries whose id
/// is already queued. Pure so the playlist "+" logic is unit-testable.
List<VideoTrack> mergeQueueVideos(
  List<VideoTrack> queue,
  List<VideoTrack> added,
) {
  final out = [...queue];
  final have = queue.map((v) => v.id).toSet();
  for (final v in added) {
    if (have.add(v.id)) out.add(v);
  }
  return out;
}

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

  /// Short user-facing notices ("Resumed 12:34" etc) - the player screen
  /// shows these as a transient overlay indicator.
  final _notices = StreamController<String>.broadcast();
  Stream<String> get notices => _notices.stream;

  /// Periodic bookmark saver ("resume from where you left off").
  Timer? _bookmarkTimer;

  /// Last-used app-local brightness (left-half swipe in the player).
  double brightness = 1.0;
  bool _brightnessSynced = false;

  // --- A-B loop ---
  Duration? loopA;
  Duration? loopB;
  bool get abLoopActive => loopA != null && loopB != null;

  // --- Long-press speed boost ---
  double? _preBoostRate;

  /// True while the long-press speed boost is engaged; the player shows a
  /// persistent "Nx" badge for the whole boost, not just a flash.
  bool get isSpeedBoosting => _preBoostRate != null;

  // --- Equalizer (libmpv lavfi filter chain) ---
  static const List<int> eqFrequencies = [60, 230, 910, 3600, 14000];
  List<double> eqGains = List.filled(eqFrequencies.length, 0);
  bool eqEnabled = false;

  // --- Watch-time stats ---
  int _watchTodaySecs = 0;
  String _todayStatsKey = '';

  /// v27: cumulative watch seconds PER VIDEO (path -> seconds), powering
  /// the Statistics screen's "Most watched" list. Persisted as one small
  /// JSON map, capped at the 60 heaviest entries so it never grows wild.
  Map<String, int> _watchByVideo = const {};
  static const String _kWatchByVideoKey = 'stats.video';
  static const int _kWatchByVideoMax = 60;

  // --- Watch history (drives the home History screen + resume playback) ---
  final List<HistoryEntry> _history = [];
  bool _historyLoaded = false;
  static const String _kHistoryKey = 'history';
  static const int _kHistoryMax = 150;

  List<HistoryEntry> get history => List.unmodifiable(_history);

  VideoTrack? get currentTrack =>
      playlist.isNotEmpty && currentIndex < playlist.length
      ? playlist[currentIndex]
      : null;

  final _rand = Random();
  Timer? _uiTicker;
  late final List<StreamSubscription> _subs;

  MediaPlayerState() {
    _subs = [
      player.stream.playing.listen((v) {
        isPlaying = v;
        notifyListeners();
        // Keep the PiP window's play/pause remote action in sync
        // (native side ignores this when not in PiP).
        NativeBridge.setPipPlaying(v);
      }),
      player.stream.position.listen((v) {
        position = v;
        // Enforce the A-B loop window.
        final a = loopA;
        final b = loopB;
        if (a != null && b != null && b > a && v >= b) {
          player.seek(a);
        }
        _checkSleepAtEnd(v); // "sleep at end of video" timer
        _maybeCaptureThumb(v); // 4K/HDR thumbnail fallback (v22)
        notifyListeners();
      }),
      player.stream.duration.listen((v) {
        duration = v;
        notifyListeners();
        // Kick off scrub-preview thumbnail generation (idempotent - runs
        // once per file, cached on disk afterwards).
        _ensureThumbStrip();
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
        // Karaoke mode: switching to a real subtitle track flips the
        // overlay on (and mpv's own rendering off) immediately.
        if (karaokeMode) unawaited(_applySubVisibility());
        notifyListeners();
      }),
    ];
    // libmpv stays at 100%: loudness is driven by the DEVICE media volume
    // (MX Player / VLC style) so the swipe can always reach the phone's
    // true maximum, no matter where the system volume started.
    player.setVolume(100);
    // Play/pause from the picture-in-picture window's own button.
    NativeBridge.configureCallbacks(onPipAction: togglePlay);
    _init();
    // Persist the resume point + watch time every few seconds.
    _bookmarkTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _saveBookmark();
      _trackWatchTime();
    });
    // v19: guaranteed UI pulse - the mini player / scrub bar / time labels
    // keep ticking even if the position stream coalesces (the home-screen
    // mini player's progress bar looked frozen because of that).
    _uiTicker = Timer.periodic(const Duration(milliseconds: 500), (_) {
      // v22: also pulse while a sleep timer runs so the under-title
      // countdown keeps counting even when playback is paused.
      if (!isPlaying && !sleepTimerActive) return;
      final p = player.state.position;
      if (p != position || sleepTimerActive) {
        position = p;
        _maybeCaptureThumb(p);
        notifyListeners();
      }
    });
    _startLiveSubObserver();
  }

  Future<void> _init() async {
    await _ensureHistoryLoaded();
    final s = await NativeBridge.loadSettings();
    // Restore today's accumulated watch time (+ the v27 per-video totals).
    _todayStatsKey = statsKeyFor(DateTime.now());
    _watchTodaySecs = int.tryParse(s[_todayStatsKey] ?? '') ?? 0;
    try {
      final raw = s[_kWatchByVideoKey] ?? '';
      if (raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          _watchByVideo = {
            for (final e in decoded.entries)
              if (e.value is num) '${e.key}': (e.value as num).toInt(),
          };
        }
      }
    } catch (_) {
      _watchByVideo = const {}; // corrupt payload -> start fresh
    }
    // Restore equalizer.
    eqEnabled = s[_kEqEnabledKey] == 'true';
    final gainsRaw = (s[_kEqGainsKey] ?? '').split(',');
    for (var i = 0; i < eqFrequencies.length && i < gainsRaw.length; i++) {
      eqGains[i] = double.tryParse(gainsRaw[i]) ?? 0;
    }
    if (eqEnabled) _applyEqFilter();
  }

  // ---------------------------------------------------------------------------
  // Watch history
  // ---------------------------------------------------------------------------

  Future<void> _ensureHistoryLoaded() async {
    if (_historyLoaded) return;
    _historyLoaded = true;
    try {
      final s = await NativeBridge.loadSettings();
      final raw = s[_kHistoryKey];
      if (raw == null || raw.isEmpty) return;
      final list = jsonDecode(raw) as List<dynamic>;
      _history
        ..clear()
        ..addAll([
          for (final e in list)
            HistoryEntry.fromJson(Map<String, dynamic>.from(e as Map)),
        ]);
      notifyListeners();
    } catch (_) {
      // Corrupt payload -> start with an empty history.
    }
  }

  void _persistHistory() {
    final capped = _history.length > _kHistoryMax
        ? _history.sublist(0, _kHistoryMax)
        : _history;
    NativeBridge.saveSetting(
      _kHistoryKey,
      jsonEncode([for (final e in capped) e.toJson()]),
    );
  }

  HistoryEntry? _historyEntryFor(String path) {
    for (final e in _history) {
      if (e.path == path) return e;
    }
    return null;
  }

  /// Move the just-opened video to the top of the history, preserving its
  /// previous resume position.
  Future<void> _recordOpen(VideoTrack track) async {
    try {
      await _ensureHistoryLoaded();
      final prevPos = _historyEntryFor(track.path)?.lastPositionSecs ?? 0;
      _history.removeWhere((e) => e.path == track.path);
      _history.insert(
        0,
        HistoryEntry(
          path: track.path,
          title: track.title,
          thumbnailPath: track.thumbnailPath,
          durationSecs: track.duration?.inSeconds ?? 0,
          lastPositionSecs: prevPos,
          playedAtMs: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      _persistHistory();
      notifyListeners();
    } catch (_) {}
  }

  void clearHistory() {
    _history.clear();
    _persistHistory();
    notifyListeners();
  }

  void removeHistoryEntry(String path) {
    _history.removeWhere((e) => e.path == path);
    _persistHistory();
    notifyListeners();
  }

  /// Play a single video straight from a history row.
  Future<void> playHistoryEntry(HistoryEntry entry) async {
    final track = VideoTrack(
      id: entry.path,
      title: entry.title,
      path: entry.path,
      thumbnailPath: entry.thumbnailPath,
      duration: entry.durationSecs > 0
          ? Duration(seconds: entry.durationSecs)
          : null,
    );
    await setPlaylistAndPlay([track], 0);
  }

  /// Play a network stream URL (http/https/rtsp/rtmp). Handled directly by
  /// libmpv - the local-file metadata pipeline is skipped upstream.
  Future<void> playStream(String url, String title) async {
    final track = VideoTrack(id: url, title: title, path: url);
    await setPlaylistAndPlay([track], 0);
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
  Future<void> setPlaylistAndPlay(
    List<VideoTrack> videos, [
    int startIndex = 0,
  ]) async {
    playlist = videos;
    currentIndex = startIndex.clamp(0, videos.isEmpty ? 0 : videos.length - 1);
    notifyListeners();
    await _loadCurrent(autoplay: true);
  }

  /// v30: "+" in the playlist sheet - appends the picked videos to the
  /// current queue without changing what is playing. Duplicates are
  /// skipped. The player keeps showing only the playlist: previous/next
  /// never leave these entries.
  void addToPlaylist(List<VideoTrack> videos) {
    final merged = mergeQueueVideos(playlist, videos);
    if (merged.length == playlist.length) return;
    playlist = merged;
    // The shuffle order is keyed to queue positions - rebuild it so the
    // new entries become reachable in shuffle mode too.
    if (isShuffled) {
      _shuffledOrder = _generateShuffledOrder(playlist.length, currentIndex);
    }
    notifyListeners();
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
    // A new file invalidates any A-B loop points from the previous one.
    loopA = null;
    loopB = null;
    final plat = player.platform;
    if (plat is NativePlayer) {
      // Head-room for the 200% volume boost + re-apply the current gain /
      // leveling filter for the new file.
      unawaited(plat.setProperty('volume-max', '200'));
      // Force the sub-visibility to be re-pushed for the new file (mpv may
      // reset it at open, while our cache would think it's still applied).
      _appliedSubVisibility = null;
    }
    await player.open(Media(track.path), play: autoplay);
    await player.setRate(playbackRate);
    await _applyMpvVolume();
    await _applyAudioFilters(); // equalizer + leveling survive file changes
    await _attachSidecarSubtitles(track.path);
    await _recordOpen(track);
    await _restoreBookmark(track);
    // v25: re-verify karaoke's subtitle hiding after the demuxer settles -
    // the track listener can fire before the subtitle selection is known.
    if (karaokeMode) {
      Future<void>.delayed(const Duration(milliseconds: 800), () {
        _appliedSubVisibility = null; // force a fresh push (engine may reset)
        _applySubVisibility();
      });
    }
    // v22: if this file has no cached thumbnail AND Android's metadata
    // engine could not make one, remember it - after ~1.5 s of playback a
    // frame is captured through mpv instead (see _maybeCaptureThumb).
    _pendingThumbFor =
        (track.thumbnailPath == null && !track.path.contains('://'))
        ? track.path
        : null;
  }

  /// Re-attaches previously generated AI subtitles ("<video>.maxai.srt"
  /// next to the video) so they survive closing/reopening the app - they
  /// are written to disk, only the player session forgot them.
  /// v21: cues of the AI sidecar currently attached (null when none or the
  /// file is a stream). Feeds the karaoke word-highlight overlay.
  List<SrtCue>? aiCues;

  /// v22: cues parsed from the video's OWN same-name subtitle file
  /// ("movie.srt", "movie.en.srt" - the files mpv auto-loads). Used when
  /// there is no AI sidecar, so karaoke + skip-intro work on ordinary
  /// subtitled videos too.
  List<SrtCue>? sidecarCues;

  /// v21 skip-intro chip: where the dialogue actually starts, when
  /// subtitles (AI sidecar or same-name .srt) show speech begins
  /// noticeably late (see computeSkipIntro).
  Duration? skipIntroAt;

  Future<void> _attachSidecarSubtitles(String videoPath) async {
    aiCues = null;
    sidecarCues = null;
    skipIntroAt = null;
    liveSubCue = null;
    if (videoPath.contains('://')) return; // no sidecars for streams
    final platform = player.platform;
    if (platform is! NativePlayer) return;
    try {
      final srt = srtPathForVideo(videoPath);
      if (File(srt).existsSync()) {
        // "select" makes it the active track right away.
        await platform.command(['sub-add', srt, 'select']);
        await refreshAiCues(videoPath);
      }
    } catch (_) {
      // Missing/unreadable sidecar is not fatal.
    }
    // v22: no AI captions -> look for the video's own subtitle file and
    // use it as the skip-intro + karaoke source instead.
    if (aiCues == null) {
      try {
        final cues = await _loadSidecarCues(videoPath);
        if (cues != null && cues.isNotEmpty) sidecarCues = cues;
      } catch (_) {
        // An unreadable sibling file must never break playback.
      }
    }
    _recomputeSkipIntro();
    await _applySubVisibility();
    notifyListeners();
  }

  /// Parses the best same-name .srt sitting next to [videoPath], if any.
  Future<List<SrtCue>?> _loadSidecarCues(String videoPath) async {
    final dir = Directory(p.dirname(videoPath));
    if (!dir.existsSync()) return null;
    final names = <String>[];
    await for (final e in dir.list(followLinks: false)) {
      if (e is File) names.add(p.basename(e.path));
    }
    final candidates = sidecarSrtCandidates(names, videoPath);
    if (candidates.isEmpty) return null;
    final cues = parseSrt(
      await File(p.join(dir.path, candidates.first)).readAsString(),
    );
    return cues.isEmpty ? null : cues;
  }

  void _recomputeSkipIntro() {
    // AI captions win (word-accurate); same-name .srt is the fallback.
    final cues = aiCues ?? sidecarCues;
    skipIntroAt = cues == null ? null : computeSkipIntro(cues);
  }

  /// (Re)parses the AI sidecar for karaoke + skip-intro. Called when a track
  /// attaches its sidecar, and by the AI runner right after it finishes
  /// writing new subtitles.
  Future<void> refreshAiCues(String videoPath) async {
    aiCues = null;
    if (videoPath.contains('://')) return;
    try {
      final srt = File(srtPathForVideo(videoPath));
      if (!srt.existsSync()) return;
      final cues = parseSrt(await srt.readAsString());
      if (cues.isEmpty) return;
      aiCues = cues;
    } catch (_) {
      // A corrupt sidecar must never break playback.
    }
    _recomputeSkipIntro();
    await _applySubVisibility();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Karaoke mode + live subtitle reading (v22)
  // ---------------------------------------------------------------------------

  /// Whether karaoke rendering is enabled (mirrors the player setting).
  bool karaokeMode = false;

  /// The subtitle line mpv is showing RIGHT NOW (from its `sub-text` /
  /// `sub-start` / `sub-end` properties), with real cue timing. This makes
  /// karaoke work with ANY subtitle - embedded mkv tracks included - not
  /// just ones we can parse as files.
  SrtCue? liveSubCue;

  /// Last sub-visibility value we pushed to mpv (avoids redundant sets).
  String? _appliedSubVisibility;

  Future<void> _startLiveSubObserver() async {
    final platform = player.platform;
    if (platform is! NativePlayer) return;
    try {
      await platform.observeProperty('sub-text', (text) async {
        final plat = player.platform;
        if (text.trim().isEmpty || plat is! NativePlayer) {
          if (liveSubCue != null) {
            liveSubCue = null;
            notifyListeners();
          }
          return;
        }
        var startMs = 0;
        var endMs = 0;
        try {
          startMs =
              ((double.tryParse(await plat.getProperty('sub-start')) ?? 0) *
                      1000)
                  .round();
          endMs =
              ((double.tryParse(await plat.getProperty('sub-end')) ?? 0) * 1000)
                  .round();
        } catch (_) {}
        if (endMs <= startMs) endMs = startMs + 2000; // sane fallback
        final clean = text.replaceAll(RegExp(r'\s+'), ' ').trim();
        liveSubCue = isMusicOnlyText(clean)
            ? null
            : SrtCue(startMs, endMs, clean);
        notifyListeners();
      });
    } catch (_) {
      // Older engine - karaoke simply falls back to parsed cue files.
    }
  }

  /// Player-settings-driven: turn karaoke mode on/off. Hides mpv's own
  /// subtitle rendering (our overlay takes over) whenever a usable
  /// subtitle source exists.
  Future<void> setKaraokeMode(bool on) async {
    karaokeMode = on;
    await _applySubVisibility();
  }

  Future<void> _applySubVisibility() async {
    final platform = player.platform;
    if (platform is! NativePlayer) return;
    final hide =
        karaokeMode &&
        (subtitlesActive || aiCues != null || sidecarCues != null);
    final want = hide ? 'no' : 'yes';
    if (want == _appliedSubVisibility) return;
    _appliedSubVisibility = want;
    // v25 hardening (user report: the normal subtitle line stayed visible
    // next to karaoke): verify the property actually flipped; on engines
    // where setProperty silently no-ops, issue the raw mpv command too.
    try {
      await platform.setProperty('sub-visibility', want);
      final applied = await platform.getProperty('sub-visibility');
      if (applied != want) {
        await platform.command(['set', 'sub-visibility', want]);
      }
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // 4K/HDR thumbnail fallback (v22)
  //
  // Android's MediaMetadataRetriever gives up on some 4K/HDR (10-bit HEVC,
  // certain mkv) files, so their library tiles stayed placeholder-grey.
  // mpv plays those same files fine - so once such a video has been playing
  // for ~1.5 s we ask mpv for a frame and write it to the exact cache file
  // the native scanner uses, then shrink it to the standard 320px width.
  // ---------------------------------------------------------------------------

  /// Video awaiting a playback-captured thumbnail.
  String? _pendingThumbFor;

  /// Wired by main.dart: (videoPath, thumbPath) -> live-updates the
  /// library tile so the image appears without a rescan.
  void Function(String videoPath, String thumbPath)? onThumbnailCaptured;

  void _maybeCaptureThumb(Duration pos) {
    final path = _pendingThumbFor;
    if (path == null || pos < const Duration(milliseconds: 1500)) return;
    _pendingThumbFor = null;
    unawaited(_captureThumbWithMpv(path));
  }

  Future<void> _captureThumbWithMpv(String videoPath) async {
    try {
      final platform = player.platform;
      if (platform is! NativePlayer) return;
      final target = await NativeBridge.thumbnailPathFor(videoPath);
      if (target == null) return;
      final thumb = File(target);
      if (thumb.existsSync()) return; // scanner beat us to it meanwhile
      final tmp = File('$target.capture');
      if (tmp.existsSync()) await tmp.delete();
      await platform.setProperty('screenshot-format', 'jpg');
      await platform.setProperty('screenshot-jpeg-quality', '82');
      await platform.command(['screenshot-to-file', tmp.path, 'video']);
      // mpv encodes the shot asynchronously - wait briefly for the file.
      for (var i = 0; i < 25; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        if (tmp.existsSync() && tmp.lengthSync() > 0) break;
      }
      if (!tmp.existsSync() || tmp.lengthSync() == 0) return;
      // A 4K screenshot decodes to a ~33 MB bitmap; shrink to the same
      // 320px width the native scanner writes, so scrolling the library
      // never decodes a giant image.
      final data = await tmp.readAsBytes();
      final codec = await ui.instantiateImageCodec(data, targetWidth: 320);
      final frame = await codec.getNextFrame();
      final png = await frame.image.toByteData(format: ui.ImageByteFormat.png);
      frame.image.dispose();
      codec.dispose();
      if (png == null) return;
      await thumb.writeAsBytes(png.buffer.asUint8List(), flush: true);
      await tmp.delete();
      onThumbnailCaptured?.call(videoPath, target);
    } catch (_) {
      // Worst case: the tile keeps its movie-icon placeholder.
    }
  }

  // ---------------------------------------------------------------------------
  // Sleep timer (v21)
  // ---------------------------------------------------------------------------

  Timer? _sleepTimer;
  DateTime? _sleepFireAt;
  bool _sleepAtEndOfVideo = false;

  bool get sleepTimerActive => _sleepFireAt != null || _sleepAtEndOfVideo;

  /// Short label for menus ("12 min" / "end of video"); null when inactive.
  String? get sleepTimerLabel {
    if (_sleepAtEndOfVideo) return 'end of video';
    final at = _sleepFireAt;
    if (at == null) return null;
    final left = at.difference(DateTime.now()).inSeconds;
    if (left <= 0) return null;
    return '${(left + 30) ~/ 60} min'; // rounded while counting down
  }

  /// v22: precise live countdown for the player top bar ("23:41" or
  /// "end of video"); null when no timer runs. The state pulses every
  /// 500 ms while a timer is active, so this ticks visibly.
  String? get sleepTimerCountdown {
    if (_sleepAtEndOfVideo) return 'end of video';
    final at = _sleepFireAt;
    if (at == null) return null;
    final left = at.difference(DateTime.now());
    return left.inSeconds <= 0 ? null : formatCountdown(left.inSeconds);
  }

  void setSleepTimer({Duration? forDuration, bool atEndOfVideo = false}) {
    cancelSleepTimer();
    if (atEndOfVideo) {
      _sleepAtEndOfVideo = true;
    } else if (forDuration != null) {
      _sleepFireAt = DateTime.now().add(forDuration);
      _sleepTimer = Timer(forDuration, _fireSleepTimer);
    }
    notifyListeners();
  }

  void cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepFireAt = null;
    _sleepAtEndOfVideo = false;
    notifyListeners();
  }

  Future<void> _fireSleepTimer() async {
    cancelSleepTimer();
    _notices.add('Sleep timer paused playback');
    await pause();
  }

  void _checkSleepAtEnd(Duration pos) {
    if (!_sleepAtEndOfVideo || duration <= Duration.zero) return;
    if (duration - pos <= const Duration(milliseconds: 1500)) {
      cancelSleepTimer();
      _notices.add('Sleep timer: stopped at end of video');
      pause();
    }
  }

  /// Jump to where the user left off last time this file was open. The saved
  /// position lives in the watch history; honours the "Resume playback"
  /// player setting.
  Future<void> _restoreBookmark(VideoTrack track) async {
    try {
      final settings = await NativeBridge.loadSettings();
      if (settings[PlayerSettings.kResumePlayback] == 'false') return;
      final secs = _historyEntryFor(track.path)?.lastPositionSecs ?? 0;
      if (secs < 10) return; // ignore tiny offsets

      var d = duration;
      if (d == Duration.zero) {
        // Wait briefly for the demuxer to report the length.
        d = await player.stream.duration
            .firstWhere((v) => v > Duration.zero)
            .timeout(
              const Duration(seconds: 3),
              onTimeout: () => Duration.zero,
            );
      }
      if (d == Duration.zero) return;
      // Almost-finished videos start from the beginning again.
      if (secs >= d.inSeconds - 15) {
        final e = _historyEntryFor(track.path);
        if (e != null) {
          e.lastPositionSecs = 0;
          _persistHistory();
        }
        return;
      }
      // User may have switched tracks while we waited.
      if (currentTrack?.path != track.path) return;
      await player.seek(Duration(seconds: secs));
      _notices.add('Resumed ${formatDuration(Duration(seconds: secs))}');
    } catch (_) {
      // Resume is best-effort.
    }
  }

  void _saveBookmark() {
    final track = currentTrack;
    if (track == null || !isPlaying) return;
    final secs = position.inSeconds;
    if (secs <= 0) return;
    final entry = _historyEntryFor(track.path);
    if (entry != null && entry.lastPositionSecs != secs) {
      entry.lastPositionSecs = secs;
      _persistHistory();
    }
  }

  // ---------------------------------------------------------------------------
  // Brightness (left-half swipe in the player)
  // ---------------------------------------------------------------------------

  /// Reads the current override once so the first drag starts from the real
  /// screen brightness instead of a guess.
  Future<double> currentBrightness() async {
    if (!_brightnessSynced) {
      brightness = await NativeBridge.getBrightness();
      _brightnessSynced = true;
      notifyListeners();
    }
    return brightness;
  }

  Future<void> setBrightness(double v) async {
    brightness = v.clamp(0.0, 1.0);
    notifyListeners();
    await NativeBridge.setBrightness(brightness);
  }

  Future<void> resetBrightness() async {
    brightness = 1.0;
    _brightnessSynced = false;
    notifyListeners();
    await NativeBridge.resetBrightness();
  }

  Future<void> togglePlay() async {
    // v19: optimistic UI - flip the icon instantly; the playing stream
    // confirms (or corrects) a moment later. Kills the visible tap->icon
    // lag that made the play/pause button feel delayed.
    final wantPlay = !isPlaying;
    isPlaying = wantPlay;
    notifyListeners();
    if (wantPlay) {
      await player.play();
    } else {
      await pause();
    }
  }

  /// Unconditional resume (used when handing playback back from a TV cast
  /// session - togglePlay would pause if the user already resumed).
  Future<void> resumePlayback() => player.play();

  /// Saves the CURRENT video frame exactly as shown (subtitles included)
  /// as a PNG into /storage/emulated/0/Pictures/Max Player and registers it
  /// with the media scanner so gallery apps see it immediately.
  ///
  /// Returns the saved path, or null when there is nothing to capture
  /// (no video, or a network stream) or the capture failed.
  Future<String?> captureScreenshot() async {
    final track = currentTrack;
    if (track == null) return null;
    if (track.path.startsWith('http')) return null; // stream: nothing on disk
    final platform = player.platform;
    if (platform is! NativePlayer) return null;
    try {
      final dir = Directory('/storage/emulated/0/Pictures/Max Player');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final out =
          '${dir.path}/MaxPlayer_${DateTime.now().millisecondsSinceEpoch}.png';
      // libmpv command; plain (non-async) screenshot-to-file blocks mpv's
      // core until the PNG is written, then we verify from Dart.
      await platform.command(['screenshot-to-file', out]);
      final f = File(out);
      for (var i = 0; i < 20; i++) {
        if (f.existsSync() && f.lengthSync() > 0) {
          await NativeBridge.scanFile(out);
          return out;
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> pause() async {
    // v20: pause FIRST so the video freezes instantly. The previous order
    // (boost cleanup + bookmark disk write BEFORE pausing) added a visible
    // delay between tapping pause and the video actually stopping.
    await player.pause();
    // Pausing always ends an active long-press boost (and its badge).
    await stopSpeedBoost();
    _saveBookmark();
  }

  Future<void> seek(Duration to) => player.seek(to);

  /// Relative seek (e.g. ±10s), clamped to the media bounds.
  Future<void> seekBy(int seconds) async {
    if (currentTrack == null) return;
    var target = position + Duration(seconds: seconds);
    if (target < Duration.zero) target = Duration.zero;
    if (duration > Duration.zero && target > duration) target = duration;
    await player.seek(target);
  }

  // ---------------------------------------------------------------------------
  // Volume (device MEDIA volume, MX Player / VLC style)
  // ---------------------------------------------------------------------------

  bool _volumeSynced = false;
  double _preMuteVolume = 0.5;

  /// Reads the real device media volume once so the player swipe starts
  /// from the true level (mirrors [currentBrightness]).
  Future<double> currentVolume() async {
    if (!_volumeSynced) {
      volume = await NativeBridge.getMediaVolume();
      isMuted = volume <= 0;
      _volumeSynced = true;
      notifyListeners();
    }
    return volume;
  }

  /// v21: when the setting is on, the volume range becomes 0..200%.
  /// The device volume covers 0..100%; mpv's decoder gain (volume-max=200
  /// is set when a track opens) covers the 100..200% boost region.
  bool volumeBoost200 = false;

  /// Current volume upper limit for the swipe gesture / slider math.
  double get volumeCap => volumeBoost200 ? 2.0 : 1.0;

  Future<void> setVolume(double v) async {
    volume = v.clamp(0.0, volumeCap);
    if (volume > 0) {
      isMuted = false;
      _preMuteVolume = volume;
    }
    await NativeBridge.setMediaVolume(isMuted ? 0 : volume.clamp(0.0, 1.0));
    await _applyMpvVolume();
    notifyListeners();
  }

  Future<void> _applyMpvVolume() async {
    final platform = player.platform;
    if (platform is! NativePlayer) return;
    final pct = volume <= 1 ? 100.0 : volume * 100.0;
    try {
      await platform.setProperty('volume', pct.toStringAsFixed(0));
    } catch (_) {}
  }

  /// Settings toggle: enable/disable the 200% boost region. Turning it off
  /// while boosted pulls the volume back to 100%.
  Future<void> setVolumeBoost200(bool on) async {
    volumeBoost200 = on;
    if (!on && volume > 1.0) await setVolume(1.0);
    if (!on) await _applyMpvVolume();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Volume leveling (v21) - mpv dynaudnorm: quiet dialogue and loud
  // explosions come out at a steady level.
  // v22: merged with the equalizer into ONE mpv `af` chain (both used to
  // overwrite the whole property, silently cancelling each other), the
  // window was widened so the effect is actually audible, and the applied
  // chain is read back once - if this engine build lacks dynaudnorm the
  // user is told instead of the toggle doing nothing.
  // ---------------------------------------------------------------------------

  static const String kLevelingFilter = 'dynaudnorm=f=150:g=15:m=5:p=0.95';
  bool _levelingOn = false;
  bool _levelingWarned = false;
  bool get volumeLeveling => _levelingOn;

  Future<void> setVolumeLeveling(bool on) async {
    _levelingOn = on;
    notifyListeners();
    await _applyAudioFilters();
  }

  /// v32: mpv tone-mapping curve for HDR sources ("How does an HDR10 or
  /// Dolby Vision file render on this screen"). Values validated in
  /// PlayerSettings - anything unknown becomes 'auto' upstream.
  Future<void> setToneMapping(String mode) async {
    final plat = player.platform;
    if (plat is! NativePlayer) return;
    try {
      await plat.setProperty('tone-mapping', mode);
    } catch (_) {}
  }

  /// v32: real-time picture enhancement. The shader is a tiny one-pass
  /// sharpen+contrast+vibrance GLSL hook (assets/shaders/mx_enhance.glsl)
  /// written to a cache file and given to mpv via glsl-shaders. Off simply
  /// clears the list. Any failure (missing shader, old output driver) is
  /// silent - playback continues untouched.
  Future<void> setEnhanceVideo(bool on) async {
    final plat = player.platform;
    if (plat is! NativePlayer) return;
    try {
      if (!on) {
        await plat.setProperty('glsl-shaders', '');
        return;
      }
      const asset = 'assets/shaders/mx_enhance.glsl';
      final src = await rootBundle.loadString(asset);
      final f = File('${Directory.systemTemp.path}/mx_enhance.glsl');
      if (!f.existsSync() || await f.readAsString() != src) {
        await f.writeAsString(src, flush: true);
      }
      await plat.setProperty('glsl-shaders', f.path);
    } catch (_) {}
  }

  /// The single writer of mpv's `af` property: equalizer bands + leveling
  /// combined. Replaces the old pair of writers that clobbered each other.
  Future<void> _applyAudioFilters() async {
    final platform = player.platform;
    if (platform is! NativePlayer) return;
    final chain = <String>[
      if (eqEnabled) buildEqualizerFilter(eqGains),
      if (_levelingOn) kLevelingFilter,
    ].join(',');
    try {
      await platform.setProperty('af', chain);
      if (_levelingOn && !_levelingWarned) {
        final applied = await platform.getProperty('af');
        if (!applied.contains('dynaudnorm')) {
          _levelingWarned = true;
          _notices.add(
            'Volume leveling is not supported by this video engine build',
          );
        }
      }
    } catch (_) {}
  }

  Future<void> toggleMute() async {
    if (isMuted) {
      isMuted = false;
      if (volume <= 0) volume = _preMuteVolume;
      await NativeBridge.setMediaVolume(volume);
    } else {
      if (volume > 0) _preMuteVolume = volume;
      isMuted = true;
      await NativeBridge.setMediaVolume(0);
    }
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

  // ---------------------------------------------------------------------------
  // A-B loop
  // ---------------------------------------------------------------------------

  /// Button callback: 1st tap sets A, 2nd sets B (loop starts), 3rd clears.
  /// Returns a short message for the on-screen indicator.
  String tapLoopPoint() {
    if (loopA == null) {
      loopA = position;
      notifyListeners();
      return 'A set ${formatDuration(position)}';
    }
    if (loopB == null) {
      // Ignore a B that's not after A (user double-tapped by accident).
      if (position <= loopA! + const Duration(seconds: 1)) {
        loopA = position;
        notifyListeners();
        return 'A set ${formatDuration(position)}';
      }
      loopB = position;
      notifyListeners();
      return 'Looping ${formatDuration(loopA!)} → ${formatDuration(loopB!)}';
    }
    loopA = null;
    loopB = null;
    notifyListeners();
    return 'A-B loop cleared';
  }

  // ---------------------------------------------------------------------------
  // Long-press speed boost (customizable multiplier)
  // ---------------------------------------------------------------------------

  Future<void> startSpeedBoost(double multiplier) async {
    if (_preBoostRate != null) return; // already boosting
    if (!isPlaying) return; // no boost/badge while paused
    _preBoostRate = playbackRate;
    playbackRate = multiplier;
    await player.setRate(multiplier);
    notifyListeners();
  }

  Future<void> stopSpeedBoost() async {
    final restore = _preBoostRate;
    if (restore == null) return;
    _preBoostRate = null;
    playbackRate = restore;
    await player.setRate(restore);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Equalizer (libmpv `af` lavfi chain)
  // ---------------------------------------------------------------------------

  static const String _kEqEnabledKey = 'eq.enabled';
  static const String _kEqGainsKey = 'eq.gains';

  /// Builds the lavfi audio-filter chain, skipping bands at 0 dB.
  /// Pure + testable.
  static String buildEqualizerFilter(List<double> gains) {
    final parts = <String>[];
    for (var i = 0; i < eqFrequencies.length && i < gains.length; i++) {
      if (gains[i] == 0) continue;
      parts.add(
        'equalizer=f=${eqFrequencies[i]}:t=q:w=1.0:g=${gains[i].toStringAsFixed(1)}',
      );
    }
    return parts.isEmpty ? '' : 'lavfi=[${parts.join(',')}]';
  }

  Future<void> applyEqualizer(List<double> gains, bool enabled) async {
    eqGains = List.of(gains);
    eqEnabled = enabled;
    NativeBridge.saveSetting(_kEqEnabledKey, '$enabled');
    NativeBridge.saveSetting(
      _kEqGainsKey,
      gains.map((g) => g.toStringAsFixed(1)).join(','),
    );
    notifyListeners();
    await _applyEqFilter();
  }

  Future<void> _applyEqFilter() => _applyAudioFilters(); // v22: shared chain

  // ---------------------------------------------------------------------------
  // Watch-time stats
  // ---------------------------------------------------------------------------

  /// Persisted key for a day bucket, e.g. stats.20260811. Pure + testable.
  static String statsKeyFor(DateTime d) =>
      'stats.${d.year * 10000 + d.month * 100 + d.day}';

  void _trackWatchTime() {
    if (!isPlaying) return;
    final key = statsKeyFor(DateTime.now());
    if (key != _todayStatsKey) {
      // Day rolled over while playing.
      _todayStatsKey = key;
      _watchTodaySecs = 0;
    }
    _watchTodaySecs += 5;
    NativeBridge.saveSetting(key, '$_watchTodaySecs');
    // v27: per-video totals for the "Most watched" list (same 5s tick,
    // trimmed to the heaviest entries so the stored blob stays tiny).
    final path = currentTrack?.path;
    if (path != null) {
      final map = Map<String, int>.of(_watchByVideo);
      map[path] = (map[path] ?? 0) + 5;
      if (map.length > _kWatchByVideoMax) {
        final sorted = map.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        map
          ..clear()
          ..addEntries(sorted.take(_kWatchByVideoMax));
      }
      _watchByVideo = map;
      NativeBridge.saveSetting(_kWatchByVideoKey, jsonEncode(map));
    }
  }

  /// Last 7 days of watch time (index 0 = 6 days ago, last = today).
  Future<List<WatchDay>> getWeekStats() async {
    final s = await NativeBridge.loadSettings();
    final now = DateTime.now();
    final todayKey = statsKeyFor(now);
    final days = <WatchDay>[];
    for (var i = 6; i >= 0; i--) {
      final d = now.subtract(Duration(days: i));
      final key = statsKeyFor(d);
      var secs = int.tryParse(s[key] ?? '') ?? 0;
      if (key == todayKey && _watchTodaySecs > secs) secs = _watchTodaySecs;
      days.add(WatchDay(d, secs));
    }
    return days;
  }

  /// v27 advanced stats: total watch seconds over the last [days] days
  /// (including today's in-progress count).
  Future<int> getWatchSecondsForLastDays(int days) async {
    final s = await NativeBridge.loadSettings();
    final now = DateTime.now();
    final todayKey = statsKeyFor(now);
    var total = 0;
    for (var i = days - 1; i >= 0; i--) {
      final key = statsKeyFor(now.subtract(Duration(days: i)));
      var secs = int.tryParse(s[key] ?? '') ?? 0;
      if (key == todayKey && _watchTodaySecs > secs) secs = _watchTodaySecs;
      total += secs;
    }
    return total;
  }

  /// v27: how many days IN A ROW something was watched (today counts when
  /// already non-zero; the chain may start yesterday and still count).
  Future<int> getWatchStreakDays() async {
    final s = await NativeBridge.loadSettings();
    final now = DateTime.now();
    final todayKey = statsKeyFor(now);
    final todaySecs = _watchTodaySecs > (int.tryParse(s[todayKey] ?? '') ?? 0)
        ? _watchTodaySecs
        : (int.tryParse(s[todayKey] ?? '') ?? 0);
    var streak = 0;
    var offset = todaySecs > 0
        ? 0
        : 1; // no watching today yet -> start yesterday
    while (true) {
      final key = statsKeyFor(now.subtract(Duration(days: offset)));
      final secs = int.tryParse(s[key] ?? '') ?? 0;
      if (secs <= 0) break;
      streak++;
      offset++;
      if (offset > 3650) break; // paranoia guard
    }
    return streak;
  }

  /// v27: the [limit] most-watched videos (path -> total seconds),
  /// heaviest first. Uses the in-memory map restored in [_init].
  List<MapEntry<String, int>> getTopWatchedVideos({int limit = 5}) {
    final entries = _watchByVideo.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.take(limit).toList();
  }

  /// Display title for a path: the history entry's title when known,
  /// else the file name.
  String titleForPath(String path) {
    for (final e in _history) {
      if (e.path == path) return e.title;
    }
    return path.split('/').last;
  }

  // ---------------------------------------------------------------------------
  // Scrub preview thumbnail strip (v19)
  // ---------------------------------------------------------------------------

  /// Frames generated per video - must match the native generator
  /// (MainActivity.thumbStripEnsureSync).
  static const int thumbStripCount = 72;

  String? _thumbStripFor;
  String? _thumbStripDir;

  void _ensureThumbStrip() {
    final track = currentTrack;
    if (track == null) return;
    final path = track.path;
    if (path.startsWith('http')) return; // streams: nothing on disk to scan
    if (_thumbStripFor == path) return; // already requested for this file
    _thumbStripFor = path;
    _thumbStripDir = null;
    NativeBridge.thumbStripEnsure(path).then((dir) {
      if (dir != null && _thumbStripFor == path) {
        _thumbStripDir = dir;
        notifyListeners();
      }
    });
  }

  /// Thumbnail file for the preview bubble at [fraction] (0..1 of the
  /// video), or null while that frame hasn't been generated yet (the
  /// bubble then shows the timestamp only).
  String? scrubThumbPath(double fraction) {
    final dir = _thumbStripDir;
    if (dir == null) return null;
    final i = (fraction.clamp(0.0, 1.0) * (thumbStripCount - 1)).round();
    final f = File('$dir/f_${i.toString().padLeft(3, '0')}.jpg');
    return f.existsSync() ? f.path : null;
  }

  // ---------------------------------------------------------------------------
  // Mini player
  // ---------------------------------------------------------------------------

  /// Dismisses the mini player: clears the queue and stops playback.
  Future<void> stopMini() async {
    playlist = [];
    currentIndex = 0;
    notifyListeners();
    await player.stop();
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
    // Completed video: reset its saved position so it replays from the start.
    final track = currentTrack;
    if (track != null) {
      final e = _historyEntryFor(track.path);
      if (e != null) {
        e.lastPositionSecs = 0;
        _persistHistory();
      }
    }
    if (repeatMode == RepeatMode.one) {
      await player.seek(Duration.zero);
      await player.play();
    } else if (repeatMode == RepeatMode.all ||
        currentIndex < playlist.length - 1) {
      await nextTrack();
    }
  }

  @override
  void dispose() {
    _uiTicker?.cancel();
    _bookmarkTimer?.cancel();
    _notices.close();
    for (final s in _subs) {
      s.cancel();
    }
    player.dispose();
    super.dispose();
  }
}

/// One day of watch time for the stats screen.
class WatchDay {
  final DateTime day;
  final int seconds;
  const WatchDay(this.day, this.seconds);
}
EOF_MARKER_7

mkdir -p "$(dirname 'lib/state/player_settings.dart')"
cat > 'lib/state/player_settings.dart' <<'EOF_MARKER_8'
import '../services/native_bridge.dart';

/// Immutable snapshot of the customizable player settings (gestures, auto
/// hide, resume). Persisted through the native settings store so only plain
/// key/value strings cross the MethodChannel - no extra plugin deps.
class PlayerSettings {
  final bool doubleTapSeek;
  final int seekSeconds;
  final bool doubleTapPlayPause;
  final bool volumeSwipe;
  final bool brightnessSwipe;
  final bool pinchZoom;

  /// Hold a finger on the video to temporarily play faster.
  final bool longPressSpeed;

  /// Multiplier applied while long-pressing (1.5 / 2.0 / 2.5 / 3.0).
  final double longPressMultiplier;

  /// Seconds of inactivity before the controls vanish. 0 = never auto-hide.
  final int autoHideSeconds;

  /// Reopen a video where you left off (backed by the watch history).
  final bool resumePlayback;

  /// Drag horizontally anywhere on the video to scrub through it.
  final bool horizontalSeek;

  /// Show the "Cast to TV" (DLNA) button in the player top bar.
  final bool castButton;

  /// Show the screenshot button in the player top bar.
  final bool screenshotButton;

  /// Show the screen-lock (kids mode) button on the video.
  final bool lockButton;

  /// v21: playback extras.
  /// Volume slider/drag may go past 100% up to 200% (mpv decoder gain).
  final bool volumeBoost200;

  /// mpv dynaudnorm: loud explosions and quiet dialogue evened out.
  final bool volumeLeveling;

  /// Karaoke-style word highlight for AI subtitles.
  final bool karaokeSubs;

  /// Offer a "Skip intro" chip when AI subtitles show the dialogue starts
  /// noticeably after the video start.
  final bool skipIntroChip;

  /// v32: real-time picture enhancement (GPU sharpen + contrast + vibrance
  /// shader, assets/shaders/mx_enhance.glsl).
  final bool enhanceVideo;

  /// v32: mpv tone-mapping curve for HDR sources ('auto' | 'clip' |
  /// 'mobius' | 'hable' | 'bt.2390').
  final String toneMapping;

  const PlayerSettings({
    this.doubleTapSeek = true,
    this.seekSeconds = 10,
    this.doubleTapPlayPause = true,
    this.volumeSwipe = true,
    this.brightnessSwipe = true,
    this.pinchZoom = true,
    this.longPressSpeed = true,
    this.longPressMultiplier = 2.0,
    this.autoHideSeconds = 4,
    this.resumePlayback = true,
    this.horizontalSeek = true,
    this.castButton = true,
    this.screenshotButton = true,
    this.lockButton = true,
    // v22: ON by default ("volume up to 200% out of the box"); only people
    // who explicitly turned it off keep it off (saved 'false' below).
    this.volumeBoost200 = true,
    this.volumeLeveling = false,
    this.karaokeSubs = false,
    this.skipIntroChip = true,
    this.enhanceVideo = false,
    this.toneMapping = 'auto',
  });

  // Persisted keys (MediaPlayerState reads the resume key directly).
  static const String kDoubleTapSeek = 'player.doubleTapSeek';
  static const String kSeekSeconds = 'player.seekSeconds';
  static const String kDoubleTapPlayPause = 'player.doubleTapPlayPause';
  static const String kVolumeSwipe = 'player.volumeSwipe';
  static const String kBrightnessSwipe = 'player.brightnessSwipe';
  static const String kPinchZoom = 'player.pinchZoom';
  static const String kLongPressSpeed = 'player.longPressSpeed';
  static const String kLongPressMultiplier = 'player.longPressMultiplier';
  static const String kAutoHideSeconds = 'player.autoHideSeconds';
  static const String kResumePlayback = 'player.resumePlayback';
  static const String kHorizontalSeek = 'player.horizontalSeek';
  static const String kCastButton = 'player.castButton';
  static const String kScreenshotButton = 'player.screenshotButton';
  static const String kLockButton = 'player.lockButton';
  static const String kVolumeBoost200 = 'player.volumeBoost200';
  static const String kVolumeLeveling = 'player.volumeLeveling';
  static const String kKaraokeSubs = 'player.karaokeSubs';
  static const String kSkipIntroChip = 'player.skipIntroChip';
  static const String kEnhanceVideo = 'player.enhanceVideo';
  static const String kToneMapping = 'player.toneMapping';

  static Future<PlayerSettings> load() async {
    final s = await NativeBridge.loadSettings();
    const d = PlayerSettings();
    return PlayerSettings(
      doubleTapSeek: s[kDoubleTapSeek] != 'false',
      seekSeconds: int.tryParse(s[kSeekSeconds] ?? '') ?? d.seekSeconds,
      doubleTapPlayPause: s[kDoubleTapPlayPause] != 'false',
      volumeSwipe: s[kVolumeSwipe] != 'false',
      brightnessSwipe: s[kBrightnessSwipe] != 'false',
      pinchZoom: s[kPinchZoom] != 'false',
      longPressSpeed: s[kLongPressSpeed] != 'false',
      longPressMultiplier:
          double.tryParse(s[kLongPressMultiplier] ?? '') ??
          d.longPressMultiplier,
      autoHideSeconds:
          int.tryParse(s[kAutoHideSeconds] ?? '') ?? d.autoHideSeconds,
      resumePlayback: s[kResumePlayback] != 'false',
      horizontalSeek: s[kHorizontalSeek] != 'false',
      castButton: s[kCastButton] != 'false',
      screenshotButton: s[kScreenshotButton] != 'false',
      lockButton: s[kLockButton] != 'false',
      volumeBoost200: s[kVolumeBoost200] != 'false', // v22: default on
      volumeLeveling: s[kVolumeLeveling] == 'true',
      karaokeSubs: s[kKaraokeSubs] == 'true',
      skipIntroChip: s[kSkipIntroChip] != 'false',
      enhanceVideo: s[kEnhanceVideo] == 'true',
      toneMapping: kToneMappingModes.contains(s[kToneMapping])
          ? s[kToneMapping]!
          : d.toneMapping,
    );
  }

  /// mpv accepts more algorithms, but these four+auto cover SDR phones to
  /// HDR TVs without overwhelming the settings sheet.
  static const List<String> kToneMappingModes = [
    'auto',
    'clip',
    'mobius',
    'hable',
    'bt.2390',
  ];

  Future<void> save() {
    NativeBridge.saveSetting(kDoubleTapSeek, '$doubleTapSeek');
    NativeBridge.saveSetting(kSeekSeconds, '$seekSeconds');
    NativeBridge.saveSetting(kDoubleTapPlayPause, '$doubleTapPlayPause');
    NativeBridge.saveSetting(kVolumeSwipe, '$volumeSwipe');
    NativeBridge.saveSetting(kBrightnessSwipe, '$brightnessSwipe');
    NativeBridge.saveSetting(kPinchZoom, '$pinchZoom');
    NativeBridge.saveSetting(kLongPressSpeed, '$longPressSpeed');
    NativeBridge.saveSetting(
      kLongPressMultiplier,
      longPressMultiplier.toStringAsFixed(1),
    );
    NativeBridge.saveSetting(kAutoHideSeconds, '$autoHideSeconds');
    NativeBridge.saveSetting(kResumePlayback, '$resumePlayback');
    NativeBridge.saveSetting(kHorizontalSeek, '$horizontalSeek');
    NativeBridge.saveSetting(kCastButton, '$castButton');
    NativeBridge.saveSetting(kScreenshotButton, '$screenshotButton');
    NativeBridge.saveSetting(kLockButton, '$lockButton');
    NativeBridge.saveSetting(kVolumeBoost200, '$volumeBoost200');
    NativeBridge.saveSetting(kVolumeLeveling, '$volumeLeveling');
    NativeBridge.saveSetting(kKaraokeSubs, '$karaokeSubs');
    NativeBridge.saveSetting(kSkipIntroChip, '$skipIntroChip');
    NativeBridge.saveSetting(kEnhanceVideo, '$enhanceVideo');
    return NativeBridge.saveSetting(kToneMapping, toneMapping);
  }

  PlayerSettings copyWith({
    bool? doubleTapSeek,
    int? seekSeconds,
    bool? doubleTapPlayPause,
    bool? volumeSwipe,
    bool? brightnessSwipe,
    bool? pinchZoom,
    bool? longPressSpeed,
    double? longPressMultiplier,
    int? autoHideSeconds,
    bool? resumePlayback,
    bool? horizontalSeek,
    bool? castButton,
    bool? screenshotButton,
    bool? lockButton,
    bool? volumeBoost200,
    bool? volumeLeveling,
    bool? karaokeSubs,
    bool? skipIntroChip,
    bool? enhanceVideo,
    String? toneMapping,
  }) {
    return PlayerSettings(
      doubleTapSeek: doubleTapSeek ?? this.doubleTapSeek,
      seekSeconds: seekSeconds ?? this.seekSeconds,
      doubleTapPlayPause: doubleTapPlayPause ?? this.doubleTapPlayPause,
      volumeSwipe: volumeSwipe ?? this.volumeSwipe,
      brightnessSwipe: brightnessSwipe ?? this.brightnessSwipe,
      pinchZoom: pinchZoom ?? this.pinchZoom,
      longPressSpeed: longPressSpeed ?? this.longPressSpeed,
      longPressMultiplier: longPressMultiplier ?? this.longPressMultiplier,
      autoHideSeconds: autoHideSeconds ?? this.autoHideSeconds,
      resumePlayback: resumePlayback ?? this.resumePlayback,
      horizontalSeek: horizontalSeek ?? this.horizontalSeek,
      castButton: castButton ?? this.castButton,
      screenshotButton: screenshotButton ?? this.screenshotButton,
      lockButton: lockButton ?? this.lockButton,
      volumeBoost200: volumeBoost200 ?? this.volumeBoost200,
      volumeLeveling: volumeLeveling ?? this.volumeLeveling,
      karaokeSubs: karaokeSubs ?? this.karaokeSubs,
      skipIntroChip: skipIntroChip ?? this.skipIntroChip,
      enhanceVideo: enhanceVideo ?? this.enhanceVideo,
      toneMapping: toneMapping ?? this.toneMapping,
    );
  }
}
EOF_MARKER_8

mkdir -p "$(dirname 'lib/utils/cleaner_stats.dart')"
cat > 'lib/utils/cleaner_stats.dart' <<'EOF_MARKER_9'
// v31 Cleaner: pure data + graph math for the cleaner sheet. The painters
// only draw what these functions return, so every byte that ends up in the
// graphs is unit-tested.

/// One coloured slice of the cleaner donut graph.
class CleanerSegment {
  final String label;
  final int bytes;

  /// ARGB colour value (wrapped in Color by the UI - keeps this util pure).
  final int colorValue;

  const CleanerSegment(this.label, this.bytes, this.colorValue);

  /// Share of the whole graph, 0..1 (0 when the graph is empty).
  double fractionOf(int total) => total <= 0 ? 0 : bytes / total;
}

/// Stable palette per cache kind - legend and graph always agree.
const Map<String, int> cleanerKindColors = {
  'thumbs': 0xFF7C4DFF, // deep purple
  'strips': 0xFF40C4FF, // light blue
  'temp': 0xFFFFAB40, // orange
  'models': 0xFF69F0AE, // green
  'device': 0xFFFF5252, // red
};

/// Builds the donut segments for the five reclaimable kinds, in a stable
/// order. Empty kinds are dropped so the graph never draws 0-width slices.
List<CleanerSegment> cleanerSegments({
  required int thumbs,
  required int strips,
  required int temp,
  required int models,
  required int deviceCache,
}) {
  final raw = <(String, String, int)>[
    ('thumbs', 'App thumbnails', thumbs),
    ('strips', 'Preview strips', strips),
    ('temp', 'Temporary AI files', temp),
    ('models', 'AI models', models),
    ('device', 'Gallery cache', deviceCache),
  ];
  return [
    for (final (kind, label, bytes) in raw)
      if (bytes > 0)
        CleanerSegment(label, bytes, cleanerKindColors[kind] ?? 0xFF9E9E9E),
  ];
}

/// What the big "Clean cache" button frees: every cache kind EXCEPT the AI
/// models (those are downloads - cleared from their own row with a warning
/// because they need mobile data to come back).
int cleanerCacheTotal({
  required int thumbs,
  required int strips,
  required int temp,
  required int deviceCache,
}) =>
    thumbs + strips + temp + deviceCache;

/// Everything the cleaner can reclaim, caches + models combined (used for
/// the "X reclaimable" headline and as the donut's total).
int cleanerGrandTotal({
  required int thumbs,
  required int strips,
  required int temp,
  required int models,
  required int deviceCache,
}) =>
    cleanerCacheTotal(
      thumbs: thumbs,
      strips: strips,
      temp: temp,
      deviceCache: deviceCache,
    ) +
    models;
EOF_MARKER_9

mkdir -p "$(dirname 'lib/utils/formatters.dart')"
cat > 'lib/utils/formatters.dart' <<'EOF_MARKER_10'
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

/// v32: human label for the HDR format detected natively. Returns null for
/// SDR/unknown so the info sheet can stay quiet on plain files. Dolby
/// Vision is rendered through its HDR10-compatible base layer - there is
/// no licensed DV pipeline on this engine, so the label says so honestly.
String? hdrLabelFor(String? hdr) => switch (hdr) {
  'hdr10' => 'HDR10',
  'hdr10+' => 'HDR10+',
  'hlg' => 'HLG',
  'dolby-vision' => 'Dolby Vision (HDR mode)',
  _ => null,
};

/// Compact watch-time totals for the stats screen ("2h 15m", "45m", "30s").
String formatWatchTime(int seconds) {
  if (seconds < 60) return '${seconds}s';
  final m = seconds ~/ 60;
  if (m < 60) return '${m}m';
  return '${m ~/ 60}h ${m % 60}m';
}

/// Relative "watched" timestamps for the history list ("5m ago", "3h ago",
/// "12 Aug", ...).
String timeAgo(int msSinceEpoch) {
  if (msSinceEpoch <= 0) return '';
  final dt = DateTime.fromMillisecondsSinceEpoch(msSinceEpoch);
  final diff = DateTime.now().difference(dt);
  if (diff.isNegative || diff.inSeconds < 60) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${dt.day} ${months[dt.month - 1]}';
}

const List<String> videoExtensions = [
  '.mp4',
  '.webm',
  '.mkv',
  '.avi',
  '.mov',
  '.wmv',
  '.flv',
  '.m4v',
  '.3gp',
  '.3gpp',
  '.ogv',
  '.ts',
  '.mts',
  '.m2ts',
  '.vob',
  '.mpg',
  '.mpeg',
  '.rmvb',
  '.divx',
  '.f4v',
];

bool isVideoFile(String name) {
  final lower = name.toLowerCase();
  return videoExtensions.any((ext) => lower.endsWith(ext));
}

/// hh:mm:ss / m:ss countdown text from a number of seconds (sleep timer
/// "22:41" under the player title). Pure + unit-tested.
String formatCountdown(int totalSeconds) {
  final s = totalSeconds < 0 ? 0 : totalSeconds;
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final sec = s % 60;
  String two(int v) => v.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(sec)}' : '$m:${two(sec)}';
}

/// v27: friendly aspect-ratio label for the advanced Video info sheet.
/// Exact/simple ratios show as "16:9" style; awkward ones as "2.36:1".
/// Pure + unit-tested.
String formatAspectRatio(int w, int h) {
  if (w <= 0 || h <= 0) return '';
  int a = w;
  int b = h;
  while (b != 0) {
    final t = a % b;
    a = b;
    b = t;
  }
  final num = w ~/ a;
  final den = h ~/ a;
  if (num <= 40 && den <= 40) return '$num:$den';
  return '${(w / h).toStringAsFixed(2)}:1';
}
EOF_MARKER_10

mkdir -p "$(dirname 'lib/models/saved_server.dart')"
cat > 'lib/models/saved_server.dart' <<'EOF_MARKER_11'
import 'dart:convert';

/// v32 BYOS phase A: a saved streaming endpoint (NAS over WebDAV/HTTP, a
/// direct link, an rtsp camera...). The user brings the storage; Max Player
/// is the player. Stored as a JSON list in the native settings store under
/// the key [kServersSettingKey] - no new plugin needed.
const String kServersSettingKey = 'servers.list';

class SavedServer {
  final String name;
  final String url;

  const SavedServer({required this.name, required this.url});

  Map<String, String> toJson() => {'name': name, 'url': url};

  factory SavedServer.fromJson(Map<dynamic, dynamic> json) =>
      SavedServer(name: '${json['name'] ?? ''}', url: '${json['url'] ?? ''}');
}

/// Parses the stored JSON list. Anything malformed (empty, wrong type,
/// entries without a url) is dropped instead of throwing - the store is
/// plain text and may hold anything.
List<SavedServer> parseServersJson(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const [];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return [
      for (final e in decoded)
        if (e is Map && e['url'] != null && '${e['url']}'.isNotEmpty)
          SavedServer.fromJson(e),
    ];
  } catch (_) {
    return const [];
  }
}

String serversToJson(List<SavedServer> servers) =>
    jsonEncode([for (final s in servers) s.toJson()]);

/// Adds [server] unless the same url is already saved (dedupe by url).
List<SavedServer> addSavedServer(
  List<SavedServer> servers,
  SavedServer server,
) {
  if (servers.any((s) => s.url == server.url)) return servers;
  return [...servers, server];
}
EOF_MARKER_11

mkdir -p "$(dirname 'lib/widgets/cleaner_sheet.dart')"
cat > 'lib/widgets/cleaner_sheet.dart' <<'EOF_MARKER_12'
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
EOF_MARKER_12

mkdir -p "$(dirname 'lib/widgets/user_manual_sheet.dart')"
cat > 'lib/widgets/user_manual_sheet.dart' <<'EOF_MARKER_13'
import 'package:flutter/material.dart';

import '../app_info.dart';
import '../state/theme_state.dart';
import 'gesture_illustrations.dart';

/// In-app user manual, opened from the home screen's ⋮ menu
/// ("User manual"). Static content only - no platform calls. Gesture
/// entries are illustrated with drawn vector diagrams
/// ([GestureIllustration]) so no image assets are bundled.
class UserManualSheet extends StatelessWidget {
  final ScrollController? scrollController;

  const UserManualSheet({super.key, this.scrollController});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF14141c),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (context, controller) =>
            UserManualSheet(scrollController: controller),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = themeState.accent;
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
      children: [
        // Grab handle.
        Center(
          child: Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 14),
            decoration: const BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.all(Radius.circular(2)),
            ),
          ),
        ),
        Row(
          children: [
            Icon(Icons.menu_book_outlined, color: accent),
            const SizedBox(width: 10),
            const Text(
              'User manual',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),

        // --- Home screen ------------------------------------------------
        _SectionTitle('Home screen', accent),
        for (final item in _homeItems) _IconRow(item: item),

        // --- Gestures (illustrated) -------------------------------------
        _SectionTitle('Gesture controls', accent),
        const Padding(
          padding: EdgeInsets.only(bottom: 6),
          child: Text(
            'All gestures work both in windowed and full-screen mode, on '
            'every video. Each one can be switched off individually in the '
            'player\'s ⚙ settings sheet.',
            style: TextStyle(color: Colors.white54, fontSize: 12.5),
          ),
        ),
        for (final g in _gestureItems) _GestureCard(item: g),

        // --- Player buttons ---------------------------------------------
        _SectionTitle('Player buttons', accent),
        for (final item in _playerItems) _IconRow(item: item),

        // --- Smart features ---------------------------------------------
        _SectionTitle('Smart features', accent),
        for (final item in _smartItems) _IconRow(item: item),

        // --- Tips & FAQ ---------------------------------------------------
        _SectionTitle('Tips & answers', accent),
        for (final item in _tipItems) _IconRow(item: item),

        const SizedBox(height: 22),
        const Center(
          child: Text(
            'Max Player v$kAppVersion  ·  Hyper Tech Labs',
            style: TextStyle(color: Colors.white24, fontSize: 12),
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  final Color accent;
  const _SectionTitle(this.text, this.accent);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 6),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color: accent,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}

/// Text row with a small leading icon (non-illustrated entries).
class _IconRow extends StatelessWidget {
  final _Item item;
  const _IconRow({required this.item});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(item.icon, size: 20, color: Colors.white70),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.description,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 12.5,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Gesture guide card: drawn illustration on top, title + detailed
/// step-by-step description underneath.
class _GestureCard extends StatelessWidget {
  final _GestureItem item;
  const _GestureCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        children: [
          GestureIllustration(kind: item.kind),
          const SizedBox(height: 8),
          Text(
            item.title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            item.description,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _Item {
  final IconData icon;
  final String title;
  final String description;
  const _Item(this.icon, this.title, this.description);
}

class _GestureItem {
  final GestureKind kind;
  final String title;
  final String description;
  const _GestureItem(this.kind, this.title, this.description);
}

// ---------------------------------------------------------------------------
// Content
// ---------------------------------------------------------------------------

const List<_Item> _homeItems = [
  _Item(
    Icons.sync,
    'Rescan button (⟳ top bar)',
    'New videos you download or copy do not appear by themselves - tap the '
        '⟳ button in the top bar and the whole device is re-scanned. While '
        'scanning, the button turns into a spinner and a progress bar shows '
        'how far along it is. The same action lives in ⋮ → Rescan library.',
  ),
  _Item(
    Icons.search,
    'Search',
    'Type any part of a file name into the search bar under the title. The '
        'list filters live as you type; clear the text to see everything '
        'again.',
  ),
  _Item(
    Icons.favorite_border,
    'Favourites',
    'Tap the ♥ on any video to star it. Then open ⋮ → Display settings and '
        'enable "Show only favourites" to see just your picks. Stars are '
        'remembered between launches.',
  ),
  _Item(
    Icons.tune,
    'Sort, group, grid & accent colour',
    '⋮ → Display settings lets you: switch between list and grid view, sort '
        'by name / length / date added / size (tap again to flip the '
        'direction), group by first letter or by folder, and change the app\'s '
        'accent colour from seven swatches - white is the default.',
  ),
  _Item(
    Icons.grid_view_rounded,
    'Quick tiles under the search bar',
    'Four shortcuts sit under the library search bar: Private folder, '
        'Cleaner, Playlist and Folders. The grid slides away when you '
        'scroll down through your videos and returns when you scroll '
        'back up. Cleaner scans every cache (app thumbnails, AI '
        'leftovers, the gallery thumbnail cache), draws graphs of your '
        'device storage and the reclaimable space, and Clean cache '
        'frees all caches at once; the largest videos and duplicate '
        'copies sit below - cache cleaning never touches your videos. '
        'Playlist shows the current '
        'playlist: tap + to add videos one by one, or "Build playlist" to '
        'pick videos and play only them - previous/next then stay inside '
        'your selection. Folders shows only the videos of one folder; '
        'clear the chip under the search bar to see everything again.',
  ),
  _Item(
    Icons.open_in_new,
    'Playing videos from other apps',
    'In your Gallery or Files app, tap a video → "Open with" → Max Player. '
        'Some galleries hide this under Share - Share → Max Player works the '
        'same. Videos stored only in the cloud (e.g. Google Photos) are '
        'copied to a temporary file first, so they can take a few seconds to '
        'start.',
  ),
  _Item(
    Icons.link,
    'Network streams & saved servers',
    '⋮ → Open stream / server: paste a direct video link (http/https), a '
        'live stream (rtsp/rtmp/mms) or a NAS / WebDAV link and it plays '
        'immediately. Tap Save to keep it in the list - your storage, our '
        'player. Links opened in a browser can also be handed to Max '
        'Player directly from the "Open with" dialog.',
  ),
  _Item(
    Icons.history,
    'History & resume',
    'The 🕘 button in the top bar lists your recently watched videos. Every '
        'video reopens exactly where you stopped watching (a "Resumed …" '
        'message confirms it). Turn this off in the player\'s ⚙ settings → '
        'Resume playback.',
  ),
  _Item(
    Icons.bar_chart,
    'Statistics',
    '⋮ → Statistics shows how much you watched each day of the last week '
        'as a bar chart, plus advanced cards: today, daily average, best '
        'day, last 30 days total and your day-by-day watching streak. '
        'The "Most watched" list ranks the videos you have spent the '
        'most time on.',
  ),
];

const List<_GestureItem> _gestureItems = [
  _GestureItem(
    GestureKind.singleTap,
    'Single tap - show / hide controls',
    'Tap once anywhere on the video: the seek bar and all buttons slide in. '
        'Tap again (or wait ~4 seconds) and they hide so nothing covers the '
        'picture. The auto-hide delay can be changed in ⚙ settings.',
  ),
  _GestureItem(
    GestureKind.doubleTapSides,
    'Double-tap the sides - seek ±10 seconds',
    'Double-tap the LEFT third of the video to jump back 10 seconds, the '
        'RIGHT third to jump forward 10 seconds. Each extra double-tap adds '
        'another 10 seconds. The 10-second step is configurable in ⚙ '
        'settings (5s-30s).',
  ),
  _GestureItem(
    GestureKind.doubleTapMiddle,
    'Double-tap the middle - play / pause',
    'Double-tap the CENTER of the video to pause and resume - no need to '
        'aim for the small button.',
  ),
  _GestureItem(
    GestureKind.swipeBrightness,
    'Swipe on the LEFT half - brightness',
    'Put a finger on the left half of the video and slide UP to brighten or '
        'DOWN to dim (a percentage shows at the top while you swipe). This '
        'is app-local: your normal brightness is restored the moment you '
        'leave the player.',
  ),
  _GestureItem(
    GestureKind.swipeVolume,
    'Swipe on the RIGHT half - volume',
    'The same gesture on the right half changes the volume. Sliding all the '
        'way down mutes the video; swipe up or tap the speaker button to '
        'unmute.',
  ),
  _GestureItem(
    GestureKind.swipeSeek,
    'Swipe SIDEWAYS - scrub through the video',
    'Drag one finger LEFT or RIGHT anywhere on the video to scrub: the pill '
        'at the top shows how far you are jumping ("+45s · 03:12") and the '
        'video follows live while you drag. A full screen-width swipe is '
        '±90 seconds. Release to land exactly there. When zoomed in, the '
        'same drag moves the picture instead. Can be turned off in ⚙ '
        'settings → Gesture controls.',
  ),
  _GestureItem(
    GestureKind.pinchZoom,
    'Pinch with two fingers - zoom up to 4×',
    'Place TWO fingers on the video and spread them apart to zoom in, pinch '
        'them together to zoom out (1.0× to 4.0×). The zoom anchors at your '
        'fingers, and while zoomed you can drag with ONE finger to move the '
        'picture around. If you pinch back almost to 1×, the video snaps '
        'back to normal on its own.',
  ),
  _GestureItem(
    GestureKind.holdSpeed,
    'Hold your finger - speed boost',
    'Press and HOLD anywhere on the video to play faster (2× by default) '
        'for as long as you keep holding; lift your finger to return to '
        'normal speed. The "2.0x" badge stays visible at the top for the '
        'whole boost. The multiplier (1.5×/2×/2.5×/3×) is set in ⚙ settings.',
  ),
];

const List<_Item> _playerItems = [
  _Item(
    Icons.queue_music,
    'Playlist / queue',
    'Opens the playlist panel. When you picked the videos yourself (home '
        'screen → Playlist), the panel and the previous/next buttons use '
        'only those videos - nothing else sneaks in. Tap a row to jump to '
        'it, the small ✕ to remove one, and » at the top to collapse.',
  ),
  _Item(
    Icons.auto_fix_high_outlined,
    'Enhance & HDR',
    'Settings (⚙) → Picture: "Enhance video" switches on a real-time GPU '
        'boost (sharpen + contrast + colour) that makes ordinary videos '
        'look crisper. The HDR tone-mapping choice controls how HDR10, '
        'HDR10+ and Dolby Vision videos (they play via their HDR layer) '
        'fit your screen - Auto suits most phones.',
  ),
  _Item(
    Icons.fullscreen,
    'Fullscreen',
    'Fills the entire screen (and switches to landscape). All gestures keep '
        'working. Press the same button or the back gesture to return.',
  ),
  _Item(
    Icons.screen_rotation,
    'Rotation lock',
    'By default the player follows your phone - tip it sideways and the '
        'video rotates with you. Tap the rotate button to LOCK the current '
        'orientation (it keeps the video put no matter how you tilt); tap '
        'again to release the lock.',
  ),
  _Item(
    Icons.aspect_ratio,
    'Fit (picture size)',
    'Cycles Contain → Crop → Stretch. Contain shows the whole frame with '
        'bars, Crop zooms to fill the screen (edges cut), Stretch fills '
        'exactly (may distort).',
  ),
  _Item(
    Icons.graphic_eq,
    'Equalizer (top bar)',
    'Five-band equalizer with presets (Bass, Vocal, Treble, Rock...). Your '
        'last setting is remembered and applied to every video.',
  ),
  _Item(
    Icons.info_outline,
    'Video info (top ⋮ menu)',
    'Player ⋮ menu → Video info: full technical card for the current '
        'video - container format, resolution and aspect ratio, frame '
        'rate, video codec, audio codec with channels and sample rate, '
        'bitrate, file size and modified date.',
  ),
  _Item(
    Icons.timer_outlined,
    'A→B loop',
    'Tap at the start of the part you want to repeat (A lights up), tap '
        'again at the end (B lights up) - that section loops until you tap '
        'a third time to clear.',
  ),
  _Item(
    Icons.picture_in_picture_alt_outlined,
    'Picture-in-picture (top bar)',
    'Shrinks the video to a floating window that keeps playing while you '
        'use other apps. Tap the window for a play/pause button, drag it to '
        'any corner, and tap the expand icon to come back full-screen.',
  ),
  _Item(
    Icons.speed,
    'Playback speed',
    'Tap the "1.0x" label in the bottom controls to pick a constant speed '
        'from 0.5× up to 2×.',
  ),
  _Item(
    Icons.subtitles_outlined,
    'Subtitles & audio tracks',
    'Switch between embedded subtitle languages or turn them off, and pick '
        'a different audio track for dual-audio files (e.g. Hindi / '
        'English).',
  ),
  _Item(
    Icons.cast_outlined,
    'Cast to TV (top bar)',
    'Tap the cast icon to send the video to any DLNA smart TV or Android '
        'box on the same Wi-Fi. The phone turns into a remote: play/pause, '
        'a live seek slider, and "Stop casting" hands the video back to '
        'the phone right where the TV left off. Closing the player stops '
        'casting. (Chromecast dongles use a different protocol and are '
        'not supported yet.)',
  ),
  _Item(
    Icons.camera_alt_outlined,
    'Screenshot (top bar)',
    'Saves the current frame - with any subtitles burned in, exactly as '
        'you see it - as a PNG into Pictures/Max Player, visible in your '
        'gallery at once. Not available for online streams.',
  ),
  _Item(
    Icons.lock_outline,
    'Screen lock / kids mode (left edge)',
    'The lock button on the left edge of the video locks EVERY button and '
        'gesture - safe to hand the phone to a child or keep in a pocket. '
        'To unlock, double-tap (or long-press) the lock on the right edge. '
        'The button can be hidden in ⚙ settings → Player buttons.',
  ),
  _Item(
    Icons.settings_outlined,
    'Player settings (⚙ top bar)',
    'Every gesture can be turned on/off individually (including horizontal '
        'swipe-to-seek), plus: seek step, auto-hide delay, speed-boost '
        'multiplier, resume playback, and which extra buttons (cast / '
        'screenshot / lock) show in the player.',
  ),
];

/// v21: the feature list Max Player has that other players do not.
const List<_Item> _smartItems = [
  _Item(
    Icons.translate,
    'AI subtitles in English (translate)',
    'Play a foreign-language video → subtitle button → AI subtitles → '
        'choose "→ English" before generating. Any spoken language becomes '
        'English subtitles, fully on-device.',
  ),
  _Item(
    Icons.lyrics_outlined,
    'Karaoke word highlight',
    'Player → the "tune" button (beside play, with Subtitles / Audio '
        'track / A-B loop) → Karaoke subtitles: words '
        'light up one by one as they '
        'are spoken. Works with ANY subtitle - AI captions, the video\'s own '
        '.srt file, or subtitles embedded in the video. While karaoke is '
        'on, the normal subtitle display turns OFF so only the karaoke '
        'line shows; turning karaoke OFF brings the normal subtitles '
        'straight back.',
  ),
  _Item(
    Icons.fast_forward,
    'Skip intro chip',
    'When subtitles (AI captions or the video\'s own .srt file) show the '
        'dialogue starts late, a "Skip to …" chip appears near the start '
        'of the video. Turn it off in Player settings → Skip intro chip.',
  ),
  _Item(
    Icons.volume_up,
    'Volume boost up to 200%',
    'ON by default: the volume swipe simply continues past 100% for quiet '
        'videos. Player settings → Sound & subtitles switches it off.',
  ),
  _Item(
    Icons.graphic_eq,
    'Volume leveling',
    'Player settings → Sound & subtitles → Volume leveling: soft dialogue '
        'and loud explosions play at a steady loudness. Combines with the '
        'equalizer instead of replacing it.',
  ),
  _Item(
    Icons.bedtime_outlined,
    'Sleep timer',
    'Player ⋮ menu → Sleep timer: pauses playback after 15/30/45/60 '
        'minutes, or exactly at the end of the current video. While it '
        'runs, the remaining time shows under the video title.',
  ),
  _Item(
    Icons.speed,
    'Playback speed up to 3x',
    'Tap the "1.0x" button in the player controls: 0.5x … 3x (v22 added '
        '2.5x and 3x).',
  ),
  _Item(
    Icons.lock_outline,
    'Private folder (PIN)',
    'Long-press any video → "Move to Private folder". Hidden videos '
        'disappear from Gallery and file managers. Open them from the '
        '"Private folder" tile under the library search bar after your '
        'PIN; simply opening and '
        'closing the folder no longer reloads the library. '
        'Forgot the PIN? Tap "Forgot PIN?" on the lock screen → unlock '
        'your PHONE once (device password, pattern or fingerprint) → '
        'set a new PIN - hidden videos are never wiped. '
        'Note: uninstalling the app deletes hidden videos - move them '
        'out first.',
  ),
];

const List<_Item> _tipItems = [
  _Item(
    Icons.info_outline,
    'A new video does not appear in the library?',
    'Press the ⟳ rescan button in the top bar. If it is still missing, '
        'check the file extension is a common one (.mp4, .mkv, .webm, ...) '
        'and that Max Player has storage permission.',
  ),
  _Item(
    Icons.info_outline,
    'Max Player does not show in "Open with"?',
    'Some galleries only offer Share: long-press the video → Share → Max '
        'Player. You can also open Android Settings → Apps → Max Player → '
        '"Open by default" and enable it for videos.',
  ),
  _Item(
    Icons.info_outline,
    'Can it play 8K video?',
    'Yes - 8K files (HEVC, VP9 or AV1) open and play. Smooth playback '
        'depends on your phone: recent flagships decode 8K in hardware, '
        'while mid-range chips may stutter at 8K. 1080p and 4K play '
        'smoothly on almost every device.',
  ),
  _Item(
    Icons.info_outline,
    'A video will not play at all?',
    'Very rarely a file uses an unusual codec. Try playing it from its '
        'share menu (Share → Max Player) or re-encode it to H.264/AAC - '
        'the most compatible combination.',
  ),
];
EOF_MARKER_13

mkdir -p "$(dirname 'lib/widgets/player_settings_sheet.dart')"
cat > 'lib/widgets/player_settings_sheet.dart' <<'EOF_MARKER_14'
import 'package:flutter/material.dart';

import '../state/player_settings.dart';
import '../state/theme_state.dart';

/// "Player settings" sheet - customize every gesture and playback behavior.
/// Changes are saved immediately and picked up by the open PlayerScreen.
class PlayerSettingsSheet extends StatefulWidget {
  const PlayerSettingsSheet({super.key});

  static Color get _accent => themeState.accent;
  static const Color _surface = Color(0xFF1a1a24);

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const PlayerSettingsSheet(),
    );
  }

  @override
  State<PlayerSettingsSheet> createState() => _PlayerSettingsSheetState();
}

class _PlayerSettingsSheetState extends State<PlayerSettingsSheet> {
  PlayerSettings _settings = const PlayerSettings();
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await PlayerSettings.load();
    if (!mounted) return;
    setState(() {
      _settings = s;
      _loaded = true;
    });
  }

  void _update(PlayerSettings s) {
    setState(() => _settings = s);
    s.save(); // fire-and-forget persistence
  }

  @override
  Widget build(BuildContext context) {
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
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
              child: Text(
                'Player settings',
                style: TextStyle(
                  color: PlayerSettingsSheet._accent,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (!_loaded)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: CircularProgressIndicator(
                    color: PlayerSettingsSheet._accent,
                  ),
                ),
              )
            else ...[
              const _SectionHeader('Gesture controls'),
              _SwitchTile(
                icon: Icons.touch_app_outlined,
                label: 'Double-tap sides to seek',
                subtitle: 'Double-tap left/right edge',
                value: _settings.doubleTapSeek,
                onChanged: (v) => _update(_settings.copyWith(doubleTapSeek: v)),
                trailing: _settings.doubleTapSeek
                    ? _MiniDropdown<int>(
                        value: _settings.seekSeconds,
                        entries: const {
                          5: '5s',
                          10: '10s',
                          15: '15s',
                          30: '30s',
                        },
                        onChanged: (v) =>
                            _update(_settings.copyWith(seekSeconds: v ?? 10)),
                      )
                    : null,
              ),
              _SwitchTile(
                icon: Icons.play_circle_outline,
                label: 'Double-tap middle to play/pause',
                value: _settings.doubleTapPlayPause,
                onChanged: (v) =>
                    _update(_settings.copyWith(doubleTapPlayPause: v)),
              ),
              _SwitchTile(
                icon: Icons.volume_up_outlined,
                label: 'Swipe right side for volume',
                value: _settings.volumeSwipe,
                onChanged: (v) => _update(_settings.copyWith(volumeSwipe: v)),
              ),
              _SwitchTile(
                icon: Icons.brightness_6_outlined,
                label: 'Swipe left side for brightness',
                value: _settings.brightnessSwipe,
                onChanged: (v) =>
                    _update(_settings.copyWith(brightnessSwipe: v)),
              ),
              _SwitchTile(
                icon: Icons.swap_horizontal_circle_outlined,
                label: 'Horizontal swipe to seek',
                subtitle: 'Drag sideways anywhere to scrub (±90s per screen)',
                value: _settings.horizontalSeek,
                onChanged: (v) =>
                    _update(_settings.copyWith(horizontalSeek: v)),
              ),
              _SwitchTile(
                icon: Icons.pinch_outlined,
                label: 'Pinch to zoom (two fingers)',
                value: _settings.pinchZoom,
                onChanged: (v) => _update(_settings.copyWith(pinchZoom: v)),
              ),
              _SwitchTile(
                icon: Icons.fast_forward,
                label: 'Long-press to speed up',
                subtitle: 'Hold finger on the video',
                value: _settings.longPressSpeed,
                onChanged: (v) =>
                    _update(_settings.copyWith(longPressSpeed: v)),
                trailing: _settings.longPressSpeed
                    ? _MiniDropdown<double>(
                        value: _settings.longPressMultiplier,
                        entries: {
                          1.5: '1.5x',
                          2.0: '2x',
                          2.5: '2.5x',
                          3.0: '3x',
                        },
                        onChanged: (v) => _update(
                          _settings.copyWith(longPressMultiplier: v ?? 2.0),
                        ),
                      )
                    : null,
              ),
              const _SectionHeader('Playback'),
              _SwitchTile(
                icon: Icons.timer_off_outlined,
                label: 'Auto-hide controls',
                subtitle: 'Hide during playback after inactivity',
                value: _settings.autoHideSeconds > 0,
                onChanged: (v) =>
                    _update(_settings.copyWith(autoHideSeconds: v ? 4 : 0)),
                trailing: _settings.autoHideSeconds > 0
                    ? _MiniDropdown<int>(
                        value: _settings.autoHideSeconds,
                        entries: const {3: '3s', 4: '4s', 5: '5s', 6: '6s'},
                        onChanged: (v) => _update(
                          _settings.copyWith(autoHideSeconds: v ?? 4),
                        ),
                      )
                    : null,
              ),
              _SwitchTile(
                icon: Icons.history,
                label: 'Resume playback',
                subtitle: 'Continue videos where you left off',
                value: _settings.resumePlayback,
                onChanged: (v) =>
                    _update(_settings.copyWith(resumePlayback: v)),
              ),
              const _SectionHeader('Picture'),
              _SwitchTile(
                icon: Icons.auto_fix_high_outlined,
                label: 'Enhance video (real-time)',
                subtitle: 'GPU sharpen + contrast + colour boost',
                value: _settings.enhanceVideo,
                onChanged: (v) => _update(_settings.copyWith(enhanceVideo: v)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 2,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.hdr_on_outlined,
                      color: Colors.white70,
                      size: 22,
                    ),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'HDR tone-mapping',
                            style: TextStyle(color: Colors.white, fontSize: 15),
                          ),
                          Text(
                            'How HDR10/Dolby sources fit your screen',
                            style: TextStyle(
                              color: Colors.white38,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _MiniDropdown<String>(
                      value: _settings.toneMapping,
                      entries: const {
                        'auto': 'Auto',
                        'mobius': 'Mobius',
                        'hable': 'Hable',
                        'bt.2390': 'BT.2390',
                      },
                      onChanged: (v) =>
                          _update(_settings.copyWith(toneMapping: v ?? 'auto')),
                    ),
                  ],
                ),
              ),
              const _SectionHeader('Player buttons'),
              _SwitchTile(
                icon: Icons.cast_outlined,
                label: 'Cast to TV (DLNA)',
                subtitle: 'Show the cast button in the player top bar',
                value: _settings.castButton,
                onChanged: (v) => _update(_settings.copyWith(castButton: v)),
              ),
              _SwitchTile(
                icon: Icons.camera_alt_outlined,
                label: 'Screenshot button',
                subtitle: 'Save the current frame to the gallery',
                value: _settings.screenshotButton,
                onChanged: (v) =>
                    _update(_settings.copyWith(screenshotButton: v)),
              ),
              _SwitchTile(
                icon: Icons.lock_outline,
                label: 'Screen lock (kids mode)',
                subtitle: 'Lock button on the video edge locks every touch',
                value: _settings.lockButton,
                onChanged: (v) => _update(_settings.copyWith(lockButton: v)),
              ),
              const _SectionHeader('Sound & subtitles'),
              _SwitchTile(
                icon: Icons.volume_up,
                label: 'Volume boost up to 200%',
                subtitle:
                    'ON by default - the swipe just continues past '
                    '100% for quiet videos',
                value: _settings.volumeBoost200,
                onChanged: (v) =>
                    _update(_settings.copyWith(volumeBoost200: v)),
              ),
              _SwitchTile(
                icon: Icons.graphic_eq,
                label: 'Volume leveling',
                subtitle:
                    'Steady loudness: soft dialogue and loud '
                    'explosions evened out',
                value: _settings.volumeLeveling,
                onChanged: (v) =>
                    _update(_settings.copyWith(volumeLeveling: v)),
              ),
              // v26: the karaoke switch no longer lives in settings - it
              // exists ONLY in the player's tracks sheet (the "tune"
              // button beside play), per user request.
              _SwitchTile(
                icon: Icons.fast_forward,
                label: 'Skip intro chip',
                subtitle:
                    'Offer to jump when subtitles (AI or the video\'s '
                    'own .srt file) show the dialogue starts later',
                value: _settings.skipIntroChip,
                onChanged: (v) => _update(_settings.copyWith(skipIntroChip: v)),
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Text(
        title,
        style: TextStyle(
          color: PlayerSettingsSheet._accent,
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Widget? trailing;

  const _SwitchTile({
    required this.icon,
    required this.label,
    this.subtitle,
    required this.value,
    required this.onChanged,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: Row(
        children: [
          Icon(icon, color: Colors.white70, size: 22),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
              ],
            ),
          ),
          if (trailing != null) trailing!,
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: PlayerSettingsSheet._accent,
          ),
        ],
      ),
    );
  }
}

class _MiniDropdown<T> extends StatelessWidget {
  final T value;
  final Map<T, String> entries;
  final ValueChanged<T?> onChanged;

  const _MiniDropdown({
    required this.value,
    required this.entries,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButton<T>(
      value: value,
      dropdownColor: const Color(0xFF26262f),
      underline: const SizedBox.shrink(),
      isDense: true,
      style: const TextStyle(color: Colors.white70, fontSize: 13),
      items: [
        for (final e in entries.entries)
          DropdownMenuItem(value: e.key, child: Text(e.value)),
      ],
      onChanged: onChanged,
    );
  }
}
EOF_MARKER_14

mkdir -p "$(dirname 'lib/widgets/video_info_sheet.dart')"
cat > 'lib/widgets/video_info_sheet.dart' <<'EOF_MARKER_15'
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/native_bridge.dart';
import '../state/media_player_state.dart';
import '../state/theme_state.dart';
import '../utils/formatters.dart';

/// Bottom sheet with technical details about the video currently loaded in
/// the player (resolution, codec, bitrate, size, duration, path...).
/// Values are refreshed live from the native MediaMetadataRetriever.
class VideoInfoSheet extends StatelessWidget {
  final MediaPlayerState player;

  /// Provided by the wrapping DraggableScrollableSheet so the info list can
  /// be dragged/scrolled up to see every row (v20).
  final ScrollController? scrollController;

  const VideoInfoSheet({
    super.key,
    required this.player,
    this.scrollController,
  });

  static Future<void> show(BuildContext context, MediaPlayerState player) {
    // v20: isScrollControlled + DraggableScrollableSheet - the old
    // fixed-height sheet cropped the bottom rows on small screens and
    // could not be dragged up ("video info is not sliding"). Now it drags
    // between 30% and 90% of the screen and the rows scroll.
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1a1a24),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => VideoInfoSheet(
          player: player,
          scrollController: scrollController,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final track = player.currentTrack;
    final accent = themeState.accent;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
        // v20: scrollable content - pairs with the DraggableScrollableSheet
        // in show() so every row can be pulled up into view.
        child: SingleChildScrollView(
          controller: scrollController,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Video info',
                style: TextStyle(
                  color: accent,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              if (track == null)
                const Text('Nothing is loaded right now',
                    style: TextStyle(color: Colors.white38))
              else
                FutureBuilder<VideoMetadata>(
                  future: track.path.contains('://')
                      ? null
                      : NativeBridge.fetchMetadata(track.path),
                  builder: (context, snap) {
                    final meta = snap.data;
                    final w = meta?.width ?? track.width;
                    final h = meta?.height ?? track.height;
                    final sizeBytes =
                        track.sizeBytes ?? _fileSizeOrNull(track.path);
                    // v27: container from the file extension (MKV, MP4...).
                    final isStream = track.path.contains('://');
                    final container = isStream
                        ? null
                        : (track.path.contains('.')
                            ? track.path.split('.').last.toUpperCase()
                            : null);
                    final aspect = (w != null && h != null && w > 0 && h > 0)
                        ? formatAspectRatio(w, h)
                        : '';
                    // v27: "AAC · 2 ch · 48 kHz" style audio summary.
                    final audioParts = <String>[
                      if (meta?.audioCodec != null) meta!.audioCodec!,
                      if (meta?.audioChannels != null)
                        '${meta!.audioChannels} ch',
                      if (meta?.audioSampleRate != null)
                        '${(meta!.audioSampleRate! / 1000).toStringAsFixed(0)} kHz',
                    ];
                    final modified =
                        isStream ? null : _modifiedLabel(track.path);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _Row('Name', track.title),
                        _Row('Location', track.path, small: true),
                        if (container != null) _Row('Format', container),
                        _Row(
                          'Resolution',
                          (w != null && h != null && w > 0)
                              ? '$w × $h  ·  ${track.qualityLabel ?? ''}'
                                  '${aspect.isNotEmpty ? '  ·  $aspect' : ''}'
                              : 'Unknown',
                        ),
                        if (meta?.frameRate != null)
                          _Row('Frame rate', '${meta!.frameRate} fps'),
                        _Row(
                            'Duration',
                            formatDuration(meta?.duration ??
                                track.duration ??
                                player.duration)),
                        _Row(
                            'File size',
                            sizeBytes == null
                                ? 'Unknown'
                                : formatFileSize(sizeBytes)),
                        if (modified != null) _Row('Modified', modified),
                        if (meta?.codec != null)
                          _Row('Video codec', meta!.codec!.toUpperCase()),
                        if (hdrLabelFor(meta?.hdr) != null)
                          _Row('Video range', hdrLabelFor(meta!.hdr)!),
                        if (audioParts.isNotEmpty)
                          _Row('Audio', audioParts.join('  ·  ')),
                        if (meta?.bitrateBps != null && meta!.bitrateBps! > 0)
                          _Row('Bitrate',
                              '${(meta.bitrateBps! / 1000000).toStringAsFixed(1)} Mbps'),
                        _Row('Queue position',
                            '${player.currentIndex + 1} of ${player.playlist.length}'),
                      ],
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  int? _fileSizeOrNull(String path) {
    try {
      if (path.contains('://')) return null;
      return File(path).lengthSync();
    } catch (_) {
      return null;
    }
  }

  /// v27: "14 Aug 2026 · 03:10" for the Modified row.
  String? _modifiedLabel(String path) {
    try {
      final ts = File(path).lastModifiedSync();
      return DateFormat('dd MMM yyyy · HH:mm').format(ts);
    } catch (_) {
      return null;
    }
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  final bool small;

  const _Row(this.label, this.value, {this.small = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 106,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white38, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: Colors.white,
                fontSize: small ? 11.5 : 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
EOF_MARKER_15

mkdir -p "$(dirname 'lib/screens/library_screen.dart')"
cat > 'lib/screens/library_screen.dart' <<'EOF_MARKER_16'
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../app_info.dart';
import '../models/video_track.dart';
import '../state/media_player_state.dart';
import '../state/theme_state.dart';
import '../state/video_library_state.dart';
import '../utils/crash_log.dart';
import '../widgets/about_sheet.dart';
import '../widgets/display_settings_sheet.dart';
import '../state/private_vault.dart';
import '../widgets/mini_player.dart';
import '../models/saved_server.dart';
import '../services/native_bridge.dart';
import '../widgets/cleaner_sheet.dart';
import '../widgets/playlist_panel.dart';
import '../widgets/video_picker_sheet.dart';
import '../widgets/user_manual_sheet.dart';
import 'private_screen.dart';
import '../widgets/video_list_item.dart';
import '../widgets/video_tile.dart';
import 'history_screen.dart';
import 'player_screen.dart';
import 'stats_screen.dart';

class LibraryScreen extends StatefulWidget {
  final VideoLibraryState library;
  final MediaPlayerState player;

  const LibraryScreen({super.key, required this.library, required this.player});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  /// v26: last known Private-vault change counter. Returning from the
  /// Private folder rescans ONLY when this differs (see below) - a plain
  /// look inside no longer reloads the library grid.
  int _lastVaultRevision = PrivateVault.revision;

  /// v28: the quick-tiles grid tucks away while scrolling DOWN through
  /// the videos and slides back when scrolling up / reaching the top.
  final ScrollController _listScroll = ScrollController();
  double _lastListOffset = 0;
  bool _tilesVisible = true;

  void _onListScroll() {
    final offset = _listScroll.offset;
    final goingDown = offset > _lastListOffset + 6;
    final goingUp = offset < _lastListOffset - 6;
    if (_tilesVisible && goingDown && offset > 24) {
      setState(() => _tilesVisible = false);
    } else if (!_tilesVisible && (goingUp || offset <= 24)) {
      setState(() => _tilesVisible = true);
    }
    _lastListOffset = offset;
  }

  @override
  void initState() {
    super.initState();
    _listScroll.addListener(_onListScroll);
    widget.library.addListener(_onChange);
    // Automatically ask for storage permission and scan the whole device
    // the first time this screen opens.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.library.folderName == null && !widget.library.isScanning) {
        widget.library.scanAllStorage();
      }
      // If the previous session died with an error, offer the recorded
      // crash report (copyable) so it can be sent for analysis.
      CrashLog.takeLastIncludingNative().then((report) {
        if (report != null && mounted) _showCrashReport(report);
      });
    });
  }

  void _showCrashReport(String report) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a24),
        title: const Row(
          children: [
            Icon(Icons.error_outline, color: Colors.redAccent, size: 20),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Max Player closed unexpectedly',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: SelectableText(
            report,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11.5,
              fontFamily: 'monospace',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              await Clipboard.setData(ClipboardData(text: report));
              if (dialogContext.mounted) {
                Navigator.of(dialogContext).pop();
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Crash report copied - send it to the developer',
                    ),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            child: const Text('Copy'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Dismiss'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _listScroll.dispose();
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

  /// v21: long-press a video -> offer moving it into the Private folder.
  Future<void> _offerHide(VideoTrack track, VideoLibraryState lib) async {
    // v22: moving a file out of public storage needs the same "All files
    // access" grant the scanner uses. Ask up-front instead of letting the
    // move fail with a cryptic snackbar.
    if (!await Permission.manageExternalStorage.isGranted) {
      final status = await Permission.manageExternalStorage.request();
      if (!mounted) return;
      if (!status.isGranted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Private folder needs "All files access": allow it, then '
              'long-press the video again',
            ),
          ),
        );
        return;
      }
    }
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a24),
        title: const Text(
          'Move to Private folder?',
          style: TextStyle(color: Colors.white, fontSize: 17),
        ),
        content: Text(
          '"${track.title}" moves into the app\'s private folder - invisible '
          'to Gallery and file managers, visible here only after your PIN.\n\n'
          'Warning: uninstalling the app deletes hidden videos.',
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 13,
            height: 1.45,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.lock_outline, size: 16),
            label: const Text('Hide'),
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              try {
                await PrivateVault().hide(track.path);
                widget.player.removeHistoryEntry(track.path);
                lib.rescan();
                // v26: the rescan above already reflects this move - keep
                // the stamp in sync so closing the Private folder later
                // doesn't rescan AGAIN for the same change.
                _lastVaultRevision = PrivateVault.revision;
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Moved to Private folder')),
                  );
                }
              } catch (e) {
                if (mounted) {
                  // v22: show WHY it failed (was a bare "Could not hide")
                  final why = e
                      .toString()
                      .replaceAll('FileSystemException: ', '')
                      .replaceAll('Exception: ', '');
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Could not hide: $why')),
                  );
                }
              }
            },
          ),
        ],
      ),
    );
  }

  /// v28: the Private folder moved from the top bar into the quick-tiles
  /// grid. v26: rescan on return ONLY when something was actually
  /// hidden/unhidden inside (the revision counter moves on every vault
  /// file move) - a plain visit no longer reloads the grid.
  Future<void> _openPrivate(VideoLibraryState lib) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        // v29: the vault screen gets the library too (its "+" button
        // moves selected videos into the vault).
        builder: (_) => PrivateScreen(player: widget.player, library: lib),
      ),
    );
    final rev = PrivateVault.revision;
    if (rev != _lastVaultRevision) {
      _lastVaultRevision = rev;
      lib.rescan();
    }
  }

  /// v28 "Playlist" tile: the current play queue in a bottom sheet.
  /// v29: "Build playlist" creates a queue from videos you SELECT.
  /// v30: "+" appends videos to the queue; the player shows ONLY these.
  void _showQueueSheet(VideoLibraryState lib) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1a1a24),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => SafeArea(
          child: SizedBox(
            height: 420,
            child: Column(
              children: [
                Row(
                  children: [
                    const SizedBox(width: 20),
                    Expanded(
                      child: Text(
                        'Playlist - ${widget.player.playlist.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    // v30: "+" appends picked videos to the current queue.
                    IconButton(
                      tooltip: 'Add videos',
                      onPressed: () {
                        Navigator.of(sheetContext).pop();
                        _showAppendPicker(lib);
                      },
                      icon: Icon(Icons.add, color: themeState.accent),
                    ),
                    // Replaces the whole queue and starts playing it now.
                    TextButton.icon(
                      onPressed: () {
                        Navigator.of(sheetContext).pop();
                        _showPlaylistPicker(lib);
                      },
                      icon: Icon(Icons.playlist_add, color: themeState.accent),
                      label: const Text('Build playlist'),
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
                Expanded(
                  child: widget.player.playlist.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(28),
                            child: Text(
                              'The playlist is empty - tap + to add videos '
                              'one by one, or "Build playlist" to pick some '
                              'and play them right away. The player then '
                              'shows only these videos.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white54,
                                height: 1.4,
                              ),
                            ),
                          ),
                        )
                      : PlaylistPanel(
                          playlist: widget.player.playlist,
                          currentIndex: widget.player.currentIndex,
                          onPlay: (i) {
                            widget.player.playTrack(i);
                            Navigator.of(sheetContext).pop();
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    PlayerScreen(player: widget.player),
                              ),
                            );
                          },
                          onRemove: (i) {
                            widget.player.removeFromPlaylist(i);
                            setSheetState(() {});
                          },
                          onClose: () => Navigator.of(sheetContext).pop(),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// v29: select videos -> they become the play queue and start playing.
  Future<void> _showPlaylistPicker(VideoLibraryState lib) async {
    final selected = await VideoPickerSheet.show(
      context,
      lib.videos,
      title: 'Build a playlist',
      actionLabel: 'Play',
    );
    if (selected == null || selected.isEmpty || !mounted) return;
    widget.player.setPlaylistAndPlay(selected, 0);
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PlayerScreen(player: widget.player)),
    );
  }

  /// v30: "+" in the playlist sheet - appends the picked videos to the
  /// current queue (duplicates skipped), then reopens the sheet so the
  /// user sees the new entries; tapping one plays only the playlist.
  Future<void> _showAppendPicker(VideoLibraryState lib) async {
    final selected = await VideoPickerSheet.show(
      context,
      lib.videos,
      title: 'Add to playlist',
      actionLabel: 'Add',
    );
    if (selected == null || selected.isEmpty || !mounted) return;
    final before = widget.player.playlist.length;
    widget.player.addToPlaylist(selected);
    final added = widget.player.playlist.length - before;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          added == 0
              ? 'Those videos are already in the playlist'
              : 'Added $added video${added == 1 ? '' : 's'} to the playlist',
        ),
      ),
    );
    _showQueueSheet(lib);
  }

  /// v28 "Folders" tile: show only one folder's videos (or everything).
  void _showFoldersSheet(VideoLibraryState lib) {
    final counts = lib.folderCounts;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1a1a24),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
            const SizedBox(height: 6),
            ListTile(
              leading: Icon(
                Icons.video_library_outlined,
                color: themeState.accent,
              ),
              title: const Text(
                'All videos',
                style: TextStyle(color: Colors.white),
              ),
              trailing: lib.folderFilter == null
                  ? Icon(Icons.check, color: themeState.accent)
                  : Text(
                      '${lib.allVideosCount}',
                      style: const TextStyle(color: Colors.white38),
                    ),
              onTap: () {
                lib.setFolderFilter(null);
                Navigator.of(sheetContext).pop();
              },
            ),
            const Divider(height: 1, color: Colors.white12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 340),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final e in counts.entries)
                    ListTile(
                      leading: Icon(
                        Icons.folder_outlined,
                        color: themeState.accent,
                      ),
                      title: Text(
                        e.key,
                        style: const TextStyle(color: Colors.white),
                      ),
                      subtitle: Text(
                        '${e.value} ${e.value == 1 ? 'video' : 'videos'}',
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 12,
                        ),
                      ),
                      trailing: lib.folderFilter == e.key
                          ? Icon(Icons.check, color: themeState.accent)
                          : null,
                      onTap: () {
                        lib.setFolderFilter(e.key);
                        Navigator.of(sheetContext).pop();
                      },
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _onMenuChoice(String choice, VideoLibraryState lib) {
    switch (choice) {
      case 'stream':
        _openStreamDialog();
        break;
      case 'stats':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => StatsScreen(player: widget.player)),
        );
        break;
      case 'rescan':
        _rescan(lib);
        break;
      case 'manual':
        UserManualSheet.show(context);
        break;
      case 'about':
        AboutSheet.show(context);
        break;
      case 'display':
        DisplaySettingsSheet.show(context, lib);
        break;
    }
  }

  /// User-triggered rescan (top-bar ⟳ button or the ⋮ menu entry) with
  /// feedback so it's obvious something is happening.
  void _rescan(VideoLibraryState lib) {
    if (lib.isScanning) return;
    lib.rescan();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Rescanning device for videos…'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
  }

  /// Lets the user paste an http(s)/rtsp/rtmp URL and play it directly.
  /// v32 BYOS phase A: the stream dialog doubles as the "saved servers"
  /// list - NAS boxes over WebDAV/HTTP, public share links, IP cameras...
  /// stored as JSON in the native settings store (no account, no cloud
  /// lock-in: the user brings the storage, we are the player).
  Future<void> _openStreamDialog() async {
    final controller = TextEditingController();
    final all = await NativeBridge.loadSettings();
    var servers = parseServersJson(all[kServersSettingKey]);
    if (!mounted) return;

    Future<void> persist() =>
        NativeBridge.saveSetting(kServersSettingKey, serversToJson(servers));

    void snack(String message) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
    }

    final url = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1a1a24),
          title: const Text(
            'Open stream / server',
            style: TextStyle(color: Colors.white, fontSize: 17),
          ),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: controller,
                  autofocus: true,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    hintText: 'https:// or rtsp:// ... (WebDAV/NAS links work)',
                    hintStyle: TextStyle(color: Colors.white38),
                  ),
                ),
                if (servers.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(
                    'Saved servers',
                    style: TextStyle(
                      color: themeState.accent,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 150),
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (var i = 0; i < servers.length; i++)
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              Icons.dns_outlined,
                              color: themeState.accent,
                              size: 20,
                            ),
                            title: Text(
                              servers[i].name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13.5,
                              ),
                            ),
                            subtitle: Text(
                              servers[i].url,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white38,
                                fontSize: 11,
                              ),
                            ),
                            trailing: IconButton(
                              tooltip: 'Remove server',
                              icon: const Icon(
                                Icons.close,
                                color: Colors.white38,
                                size: 18,
                              ),
                              onPressed: () async {
                                servers = [...servers]..removeAt(i);
                                await persist();
                                setDialogState(() {});
                              },
                            ),
                            onTap: () =>
                                Navigator.of(dialogContext).pop(servers[i].url),
                          ),
                      ],
                    ),
                  ),
                ] else
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text(
                      'Tip: press Save to keep a link (NAS, camera, share '
                      'URL) in this list.',
                      style: TextStyle(color: Colors.white38, fontSize: 11.5),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            TextButton.icon(
              icon: Icon(
                Icons.bookmark_add_outlined,
                size: 18,
                color: themeState.accent,
              ),
              label: const Text('Save'),
              onPressed: () async {
                final u = controller.text.trim();
                if (!_isStreamUrl(u)) {
                  snack('Enter a valid URL first');
                  return;
                }
                final before = servers.length;
                servers = addSavedServer(
                  servers,
                  SavedServer(name: _serverNameFor(u), url: u),
                );
                await persist();
                setDialogState(() {});
                snack(
                  servers.length > before
                      ? 'Server saved - tap it here any time'
                      : 'That link is already saved',
                );
              },
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: themeState.accent),
              onPressed: () =>
                  Navigator.of(dialogContext).pop(controller.text.trim()),
              child: const Text('Play'),
            ),
          ],
        ),
      ),
    );
    if (url == null || url.isEmpty) return;
    if (!_isStreamUrl(url)) {
      snack('That does not look like a stream URL');
      return;
    }
    final uri = Uri.parse(url);
    final title =
        uri.pathSegments.isNotEmpty && uri.pathSegments.last.isNotEmpty
        ? Uri.decodeComponent(uri.pathSegments.last)
        : uri.host;
    await widget.player.playStream(url, title);
    if (!mounted) return;
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
          child: const Text(
            'Max Player',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
          ),
        ),
        actions: [
          // v26: all home-screen buttons follow the picked theme colour.
          // Prominent rescan button (new videos don't appear otherwise).
          IconButton(
            tooltip: 'Rescan library',
            onPressed: lib.isScanning ? null : () => _rescan(lib),
            icon: lib.isScanning
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: themeState.accent,
                    ),
                  )
                : Icon(Icons.sync, color: themeState.accent),
          ),
          IconButton(
            tooltip: 'History',
            icon: Icon(Icons.history, color: themeState.accent),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => HistoryScreen(player: widget.player),
              ),
            ),
          ),

          PopupMenuButton<String>(
            tooltip: 'More',
            icon: Icon(Icons.more_vert, color: themeState.accent),
            color: const Color(0xFF26262f),
            onSelected: (choice) => _onMenuChoice(choice, lib),
            // v26: menu icons follow the picked theme colour.
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'stream',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.link, color: themeState.accent),
                  title: const Text('Open stream URL'),
                ),
              ),
              PopupMenuItem(
                value: 'stats',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.bar_chart, color: themeState.accent),
                  title: const Text('Statistics'),
                ),
              ),
              PopupMenuItem(
                value: 'rescan',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.refresh, color: themeState.accent),
                  title: const Text('Rescan library'),
                ),
              ),
              PopupMenuItem(
                value: 'display',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.tune, color: themeState.accent),
                  title: const Text('Display settings'),
                ),
              ),
              PopupMenuItem(
                value: 'manual',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.menu_book_outlined,
                    color: themeState.accent,
                  ),
                  title: const Text('User manual'),
                ),
              ),
              PopupMenuItem(
                value: 'about',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.info_outline, color: themeState.accent),
                  title: const Text('About'),
                ),
              ),
              // Footer: app version (not selectable).
              const PopupMenuItem(
                value: 'version',
                enabled: false,
                height: 30,
                padding: EdgeInsets.zero,
                child: Center(
                  child: Text(
                    'Version $kAppVersion',
                    style: TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      // Mini player sits at the bottom while something is loaded.
      bottomNavigationBar: MiniPlayer(player: widget.player),
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
                // v26: theme-coloured like the other home buttons.
                prefixIcon: Icon(Icons.search, color: themeState.accent),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.05),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          // v28: active folder filter chip (set from the Folders tile).
          if (lib.folderFilter != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: InputChip(
                  avatar: Icon(
                    Icons.folder_outlined,
                    size: 16,
                    color: themeState.accent,
                  ),
                  label: Text('Folder: ${lib.folderFilter}'),
                  labelStyle: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                  ),
                  onDeleted: () => lib.setFolderFilter(null),
                  deleteIconColor: Colors.white54,
                  backgroundColor: Colors.white.withValues(alpha: 0.06),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(
                      color: themeState.accent.withValues(alpha: 0.4),
                    ),
                  ),
                ),
              ),
            ),
          // v28: the 2x2 quick-tiles grid - slides away on scroll-down.
          ClipRect(
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              heightFactor: _tilesVisible ? 1.0 : 0.0,
              alignment: Alignment.topCenter,
              child: _QuickTiles(
                accent: themeState.accent,
                onPrivate: () => _openPrivate(lib),
                onCleaner: () => CleanerSheet.show(
                  context,
                  player: widget.player,
                  library: lib,
                ),
                onPlaylist: () => _showQueueSheet(lib),
                onFolders: () => _showFoldersSheet(lib),
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
                    color: themeState.accent,
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
          // Soft crossfade between grid/list/empty states.
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              child: _buildBody(lib),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(VideoLibraryState lib) {
    // Single evaluation - the getter filters+sorts, so compute once per build.
    final groups = lib.groups;
    final visibleCount = groups.fold<int>(0, (sum, g) => sum + g.videos.length);

    if (visibleCount == 0) {
      return _EmptyState(
        key: const ValueKey('empty'),
        isScanning: lib.isScanning,
        permissionDenied: lib.permissionDenied,
        favoritesOnly: lib.favoritesOnly,
        onGrantAccess: lib.scanAllStorage,
      );
    }

    // Keyed by view mode so grid <-> list crossfades through the
    // AnimatedSwitcher above. v28: the controller drives the quick-tiles
    // auto-hide on downward scrolls.
    return CustomScrollView(
      key: ValueKey(lib.viewMode),
      controller: _listScroll,
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
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 220,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.82,
                ),
                delegate: SliverChildBuilderDelegate((context, i) {
                  final track = group.videos[i];
                  return GestureDetector(
                    // v21: long-press moves the video to the Private folder.
                    onLongPress: () => _offerHide(track, lib),
                    child: VideoTile(
                      track: track,
                      isFavorite: lib.isFavorite(track),
                      onTap: () => _playVideo(track),
                      onFavorite: () => lib.toggleFavorite(track),
                    ),
                  );
                }, childCount: group.videos.length),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate((context, i) {
                  final track = group.videos[i];
                  return GestureDetector(
                    // v21: long-press moves the video to the Private folder.
                    onLongPress: () => _offerHide(track, lib),
                    child: VideoListItem(
                      track: track,
                      isFavorite: lib.isFavorite(track),
                      onTap: () => _playVideo(track),
                      onFavorite: () => lib.toggleFavorite(track),
                    ),
                  );
                }, childCount: group.videos.length),
              ),
            ),
        ],
      ],
    );
  }
}

/// v28: the 2x2 quick-tiles grid under the search bar. Tucks away while
/// scrolling down through the videos (see [_LibraryScreenState]) and
/// returns on scroll-up. Private folder lives here now (was a top-bar
/// icon).
class _QuickTiles extends StatelessWidget {
  final Color accent;
  final VoidCallback onPrivate;
  final VoidCallback onCleaner;
  final VoidCallback onPlaylist;
  final VoidCallback onFolders;

  const _QuickTiles({
    required this.accent,
    required this.onPrivate,
    required this.onCleaner,
    required this.onPlaylist,
    required this.onFolders,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _Tile(
                  Icons.lock_outline,
                  'Private folder',
                  accent,
                  onPrivate,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Tile(
                  Icons.cleaning_services_outlined,
                  'Cleaner',
                  accent,
                  onCleaner,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _Tile(
                  Icons.queue_music_outlined,
                  'Playlist',
                  accent,
                  onPlaylist,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Tile(
                  Icons.folder_outlined,
                  'Folders',
                  accent,
                  onFolders,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color accent;
  final VoidCallback onTap;

  const _Tile(this.icon, this.label, this.accent, this.onTap);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.05),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        splashColor: accent.withValues(alpha: 0.25),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              Icon(icon, color: accent, size: 20),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
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
    super.key,
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
          const Icon(
            Icons.video_library_outlined,
            size: 48,
            color: Colors.white24,
          ),
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

// ---------------------------------------------------------------------------
// v32 BYOS: stream/server URL helpers for the Open stream dialog.
// ---------------------------------------------------------------------------

bool _isStreamUrl(String url) {
  final uri = Uri.tryParse(url);
  const schemes = {'http', 'https', 'rtsp', 'rtmp', 'mms'};
  return uri != null &&
      schemes.contains(uri.scheme.toLowerCase()) &&
      uri.host.isNotEmpty;
}

String _serverNameFor(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return url;
  return uri.hasPort && uri.port != 80 && uri.port != 443
      ? '${uri.host}:${uri.port}'
      : uri.host;
}
EOF_MARKER_16

mkdir -p "$(dirname 'lib/screens/player_screen.dart')"
cat > 'lib/screens/player_screen.dart' <<'EOF_MARKER_17'
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../cast/cast_state.dart';
import '../services/native_bridge.dart';
import '../state/media_player_state.dart';
import '../state/player_settings.dart';
import '../state/theme_state.dart';
import '../utils/formatters.dart';
import '../utils/srt.dart';
import '../widgets/cast_sheet.dart';
import '../widgets/equalizer_sheet.dart';
import '../widgets/karaoke_subtitle.dart';
import '../widgets/player_controls_overlay.dart';
import '../widgets/player_settings_sheet.dart';
import '../widgets/playlist_panel.dart';
import '../widgets/video_info_sheet.dart';

class PlayerScreen extends StatefulWidget {
  final MediaPlayerState player;

  const PlayerScreen({super.key, required this.player});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen>
    with WidgetsBindingObserver {
  // Shared, app-lifetime controller owned by MediaPlayerState (this media_kit
  // version has no VideoController.dispose, so per-visit controllers leaked).
  late final VideoController _controller = widget.player.videoController;

  /// DLNA cast session for this visit to the player. Disposed with the
  /// screen (leaving the player stops casting).
  final CastState _castState = CastState();

  bool _controlsVisible = true;
  bool _isFullscreen = false;
  bool _showQueue = false;
  bool _isPip = false;

  /// Screen lock (kids mode): every gesture/button is swallowed until the
  /// on-screen lock is double-tapped (or long-pressed).
  bool _locked = false;

  // Orientation lock (rotation toggle in the controls).
  bool _orientationLocked = false;
  List<DeviceOrientation> _lockedOrientations = DeviceOrientation.values;

  // Customizable behavior (persisted, edited in the Settings sheet).
  PlayerSettings _settings = const PlayerSettings();

  Timer? _hideTimer;

  // Transient center indicator ("+10s", "Volume 80%", "Resumed 12:34", ...).
  String? _indicatorText;
  IconData? _indicatorIcon;
  String? _indicatorKey; // dedupe: identical text just refreshes the timer
  Timer? _indicatorTimer;
  StreamSubscription<String>? _noticeSub;

  // v20 fit cycle with REAL size choices (the old contain/cover/fill trio
  // looked identical for 16:9 videos, so it felt like "fit does nothing").
  // aspectRatio forces the frame to that shape (stretch); null keeps the
  // video's own aspect ratio.
  static const List<BoxFit> _fits = [
    BoxFit.contain, // Fit - whole frame visible
    BoxFit.cover, // Crop - fill screen, edges cropped
    BoxFit.fill, // Stretch - fill screen, ignores aspect
    BoxFit.fill, // 16:9 - frame forced to widescreen
    BoxFit.fill, // 4:3 - frame forced to classic TV
    BoxFit.none, // Original - pixels 1:1, may overflow
  ];
  static const List<double?> _fitAspects = [
    null,
    null,
    null,
    16 / 9,
    4 / 3,
    null,
  ];
  static const List<String> _fitNames = [
    'Fit',
    'Crop',
    'Stretch',
    '16:9',
    '4:3',
    'Original',
  ];
  int _fitIndex = 0;
  static const List<IconData> _fitIcons = [
    Icons.fit_screen,
    Icons.crop,
    Icons.open_in_full,
    Icons.crop_16_9,
    Icons.crop_landscape,
    Icons.crop_original,
  ];

  // Pinch zoom (1x..4x), anchored at the fingers' focal point, with
  // one-finger panning while zoomed.
  double _zoom = 1.0;
  double _zoomBase = 1.0;
  Offset _pan = Offset.zero;
  Offset _panBase = Offset.zero;
  Offset _focalBase = Offset.zero;

  // Gesture plumbing (double-tap seek / unified drag handling).
  double _gestureWidth = 0;
  double _gestureHeight = 0;
  double _lastDoubleTapDx = 0;

  // --- Unified single-recognizer drag handling -----------------------------
  //
  // EVERYTHING drag-ish (volume / brightness / horizontal seek / zoom-pan)
  // is handled through the scale recognizer only. The old code ALSO
  // registered onVerticalDrag* on the same GestureDetector, and the two
  // recognizers fought in the gesture arena - whichever won was decided by
  // tiny direction differences, which is exactly what made the volume swipe
  // feel "glitchy". One recognizer = deterministic behavior.
  _ScaleMode _scaleMode = _ScaleMode.undecided;
  Offset _dragAccum = Offset.zero;
  Offset _focalStart = Offset.zero;
  double _dragStartValue = 0;

  // Horizontal seek drag.
  Duration _seekBasePos = Duration.zero;
  Duration? _seekTarget;
  int _seekLastAppliedSec = -1;

  // Volume drag dedupe (cuts mpv IPC + indicator reflows ~10x).
  int _lastVolPct = -1;

  // NOTE: no addListener/setState on the player here. The ticking parts
  // (overlay, spinner, queue, title) listen via their own AnimatedBuilder,
  // so the video surface itself is never rebuilt during playback.

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // v19: rotation is driven by our own accelerometer listener, so the
    // player rotates even when the phone's auto-rotate switch is OFF
    // (MX Player / VLC style). The lock chip pins the current orientation;
    // dispose() hands control back to the system.
    unawaited(NativeBridge.enableSensorRotate());
    _noticeSub = widget.player.notices.listen(
      (m) => _showIndicator(m, Icons.history),
    );
    NativeBridge.configureCallbacks(
      onPipChanged: (isPip) {
        if (mounted) setState(() => _isPip = isPip);
      },
    );
    _reloadSettings();
    widget.player.currentBrightness(); // sync once for the swipe gesture
    widget.player.currentVolume(); // start swipe from REAL device volume
    _startHideTimer();
  }

  @override
  void dispose() {
    _castState.dispose(); // stops casting + the embedded file server
    WidgetsBinding.instance.removeObserver(this);
    _hideTimer?.cancel();
    _indicatorTimer?.cancel();
    _noticeSub?.cancel();
    if (_isFullscreen) _exitFullscreen();
    // Hand rotation control back to the system; never leave a lock behind.
    unawaited(NativeBridge.disableSensorRotate());
    // Do NOT keep the audio running after leaving the player screen, and
    // hand brightness control back to the system.
    unawaited(widget.player.pause());
    unawaited(widget.player.resetBrightness());
    super.dispose();
  }

  /// Pause when the app goes to the background (sound must not keep playing
  /// with the app hidden).
  ///
  /// IMPORTANT: entering picture-in-picture maps to AppLifecycleState.
  /// inactive on Android - we must NOT pause for it, and we must skip the
  /// fully-backgrounded states while the PiP window is up. Otherwise PiP
  /// would freeze the video the moment it opens.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_isPip) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      widget.player.pause();
    }
  }

  Future<void> _reloadSettings() async {
    final s = await PlayerSettings.load();
    if (mounted) setState(() => _settings = s);
    // v21: push the playback-extras settings into the player state.
    unawaited(widget.player.setVolumeBoost200(s.volumeBoost200));
    unawaited(widget.player.setVolumeLeveling(s.volumeLeveling));
    // v32: picture settings - HDR tone-mapping curve + Enhance shader.
    unawaited(widget.player.setToneMapping(s.toneMapping));
    unawaited(widget.player.setEnhanceVideo(s.enhanceVideo));
    _applyKaraokeSubtitleVisibility(s);
    _startHideTimer();
  }

  /// Karaoke mode replaces mpv's own subtitle rendering with our
  /// word-highlight overlay. v22: the visibility decision now lives in the
  /// player state (setKaraokeMode) so it also reacts to track switches and
  /// late-arriving cue files; karaoke itself now reads mpv's live subtitle
  /// line, so it works with embedded and auto-loaded subtitles too.
  void _applyKaraokeSubtitleVisibility(PlayerSettings s) {
    unawaited(widget.player.setKaraokeMode(s.karaokeSubs));
  }

  /// v25: one karaoke switch used by the tracks sheet tile (the setting
  /// persists like before).
  void _toggleKaraoke() {
    final next = _settings.copyWith(karaokeSubs: !_settings.karaokeSubs);
    setState(() => _settings = next);
    next.save();
    _applyKaraokeSubtitleVisibility(next);
    if (next.karaokeSubs && widget.player.aiCues == null) {
      widget.player.refreshAiCues(widget.player.currentTrack?.path ?? '');
    }
    _onUserInteraction();
  }

  Future<void> _openSettings() async {
    await PlayerSettingsSheet.show(context);
    await _reloadSettings(); // apply changes immediately
  }

  // ---------------------------------------------------------------------------
  // Controls visibility (auto-hide)
  // ---------------------------------------------------------------------------

  void _startHideTimer() {
    _hideTimer?.cancel();
    final delay = _settings.autoHideSeconds;
    if (delay <= 0) return; // "never auto-hide"
    _hideTimer = Timer(Duration(seconds: delay), () {
      // Only auto-hide during playback; keep controls up while paused.
      if (mounted && widget.player.isPlaying) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  /// Called by the overlay on every button press / seek / menu selection so
  /// the auto-hide countdown restarts on any interaction.
  void _onUserInteraction() {
    if (_controlsVisible) _startHideTimer();
  }

  /// v26: while the seek bar is being DRAGGED, the auto-hide countdown
  /// pauses - the controls must never fade away mid-scrub.
  void _onScrubChanged(bool scrubbing) {
    if (scrubbing) {
      _hideTimer?.cancel();
    } else if (_controlsVisible) {
      _startHideTimer();
    }
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) {
      _startHideTimer();
    } else {
      _hideTimer?.cancel();
    }
  }

  // ---------------------------------------------------------------------------
  // Screen lock (kids mode)
  // ---------------------------------------------------------------------------

  void _lockScreen() {
    _hideTimer?.cancel();
    setState(() {
      _locked = true;
      _controlsVisible = false;
    });
    _showIndicator('Screen locked', Icons.lock);
  }

  void _unlockScreen() {
    setState(() {
      _locked = false;
      _controlsVisible = true;
    });
    _startHideTimer();
    _showIndicator('Unlocked', Icons.lock_open);
  }

  void _showLockHint() {
    _showIndicator('Locked - double-tap the lock to unlock', Icons.lock);
  }

  // ---------------------------------------------------------------------------
  // Transient indicator
  // ---------------------------------------------------------------------------

  void _showIndicator(String text, [IconData? icon]) {
    if (!mounted) return;
    _indicatorTimer?.cancel();
    _indicatorKey = '$text|${icon?.codePoint ?? 0}';
    setState(() {
      _indicatorText = text;
      _indicatorIcon = icon;
    });
    _indicatorTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _indicatorText = null);
    });
  }

  /// Same as [_showIndicator] but an unchanged message only refreshes the
  /// hide timer (no setState flood while a drag gesture keeps reporting the
  /// same percentage).
  void _showIndicatorThrottled(String text, [IconData? icon]) {
    if (!mounted) return;
    final key = '$text|${icon?.codePoint ?? 0}';
    if (key == _indicatorKey) {
      _indicatorTimer?.cancel();
      _indicatorTimer = Timer(const Duration(milliseconds: 900), () {
        if (mounted) setState(() => _indicatorText = null);
      });
      return;
    }
    _showIndicator(text, icon);
  }

  // ---------------------------------------------------------------------------
  // Fullscreen, fit, zoom
  // ---------------------------------------------------------------------------

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
    _onUserInteraction();
  }

  void _exitFullscreen() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    // Respect an active rotation lock when leaving fullscreen.
    SystemChrome.setPreferredOrientations(
      _orientationLocked ? _lockedOrientations : DeviceOrientation.values,
    );
  }

  /// Rotation toggle: sensor auto-rotate <-> pinned to portrait/landscape.
  void _toggleOrientationLock() {
    final landscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    if (!_orientationLocked) {
      unawaited(NativeBridge.lockRotation(landscape: landscape));
      setState(() {
        _orientationLocked = true;
        _lockedOrientations = landscape
            ? const [
                DeviceOrientation.landscapeLeft,
                DeviceOrientation.landscapeRight,
              ]
            : const [
                DeviceOrientation.portraitUp,
                DeviceOrientation.portraitDown,
              ];
      });
      _showIndicator('Rotation locked', Icons.screen_lock_rotation);
    } else {
      _lockedOrientations = DeviceOrientation.values;
      setState(() => _orientationLocked = false);
      unawaited(NativeBridge.enableSensorRotate());
      _showIndicator('Auto-rotate on', Icons.screen_rotation);
    }
    _onUserInteraction();
  }

  // ---------------------------------------------------------------------------
  // Long-press speed boost (customizable multiplier)
  // ---------------------------------------------------------------------------

  void _onLongPressStart(LongPressStartDetails _) {
    if (!_settings.longPressSpeed) return;
    // No boost (and no badge) while the video is paused.
    if (!widget.player.isPlaying) return;
    widget.player.startSpeedBoost(_settings.longPressMultiplier);
    setState(() {}); // mount the persistent "Nx" badge
    // NOTE: no flash indicator here - the persistent purple badge IS the
    // feedback (showing both looked like a duplicated "2x" bug).
  }

  void _onLongPressEnd(LongPressEndDetails _) {
    widget.player.stopSpeedBoost();
    setState(() {}); // remove the persistent badge
  }

  /// Which intro chip the user dismissed (per dialogue-start time; a new
  /// track recomputes it, so the chip auto-reappears for the next video).
  Duration? _skipChipDismissedFor;

  // ---------------------------------------------------------------------------
  // Sleep timer (v21)
  // ---------------------------------------------------------------------------

  void _showSleepSheet() {
    final player = widget.player;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1a1a24),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        Widget item(
          IconData icon,
          String label, {
          String? sub,
          bool active = false,
          VoidCallback? onTap,
        }) {
          return ListTile(
            leading: Icon(
              icon,
              color: active ? themeState.accent : Colors.white70,
            ),
            title: Text(
              label,
              style: TextStyle(
                color: active ? themeState.accent : Colors.white,
              ),
            ),
            subtitle: sub == null
                ? null
                : Text(
                    sub,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
            trailing: active
                ? Icon(Icons.check, color: themeState.accent)
                : null,
            onTap: () {
              Navigator.of(sheetContext).pop();
              onTap?.call();
              _onUserInteraction();
            },
          );
        }

        return SafeArea(
          child: AnimatedBuilder(
            animation: player,
            builder: (context, _) {
              final label = player.sleepTimerLabel;
              return Column(
                mainAxisSize: MainAxisSize.min,
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
                  const SizedBox(height: 10),
                  Text(
                    label == null
                        ? 'Sleep timer'
                        : 'Sleep timer: stops in $label',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  for (final mins in const [15, 30, 45, 60])
                    item(
                      Icons.bedtime_outlined,
                      '$mins minutes',
                      active: label == '$mins min',
                      onTap: () => player.setSleepTimer(
                        forDuration: Duration(minutes: mins),
                      ),
                    ),
                  item(
                    Icons.movie_outlined,
                    'Until end of this video',
                    active: label == 'end of video',
                    onTap: () => player.setSleepTimer(atEndOfVideo: true),
                  ),
                  item(Icons.close, 'Off', onTap: player.cancelSleepTimer),
                  const SizedBox(height: 8),
                ],
              );
            },
          ),
        );
      },
    );
  }

  void _cycleFit() {
    setState(() => _fitIndex = (_fitIndex + 1) % _fits.length);
    _showIndicator('Fit: ${_fitNames[_fitIndex]}', _fitIcons[_fitIndex]);
    _onUserInteraction();
  }

  // ---------------------------------------------------------------------------
  // Unified scale recognizer (pinch zoom + ALL drag gestures)
  // ---------------------------------------------------------------------------

  void _onScaleStart(ScaleStartDetails details) {
    _scaleMode = _ScaleMode.undecided;
    _dragAccum = Offset.zero;
    _focalStart = details.localFocalPoint;
    _zoomBase = _zoom;
    _panBase = _pan;
    _focalBase = details.localFocalPoint;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    // Two+ fingers -> pinch zoom (focal-anchored).
    if (details.pointerCount >= 2) {
      if (!_settings.pinchZoom) return;
      _scaleMode = _ScaleMode.zoom;

      // Focal-anchored transform: the content point that was under the
      // fingers when the pinch started stays glued to the CURRENT focal
      // point. Because we track the live focal point, moving both fingers
      // together pans the zoomed video for free.
      final z = (_zoomBase * details.scale).clamp(1.0, 4.0);
      final contentV = (_focalBase - _panBase) / _zoomBase;
      final pan = _clampPan(details.localFocalPoint - contentV * z, z);

      if (z == _zoom && pan == _pan) return;
      setState(() {
        _zoom = z;
        _pan = pan;
      });
      if (details.scale != 1.0) {
        _showIndicator('Zoom ${z.toStringAsFixed(1)}x', Icons.pinch_outlined);
      }
      return;
    }

    // One finger -> figure out WHAT the drag is once we're past the slop,
    // then stick with that mode until the gesture ends.
    switch (_scaleMode) {
      case _ScaleMode.zoom:
        return; // came from two fingers; ignore until scale end
      case _ScaleMode.cant:
        return; // all relevant gestures are disabled
      case _ScaleMode.volume:
      case _ScaleMode.brightness:
        _dragAccum += details.focalPointDelta;
        _applyLevelDrag();
        return;
      case _ScaleMode.seekH:
        _dragAccum += details.focalPointDelta;
        _applySeekDrag();
        return;
      case _ScaleMode.pan:
        _applyPanDrag(details);
        return;
      case _ScaleMode.undecided:
        _dragAccum += details.focalPointDelta;
        if (_dragAccum.distance < 14) return; // slop
        final dx = _dragAccum.dx.abs();
        final dy = _dragAccum.dy.abs();
        if (dx > dy * 1.3) {
          // Horizontal: seek (or pan when zoomed in).
          if (_zoom > 1.0) {
            _scaleMode = _ScaleMode.pan;
            _applyPanDrag(details);
          } else if (_settings.horizontalSeek &&
              widget.player.currentTrack != null &&
              widget.player.duration > Duration.zero) {
            _scaleMode = _ScaleMode.seekH;
            _seekBasePos = widget.player.position;
            _seekTarget = null;
            _seekLastAppliedSec = -1;
            _dragAccum = Offset.zero;
          } else {
            _scaleMode = _ScaleMode.cant;
          }
        } else {
          // Vertical: volume (right half) or brightness (left half).
          final rightHalf = _focalStart.dx > _gestureWidth / 2;
          if (rightHalf && _settings.volumeSwipe) {
            _scaleMode = _ScaleMode.volume;
            _lastVolPct =
                (widget.player.isMuted ? 0.0 : widget.player.volume * 100)
                    .round();
            _dragStartValue = widget.player.isMuted
                ? 0.0
                : widget.player.volume;
          } else if (!rightHalf && _settings.brightnessSwipe) {
            _scaleMode = _ScaleMode.brightness;
            _dragStartValue = widget.player.brightness;
          } else {
            _scaleMode = _ScaleMode.cant;
            return;
          }
          _dragAccum = Offset.zero;
        }
        return;
    }
  }

  /// Volume / brightness value from the accumulated vertical movement.
  void _applyLevelDrag() {
    // Dragging up increases; a 300px sweep covers the full range. v21: the
    // volume range grows to 0..200% while the boost setting is on.
    final cap = _scaleMode == _ScaleMode.volume ? widget.player.volumeCap : 1.0;
    final v = (_dragStartValue - _dragAccum.dy / (300 * cap)).clamp(0.0, cap);
    if (_scaleMode == _ScaleMode.volume) {
      final pct = (v * 100).round();
      if (pct == _lastVolPct) return; // spare mpv from per-pixel IPC
      _lastVolPct = pct;
      widget.player.setVolume(v);
      _showIndicatorThrottled(
        'Volume $pct%',
        pct == 0 ? Icons.volume_off : Icons.volume_up,
      );
    } else {
      widget.player.setBrightness(v);
      _showIndicatorThrottled(
        'Brightness ${(v * 100).round()}%',
        Icons.brightness_6_outlined,
      );
    }
  }

  /// Horizontal scrub: a full screen-width drag is +-90 seconds. Seeks live
  /// in whole-second steps (mpv is fine with it) and lands exactly on end.
  void _applySeekDrag() {
    final dur = widget.player.duration;
    if (dur <= Duration.zero) return;
    final offsetSec = _dragAccum.dx / _gestureWidth * 90.0;
    final targetMs = (_seekBasePos.inMilliseconds + (offsetSec * 1000).round())
        .clamp(0, dur.inMilliseconds);
    final target = Duration(milliseconds: targetMs);
    _seekTarget = target;
    final diffMs = targetMs - _seekBasePos.inMilliseconds;
    final sign = diffMs >= 0 ? '+' : '-';
    _showIndicatorThrottled(
      '$sign${(diffMs.abs() / 1000).round()}s · ${formatDuration(target)}',
      diffMs >= 0 ? Icons.fast_forward : Icons.fast_rewind,
    );
    // Live-seek in 1s steps while the finger moves.
    final s = target.inSeconds;
    if ((s - _seekLastAppliedSec).abs() >= 1) {
      _seekLastAppliedSec = s;
      widget.player.seek(Duration(seconds: s));
    }
  }

  /// One-finger panning while zoomed in.
  void _applyPanDrag(ScaleUpdateDetails details) {
    if (_zoom <= 1.0) return;
    final pan = _clampPan(
      _panBase + (details.localFocalPoint - _focalBase),
      _zoom,
    );
    if (pan != _pan) setState(() => _pan = pan);
  }

  void _onScaleEnd(ScaleEndDetails details) {
    final mode = _scaleMode;
    _scaleMode = _ScaleMode.undecided;
    if (mode == _ScaleMode.seekH) {
      final t = _seekTarget;
      if (t != null) widget.player.seek(t); // exact final landing
      _seekTarget = null;
      return;
    }
    if (mode == _ScaleMode.volume || mode == _ScaleMode.brightness) return;
    if (!_settings.pinchZoom && mode != _ScaleMode.pan) return;
    // Snap back when barely zoomed.
    if (_zoom < 1.1) {
      if (_zoom != 1.0 || _pan != Offset.zero) {
        setState(() {
          _zoom = 1.0;
          _pan = Offset.zero;
        });
      }
    } else {
      setState(() => _pan = _clampPan(_pan, _zoom));
    }
  }

  /// Keep the scaled video covering the viewport (no drifting past edges).
  Offset _clampPan(Offset pan, double z) {
    final maxX = _gestureWidth * (z - 1);
    final maxY = _gestureHeight * (z - 1);
    return Offset(pan.dx.clamp(-maxX, 0.0), pan.dy.clamp(-maxY, 0.0));
  }

  // ---------------------------------------------------------------------------
  // Tap gestures
  // ---------------------------------------------------------------------------

  void _onDoubleTap() {
    final third = _gestureWidth / 3;
    if (_lastDoubleTapDx < third) {
      if (!_settings.doubleTapSeek) return;
      widget.player.seekBy(-_settings.seekSeconds);
      _showIndicator('-${_settings.seekSeconds}s', Icons.replay_10);
    } else if (_lastDoubleTapDx > _gestureWidth - third) {
      if (!_settings.doubleTapSeek) return;
      widget.player.seekBy(_settings.seekSeconds);
      _showIndicator('+${_settings.seekSeconds}s', Icons.forward_10);
    } else {
      // Middle third: play / pause.
      if (!_settings.doubleTapPlayPause) return;
      final wasPlaying = widget.player.isPlaying;
      widget.player.togglePlay();
      _showIndicator(
        wasPlaying ? 'Paused' : 'Playing',
        wasPlaying ? Icons.pause_circle_outline : Icons.play_circle_outline,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Screenshot + cast
  // ---------------------------------------------------------------------------

  Future<void> _takeScreenshot() async {
    final path = await widget.player.captureScreenshot();
    if (!mounted) return;
    _showIndicator(
      path == null
          ? 'Screenshot unavailable for streams'
          : 'Screenshot saved to gallery',
      path == null ? Icons.error_outline : Icons.camera_alt,
    );
  }

  Future<void> _openCast() async {
    final track = widget.player.currentTrack;
    if (track == null) {
      _showIndicator(
        'Nothing to cast - open a video first',
        Icons.videocam_off_outlined,
      );
      return;
    }
    // Offer AI-generated subtitles to the TV when they exist on disk.
    String? subsPath;
    if (!track.path.startsWith('http')) {
      final srt = srtPathForVideo(track.path);
      if (File(srt).existsSync()) subsPath = srt;
    }
    // Kick off the device scan right away (the sheet renders its states).
    unawaited(_castState.scan());
    await CastSheet.show(
      context,
      _castState,
      videoPath: track.path,
      title: track.title,
      subsPath: subsPath,
      onCastStarted: () {
        widget.player.pause(); // the TV is playing; phone becomes remote
        _showIndicator('Casting to TV', Icons.cast_connected);
      },
      onCastStopped: (tvPos) async {
        // Hand playback back to the phone at the TV's position.
        if (tvPos > Duration.zero) await widget.player.seek(tvPos);
        await widget.player.resumePlayback();
        if (mounted) _showIndicator('Back on this phone', Icons.smartphone);
      },
    );
  }

  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final player = widget.player;

    return PopScope(
      canPop: !_isFullscreen && !_locked,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_locked) {
          _showLockHint();
        } else {
          _toggleFullscreen();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        // v19: no Scaffold AppBar anymore - the title + actions live in an
        // auto-hiding top overlay INSIDE the video stack, so portrait video
        // gets the full height and a tap reveals title and controls
        // together (previously a tap surfaced only the bottom bar).
        body: SafeArea(
          top: !_isFullscreen,
          // v20: in LANDSCAPE the controls sit flush with the bottom edge
          // (requested - "one step down"); portrait keeps the gesture-bar
          // clearance so the seek bar is not touched by the system bar.
          bottom: MediaQuery.of(context).orientation == Orientation.portrait,
          child: Row(
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    _gestureWidth = constraints.maxWidth;
                    _gestureHeight = constraints.maxHeight;
                    return GestureDetector(
                      // While locked every gesture collapses to a lock hint.
                      onTap: _locked ? _showLockHint : _toggleControls,
                      onDoubleTapDown: _locked
                          ? null
                          : (d) => _lastDoubleTapDx = d.localPosition.dx,
                      onDoubleTap: _locked ? null : _onDoubleTap,
                      onLongPressStart: _locked ? null : _onLongPressStart,
                      onLongPressEnd: _locked ? null : _onLongPressEnd,
                      onScaleStart: _locked
                          ? (_) => _showLockHint()
                          : _onScaleStart,
                      onScaleUpdate: _locked ? null : _onScaleUpdate,
                      onScaleEnd: _locked ? null : _onScaleEnd,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          // Video surface - pinch zoom/pan applies a matrix
                          // (scale about the finger focal point), clipped to
                          // the available area.
                          Positioned.fill(
                            child: ClipRect(
                              child: Transform(
                                transform: Matrix4.identity()
                                  ..translateByDouble(_pan.dx, _pan.dy, 0, 1)
                                  ..scaleByDouble(_zoom, _zoom, _zoom, 1),
                                child: Center(
                                  child: player.currentTrack != null
                                      ? RepaintBoundary(
                                          child: Video(
                                            controller: _controller,
                                            controls: NoVideoControls,
                                            fit: _fits[_fitIndex],
                                            // v20: forces the frame to 16:9 /
                                            // 4:3 in those fit modes; null
                                            // keeps the video's own ratio.
                                            aspectRatio: _fitAspects[_fitIndex],
                                            // v26/v27: karaoke <=> normal
                                            // subtitles. The engine's own
                                            // Flutter subtitle layer IS the
                                            // normal subtitle display on
                                            // Android (this mpv build does
                                            // not paint subs into the video
                                            // frame) - so it must be ON for
                                            // normal playback and OFF only
                                            // while karaoke is on (v26: it
                                            // ignored mpv's hide flag and
                                            // drew next to karaoke; v27:
                                            // fully hiding it also hid the
                                            // normal subs).
                                            subtitleViewConfiguration:
                                                SubtitleViewConfiguration(
                                                  visible:
                                                      !_settings.karaokeSubs,
                                                ),
                                          ),
                                        )
                                      : const Text(
                                          'No video loaded',
                                          style: TextStyle(
                                            color: Colors.white38,
                                          ),
                                        ),
                                ),
                              ),
                            ),
                          ),
                          // Buffering spinner - follows the player stream only.
                          Positioned.fill(
                            child: AnimatedBuilder(
                              animation: player,
                              builder: (context, _) => player.isLoading
                                  ? Center(
                                      child: CircularProgressIndicator(
                                        color: themeState.accent,
                                      ),
                                    )
                                  : const SizedBox.shrink(),
                            ),
                          ),
                          // Transient indicator (seek / volume / brightness /
                          // zoom / resume / fit / play-pause) - pops in and
                          // out with a small scale+fade.
                          Positioned(
                            top: 72,
                            left: 0,
                            right: 0,
                            child: IgnorePointer(
                              child: Center(
                                // v19: this sign used to BLINK during
                                // volume/brightness swipes - the old
                                // switcher re-keyed itself on every tick,
                                // replaying a scale animation each time.
                                // Now: ONE stable container, only opacity
                                // animates, text/icon swap in place.
                                child: AnimatedOpacity(
                                  duration: const Duration(milliseconds: 120),
                                  opacity: (_indicatorText != null && !_isPip)
                                      ? 1.0
                                      : 0.0,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(
                                        alpha: 0.72,
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (_indicatorIcon != null) ...[
                                          Icon(
                                            _indicatorIcon,
                                            color: Colors.white,
                                            size: 20,
                                          ),
                                          const SizedBox(width: 8),
                                        ],
                                        Text(
                                          _indicatorText ?? '',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          // v20: BIG centred "2x" sign in the MIDDLE of the
                          // video for the WHOLE long-press boost (replaces the
                          // small top badge). Follows the player state
                          // directly, so it vanishes the moment the video is
                          // paused during a boost.
                          Positioned.fill(
                            child: IgnorePointer(
                              child: Center(
                                child: AnimatedBuilder(
                                  animation: player,
                                  builder: (context, _) => AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 160),
                                    transitionBuilder: (child, anim) =>
                                        FadeTransition(
                                          opacity: anim,
                                          child: ScaleTransition(
                                            scale: anim,
                                            child: child,
                                          ),
                                        ),
                                    child:
                                        (player.isSpeedBoosting &&
                                            player.isPlaying &&
                                            !_isPip)
                                        ? Container(
                                            key: const ValueKey('speedBadge'),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 14,
                                              vertical: 7,
                                            ),
                                            decoration: BoxDecoration(
                                              color: themeState.accent
                                                  .withValues(alpha: 0.9),
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  Icons.fast_forward,
                                                  // v22: stays readable on
                                                  // the white accent too.
                                                  color: themeState.onAccent,
                                                  size: 19,
                                                ),
                                                const SizedBox(width: 5),
                                                Text(
                                                  '${_settings.longPressMultiplier}x',
                                                  style: TextStyle(
                                                    color: themeState.onAccent,
                                                    fontSize: 15,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          )
                                        : const SizedBox.shrink(
                                            key: ValueKey('noSpeedBadge'),
                                          ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          // Screen-lock ENTER button (left edge, shown with
                          // the controls, MX-Player style).
                          Positioned(
                            left: 4,
                            top: 0,
                            bottom: 0,
                            child: IgnorePointer(
                              ignoring:
                                  !(_controlsVisible &&
                                      !_isPip &&
                                      !_locked &&
                                      _settings.lockButton &&
                                      player.currentTrack != null),
                              child: AnimatedOpacity(
                                opacity:
                                    (_controlsVisible &&
                                        !_isPip &&
                                        !_locked &&
                                        _settings.lockButton &&
                                        player.currentTrack != null)
                                    ? 1.0
                                    : 0.0,
                                duration: const Duration(milliseconds: 180),
                                child: Center(
                                  child: _lockChip(
                                    icon: Icons.lock_open_outlined,
                                    onTap: _lockScreen,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          // Screen-lock EXIT chip (right edge, always visible
                          // while locked).
                          if (_locked && !_isPip)
                            Positioned(
                              right: 4,
                              top: 0,
                              bottom: 0,
                              child: Center(
                                child: _lockChip(
                                  icon: Icons.lock,
                                  onTap: _showLockHint,
                                  onDoubleTap: _unlockScreen,
                                  onLongPress: _unlockScreen,
                                ),
                              ),
                            ),
                          // Top bar (v19): back + marquee title + the
                          // merged more-actions menu + settings. Auto-hides
                          // with the controls, always readable over video.
                          Positioned(
                            top: 0,
                            left: 0,
                            right: 0,
                            child: IgnorePointer(
                              ignoring: !_controlsVisible,
                              child: AnimatedSlide(
                                offset: _controlsVisible && !_isPip
                                    ? Offset.zero
                                    : const Offset(0, -0.5),
                                duration: const Duration(milliseconds: 220),
                                curve: Curves.easeOutCubic,
                                child: AnimatedOpacity(
                                  opacity: _controlsVisible && !_isPip
                                      ? 1.0
                                      : 0.0,
                                  duration: const Duration(milliseconds: 180),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [
                                          Colors.black.withValues(alpha: 0.75),
                                          Colors.transparent,
                                        ],
                                      ),
                                    ),
                                    padding: const EdgeInsets.fromLTRB(
                                      2,
                                      2,
                                      2,
                                      14,
                                    ),
                                    child: Row(
                                      children: [
                                        IconButton(
                                          tooltip: 'Back',
                                          // v26: player buttons follow the
                                          // picked theme colour.
                                          icon: Icon(
                                            Icons.arrow_back,
                                            size: 22,
                                            color: themeState.accent,
                                          ),
                                          onPressed: () {
                                            _onUserInteraction();
                                            Navigator.of(context).maybePop();
                                          },
                                        ),
                                        Expanded(
                                          child: AnimatedBuilder(
                                            animation: player,
                                            builder: (context, _) {
                                              // v22: while a sleep timer
                                              // runs, show the remaining
                                              // time right under the title.
                                              final countdown =
                                                  player.sleepTimerCountdown;
                                              return Column(
                                                mainAxisSize: MainAxisSize.min,
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  _MarqueeTitle(
                                                    player
                                                            .currentTrack
                                                            ?.title ??
                                                        'Max Player',
                                                    key: ValueKey(
                                                      player.currentTrack?.path,
                                                    ),
                                                  ),
                                                  if (countdown != null)
                                                    Padding(
                                                      padding:
                                                          const EdgeInsets.only(
                                                            top: 2,
                                                          ),
                                                      child: Row(
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        children: [
                                                          Icon(
                                                            Icons
                                                                .bedtime_outlined,
                                                            size: 11,
                                                            color: themeState
                                                                .accent,
                                                          ),
                                                          const SizedBox(
                                                            width: 4,
                                                          ),
                                                          Text(
                                                            countdown == 'end of video'
                                                                ? 'Sleep: stops at end of video'
                                                                : 'Sleep in $countdown',
                                                            style: TextStyle(
                                                              fontSize: 10.5,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
                                                              color: themeState
                                                                  .accent,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                ],
                                              );
                                            },
                                          ),
                                        ),
                                        _topMenu(context),
                                        IconButton(
                                          tooltip: 'Player settings',
                                          icon: Icon(
                                            Icons.settings_outlined,
                                            size: 22,
                                            color: themeState.accent,
                                          ),
                                          onPressed: () {
                                            _onUserInteraction();
                                            _openSettings();
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          // v21: karaoke word-highlight for AI subtitles
                          // (replaces mpv's own subtitle rendering).
                          if (_settings.karaokeSubs && !_isPip)
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 120,
                              child: KaraokeSubtitle(player: widget.player),
                            ),
                          // v21: "Skip intro" - offered while the AI captions
                          // say the dialogue hasn't started yet.
                          if (_settings.skipIntroChip && !_isPip)
                            Positioned(
                              right: 14,
                              bottom: 132,
                              child: AnimatedBuilder(
                                animation: widget.player,
                                builder: (context, _) {
                                  final at = widget.player.skipIntroAt;
                                  if (at == null) {
                                    return const SizedBox.shrink();
                                  }
                                  final pos = widget.player.position;
                                  final untimely =
                                      pos >= at - const Duration(seconds: 1) ||
                                      pos > const Duration(minutes: 10);
                                  if (_skipChipDismissedFor == at || untimely) {
                                    return const SizedBox.shrink();
                                  }
                                  return Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(20),
                                      onTap: () {
                                        widget.player.seek(at);
                                        setState(
                                          () => _skipChipDismissedFor = at,
                                        );
                                        _onUserInteraction();
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.fromLTRB(
                                          12,
                                          8,
                                          8,
                                          8,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xF2152026),
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                          border: Border.all(
                                            color: themeState.accent.withValues(
                                              alpha: 0.65,
                                            ),
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.fast_forward,
                                              size: 16,
                                              color: themeState.accent,
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              'Skip to ${formatDuration(at)}',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 12.5,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                            GestureDetector(
                                              onTap: () => setState(
                                                () =>
                                                    _skipChipDismissedFor = at,
                                              ),
                                              child: const Padding(
                                                padding: EdgeInsets.all(4),
                                                child: Icon(
                                                  Icons.close,
                                                  size: 14,
                                                  color: Colors.white54,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          // Controls slide up + fade in instead of snapping.
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: IgnorePointer(
                              ignoring: !_controlsVisible,
                              child: AnimatedSlide(
                                offset: _controlsVisible && !_isPip
                                    ? Offset.zero
                                    : const Offset(0, 0.45),
                                duration: const Duration(milliseconds: 220),
                                curve: Curves.easeOutCubic,
                                child: AnimatedOpacity(
                                  opacity: _controlsVisible && !_isPip
                                      ? 1.0
                                      : 0.0,
                                  duration: const Duration(milliseconds: 180),
                                  child: PlayerControlsOverlay(
                                    player: player,
                                    onToggleQueue: () {
                                      setState(() => _showQueue = !_showQueue);
                                      _onUserInteraction();
                                    },
                                    onInteract: _onUserInteraction,
                                    onScrubbing: _onScrubChanged,
                                    onCycleFit: _cycleFit,
                                    orientationLocked: _orientationLocked,
                                    onToggleOrientationLock:
                                        _toggleOrientationLock,
                                    karaokeOn: _settings.karaokeSubs,
                                    onToggleKaraoke: _toggleKaraoke,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              if (_showQueue && !_isFullscreen && !_isPip)
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
                        onClose: () => setState(() => _showQueue = false),
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

  /// The merged more-actions menu (v19): video info, equalizer,
  /// screenshot, cast and picture-in-picture behind ONE button.
  Widget _topMenu(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'More actions',
      icon: Icon(Icons.more_vert, size: 22, color: themeState.accent),
      color: const Color(0xFF1a1a24),
      onSelected: (v) {
        _onUserInteraction();
        switch (v) {
          case 'info':
            VideoInfoSheet.show(context, widget.player);
          case 'eq':
            EqualizerSheet.show(context, widget.player);
          case 'shot':
            _takeScreenshot();
          case 'cast':
            _openCast();
          case 'pip':
            NativeBridge.enterPip(playing: widget.player.isPlaying);
          case 'sleep':
            _showSleepSheet();
          // v25: karaoke toggle moved into the tracks sheet (the "tune"
          // button next to play) - see _toggleKaraoke.
        }
      },
      itemBuilder: (context) => [
        _topMenuItem('info', Icons.info_outline, 'Video info'),
        _topMenuItem('eq', Icons.graphic_eq, 'Equalizer'),
        if (_settings.screenshotButton)
          _topMenuItem('shot', Icons.camera_alt_outlined, 'Screenshot'),
        if (_settings.castButton)
          _topMenuItem('cast', Icons.cast_outlined, 'Cast to TV'),
        _topMenuItem(
          'pip',
          Icons.picture_in_picture_alt_outlined,
          'Picture in picture',
        ),
        _topMenuItem(
          'sleep',
          Icons.bedtime_outlined,
          widget.player.sleepTimerActive
              ? 'Sleep timer (${widget.player.sleepTimerLabel})'
              : 'Sleep timer',
        ),
      ],
    );
  }

  PopupMenuItem<String> _topMenuItem(String v, IconData icon, String label) {
    return PopupMenuItem(
      value: v,
      child: Row(
        children: [
          // v26: menu icons follow the picked theme colour.
          Icon(icon, size: 18, color: themeState.accent),
          const SizedBox(width: 10),
          Text(label, style: const TextStyle(color: Colors.white)),
        ],
      ),
    );
  }

  Widget _lockChip({
    required IconData icon,
    VoidCallback? onTap,
    VoidCallback? onDoubleTap,
    VoidCallback? onLongPress,
  }) {
    return GestureDetector(
      onTap: onTap,
      onDoubleTap: onDoubleTap,
      onLongPress: onLongPress,
      child: Container(
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white24),
        ),
        // v26: the lock chip follows the picked theme colour too.
        child: Icon(icon, color: themeState.accent, size: 22),
      ),
    );
  }
}

enum _ScaleMode { undecided, volume, brightness, seekH, pan, zoom, cant }

/// Player title bar (v19): long titles scroll sideways in a slow loop
/// (marquee) instead of getting ellipsized. The widget is keyed by the
/// track path, so it restarts cleanly on track change.
class _MarqueeTitle extends StatefulWidget {
  final String text;
  const _MarqueeTitle(this.text, {super.key});

  @override
  State<_MarqueeTitle> createState() => _MarqueeTitleState();
}

class _MarqueeTitleState extends State<_MarqueeTitle> {
  final ScrollController _sc = ScrollController();

  /// v21: CONSTANT speed (the timer version restarted the animation
  /// mid-flight for long titles, which made the speed visibly change).
  static const double _pixelsPerSecond = 80;
  static const Duration _holdAtStart = Duration(milliseconds: 700);
  static const Duration _holdAtEnd = Duration(milliseconds: 1100);

  @override
  void initState() {
    super.initState();
    _loop();
  }

  Future<void> _loop() async {
    while (mounted) {
      await Future<void>.delayed(_holdAtStart);
      if (!mounted || !_sc.hasClients) return;
      final max = _sc.position.maxScrollExtent;
      if (max <= 0) {
        // Text fits on screen - nothing to scroll; keep waiting.
        await Future<void>.delayed(const Duration(seconds: 2));
        continue;
      }
      final ms = (max / _pixelsPerSecond * 1000).round().clamp(400, 60000);
      try {
        await _sc.animateTo(
          max,
          duration: Duration(milliseconds: ms),
          curve: Curves.linear,
        );
      } catch (_) {
        return; // controller detached mid-animation (screen closed)
      }
      await Future<void>.delayed(_holdAtEnd);
      if (!mounted || !_sc.hasClients) return;
      _sc.jumpTo(0);
    }
  }

  @override
  void dispose() {
    _sc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: _sc,
      scrollDirection: Axis.horizontal,
      physics: const NeverScrollableScrollPhysics(),
      child: Text(
        widget.text,
        maxLines: 1,
        softWrap: false,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 15.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
EOF_MARKER_17

mkdir -p "$(dirname 'lib/screens/private_screen.dart')"
cat > 'lib/screens/private_screen.dart' <<'EOF_MARKER_18'
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/video_track.dart';
import '../services/native_bridge.dart';
import '../state/media_player_state.dart';
import '../state/private_vault.dart';
import '../state/theme_state.dart';
import '../state/video_library_state.dart';
import '../utils/formatters.dart';
import '../widgets/fade_in_image.dart';
import '../widgets/video_picker_sheet.dart';
import 'player_screen.dart';

/// Private folder screen (v21): PIN gate -> list of hidden videos with
/// play / move-out actions. Files themselves live in the app's private
/// directory (see [PrivateVault]). v29: a "+" button moves selected
/// library videos straight into the vault.
class PrivateScreen extends StatefulWidget {
  final MediaPlayerState player;

  /// Source list for the v29 "+" picker (library videos only - hidden
  /// files never appear in it since the scanner skips app-private dirs).
  final VideoLibraryState library;

  const PrivateScreen({
    super.key,
    required this.player,
    required this.library,
  });

  @override
  State<PrivateScreen> createState() => _PrivateScreenState();
}

class _PrivateScreenState extends State<PrivateScreen> {
  final _vault = PrivateVault();
  final _pinCtrl = TextEditingController();
  final _pin2Ctrl = TextEditingController();

  bool? _hasPin; // null = still loading
  bool _unlocked = false;
  String? _error;
  bool _busy = false;
  List<File>? _videos;

  /// v24: a vault-storage failure (denied mkdir on some devices) is shown
  /// here instead of crashing the app (was an unhandled zone error).
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final has = await _vault.hasPin();
    if (mounted) setState(() => _hasPin = has);
  }

  @override
  void dispose() {
    _pinCtrl.dispose();
    _pin2Ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final pin = _pinCtrl.text.trim();
    if (pin.length < 4 || pin.length > 8) {
      setState(() => _error = 'PIN must be 4-8 digits');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_hasPin == false) {
        // First visit: create the PIN (enter twice to avoid typos).
        if (_pin2Ctrl.text.trim() != pin) {
          setState(() => _error = 'PINs do not match');
          return;
        }
        await _vault.setPin(pin);
        _hasPin = true;
        _unlocked = true;
      } else {
        if (await _vault.verifyPin(pin)) {
          _unlocked = true;
        } else {
          setState(() => _error = 'Wrong PIN');
          return;
        }
      }
      await _refresh();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// v25: user forgot their PIN. v26: FIRST the phone's own screen lock
  /// (device password / pattern / PIN / fingerprint) must be passed -
  /// only the phone's owner may reset the vault PIN.
  ///
  /// The hidden videos are NOT wiped either way (they live in the
  /// app-private folder regardless of the PIN); only the door code
  /// resets, then the normal "create PIN" flow re-secures it.
  Future<void> _forgotPin() async {
    setState(() => _busy = true);
    bool unlocked;
    try {
      unlocked = await NativeBridge.confirmDeviceCredential(
        title: 'Unlock to reset the Private folder PIN',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    if (!unlocked) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Phone unlock failed or cancelled - PIN not reset'),
        ),
      );
      return;
    }
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a24),
        title: const Text('Forgot your PIN?',
            style: TextStyle(color: Colors.white, fontSize: 17)),
        content: const Text(
          'Your hidden videos are SAFE - they stay in the app\'s private '
          'folder either way.\n\nResetting removes the old PIN so you can '
          'create a new one. You just unlocked the phone, so we know it\'s '
          'really you.',
          style:
              TextStyle(color: Colors.white70, fontSize: 13, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep trying'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Reset PIN'),
          ),
        ],
      ),
    );
    if (yes == true && mounted) {
      await _vault.resetPin();
      setState(() {
        _hasPin = false;
        _unlocked = false;
        _error = null;
        _pinCtrl.clear();
        _pin2Ctrl.clear();
      });
    }
  }

  Future<void> _refresh() async {
    try {
      final vids = await _vault.listVideos();
      if (mounted) {
        setState(() {
          _videos = vids;
          _loadError = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadError = e
            .toString()
            .replaceAll('FileSystemException: ', '')
            .replaceAll('Exception: ', ''));
      }
    }
  }

  Future<void> _play(File file) async {
    final files = _videos ?? const <File>[];
    final tracks = [
      for (final f in files)
        VideoTrack(
          id: f.path,
          title: f.path.split('/').last,
          path: f.path,
        ),
    ];
    final idx = tracks.indexWhere((t) => t.path == file.path);
    await widget.player.setPlaylistAndPlay(tracks, idx < 0 ? 0 : idx);
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PlayerScreen(player: widget.player)),
    );
  }

  /// v29: "+" - select library videos and move them into the vault.
  /// Same "All files access" pre-check as the library's long-press flow.
  Future<void> _addVideos() async {
    if (!await Permission.manageExternalStorage.isGranted) {
      final status = await Permission.manageExternalStorage.request();
      if (!mounted) return;
      if (!status.isGranted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Adding videos needs "All files access": allow it, then '
              'tap + again',
            ),
          ),
        );
        return;
      }
    }
    if (!mounted) return;
    final selected = await VideoPickerSheet.show(
      context,
      widget.library.videos,
      title: 'Add to Private folder',
      actionLabel: 'Hide',
    );
    if (selected == null || selected.isEmpty || !mounted) return;
    setState(() => _busy = true);
    var moved = 0;
    try {
      for (final t in selected) {
        try {
          await _vault.hide(t.path);
          widget.player.removeHistoryEntry(t.path);
          moved++;
        } catch (_) {
          // Keep going with the rest of the selection.
        }
      }
      await _refresh();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            moved > 0
                ? 'Moved $moved video(s) to the Private folder'
                : 'Could not hide the videos',
          ),
        ),
      );
    }
  }

  Future<void> _unhide(File file) async {
    try {
      final moved = await _vault.unhide(file.path);
      widget.player.removeHistoryEntry(file.path);
      await _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Moved back to Movies: ${moved.path.split('/').last}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not move the video out')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = themeState.accent;
    return Scaffold(
      backgroundColor: const Color(0xFF0f0f14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1a1a24),
        title: const Text('Private folder'),
        actions: [
          // v29: add videos to the vault from right here.
          if (_unlocked)
            IconButton(
              tooltip: 'Add videos',
              icon: const Icon(Icons.add),
              onPressed: _busy ? null : _addVideos,
            ),
        ],
      ),
      body: _hasPin == null
          ? const Center(child: CircularProgressIndicator())
          : !_unlocked
              ? _pinGate(accent)
              : _videoList(accent),
    );
  }

  Widget _pinGate(Color accent) {
    final creating = _hasPin == false;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: 56, color: accent),
            const SizedBox(height: 14),
            Text(
              creating ? 'Create a PIN' : 'Private folder',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              creating
                  ? 'Choose 4-8 digits. Hidden videos stay inside the app\'s '
                      'private folder - invisible to Gallery and file managers.'
                  : 'Enter your PIN to see hidden videos.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
            const SizedBox(height: 18),
            _pinField(_pinCtrl, creating ? 'New PIN (4-8 digits)' : 'PIN'),
            if (creating) ...[
              const SizedBox(height: 10),
              _pinField(_pin2Ctrl, 'Repeat PIN'),
            ],
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
            ],
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: FilledButton.icon(
                onPressed: _busy ? null : _submit,
                icon: Icon(creating ? Icons.check : Icons.lock_open),
                label: Text(creating ? 'Create & open' : 'Unlock'),
              ),
            ),
            if (!creating) ...[
              const SizedBox(height: 6),
              // v25: forgotten PIN path - keeps the videos, only clears
              // the door code (the folder location is the real hiding).
              TextButton(
                onPressed: _busy ? null : _forgotPin,
                child: Text(
                  'Forgot PIN?',
                  style: TextStyle(
                      color: accent.withValues(alpha: 0.6), fontSize: 12.5),
                ),
              ),
            ],
            if (creating) ...[
              const SizedBox(height: 14),
              const Text(
                'Warning: uninstalling the app also deletes hidden videos. '
                'Move them out first.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.amberAccent, fontSize: 11.5),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _pinField(TextEditingController ctrl, String hint) {
    return TextField(
      controller: ctrl,
      keyboardType: TextInputType.number,
      obscureText: true,
      maxLength: 8,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      style: const TextStyle(color: Colors.white, letterSpacing: 4),
      decoration: InputDecoration(
        counterText: '',
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white38),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.06),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onSubmitted: (_) => _submit(),
    );
  }

  Widget _videoList(Color accent) {
    final loadError = _loadError;
    if (loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline,
                  size: 40, color: accent.withValues(alpha: 0.7)),
              const SizedBox(height: 12),
              Text(
                'Private folder could not open:\n$loadError',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: accent.withValues(alpha: 0.8), height: 1.5),
              ),
              const SizedBox(height: 14),
              TextButton.icon(
                onPressed: _refresh,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    final vids = _videos;
    if (vids == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (vids.isEmpty) {
      // v22 (user request): the how-to line belongs ON this screen.
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline,
                  size: 44, color: accent.withValues(alpha: 0.65)),
              const SizedBox(height: 12),
              const Text(
                'Hold on a video in the Library to add it to the Private folder',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.white70, fontSize: 14, height: 1.4),
              ),
              const SizedBox(height: 6),
              const Text(
                'Nothing is hidden yet.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white38, height: 1.5),
              ),
              const SizedBox(height: 14),
              // v29: same as the "+" in the top bar.
              FilledButton.icon(
                onPressed: _busy ? null : _addVideos,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add videos'),
              ),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        itemCount: vids.length,
        itemBuilder: (context, i) {
          final f = vids[i];
          final name = f.path.split('/').last;
          final size = f.lengthSync();
          return ListTile(
            // v25: real thumbnails (generated via the same native pipeline
            // the library uses) instead of a bare lock icon.
            leading: _VaultThumb(path: f.path, accent: accent),
            title: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              // v25: the private screen follows the picked theme colour.
              style: TextStyle(color: accent),
            ),
            subtitle: Text(
              formatFileSize(size),
              style: TextStyle(
                  color: accent.withValues(alpha: 0.5), fontSize: 12),
            ),
            onTap: () => _play(f),
            trailing: TextButton.icon(
              onPressed: () => _confirmUnhide(f),
              icon: const Icon(Icons.lock_open, size: 16),
              label: const Text('Move out'),
            ),
          );
        },
      ),
    );
  }

  void _confirmUnhide(File f) {
    final name = f.path.split('/').last;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a24),
        title: const Text('Move out of Private?',
            style: TextStyle(color: Colors.white)),
        content: Text(
          '"$name" will move to the Movies folder and become visible to '
          'Gallery and other apps again.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _unhide(f);
            },
            child: const Text('Move out'),
          ),
        ],
      ),
    );
  }
}

/// v25: thumbnail for a hidden video. Hidden files skip the library scan,
/// so the tile resolves the cached image itself - and if the cache has no
/// entry (video hidden before it had a thumb), it asks the native metadata
/// pipeline to build one into the shared thumbs cache.
class _VaultThumb extends StatefulWidget {
  final String path;
  final Color accent;
  const _VaultThumb({required this.path, required this.accent});

  @override
  State<_VaultThumb> createState() => _VaultThumbState();
}

class _VaultThumbState extends State<_VaultThumb> {
  String? _thumbPath;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    try {
      final cached = await NativeBridge.thumbnailPathFor(widget.path);
      if (cached != null && File(cached).existsSync()) {
        if (mounted) setState(() => _thumbPath = cached);
        return;
      }
      // Not cached: build one through the native pipeline.
      final meta = await NativeBridge.fetchMetadata(widget.path);
      final made = meta.thumbnailPath;
      if (made != null && File(made).existsSync() && mounted) {
        setState(() => _thumbPath = made);
      }
    } catch (_) {
      // No thumbnail - the lock fallback shows.
    }
  }

  @override
  Widget build(BuildContext context) {
    final thumb = _thumbPath;
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: 56,
        height: 34,
        child: thumb != null
            ? Image.file(
                File(thumb),
                fit: BoxFit.cover,
                cacheWidth: 160,
                frameBuilder: fadeInImageFrame,
                errorBuilder: (_, __, ___) => _fallback(),
              )
            : _fallback(),
      ),
    );
  }

  Widget _fallback() => Container(
        color: widget.accent.withValues(alpha: 0.12),
        child: Icon(Icons.lock, size: 15, color: widget.accent),
      );
}
EOF_MARKER_18

mkdir -p "$(dirname 'lib/services/native_bridge.dart')"
cat > 'lib/services/native_bridge.dart' <<'EOF_MARKER_19'
import 'package:flutter/services.dart';

/// Result of a native metadata extraction for one video file.
class VideoMetadata {
  final Duration? duration;
  final String? thumbnailPath;
  final int? width;
  final int? height;

  /// Overall bitrate in bits/sec (from the container), if reported.
  final int? bitrateBps;

  /// Friendly video codec name (e.g. "H.265 (HEVC)"); works on every
  /// Android version (read via MediaExtractor track MIME).
  final String? codec;

  /// v27 advanced video info: video frame rate (0 = container omits it),
  /// and the FIRST audio track's details (null/0 = none or unknown).
  final int? frameRate;
  final String? audioCodec;
  final int? audioChannels;
  final int? audioSampleRate;

  /// v32: detected dynamic range of the video track:
  /// 'sdr' | 'hdr10' | 'hdr10+' | 'hlg' | 'dolby-vision'.
  /// Dolby Vision plays via its HDR10-compatible fallback layer.
  final String? hdr;

  const VideoMetadata({
    this.duration,
    this.thumbnailPath,
    this.width,
    this.height,
    this.bitrateBps,
    this.codec,
    this.frameRate,
    this.audioCodec,
    this.audioChannels,
    this.audioSampleRate,
    this.hdr,
  });
}

/// One AI-generated subtitle cue (whisper.cpp segment).
class AiSegment {
  final int startMs;
  final int endMs;
  final String text;
  const AiSegment(this.startMs, this.endMs, this.text);
}

/// Bridge to the Android native code in `MainActivity.kt` over a single
/// MethodChannel ("maxplayer/native"):
///
///  - [fetchMetadata]: duration + cached JPEG thumbnail per video. This
///    replaces the `video_thumbnail` plugin, which was incompatible with the
///    AGP 9 / Kotlin 2.3 toolchain — the native side has no external deps.
///  - [loadSettings] / [saveSetting]: a tiny key/value store backed by
///    Android SharedPreferences, avoiding another plugin dependency.
///  - brightness helpers for the player's left-half swipe.
///  - "Open with" VIDEO intent delivery (cold + warm).
///  - Picture-in-picture enter + state callbacks.
///
/// IMPORTANT: there is exactly ONE MethodChannel.setMethodCallHandler
/// registration ([_dispatch]) — a second registration would silently replace
/// the first. All native->Dart events flow through the callbacks configured
/// via [configureCallbacks].
///
/// EVERY call is guarded: where the channel doesn't exist (unit tests,
/// desktop platforms), calls fail silently and return empty values.
class NativeBridge {
  static const MethodChannel _channel = MethodChannel('maxplayer/native');

  static void Function(String path)? _onOpenVideo;
  static void Function(String uri)? _onOpenVideoFailed;
  static void Function(bool isPip)? _onPipChanged;
  static void Function()? _onPipAction;
  static void Function(String stage, int percent)? _onAiProgress;
  static void Function(List<AiSegment> segments)? _onAiDone;
  static void Function(String error)? _onAiFailed;
  static bool _handlerRegistered = false;

  /// Registers (or replaces) the app-level native event callbacks.
  static void configureCallbacks({
    void Function(String path)? onOpenVideo,
    void Function(String uri)? onOpenVideoFailed,
    void Function(bool isPip)? onPipChanged,

    /// Fired when the play/pause button ON THE PiP WINDOW is tapped.
    void Function()? onPipAction,

    /// AI subtitle job events (see [aiSubtitleGenerate]).
    void Function(String stage, int percent)? onAiProgress,
    void Function(List<AiSegment> segments)? onAiDone,
    void Function(String error)? onAiFailed,
  }) {
    if (onOpenVideo != null) _onOpenVideo = onOpenVideo;
    if (onOpenVideoFailed != null) _onOpenVideoFailed = onOpenVideoFailed;
    if (onPipChanged != null) _onPipChanged = onPipChanged;
    if (onPipAction != null) _onPipAction = onPipAction;
    if (onAiProgress != null) _onAiProgress = onAiProgress;
    if (onAiDone != null) _onAiDone = onAiDone;
    if (onAiFailed != null) _onAiFailed = onAiFailed;
    if (_handlerRegistered) return;
    _handlerRegistered = true;
    _channel.setMethodCallHandler(_dispatch);
  }

  static Future<dynamic> _dispatch(MethodCall call) async {
    switch (call.method) {
      case 'onOpenVideo':
        final p = call.arguments as String?;
        if (p != null && p.isNotEmpty) _onOpenVideo?.call(p);
        break;
      case 'onOpenVideoFailed':
        final u = call.arguments as String?;
        if (u != null) _onOpenVideoFailed?.call(u);
        break;
      case 'onPipChanged':
        _onPipChanged?.call(call.arguments == true);
        break;
      case 'onPipAction':
        _onPipAction?.call();
        break;
      case 'onAiProgress':
        final m = call.arguments as Map?;
        if (m != null) {
          _onAiProgress?.call(
            '${m['stage']}',
            (m['percent'] as num?)?.toInt() ?? 0,
          );
        }
        break;
      case 'onAiSubtitleDone':
        final list = call.arguments as Map?;
        final raw = list?['segments'] as List?;
        if (raw != null) {
          final segments = <AiSegment>[
            for (final e in raw)
              if (e is Map)
                AiSegment(
                  (e['start'] as num?)?.toInt() ?? 0,
                  (e['end'] as num?)?.toInt() ?? 0,
                  '${e['text']}',
                ),
          ];
          _onAiDone?.call(segments);
        }
        break;
      case 'onAiSubtitleFailed':
        final m = call.arguments as Map?;
        _onAiFailed?.call('${m?['message'] ?? 'failed'}');
        break;
    }
    return null;
  }

  static Future<VideoMetadata> fetchMetadata(String path) async {
    try {
      final Map<Object?, Object?>? res = await _channel
          .invokeMethod<Map<Object?, Object?>>('getMetadata', {'path': path});
      if (res == null) return const VideoMetadata();
      final durationMs = res['durationMs'];
      final width = res['width'];
      final height = res['height'];
      final bitrate = res['bitrate'];
      final fps = res['frameRate'];
      final aCh = res['audioChannels'];
      final aRate = res['audioSampleRate'];
      return VideoMetadata(
        duration: durationMs is int ? Duration(milliseconds: durationMs) : null,
        thumbnailPath: res['thumbnailPath'] as String?,
        width: width is int ? width : null,
        height: height is int ? height : null,
        bitrateBps: bitrate is int ? bitrate : null,
        codec: res['codec'] as String?,
        // v27: advanced track details (0 on the wire = unknown -> null).
        frameRate: fps is int && fps > 0 ? fps : null,
        audioCodec: res['audioCodec'] as String?,
        audioChannels: aCh is int && aCh > 0 ? aCh : null,
        audioSampleRate: aRate is int && aRate > 0 ? aRate : null,
        // v32: 'sdr' | 'hdr10' | 'hdr10+' | 'hlg' | 'dolby-vision'.
        hdr: res['hdr'] as String?,
      );
    } catch (_) {
      return const VideoMetadata();
    }
  }

  static Future<Map<String, String>> loadSettings() async {
    try {
      final Map<Object?, Object?>? res = await _channel
          .invokeMethod<Map<Object?, Object?>>('settingsGetAll');
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

  // --- App-local screen brightness (player swipe gesture) ---

  static Future<double> getBrightness() async {
    try {
      final res = await _channel.invokeMethod<double>('getBrightness');
      if (res != null) return res.clamp(0.0, 1.0);
    } catch (_) {}
    return 1.0;
  }

  static Future<void> setBrightness(double value) async {
    try {
      await _channel.invokeMethod('setBrightness', {'value': value});
    } catch (_) {}
  }

  /// Give control back to the system auto-brightness.
  static Future<void> resetBrightness() async {
    try {
      await _channel.invokeMethod('resetBrightness');
    } catch (_) {}
  }

  // --- Device MEDIA volume (player swipe drives the real system volume) ---

  /// Current media volume as 0..1. Falls back to 1.0 when unavailable.
  static Future<double> getMediaVolume() async {
    try {
      final res = await _channel.invokeMethod<Map<Object?, Object?>>(
        'getMediaVolume',
      );
      final level = (res?['level'] as num?)?.toDouble() ?? 1.0;
      final max = (res?['max'] as num?)?.toDouble() ?? 1.0;
      if (max <= 0) return 1.0;
      return (level / max).clamp(0.0, 1.0);
    } catch (_) {
      return 1.0;
    }
  }

  /// Sets the device media volume (0..1). MX Player / VLC style: the
  /// player's inline volume IS the system media volume, so the user can
  /// always reach the phone's true maximum.
  static Future<void> setMediaVolume(double value) async {
    try {
      await _channel.invokeMethod('setMediaVolume', {
        'value': value.clamp(0.0, 1.0),
      });
    } catch (_) {}
  }

  // --- "Open with" intent delivery ---

  /// Cold-start check: a video opened from another app before Dart attached.
  /// Returns a map with keys 'path' (resolved file path) and/or 'failed'
  /// (the URI we could not resolve); both may be null.
  static Future<Map<String, String>> getInitialOpenVideo() async {
    try {
      final Map<Object?, Object?>? res = await _channel
          .invokeMethod<Map<Object?, Object?>>('getInitialOpenVideo');
      if (res == null) return const {};
      final out = <String, String>{};
      for (final key in ['path', 'failed']) {
        final v = res[key];
        if (v is String && v.isNotEmpty) out[key] = v;
      }
      return out;
    } catch (_) {
      return const {};
    }
  }

  // --- Picture in picture ---

  /// Ask Android to enter PiP. [playing] picks the correct initial icon for
  /// the PiP window's play/pause remote action.
  static Future<void> enterPip({bool playing = true}) async {
    try {
      await _channel.invokeMethod('enterPip', {'playing': playing});
    } catch (_) {}
  }

  /// Keeps the PiP window's play/pause action in sync with the player.
  /// Cheap no-op when not in PiP (and on non-Android platforms).
  static Future<void> setPipPlaying(bool playing) async {
    try {
      await _channel.invokeMethod('setPipPlaying', playing);
    } catch (_) {}
  }

  // --- AI subtitles (Phase 1 probe) ---

  /// Returns the whisper.cpp system-info string when the on-device AI
  /// subtitle engine is bundled and its native library loads, else null.
  /// Used by the About sheet as a build verification.
  static Future<String?> whisperEngineStatus() async {
    try {
      final res = await _channel.invokeMethod<String>('whisperAvailable');
      return (res != null && res.isNotEmpty) ? res : null;
    } catch (_) {
      return null;
    }
  }

  // --- AI subtitles pipeline (Phases 2+3) ---

  /// Which models are present on device. Returns {tiny: MB, base: MB,
  /// small: MB}; 0 MB means "not downloaded yet".
  static Future<Map<String, int>> aiModelStatus() async {
    try {
      final res = await _channel.invokeMethod<Map<Object?, Object?>>(
        'aiModelStatus',
      );
      if (res == null) return const {};
      return res.map((k, v) => MapEntry('$k', (v as num?)?.toInt() ?? 0));
    } catch (_) {
      return const {};
    }
  }

  /// Starts the offline AI subtitle job for [videoPath]. Returns the job id
  /// immediately; progress/completion arrive via [configureCallbacks]
  /// (`onAiProgress` / `onAiDone` / `onAiFailed`). [model] is tiny/base/
  /// small; [language] is a whisper language code or 'auto' (detect).
  static Future<int?> aiSubtitleGenerate({
    required String videoPath,
    String model = 'base',
    String language = 'auto',
    // v21: whisper's translate task - any spoken language -> English subs.
    bool translate = false,
  }) async {
    try {
      return await _channel.invokeMethod<int>('aiSubtitleGenerate', {
        'videoPath': videoPath,
        'model': model,
        'language': language,
        'translate': translate,
      });
    } catch (_) {
      return null;
    }
  }

  /// Asks the running job to stop (effective during download/extraction; a
  /// running transcription finishes but its result is discarded).
  static Future<void> aiSubtitleCancel() async {
    try {
      await _channel.invokeMethod('aiSubtitleCancel');
    } catch (_) {}
  }

  /// Registers [path] with the Android media scanner so freshly-written
  /// files (screenshots, AI subtitles) show up in gallery apps at once.
  static Future<void> scanFile(String path) async {
    try {
      await _channel.invokeMethod('scanFile', {'path': path});
    } catch (_) {}
  }

  /// v22: the cache-file path the native scanner uses for [path]'s
  /// thumbnail (null for streams/missing files). The player writes an
  /// mpv-captured frame there when Android can't decode one itself.
  static Future<String?> thumbnailPathFor(String path) async {
    try {
      return await _channel.invokeMethod<String>('thumbnailPathFor', {
        'path': path,
      });
    } catch (_) {
      return null;
    }
  }

  /// v24: absolute path of the Private-folder vault directory, created and
  /// owned through the Android framework (no storage permission needed).
  /// Null = this build can't provide one.
  static Future<String?> vaultDirPath() async {
    try {
      return await _channel.invokeMethod<String>('vaultDirPath');
    } catch (_) {
      return null;
    }
  }

  /// v28 Cleaner tile: reclaimable app storage in bytes, split by kind
  /// ({thumbs, strips, temp, models}). Your videos are never included.
  static Future<Map<String, int>> storageReport() async {
    try {
      final res = await _channel.invokeMethod<Map<Object?, Object?>>(
        'storageReport',
      );
      if (res == null) return const {};
      return res.map((k, v) => MapEntry('$k', (v as num?)?.toInt() ?? 0));
    } catch (_) {
      return const {};
    }
  }

  /// v28: deletes one storage kind ('thumbs' | 'temp' | 'models') and
  /// returns the freed bytes. Everything is recreated on demand.
  static Future<int> clearStorage(String kind) async {
    try {
      final res = await _channel.invokeMethod<int>('clearStorage', {
        'kind': kind,
      });
      return res ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// v31 Cleaner: total/free bytes of the device's internal storage
  /// (StatFs on the app files dir). Null when the platform side is
  /// unavailable (desktop, tests) - the UI hides the graph then.
  static Future<DeviceStorage?> storageTotals() async {
    try {
      final res = await _channel.invokeMethod<Map<Object?, Object?>>(
        'storageTotals',
      );
      if (res == null) return null;
      final total = (res['total'] as num?)?.toInt() ?? 0;
      final free = (res['free'] as num?)?.toInt() ?? 0;
      if (total <= 0) return null;
      return DeviceStorage(total: total, free: free);
    } catch (_) {
      return null;
    }
  }

  /// Holds/releases the Wi-Fi multicast lock used during DLNA (SSDP)
  /// device discovery. [hold] true = acquire, false = release.
  static Future<void> setMulticastLock(bool hold) async {
    try {
      await _channel.invokeMethod('setMulticastLock', hold);
    } catch (_) {}
  }

  /// v26: asks for the PHONE's own unlock secret - device PIN / pattern /
  /// password, or fingerprint/face - before the Private-folder PIN may be
  /// reset (user request: a forgotten PIN must not be openable by anyone
  /// holding the unlocked phone). True = the owner proved it; false =
  /// cancelled / failed / unavailable. A device WITHOUT any screen lock
  /// answers true (nothing exists to ask - the unlocked phone is the
  /// proof of possession).
  static Future<bool> confirmDeviceCredential({String? title}) async {
    try {
      final res = await _channel.invokeMethod<bool>('confirmDeviceCredential', {
        'title': title ?? 'Unlock to continue',
      });
      return res == true;
    } catch (_) {
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // v19: sensor-driven rotation + scrub thumbnail strip
  // ---------------------------------------------------------------------------

  /// Player rotation that IGNORES the phone's system auto-rotate switch:
  /// native tracks the accelerometer and requests portrait/landscape
  /// directly (MX Player / VLC style). Enabled when the player opens.
  static Future<void> enableSensorRotate() async {
    try {
      await _channel.invokeMethod('enableSensorRotate');
    } catch (_) {}
  }

  /// Hands rotation control back to the system (leaving the player).
  static Future<void> disableSensorRotate() async {
    try {
      await _channel.invokeMethod('disableSensorRotate');
    } catch (_) {}
  }

  /// Rotation lock chip: pins the player to landscape (both sides still
  /// flippable) or portrait until [enableSensorRotate] is called again.
  static Future<void> lockRotation({required bool landscape}) async {
    try {
      await _channel.invokeMethod('lockRotation', {'landscape': landscape});
    } catch (_) {}
  }

  /// Ensures a strip of small JPEG frames exists for scrub previews and
  /// returns its cache directory (null for streams/failures). Idempotent:
  /// a strip is generated once per file and reused after that.
  static Future<String?> thumbStripEnsure(String path) async {
    try {
      return await _channel.invokeMethod<String>('thumbStripEnsure', {
        'path': path,
      });
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // v34: Android-layer crash reporter ("Max Player has stopped")
  // ---------------------------------------------------------------------------

  /// Reads the JVM crash report the native Application class recorded
  /// after an uncaught Android-layer exception; null when there is none.
  /// (Dart-side errors are journaled separately by CrashLog.)
  static Future<String?> nativeCrashGet() async {
    try {
      return await _channel.invokeMethod<String>('nativeCrashGet');
    } catch (_) {
      return null;
    }
  }

  /// Wipes the stored Android-layer crash report (after it was shown).
  static Future<void> nativeCrashClear() async {
    try {
      await _channel.invokeMethod('nativeCrashClear');
    } catch (_) {}
  }

  /// v37: startup breadcrumb - appends a stage mark to
  /// maxplayer_start.log (internal + Android/data). If the app dies early
  /// on some phone, that file shows the last stage it reached.
  static Future<void> crumb(String stage) async {
    try {
      await _channel.invokeMethod('crumb', {'stage': stage});
    } catch (_) {}
  }
}

/// v31: device internal-storage totals for the cleaner's storage graph.
class DeviceStorage {
  final int total;
  final int free;
  const DeviceStorage({required this.total, required this.free});

  int get used => total - free;

  /// 0..1 fill of the usage bar (guarded against a bogus total).
  double get usedFraction => total <= 0 ? 0 : (used.clamp(0, total)) / total;
}
EOF_MARKER_19

mkdir -p "$(dirname 'lib/utils/crash_log.dart')"
cat > 'lib/utils/crash_log.dart' <<'EOF_MARKER_20'
import '../services/native_bridge.dart';

/// Minimal crash journal so an "app closed unexpectedly" is no longer
/// invisible: the Dart-side error is stored in the native settings store
/// (plain strings) and shown ONCE on the next app launch, where the user
/// can copy it and send it for analysis.
///
/// NOTE: this catches Dart/framework errors. A native abort inside libmpv
/// or a decoder can't be caught here - those still need a logcat or the
/// Android tombstone, but in practice most unexpected closes surface as
/// Dart errors.
class CrashLog {
  CrashLog._();

  static const String _kCrashKey = 'crash.last';

  /// Records [error] (+ truncated [stack]) under [kind] ('flutter' for
  /// widget-tree errors, 'async' for uncaught zone errors, 'zone' for the
  /// outermost guard).
  static Future<void> record(
    String kind,
    String error,
    StackTrace? stack,
  ) async {
    try {
      final buf = StringBuffer()
        ..writeln('Max Player crash report')
        ..writeln('time: ${DateTime.now().toIso8601String()}')
        ..writeln('kind: $kind')
        ..writeln('error: $error')
        ..writeln('stack:');
      final frames = stack?.toString().split('\n') ?? const <String>[];
      buf.write(frames.take(24).join('\n'));
      var text = buf.toString();
      if (text.length > 6000) text = text.substring(0, 6000);
      await NativeBridge.saveSetting(_kCrashKey, text);
    } catch (_) {
      // Never let crash-reporting itself crash the app.
    }
  }

  /// Returns the last stored report and clears it (shown once).
  static Future<String?> takeLast() async {
    try {
      final s = await NativeBridge.loadSettings();
      final v = s[_kCrashKey];
      if (v == null || v.isEmpty) return null;
      await NativeBridge.saveSetting(_kCrashKey, '');
      return v;
    } catch (_) {
      return null;
    }
  }

  /// v34: an Android-layer crash ("Max Player has stopped" - e.g. at app
  /// start, before Dart even runs) is recorded to a file by the native
  /// Application class. Prefer that report over the Dart journal; either
  /// source is cleared when taken, so it is shown exactly once.
  static Future<String?> takeLastIncludingNative() async {
    try {
      final nativeReport = await NativeBridge.nativeCrashGet();
      if (nativeReport != null && nativeReport.isNotEmpty) {
        await NativeBridge.nativeCrashClear();
        return nativeReport;
      }
    } catch (_) {
      // fall through to the Dart journal
    }
    return takeLast();
  }
}
EOF_MARKER_20

mkdir -p "$(dirname 'android/app/src/main/kotlin/com/hypertechlabs/maxplayer/MaxPlayerApp.kt')"
cat > 'android/app/src/main/kotlin/com/hypertechlabs/maxplayer/MaxPlayerApp.kt' <<'EOF_MARKER_21'
package com.hypertechlabs.maxplayer

import android.app.Application
import android.content.Context
import android.os.Build
import android.os.Process
import android.os.SystemClock
import java.io.File
import java.io.PrintWriter
import java.io.StringWriter

/**
 * v34/v36/v37: two crash-diagnosis tools that need NO PC and NO app
 * reopen on the failing phone:
 *
 *  (1) CRASH REPORT (v34/v36): catches JVM-level uncaught exceptions -
 *      the "Max Player has stopped" case - anywhere in the app,
 *      INCLUDING crashes before MainActivity exists. Saved to both:
 *       a) internal storage (shown in-app on next launch via
 *          nativeCrashGet/nativeCrashClear + takeLastIncludingNative),
 *       b) Android/data/<package>/files/maxplayer_crash.txt - readable
 *          with ANY file manager, no permission needed (v36).
 *
 *  (2) STARTUP TRACE (v37): a breadcrumb stage log that survives even
 *      when the app dies before Dart or the UI ever comes up:
 *      Android/data/<package>/files/maxplayer_start.log
 *      Records: app_create -> activity_create_begin/ok -> channel_ready
 *      -> dart_main -> mediakit_ok -> player_ok/player_FAIL -> scan_*
 *      plus a final "CRASH: <exception>" line from the handler above.
 *      The LAST stage line tells us exactly which component killed a
 *      phone that "never opens".
 *
 * The previous default handler is chained afterwards, so the system
 * crash dialog, process teardown and Play Console crash stats keep
 * working. A hard native abort (SIGSEGV inside a .so) bypasses the JVM
 * channel by design - but the trace file still shows the last stage.
 */
class MaxPlayerApp : Application() {

    override fun attachBaseContext(base: Context?) {
        super.attachBaseContext(base)
        // Install as EARLY as possible - attachBaseContext runs before
        // content providers and before onCreate.
        installCrashHandler()
    }

    override fun onCreate() {
        super.onCreate()
        installCrashHandler()
        CrashCrumbs.reset(this)
        CrashCrumbs.mark(this, "app_create")
    }

    private fun installCrashHandler() {
        if (handlerInstalled) return
        handlerInstalled = true
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, error ->
            try {
                CrashCrumbs.crash(
                    this,
                    "${error.javaClass.simpleName}: ${
                        error.message?.lineSequence()?.firstOrNull() ?: ""
                    }",
                )
            } catch (_: Throwable) {
            }
            try {
                writeCrashReport(thread, error)
            } catch (_: Throwable) {
                // Reporting must never crash the crash handler itself.
            }
            // Chain so the system dialogue + Play crash stats still work.
            if (previous != null) {
                previous.uncaughtException(thread, error)
            } else {
                Process.killProcess(Process.myPid())
            }
        }
    }

    private fun writeCrashReport(thread: Thread, error: Throwable) {
        val trace =
            StringWriter().also { error.printStackTrace(PrintWriter(it)) }.toString()
        @Suppress("DEPRECATION")
        val versionName = try {
            packageManager.getPackageInfo(packageName, 0).versionName ?: "?"
        } catch (_: Throwable) {
            "?"
        }
        val text = buildString {
            appendLine("Max Player crash report (Android layer)")
            appendLine("time-ms: ${System.currentTimeMillis()}")
            appendLine("app: $versionName")
            appendLine("device: ${Build.MANUFACTURER} ${Build.MODEL}")
            appendLine("android: ${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT})")
            appendLine("thread: ${thread.name}")
            appendLine()
            append(trace)
        }
        val trimmed = if (text.length > 12000) text.substring(0, 12000) else text
        // 1) internal storage: the app itself reads it on the next launch.
        try {
            File(filesDir, CRASH_FILE).writeText(trimmed)
        } catch (_: Throwable) {
        }
        // 2) app-specific external folder: browsable with any file
        //    manager on Android 10 and older, no permission needed.
        try {
            val ext = getExternalFilesDir(null)
            if (ext != null) File(ext, CRASH_FILE).writeText(trimmed)
        } catch (_: Throwable) {
        }
    }

    companion object {
        @Volatile
        private var handlerInstalled = false
        const val CRASH_FILE = "maxplayer_crash.txt"
    }
}

/** v37: tiny append-only startup trace, dual-written like the crash
 *  report. Reset on every cold start (Application.onCreate). */
internal object CrashCrumbs {
    private const val START_FILE = "maxplayer_start.log"

    @Volatile
    private var t0: Long = -1

    /** Fresh log for a cold start. */
    fun reset(context: Context?) {
        if (context == null) return
        t0 = SystemClock.elapsedRealtime()
        val header = buildString {
            appendLine("Max Player startup trace (v37)")
            appendLine("app-create @ ${System.currentTimeMillis()}")
            appendLine(
                "android ${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT}), " +
                    "${Build.MANUFACTURER} ${Build.MODEL}",
            )
            appendLine("stages:")
        }
        write(context, header, append = false)
    }

    fun mark(context: Context?, stage: String) {
        if (context == null) return
        if (t0 < 0) t0 = SystemClock.elapsedRealtime()
        val ms = SystemClock.elapsedRealtime() - t0
        write(context, "  $stage  (+${ms}ms)\n", append = true)
    }

    fun crash(context: Context?, short: String) {
        val single = short.lineSequence().firstOrNull() ?: short
        write(context, "  CRASH: ${single.take(300)}\n", append = true)
    }

    private fun write(context: Context?, text: String, append: Boolean) {
        if (context == null) return
        try {
            val f = File(context.filesDir, START_FILE)
            if (append) f.appendText(text) else f.writeText(text)
        } catch (_: Throwable) {
        }
        try {
            val ext = context.getExternalFilesDir(null)
            if (ext != null) {
                val f = File(ext, START_FILE)
                if (append) f.appendText(text) else f.writeText(text)
            }
        } catch (_: Throwable) {
        }
    }
}
EOF_MARKER_21

mkdir -p "$(dirname 'android/app/src/main/kotlin/com/hypertechlabs/maxplayer/MainActivity.kt')"
cat > 'android/app/src/main/kotlin/com/hypertechlabs/maxplayer/MainActivity.kt' <<'EOF_MARKER_22'
package com.hypertechlabs.maxplayer

import android.app.KeyguardManager
import android.app.PendingIntent
import android.app.PictureInPictureParams
import android.app.RemoteAction
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.drawable.Icon
import android.hardware.biometrics.BiometricManager
import android.hardware.biometrics.BiometricPrompt
import android.media.AudioFormat
import android.media.AudioManager
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.media.MediaScannerConnection
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Bundle
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import android.os.StatFs
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.view.WindowManager
import dev.ffmpegkit.whisper.Whisper
import dev.ffmpegkit.whisper.WhisperConfig
import dev.ffmpegkit.whisper.WhisperModel
import android.hardware.SensorManager
import android.view.OrientationEventListener
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.io.RandomAccessFile
import java.net.HttpURLConnection
import java.net.URL
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.security.MessageDigest
import java.util.concurrent.Executors
import kotlin.math.roundToInt
import kotlin.math.min
import kotlinx.coroutines.runBlocking

/**
 * Native bridge for Max Player. One MethodChannel ("maxplayer/native") exposes:
 *
 *  - getMetadata(path): video duration/dimensions + a cached JPEG thumbnail,
 *    extracted with Android's own MediaMetadataRetriever (no third-party
 *    plugin = no AAR conflicts with the AGP 9 / Kotlin 2.3 toolchain).
 *
 *  - settingsGetAll / settingsPut: tiny key/value store backed by Android
 *    SharedPreferences (settings, watch history, gesture prefs).
 *
 *  - getBrightness / setBrightness / resetBrightness: app-local screen
 *    brightness for the player's left-half swipe gesture.
 *
 *  - "Open with" / "Share" support: VIEW and SEND intents carrying videos are
 *    resolved to real filesystem paths (file://, MediaStore content://,
 *    external-storage document URIs) and delivered to Dart via
 *    getInitialOpenVideo (cold start) or onOpenVideo / onOpenVideoFailed
 *    (warm start, singleTop re-use). Gallery/cloud URIs that do not expose a
 *    real path are stream-copied into the app cache as a fallback. Network
 *    URLs (http/https/rtsp/rtmp/mms) are passed to the player as-is.
 *
 *  - Picture-in-picture with a custom play/pause remote action: providing our
 *    own action also replaces the system's default "settings" gear in the PiP
 *    window. Playback state is kept in sync via setPipPlaying; taps on the
 *    PiP action arrive as the "onPipAction" channel call.
 */
class MainActivity : FlutterActivity() {
    private val channelName = "maxplayer/native"
    private val executor = Executors.newFixedThreadPool(4)
    private val mainHandler = Handler(Looper.getMainLooper())

    private var channel: MethodChannel? = null
    private var pendingOpenPath: String? = null
    private var pendingOpenFailed: String? = null

    // --- Picture-in-picture remote action state ---
    private var pipPlaying = true
    private var pipReceiverRegistered = false

    // --- AI subtitles job state ---
    @Volatile
    private var aiCancelled = false
    private var aiJobCounter = 0

    // --- DLNA casting: multicast lock held during SSDP discovery ---
    private var multicastLock: WifiManager.MulticastLock? = null

    /** Thrown by the model downloader when the user cancels the job. */
    private class AiCancelledException : Exception("cancelled")

    companion object {
        private const val ACTION_PIP_TOGGLE = "com.hypertechlabs.maxplayer.action.PIP_TOGGLE"
        private const val REQ_PIP_TOGGLE = 42
        private const val REQ_PIP_OPEN = 43
        private const val REQ_CONFIRM_CREDENTIAL = 44
        private val STREAM_SCHEMES = setOf("http", "https", "rtsp", "rtmp", "mms")
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        CrashCrumbs.mark(this, "activity_create_begin")
        super.onCreate(savedInstanceState)
        CrashCrumbs.mark(this, "activity_create_ok")
        handleIncomingIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIncomingIntent(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        channel?.setMethodCallHandler { call, result ->
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
                "getBrightness" -> {
                    // screenBrightness < 0 means "no override" (system default).
                    val b = window.attributes.screenBrightness
                    result.success(if (b < 0f) 1.0 else b.toDouble())
                }
                "setBrightness" -> {
                    // Clamp to [0.02, 1] so the screen can never go fully
                    // black and trap the user.
                    val v = (call.argument<Double>("value") ?: 1.0).coerceIn(0.02, 1.0)
                    val lp = window.attributes
                    lp.screenBrightness = v.toFloat()
                    window.attributes = lp
                    result.success(true)
                }
                "resetBrightness" -> {
                    val lp = window.attributes
                    lp.screenBrightness =
                        WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE
                    window.attributes = lp
                    result.success(true)
                }
                "getMediaVolume" -> {
                    // DEVICE media volume (the player's swipe drives this,
                    // like MX Player/VLC, so it can always reach the phone's
                    // true maximum loudness).
                    try {
                        val am =
                            getSystemService(Context.AUDIO_SERVICE) as AudioManager
                        val max = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                            .coerceAtLeast(1)
                        val cur = am.getStreamVolume(AudioManager.STREAM_MUSIC)
                        result.success(hashMapOf("level" to cur, "max" to max))
                    } catch (e: Exception) {
                        result.error("volume", e.message, null)
                    }
                }
                "setMediaVolume" -> {
                    try {
                        val v = (call.argument<Double>("value") ?: 0.75)
                            .coerceIn(0.0, 1.0)
                        val am =
                            getSystemService(Context.AUDIO_SERVICE) as AudioManager
                        val max = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                            .coerceAtLeast(1)
                        am.setStreamVolume(
                            AudioManager.STREAM_MUSIC,
                            (v * max).roundToInt().coerceIn(0, max),
                            0
                        )
                        result.success(true)
                    } catch (_: Exception) {
                        result.success(false)
                    }
                }
                "getInitialOpenVideo" -> {
                    val map = HashMap<String, String?>()
                    map["path"] = pendingOpenPath
                    map["failed"] = pendingOpenFailed
                    pendingOpenPath = null
                    pendingOpenFailed = null
                    result.success(map)
                }
                "enterPip" -> {
                    pipPlaying = call.argument<Boolean>("playing") ?: true
                    result.success(
                        try {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                ensurePipReceiver()
                                enterPictureInPictureMode(buildPipParams())
                                true
                            } else {
                                false
                            }
                        } catch (e: Exception) {
                            false
                        }
                    )
                }
                "setPipPlaying" -> {
                    pipPlaying = (call.arguments as? Boolean) ?: true
                    // Only refresh the action while actually in PiP; swapping
                    // the action replaces the default settings gear with our
                    // play/pause button.
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                        isInPictureInPictureMode
                    ) {
                        try {
                            // Swapping the action also REPLACES the default
                            // "settings" gear with our play/pause button.
                            setPictureInPictureParams(buildPipParams())
                        } catch (_: Exception) {
                        }
                    }
                    result.success(true)
                }
                "enableSensorRotate" -> {
                    // v19: rotate the player by ACCELEROMETER, ignoring the
                    // phone's auto-rotate switch (explicit orientation
                    // requests win over the system toggle).
                    ensureRotateListener()
                    rotateLocked = false
                    rotateListener?.enable()
                    result.success(true)
                }
                "disableSensorRotate" -> {
                    rotateListener?.disable()
                    rotateLocked = false
                    // Hand rotation control back to the system.
                    requestedOrientation =
                        android.content.pm.ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
                    result.success(true)
                }
                "lockRotation" -> {
                    val landscape = call.argument<Boolean>("landscape") ?: true
                    rotateLocked = true
                    rotateListener?.disable()
                    requestedOrientation = if (landscape)
                        android.content.pm.ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
                    else
                        android.content.pm.ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
                    result.success(true)
                }
                "thumbStripEnsure" -> {
                    val p = call.argument<String>("path")
                    executor.execute {
                        val dir = thumbStripEnsureSync(p)
                        mainHandler.post { result.success(dir) }
                    }
                }
                "whisperAvailable" -> {
                    // AI SUBTITLES Phase-1 probe: proves the on-device
                    // whisper.cpp engine loaded its native library on this
                    // device. Runs off the main thread (first call may load
                    // libwhisper.so).
                    executor.execute {
                        val info = try {
                            Whisper.getSystemInfo()
                        } catch (t: Throwable) {
                            null
                        }
                        mainHandler.post { result.success(info) }
                    }
                }
                "aiModelStatus" -> {
                    // Which models are already on disk, with size in MB.
                    val map = HashMap<String, Any>()
                    for (name in listOf("tiny", "base", "small")) {
                        val f = modelFileFor(name)
                        map[name] = if (f.exists() && f.length() > 1_000_000) {
                            (f.length() / (1024 * 1024)).toInt()
                        } else {
                            0
                        }
                    }
                    result.success(map)
                }
                "aiSubtitleGenerate" -> {
                    val videoPath = call.argument<String>("videoPath")
                    val model = call.argument<String>("model") ?: "base"
                    val language = call.argument<String>("language") ?: "auto"
                    // v21: whisper translate task -> English subtitles from
                    // any spoken language.
                    val translate = call.argument<Boolean>("translate") ?: false
                    if (videoPath.isNullOrEmpty()) {
                        result.error("bad_args", "videoPath is required", null)
                    } else {
                        aiCancelled = false
                        val jobId = ++aiJobCounter
                        executor.execute {
                            runAiPipeline(jobId, videoPath, model, language, translate)
                        }
                        result.success(jobId)
                    }
                }
                "aiSubtitleCancel" -> {
                    aiCancelled = true
                    result.success(true)
                }
                "scanFile" -> {
                    // Register a freshly-written file (screenshot, AI .srt)
                    // with the media scanner so gallery apps see it at once.
                    val path = call.argument<String>("path")
                    if (path.isNullOrEmpty()) {
                        result.error("bad_args", "path is required", null)
                    } else {
                        try {
                            MediaScannerConnection.scanFile(
                                applicationContext, arrayOf(path), null, null
                            )
                            result.success(true)
                        } catch (_: Exception) {
                            result.success(false)
                        }
                    }
                }
                "vaultDirPath" -> {
                    // v24 private-folder crash fix: the vault lived at a
                    // hardcoded /Android/data/<pkg> path, and creating the
                    // package folder there via raw mkdir is EACCES-denied
                    // on some devices when it is missing (real crash:
                    // PathAccessException errno=13 right after PIN entry).
                    // getExternalFilesDir lets the FRAMEWORK create/own it -
                    // no storage permission involved at all. On most phones
                    // this resolves to the exact same path as before, so
                    // already-hidden files stay put (Dart also migrates).
                    try {
                        val base = getExternalFilesDir(null) ?: filesDir
                        val dir = File(base, "Private")
                        if (dir.exists() || dir.mkdirs()) {
                            result.success(dir.absolutePath)
                        } else {
                            result.success(null)
                        }
                    } catch (e: Exception) {
                        result.success(null)
                    }
                }
                "confirmDeviceCredential" -> {
                    // v26: "Forgot PIN" for the Private folder must first
                    // pass the PHONE's own lock (device password / pattern /
                    // PIN or fingerprint) - pure platform APIs, no new deps.
                    confirmDeviceCredential(
                        call.argument<String>("title") ?: "Unlock to continue",
                        result,
                    )
                }
                "thumbnailPathFor" -> {
                    // The Dart player's 4K/HDR thumbnail fallback (v22): when
                    // Android's metadata engine can't decode a frame from a
                    // file, mpv (which plays them fine) captures one at this
                    // exact cache path during playback. Returning null tells
                    // Dart "don't even try" (missing file / stream).
                    val path = call.argument<String>("path")
                    if (path.isNullOrEmpty() || !File(path).exists()) {
                        result.success(null)
                    } else {
                        result.success(thumbFileFor(path).absolutePath)
                    }
                }
                "storageReport" -> {
                    // v28 Cleaner tile: sizes of the app's own reclaimable
                    // storage (thumbs / preview strips / AI temp / models).
                    result.success(storageReport())
                }
                "clearStorage" -> {
                    // Long (bytes freed); videos themselves are untouched.
                    result.success(clearStorageKind(call.argument<String>("kind") ?: ""))
                }
                "storageTotals" -> {
                    // v31 Cleaner graph: total/free bytes of the internal
                    // storage volume the app lives on.
                    val stat = StatFs(filesDir.absolutePath)
                    val out = HashMap<String, Long>()
                    out["total"] = stat.blockSizeLong * stat.blockCountLong
                    out["free"] = stat.blockSizeLong * stat.availableBlocksLong
                    result.success(out)
                }
                "setMulticastLock" -> {
                    // DLNA casting: SSDP multicast discovery needs a Wi-Fi
                    // multicast lock on many devices; Dart holds it while a
                    // device scan runs and releases it afterwards.
                    val hold = call.arguments as? Boolean ?: false
                    try {
                        if (hold) {
                            if (multicastLock == null) {
                                val wm =
                                    applicationContext.getSystemService(Context.WIFI_SERVICE)
                                        as WifiManager
                                multicastLock = wm.createMulticastLock("maxplayer_cast")
                                multicastLock?.setReferenceCounted(true)
                            }
                            multicastLock?.acquire()
                        } else {
                            if (multicastLock?.isHeld == true) multicastLock?.release()
                        }
                        result.success(true)
                    } catch (_: Exception) {
                        result.success(false)
                    }
                }
                "crumb" -> {
                    // v37: startup breadcrumb from Dart - append a stage
                    // mark to maxplayer_start.log (internal + the
                    // Android/data folder), survives a dead Dart/engine.
                    CrashCrumbs.mark(this, call.argument<String>("stage") ?: "unknown")
                    result.success(true)
                }
                "nativeCrashGet" -> {
                    // v34: read the JVM crash report the Application-level
                    // catcher (MaxPlayerApp) wrote after a "has stopped".
                    // null when there is none.
                    val text = try {
                        val f = File(filesDir, MaxPlayerApp.CRASH_FILE)
                        if (f.exists()) f.readText() else null
                    } catch (_: Exception) {
                        null
                    }
                    result.success(text)
                }
                "nativeCrashClear" -> {
                    // Called once the report was shown to the user.
                    try {
                        val f = File(filesDir, MaxPlayerApp.CRASH_FILE)
                        if (f.exists()) f.delete()
                    } catch (_: Exception) {
                        // best effort only
                    }
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
        CrashCrumbs.mark(this, "channel_ready")
        // Channel is ready: deliver anything that arrived before Dart attached.
        pendingOpenPath?.let {
            channel?.invokeMethod("onOpenVideo", it)
            pendingOpenPath = null
        }
        pendingOpenFailed?.let {
            channel?.invokeMethod("onOpenVideoFailed", it)
            pendingOpenFailed = null
        }
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        channel?.invokeMethod("onPipChanged", isInPictureInPictureMode)
    }

    // ---------------------------------------------------------------------------
    // PiP play/pause remote action
    // ---------------------------------------------------------------------------

    private fun buildPipParams(): PictureInPictureParams {
        val toggleIntent = PendingIntent.getBroadcast(
            this,
            REQ_PIP_TOGGLE,
            Intent(ACTION_PIP_TOGGLE).setPackage(packageName),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val label = if (pipPlaying) "Pause" else "Play"
        val toggle = RemoteAction(makePipIcon(pause = pipPlaying), label, label, toggleIntent)
        // Second action: pop the PiP window back into the full app. Filling
        // the action tray with OUR buttons replaces any default system
        // "settings" gear the launcher would otherwise show.
        val openIntent = PendingIntent.getActivity(
            this,
            REQ_PIP_OPEN,
            packageManager.getLaunchIntentForPackage(packageName)
                ?: Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val open = RemoteAction(makeExpandIcon(), "Open Max Player", "Open Max Player", openIntent)
        return PictureInPictureParams.Builder()
            .setActions(listOf(toggle, open))
            .build()
    }

    /** Draws a simple white play triangle / pause bars icon (no resources needed). */
    private fun makePipIcon(pause: Boolean): Icon {
        val size = 96
        val bmp = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bmp)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE
            style = Paint.Style.FILL
        }
        if (pause) {
            val barW = size * 0.18f
            val gap = size * 0.14f
            val top = size * 0.24f
            val bottom = size * 0.76f
            val left = (size - barW * 2 - gap) / 2f
            canvas.drawRect(left, top, left + barW, bottom, paint)
            canvas.drawRect(left + barW + gap, top, left + barW * 2 + gap, bottom, paint)
        } else {
            val path = Path()
            path.moveTo(size * 0.36f, size * 0.24f)
            path.lineTo(size * 0.74f, size * 0.5f)
            path.lineTo(size * 0.36f, size * 0.76f)
            path.close()
            canvas.drawPath(path, paint)
        }
        return Icon.createWithBitmap(bmp)
    }

    /** Draws a white "expand" glyph (inner square + outward arrow). */
    private fun makeExpandIcon(): Icon {
        val size = 96
        val bmp = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bmp)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE
            style = Paint.Style.STROKE
            strokeWidth = size * 0.07f
            strokeCap = Paint.Cap.ROUND
        }
        val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE
            style = Paint.Style.FILL
        }
        // Inner square.
        val inset = size * 0.28f
        canvas.drawRect(inset, inset, size - inset, size - inset, paint)
        // Outward diagonal arrow (top-right).
        val ax = size * 0.58f
        val ay = size * 0.42f
        canvas.drawLine(ax - size * 0.12f, ay + size * 0.12f, ax, ay, paint)
        val arrowHead = Path()
        arrowHead.moveTo(ax - size * 0.13f, ay - size * 0.02f)
        arrowHead.lineTo(ax + size * 0.02f, ay - size * 0.02f)
        arrowHead.lineTo(ax + size * 0.02f, ay + size * 0.13f)
        arrowHead.close()
        canvas.drawPath(arrowHead, fill)
        return Icon.createWithBitmap(bmp)
    }

    private val pipReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == ACTION_PIP_TOGGLE) {
                channel?.invokeMethod("onPipAction", "toggle")
            }
        }
    }

    private fun ensurePipReceiver() {
        if (pipReceiverRegistered) return
        pipReceiverRegistered = true
        val filter = IntentFilter(ACTION_PIP_TOGGLE)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(pipReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            registerReceiver(pipReceiver, filter)
        }
    }

    // ---------------------------------------------------------------------------
    // "Open with" / "Share" handling
    // ---------------------------------------------------------------------------

    private fun handleIncomingIntent(intent: Intent?) {
        if (intent == null) return
        val uri: Uri = when (intent.action) {
            Intent.ACTION_VIEW -> intent.data ?: return
            Intent.ACTION_SEND -> extractSendUri(intent) ?: return
            else -> return
        }
        val scheme = uri.scheme?.lowercase()
        when {
            // Network link: hand the URL to libmpv directly.
            scheme in STREAM_SCHEMES -> deliverOpen(uri.toString(), null)
            else -> {
                // Path resolution + possible stream copy hit the disk - keep
                // it off the main thread.
                executor.execute {
                    var resolved = resolveVideoPath(uri)
                    if (resolved == null && scheme == "content") {
                        resolved = copyContentToCache(uri)
                    }
                    mainHandler.post {
                        deliverOpen(resolved, if (resolved == null) uri.toString() else null)
                    }
                }
            }
        }
    }

    private fun deliverOpen(resolved: String?, failed: String?) {
        if (channel != null) {
            if (resolved != null) {
                channel?.invokeMethod("onOpenVideo", resolved)
            } else if (failed != null) {
                channel?.invokeMethod("onOpenVideoFailed", failed)
            }
        } else {
            // Dart side not attached yet - getInitialOpenVideo picks this up.
            if (resolved != null) pendingOpenPath = resolved
            else if (failed != null) pendingOpenFailed = failed
        }
    }

    @Suppress("DEPRECATION")
    private fun extractSendUri(intent: Intent): Uri? {
        val direct: Uri? =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
            } else {
                intent.getParcelableExtra(Intent.EXTRA_STREAM)
            }
        if (direct != null) return direct
        // A few apps stuff the Uri into ClipData instead of EXTRA_STREAM.
        val clip = intent.clipData
        if (clip != null && clip.itemCount > 0) {
            return clip.getItemAt(0).uri
        }
        return null
    }

    /**
     * Turns a content:// or file:// URI into a real filesystem path our
     * player (libmpv) can open. Strategies:
     *  1. file:// -> direct path
     *  2. MediaStore DATA column (we hold all-files access, so it answers)
     *  3. ExternalStorageProvider document URIs ("primary:Downloads/x.mp4")
     */
    private fun resolveVideoPath(uri: Uri): String? {
        when (uri.scheme) {
            "file" -> return uri.path
            "content" -> {
                // MediaStore / generic providers exposing the _data column.
                try {
                    contentResolver.query(
                        uri, arrayOf(MediaStore.MediaColumns.DATA), null, null, null
                    )?.use { c ->
                        if (c.moveToFirst()) {
                            val p = c.getString(0)
                            if (!p.isNullOrEmpty()) return p
                        }
                    }
                } catch (e: Exception) {
                    // fall through to document parsing
                }
                // content://com.android.externalstorage.documents/document/primary:Dir/x.mp4
                if (uri.authority == "com.android.externalstorage.documents") {
                    val doc = uri.lastPathSegment ?: return null
                    val parts = doc.split(":", limit = 2)
                    if (parts.size == 2) {
                        val decoded = Uri.decode(parts[1])
                        return if (parts[0].equals("primary", ignoreCase = true)) {
                            "/storage/emulated/0/$decoded"
                        } else {
                            // SD card style volumes: "1234-5678:Dir/x.mp4"
                            "/storage/${parts[0]}/$decoded"
                        }
                    }
                }
            }
        }
        return null
    }

    /**
     * Last-resort fallback for gallery/cloud URIs that expose no real path
     * (e.g. Google Photos mediakey URIs): stream the bytes into the app cache
     * and play the copy. Older copies are cleared out first so this cannot
     * grow unboundedly.
     */
    private fun copyContentToCache(uri: Uri): String? {
        return try {
            var name = queryDisplayName(uri) ?: "video.mp4"
            name = name.replace(Regex("[^A-Za-z0-9._-]"), "_")
            if (!name.contains('.')) name += ".mp4"
            val dir = File(cacheDir, "opened")
            if (dir.exists()) {
                dir.listFiles()?.forEach { it.delete() }
            } else {
                dir.mkdirs()
            }
            val out = File(dir, name)
            contentResolver.openInputStream(uri)?.use { input ->
                FileOutputStream(out).use { output -> input.copyTo(output) }
            } ?: return null
            if (out.length() <= 0) {
                out.delete()
                null
            } else {
                out.absolutePath
            }
        } catch (e: Exception) {
            null
        }
    }

    private fun queryDisplayName(uri: Uri): String? {
        return try {
            contentResolver.query(
                uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null
            )?.use { c ->
                if (c.moveToFirst() && !c.isNull(0)) c.getString(0) else null
            }
        } catch (e: Exception) {
            null
        }
    }

    // ---------------------------------------------------------------------------
    // Metadata + thumbnails
    // ---------------------------------------------------------------------------

    /**
     * v21 4K/HDR-safe frame grab, least-risk first. The old code asked for a
     * FULL-SIZE frame and scaled it afterwards - on 4K videos that bitmap is
     * ~33 MB, which OOM-failed (or returned null on some 10-bit HEVC rips)
     * and the tile silently kept the placeholder icon. Ladder:
     *   1. getScaledFrameAtTime: decode directly at 320px wide (API 27+)
     *   2. plain getFrameAtTime at the same timestamp
     *   3. plain getFrameAtTime(0)  - some files only expose the first frame
     *   4. embedded cover art
     * Every step swallows Throwables (incl. OutOfMemoryError) and falls
     * through to the next one.
     */
    private fun grabFrameSafely(
        retriever: MediaMetadataRetriever,
        seekUs: Long,
        width: Int?,
        height: Int?
    ): Bitmap? {
        if (Build.VERSION.SDK_INT >= 27 && width != null && height != null && width > 0 && height > 0) {
            val dstW = 320
            val dstH = (320.0 * height / width).toInt().coerceAtLeast(1)
            try {
                val f = retriever.getScaledFrameAtTime(
                    seekUs, MediaMetadataRetriever.OPTION_CLOSEST_SYNC, dstW, dstH
                )
                if (f != null) return f
            } catch (_: Throwable) {
            }
        }
        try {
            val f = retriever.getFrameAtTime(seekUs, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
            if (f != null) return f
        } catch (_: Throwable) {
        }
        try {
            val f = retriever.getFrameAtTime(0L, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
            if (f != null) return f
        } catch (_: Throwable) {
        }
        try {
            val art = retriever.embeddedPicture
            if (art != null) return BitmapFactory.decodeByteArray(art, 0, art.size)
        } catch (_: Throwable) {
        }
        return null
    }

    /**
     * Cache file holding the thumbnail of [path]. Shared with the Dart
     * player's mpv-screenshot fallback (v22), which writes to this exact
     * location when Android's MediaMetadataRetriever can't decode a file.
     */
    private fun thumbFileFor(path: String): File {
        val thumbsDir = File(cacheDir, "thumbs").apply { mkdirs() }
        return File(thumbsDir, md5(path) + ".jpg")
    }

    // ------------------------------------------------------------------
    // v28: Cleaner tile - reclaimable app storage report + freeing
    // ------------------------------------------------------------------

    private fun dirSizeBytes(f: File): Long {
        try {
            if (!f.exists()) return 0L
            if (f.isFile) return f.length()
            var total = 0L
            val list = f.listFiles() ?: return 0L
            for (c in list) total += dirSizeBytes(c)
            return total
        } catch (_: Exception) {
            return 0L
        }
    }

    private fun thumbStripDirs(): List<File> {
        val list = cacheDir.listFiles() ?: return emptyList()
        return list.filter { it.isDirectory && it.name.startsWith("thumbstrip_") }
    }

    /** Leftover AI wav chunks / abandoned capture temp files in the cache root. */
    private fun tempAiFiles(): List<File> {
        val list = cacheDir.listFiles() ?: return emptyList()
        return list.filter {
            it.isFile && (
                it.name.startsWith("ai_audio_") ||
                    it.name.startsWith("ai_span_") ||
                    it.name.endsWith(".capture")
                )
        }
    }

    private fun storageReport(): HashMap<String, Long> {
        val out = HashMap<String, Long>()
        var strips = 0L
        for (d in thumbStripDirs()) strips += dirSizeBytes(d)
        var temp = 0L
        for (f in tempAiFiles()) temp += f.length()
        out["thumbs"] = dirSizeBytes(File(cacheDir, "thumbs"))
        out["strips"] = strips
        out["temp"] = temp
        out["models"] = dirSizeBytes(File(filesDir, "models"))
        return out
    }

    private fun clearStorageKind(kind: String): Long {
        var freed = 0L
        when (kind) {
            "thumbs" -> {
                val d = File(cacheDir, "thumbs")
                freed += dirSizeBytes(d)
                d.deleteRecursively()
                d.mkdirs()
                for (s in thumbStripDirs()) {
                    freed += dirSizeBytes(s)
                    s.deleteRecursively()
                }
            }
            "temp" -> {
                for (f in tempAiFiles()) {
                    val len = f.length()
                    if (f.delete()) freed += len
                }
            }
            "models" -> {
                val d = File(filesDir, "models")
                freed += dirSizeBytes(d)
                d.deleteRecursively()
            }
        }
        return freed
    }

    /**
     * Extracts duration/dimensions and writes a thumbnail JPEG into the app
     * cache dir. Thumbnails are cached per video path and re-used while the
     * source file's mtime is older than the cached image, so rescanning the
     * library does NOT regenerate them every launch.
     */
    private fun extractMetadata(path: String): HashMap<String, Any?> {
        val out = HashMap<String, Any?>()
        out["thumbnailPath"] = null
        out["durationMs"] = null
        out["width"] = null
        out["height"] = null
        out["bitrate"] = null
        out["codec"] = null

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
            out["bitrate"] =
                retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_BITRATE)?.toLongOrNull()
            // Track details from the container (one extractor pass, works
            // on all API levels): video codec + frame rate, first audio
            // track's codec/channels/sample-rate. v27: powers the advanced
            // Video info sheet.
            addTrackDetails(path, out)

            val thumbFile = thumbFileFor(path)

            val cacheValid =
                thumbFile.exists() && thumbFile.length() > 0 &&
                    thumbFile.lastModified() >= videoFile.lastModified()

            if (cacheValid) {
                out["thumbnailPath"] = thumbFile.absolutePath
            } else {
                // Grab a frame ~1s in (or the very first frame for tiny clips).
                val seekUs = if (durationMs != null && durationMs in 0..1500) 0L else 1_000_000L
                val frame = grabFrameSafely(
                    retriever, seekUs,
                    out["width"] as? Int, out["height"] as? Int
                )
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

    /**
     * Reads the first video track's MIME type from the container and maps it to a
     * friendly codec name (e.g. "video/hevc" -> "H.265 (HEVC)"). Returns null when
     * the file has no video track or cannot be parsed.
     */
    /**
     * v27: fills [out] with codec + technical track details in ONE
     * MediaExtractor pass (cheap enough for the per-file library scan):
     *  - "codec": friendly video codec name from the video track MIME
     *  - "frameRate": video track fps (0 when the container omits it)
     *  - "audioCodec": friendly name of the FIRST audio track
     *  - "audioChannels" / "audioSampleRate": same track's layout/rate
     */
    private fun addTrackDetails(path: String, out: HashMap<String, Any?>) {
        out["frameRate"] = 0
        out["audioCodec"] = null
        out["audioChannels"] = 0
        out["audioSampleRate"] = 0
        out["hdr"] = "sdr"
        val extractor = MediaExtractor()
        try {
            extractor.setDataSource(path)
            var videoDone = false
            var audioDone = false
            for (i in 0 until extractor.trackCount) {
                val format = extractor.getTrackFormat(i)
                val mime =
                    if (format.containsKey(MediaFormat.KEY_MIME)) {
                        format.getString(MediaFormat.KEY_MIME)
                    } else {
                        null
                    } ?: continue
                if (!videoDone && mime.startsWith("video/")) {
                    out["codec"] = friendlyCodec(mime)
                    if (format.containsKey(MediaFormat.KEY_FRAME_RATE)) {
                        out["frameRate"] = format.getInteger(MediaFormat.KEY_FRAME_RATE)
                    }
                    // v32: dynamic-range detection for the info sheet.
                    // Dolby Vision has no licensed pipeline here - mpv plays
                    // its HDR10-compatible fallback, which the Dart label
                    // communicates. Dolby files report mime
                    // "video/dolby-vision" (dvhe/dvav) via MediaExtractor.
                    out["hdr"] = when {
                        mime == "video/dolby-vision" -> "dolby-vision"
                        format.containsKey("hdr10-plus-info") -> "hdr10+"
                        format.containsKey("hdr-static-info") -> "hdr10"
                        format.containsKey(MediaFormat.KEY_COLOR_TRANSFER) ->
                            when (format.getInteger(MediaFormat.KEY_COLOR_TRANSFER)) {
                                6 -> "hdr10" // MediaFormat.COLOR_TRANSFER_ST2084 (PQ)
                                7 -> "hlg"   // MediaFormat.COLOR_TRANSFER_HLG
                                else -> "sdr"
                            }
                        else -> "sdr"
                    }
                    videoDone = true
                } else if (!audioDone && mime.startsWith("audio/")) {
                    out["audioCodec"] = friendlyCodec(mime)
                    if (format.containsKey(MediaFormat.KEY_CHANNEL_COUNT)) {
                        out["audioChannels"] =
                            format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                    }
                    if (format.containsKey(MediaFormat.KEY_SAMPLE_RATE)) {
                        out["audioSampleRate"] =
                            format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                    }
                    audioDone = true
                }
                if (videoDone && audioDone) break
            }
        } catch (_: Exception) {
            // Leave the defaults/nulls - Dart renders "Unknown".
        } finally {
            extractor.release()
        }
    }

    private fun friendlyCodec(mime: String): String {
        return when (mime.lowercase()) {
            "video/avc", "video/h264" -> "H.264 (AVC)"
            "video/hevc", "video/h265" -> "H.265 (HEVC)"
            "video/av01" -> "AV1"
            "video/x-vnd.on2.vp8" -> "VP8"
            "video/x-vnd.on2.vp9" -> "VP9"
            "video/mp4v-es" -> "MPEG-4"
            "video/3gpp" -> "H.263"
            "video/mpeg2" -> "MPEG-2"
            "video/x-msvideo" -> "AVI"
            // v27: audio track names for the advanced Video info sheet.
            "audio/mp4a-latm" -> "AAC"
            "audio/mpeg", "audio/mpeg-l1", "audio/mpeg-l2" -> "MP3"
            "audio/opus" -> "Opus"
            "audio/vorbis" -> "Vorbis"
            "audio/flac" -> "FLAC"
            "audio/ac3" -> "AC-3"
            "audio/eac3", "audio/eac3-joc" -> "E-AC-3"
            "audio/truehd" -> "TrueHD"
            "audio/x-ms-wma" -> "WMA"
            "audio/amr-nb", "audio/amr-wb" -> "AMR"
            "audio/raw" -> "PCM"
            else -> mime.substringAfter('/').uppercase()
        }
    }

    // ---------------------------------------------------------------------------
    // AI subtitles pipeline (Phases 2+3)
    //
    //   video -> [MediaExtractor + MediaCodec] 16 kHz mono WAV
    //         -> whisper.cpp (offline) -> timestamped segments -> Dart
    //
    // Dart builds the .srt text (pure, unit-tested) and mpv loads it via
    // `sub-add`. The model is downloaded once from Hugging Face (~142 MB
    // base / ~466 MB small); after that everything is offline & free.
    // ---------------------------------------------------------------------------

    // v25: only the accurate models stay ("tiny" removed for good). Speed
    // comes from all-core threading instead of a weaker model. Unknown ids
    // (including a "tiny" id saved by v22-v24 builds) fall back to "base".
    private fun modelFileFor(name: String): File {
        val safe = when (name) {
            "base", "small" -> name
            else -> "base"
        }
        return File(filesDir, "models/ggml-$safe.bin")
    }

    private fun modelUrlFor(name: String): String {
        return when (name) {
            "small" ->
                "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin"
            else ->
                "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin"
        }
    }

    private fun aiProgress(jobId: Int, stage: String, percent: Int) {
        mainHandler.post {
            channel?.invokeMethod(
                "onAiProgress",
                hashMapOf("job" to jobId, "stage" to stage, "percent" to percent)
            )
        }
    }

    private fun aiDone(jobId: Int, segments: ArrayList<HashMap<String, Any>>) {
        mainHandler.post {
            channel?.invokeMethod(
                "onAiSubtitleDone",
                hashMapOf("job" to jobId, "segments" to segments)
            )
        }
    }

    private fun aiFailed(jobId: Int, message: String) {
        mainHandler.post {
            channel?.invokeMethod(
                "onAiSubtitleFailed",
                hashMapOf("job" to jobId, "message" to message)
            )
        }
    }

    private fun runAiPipeline(
        jobId: Int,
        videoPath: String,
        modelName: String,
        language: String,
        translate: Boolean = false
    ) {
        try {
            // 1. Model file (one-time download).
            val modelFile = modelFileFor(modelName)
            if (!modelFile.exists() || modelFile.length() < 1_000_000) {
                aiProgress(jobId, "downloading", 0)
                val dlError = try {
                    downloadModel(modelUrlFor(modelName), modelFile, jobId)
                    null
                } catch (e: AiCancelledException) {
                    "cancelled"
                } catch (e: Exception) {
                    (e.message ?: "network error").take(80)
                }
                if (dlError != null) {
                    modelFile.delete()
                    aiFailed(
                        jobId,
                        if (dlError == "cancelled") "cancelled"
                        else "Model download failed ($dlError) - internet is needed once; after that AI subtitles work fully offline."
                    )
                    return
                }
            }
            if (aiCancelled) return aiFailed(jobId, "cancelled")

            // 2. Extract audio track -> 16 kHz mono WAV.
            aiProgress(jobId, "extracting", 0)
            val wav = File(cacheDir, "ai_audio_$jobId.wav")
            if (!extractAudioToWav(videoPath, wav, jobId)) {
                wav.delete()
                aiFailed(
                    jobId,
                    if (aiCancelled) "cancelled" else "Could not read the audio track of this file."
                )
                return
            }
            if (aiCancelled) {
                wav.delete()
                return aiFailed(jobId, "cancelled")
            }

            // 3. Transcribe with whisper.cpp (offline), speech-gated:
            // the 16 kHz track is first split into voiced spans and only
            // those are sent to whisper. Long silent stretches of a video
            // are skipped entirely, which is FASTER (a big share of any
            // movie is non-speech) AND cleaner (whisper used to answer
            // silence with "music" hallucinations). Music is never treated
            // as silence, so speech over loud background music still gets
            // transcribed. A cancel between spans takes effect immediately;
            // a cancel mid-span discards the result afterwards.
            aiProgress(jobId, "transcribing", 0)
            val segments = ArrayList<HashMap<String, Any>>()
            runBlocking {
                var model: WhisperModel? = null
                try {
                    model = Whisper.loadModel(this@MainActivity, modelFile.absolutePath)
                    val pcmData = readWavPcm(wav) ?: ByteArray(0)
                    val spans = speechSpans(pcmData)
                    // spans empty = no voice anywhere -> empty result, and
                    // Dart shows its friendly "No speech detected" snack.
                    spans.forEachIndexed { i, span ->
                        if (aiCancelled) return@forEachIndexed
                        val spanWav = File(cacheDir, "ai_span_${jobId}_$i.wav")
                        try {
                            writeSpanWav(spanWav, pcmData, span[0], span[1])
                            // The user can pin a language ("hi", "ur", "en", ...)
                            // in the Generate dialog; "auto" = detect it. Pinning
                            // is noticeably more accurate than detection.
                            val res = Whisper.transcribe(
                                model,
                                spanWav.absolutePath,
                                WhisperConfig(
                                    language = language,
                                    translate = translate,
                                    // v22: use every core the phone offers -
                                    // whisper.cpp scales well to 8 threads,
                                    // roughly halving transcription time vs
                                    // the library default of 4.
                                    threads = Runtime.getRuntime()
                                        .availableProcessors()
                                        .coerceIn(2, 8),
                                )
                            )
                            val offsetMs = span[0] * 1000L / 16000
                            for (s in res.segments) {
                                val text = s.text.trim()
                                if (text.isEmpty()) continue
                                segments.add(
                                    hashMapOf(
                                        "start" to (s.startMs + offsetMs) as Any,
                                        "end" to (s.endMs + offsetMs) as Any,
                                        "text" to text as Any
                                    )
                                )
                            }
                        } finally {
                            spanWav.delete()
                        }
                        aiProgress(jobId, "transcribing", (i + 1) * 100 / spans.size)
                    }
                } finally {
                    model?.let { Whisper.releaseModel(it) }
                }
            }
            wav.delete()
            if (aiCancelled) return aiFailed(jobId, "cancelled")
            aiDone(jobId, segments)
        } catch (t: Throwable) {
            aiFailed(jobId, t.message ?: "AI subtitle generation failed")
        }
    }

    /**
     * Downloads [url] into [dest] via a ".part" temp file. Redirects are
     * followed MANUALLY: huggingface.co /resolve/ URLs answer with a 302 to
     * a CDN host, and relying on HttpURLConnection's automatic redirect
     * handling has proven unreliable across Android versions. Progress is
     * reported as the "downloading" stage.
     *
     * Throws [AiCancelledException] when the user cancels, and
     * [java.io.IOException] with a short machine-readable reason otherwise,
     * so the failure snackbar can say WHAT went wrong.
     */
    private fun downloadModel(url: String, dest: File, jobId: Int) {
        dest.parentFile?.mkdirs()
        val tmp = File(dest.parentFile, dest.name + ".part")
        var conn: HttpURLConnection? = null
        try {
            var current = url
            var hops = 0
            while (true) {
                val c = URL(current).openConnection() as HttpURLConnection
                conn = c
                c.connectTimeout = 20000
                c.readTimeout = 30000
                c.instanceFollowRedirects = false
                c.setRequestProperty("User-Agent", "MaxPlayer/1.0 (Android)")
                c.connect()
                val code = c.responseCode
                if (code in 300..399) {
                    val loc = c.getHeaderField("Location")
                    c.disconnect()
                    if (loc == null || ++hops > 6) {
                        throw java.io.IOException("redirect failed (HTTP $code)")
                    }
                    // Handles both absolute and relative Location headers.
                    current = URL(URL(current), loc).toString()
                    continue
                }
                if (code !in 200..299) {
                    c.disconnect()
                    throw java.io.IOException("HTTP $code")
                }
                break
            }
            val c = conn ?: throw java.io.IOException("no connection")
            val total = c.contentLengthLong
            c.inputStream.use { input ->
                FileOutputStream(tmp).use { out ->
                    val buf = ByteArray(256 * 1024)
                    var done = 0L
                    var read: Int
                    while (input.read(buf).also { read = it } != -1) {
                        if (aiCancelled) throw AiCancelledException()
                        out.write(buf, 0, read)
                        done += read
                        if (total > 0) {
                            aiProgress(jobId, "downloading", (done * 100 / total).toInt())
                        }
                    }
                    if (total > 0 && done != total) {
                        throw java.io.IOException("incomplete download")
                    }
                }
            }
            c.disconnect()
            if (!tmp.renameTo(dest)) {
                tmp.copyTo(dest, overwrite = true)
                tmp.delete()
            }
        } finally {
            if (tmp.exists()) tmp.delete()
        }
    }

    /**
     * Decodes the first audio track of [videoPath] to a 16 kHz mono 16-bit
     * PCM WAV using MediaExtractor + MediaCodec. Returns false if the file
     * has no (decodable) audio track.
     */
    private fun extractAudioToWav(videoPath: String, outFile: File, jobId: Int): Boolean {
        val extractor = MediaExtractor()
        var codec: MediaCodec? = null
        var raf: RandomAccessFile? = null
        return try {
            extractor.setDataSource(videoPath)
            var trackIndex = -1
            var sampleRate = 44100
            var channels = 1
            var durationUs = 0L
            for (i in 0 until extractor.trackCount) {
                val f = extractor.getTrackFormat(i)
                val mime = f.getString(MediaFormat.KEY_MIME) ?: continue
                if (mime.startsWith("audio/")) {
                    trackIndex = i
                    if (f.containsKey(MediaFormat.KEY_SAMPLE_RATE)) {
                        sampleRate = f.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                    }
                    if (f.containsKey(MediaFormat.KEY_CHANNEL_COUNT)) {
                        channels = f.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                    }
                    if (f.containsKey(MediaFormat.KEY_DURATION)) {
                        durationUs = f.getLong(MediaFormat.KEY_DURATION)
                    }
                    codec = MediaCodec.createDecoderByType(mime)
                    codec!!.configure(f, null, null, 0)
                    break
                }
            }
            if (trackIndex < 0 || codec == null) return false
            extractor.selectTrack(trackIndex)
            codec!!.start()

            // The decoder's OUTPUT format is authoritative: it can differ
            // from the container's declared format AND it reveals the PCM
            // encoding. Many AAC decoders output 32-bit FLOAT PCM - feeding
            // those bytes to the 16-bit resampler produced noise, and
            // whisper answered noise with "music" captions.
            var pcmEncoding = AudioFormat.ENCODING_PCM_16BIT
            try {
                val of = codec!!.outputFormat
                if (of.containsKey(MediaFormat.KEY_SAMPLE_RATE)) {
                    sampleRate = of.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                }
                if (of.containsKey(MediaFormat.KEY_CHANNEL_COUNT)) {
                    channels = of.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                }
                if (of.containsKey(MediaFormat.KEY_PCM_ENCODING)) {
                    pcmEncoding = of.getInteger(MediaFormat.KEY_PCM_ENCODING)
                }
            } catch (_: Exception) {
            }

            raf = RandomAccessFile(outFile, "rw")
            raf.setLength(0)
            writeWavHeader(raf, 16000, 0) // placeholder, patched at the end
            var dataBytes = 0L

            val info = MediaCodec.BufferInfo()
            var inputDone = false
            var outputDone = false
            while (!outputDone) {
                if (aiCancelled) return false
                if (!inputDone) {
                    val idx = codec!!.dequeueInputBuffer(10_000)
                    if (idx >= 0) {
                        val buf = codec!!.getInputBuffer(idx)!!
                        val n = extractor.readSampleData(buf, 0)
                        if (n < 0) {
                            codec!!.queueInputBuffer(
                                idx, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM
                            )
                            inputDone = true
                        } else {
                            codec!!.queueInputBuffer(idx, 0, n, extractor.sampleTime, 0)
                            extractor.advance()
                        }
                    }
                }
                val outIdx = codec!!.dequeueOutputBuffer(info, 10_000)
                if (outIdx >= 0) {
                    if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                        outputDone = true
                    }
                    if (info.size > 0) {
                        val outBuf = codec!!.getOutputBuffer(outIdx)!!
                        val pcm = ByteArray(info.size)
                        outBuf.get(pcm)
                        outBuf.clear()
                        val mono = pcmToMono16k(pcm, channels, sampleRate, pcmEncoding)
                        raf.write(mono)
                        dataBytes += mono.size
                        if (durationUs > 0 && info.presentationTimeUs > 0) {
                            aiProgress(
                                jobId,
                                "extracting",
                                (info.presentationTimeUs * 100 / durationUs)
                                    .toInt()
                                    .coerceIn(0, 99)
                            )
                        }
                    }
                    codec!!.releaseOutputBuffer(outIdx, false)
                }
            }
            writeWavHeader(raf, 16000, dataBytes) // real sizes
            true
        } catch (e: Exception) {
            false
        } finally {
            try {
                codec?.stop()
            } catch (_: Exception) {
            }
            try {
                codec?.release()
            } catch (_: Exception) {
            }
            try {
                extractor.release()
            } catch (_: Exception) {
            }
            try {
                raf?.close()
            } catch (_: Exception) {
            }
        }
    }

    /**
     * Normalizes decoder PCM (any common encoding) to interleaved signed
     * 16-bit little-endian samples. Without this, FLOAT/32-bit decoder
     * output was interpreted as 16-bit, which sounds like noise - and
     * whisper transcribes noise as "music".
     */
    private fun pcmToShorts(pcm: ByteArray, encoding: Int): ShortArray {
        return when (encoding) {
            AudioFormat.ENCODING_PCM_FLOAT -> {
                val fb = ByteBuffer.wrap(pcm).order(ByteOrder.LITTLE_ENDIAN)
                    .asFloatBuffer()
                ShortArray(fb.remaining()) { i ->
                    (fb.get(i).coerceIn(-1f, 1f) * 32767f).toInt().toShort()
                }
            }
            AudioFormat.ENCODING_PCM_32BIT -> {
                val n = pcm.size / 4
                ShortArray(n) { i ->
                    // Top two bytes of each 32-bit LE sample.
                    val hi = pcm[i * 4 + 3].toInt()
                    val mid = pcm[i * 4 + 2].toInt() and 0xFF
                    ((hi shl 8) or mid).toShort()
                }
            }
            AudioFormat.ENCODING_PCM_24BIT_PACKED -> {
                val n = pcm.size / 3
                ShortArray(n) { i ->
                    val hi = pcm[i * 3 + 2].toInt()
                    val mid = pcm[i * 3 + 1].toInt() and 0xFF
                    ((hi shl 8) or mid).toShort()
                }
            }
            else -> { // ENCODING_PCM_16BIT (and sane fallback)
                val n = pcm.size / 2
                ShortArray(n) { i ->
                    ((pcm[i * 2 + 1].toInt() shl 8) or
                        (pcm[i * 2].toInt() and 0xFF)).toShort()
                }
            }
        }
    }

    /**
     * Downmixes interleaved PCM to mono and resamples to 16 kHz using a
     * simple averaging window (good enough for speech).
     */
    private fun pcmToMono16k(
        pcm: ByteArray,
        channels: Int,
        srcRate: Int,
        encoding: Int
    ): ByteArray {
        if (channels < 1) return ByteArray(0)
        val samples = pcmToShorts(pcm, encoding)
        val frames = samples.size / channels
        if (frames == 0) return ByteArray(0)
        val step = srcRate.toDouble() / 16000.0
        val outCount = (frames / step).toInt()
        val out = ByteArray(outCount * 2)
        var pos = 0.0
        var o = 0
        while (o < outCount) {
            val startF = pos.toInt()
            val endF = min(frames, (pos + step).toInt() + 1)
            var sum = 0
            var cnt = 0
            var f = startF
            while (f < endF) {
                var mixed = 0
                for (ch in 0 until channels) {
                    mixed += samples[f * channels + ch]
                }
                sum += mixed / channels
                cnt++
                f++
            }
            val v = if (cnt > 0) sum / cnt else 0
            out[o * 2] = (v and 0xFF).toByte()
            out[o * 2 + 1] = ((v shr 8) and 0xFF).toByte()
            o++
            pos += step
        }
        return out
    }

    /** Writes a standard PCM WAV header (44 bytes) at the current position 0. */
    private fun writeWavHeader(raf: RandomAccessFile, rate: Int, dataLen: Long) {
        fun intLe(v: Long) = byteArrayOf(
            (v and 0xFF).toByte(),
            ((v shr 8) and 0xFF).toByte(),
            ((v shr 16) and 0xFF).toByte(),
            ((v shr 24) and 0xFF).toByte()
        )

        fun shortLe(v: Int) = byteArrayOf(
            (v and 0xFF).toByte(),
            ((v shr 8) and 0xFF).toByte()
        )

        raf.seek(0)
        raf.writeBytes("RIFF")
        raf.write(intLe(36 + dataLen))
        raf.writeBytes("WAVE")
        raf.writeBytes("fmt ")
        raf.write(intLe(16)) // PCM fmt chunk size
        raf.write(shortLe(1)) // PCM format
        raf.write(shortLe(1)) // mono
        raf.write(intLe(rate.toLong()))
        raf.write(intLe(rate.toLong() * 2)) // byte rate
        raf.write(shortLe(2)) // block align
        raf.write(shortLe(16)) // bit depth
        raf.writeBytes("data")
        raf.write(intLe(dataLen))
    }

    /** Reads the PCM data section of a 16 kHz mono 16-bit WAV we wrote
     * (i.e. everything after the 44-byte header). Null if unreadable. */
    private fun readWavPcm(wav: File): ByteArray? {
        return try {
            val bytes = wav.readBytes()
            if (bytes.size <= 44) null else bytes.copyOfRange(44, bytes.size)
        } catch (e: Exception) {
            null
        }
    }

    /**
     * Writes [pcm] samples in [fromSample, toSample) as a standalone 16 kHz
     * mono 16-bit WAV (header + raw little-endian data).
     */
    private fun writeSpanWav(out: File, pcm: ByteArray, fromSample: Int, toSample: Int) {
        val from = fromSample * 2
        val to = minOf(toSample * 2, pcm.size)
        val raf = RandomAccessFile(out, "rw")
        try {
            raf.setLength(0)
            writeWavHeader(raf, 16000, (to - from).toLong())
            raf.write(pcm, from, to - from)
        } finally {
            raf.close()
        }
    }

    /**
     * Speech-gate for the AI pipeline (v18): finds voiced spans in 16 kHz
     * mono 16-bit PCM (raw little-endian bytes, no header) and returns them
     * as [startSample, endSample) pairs - padded, gap-merged and chunked to
     * <=30 s so whisper's context window stays effective.
     *
     * Conservative by design: only true near-silence is dropped. The
     * threshold sits at ~2x the adaptive noise floor with a very low
     * absolute floor, so quiet speech is kept while digital/room silence is
     * skipped. Music is far above this floor and is therefore NEVER gated
     * out (speech over loud background music still reaches whisper).
     */
    private fun speechSpans(pcm: ByteArray): List<IntArray> {
        val frame = 400 // 25 ms at 16 kHz
        val totalSamples = pcm.size / 2
        val totalFrames = totalSamples / frame
        if (totalFrames < 8) return emptyList() // under 0.2 s of audio at all

        // RMS energy per 25 ms frame, straight from the raw bytes.
        val rms = DoubleArray(totalFrames)
        var i = 0
        while (i < totalFrames) {
            var sum = 0.0
            var j = 0
            val base = i * frame
            while (j < frame) {
                val idx = (base + j) * 2
                val s =
                    ((pcm[idx + 1].toInt() shl 8) or (pcm[idx].toInt() and 0xFF))
                        .toShort()
                        .toInt()
                sum += s * s
                j++
            }
            rms[i] = kotlin.math.sqrt(sum / frame)
            i++
        }

        // Adaptive threshold: ~2.2x the 20th-percentile frame energy (the
        // noise floor), but never below a conservative absolute floor.
        val sorted = rms.sorted()
        val noise = sorted[(totalFrames * 0.2).toInt().coerceIn(0, totalFrames - 1)]
        val threshold = maxOf(noise * 2.2, 260.0)

        // Voiced frames -> raw spans.
        val raw = mutableListOf<IntArray>()
        var start = -1
        i = 0
        while (i < totalFrames) {
            if (rms[i] >= threshold) {
                if (start < 0) start = i
            } else if (start >= 0) {
                raw.add(intArrayOf(start, i))
                start = -1
            }
            i++
        }
        if (start >= 0) raw.add(intArrayOf(start, totalFrames))
        if (raw.isEmpty()) return emptyList()

        // Merge spans separated by < 0.3 s (breaths / sentence gaps), then
        // pad 0.15 s on each side and drop remnants shorter than 0.4 s.
        val mergeGap = 12
        val pad = 6
        val merged = mutableListOf<IntArray>()
        var cur = raw[0]
        i = 1
        while (i < raw.size) {
            val n = raw[i]
            if (n[0] - cur[1] <= mergeGap) {
                cur[1] = n[1]
            } else {
                merged.add(cur)
                cur = n
            }
            i++
        }
        merged.add(cur)
        val padded = mutableListOf<IntArray>()
        for (m in merged) {
            val a = maxOf(0, m[0] - pad)
            val b = minOf(totalFrames, m[1] + pad)
            if (b - a >= 16) {
                padded.add(intArrayOf(a * frame, minOf(b * frame, totalSamples)))
            }
        }

        // Chunk anything longer than 30 s; split at the quietest frame near
        // the midpoint (best-effort word boundary), with a hard-split
        // fallback so the loop always makes progress.
        val maxFrames = 1200 // 30 s
        val chunked = mutableListOf<IntArray>()
        for (o in padded) {
            var s0 = o[0]
            val e0 = o[1]
            while (e0 - s0 > maxFrames * frame) {
                val midFrame = (s0 / frame + e0 / frame) / 2
                val win = 120 // +-3 s
                var best = midFrame
                var bestV = Double.MAX_VALUE
                var f = maxOf(s0 / frame + 16, midFrame - win)
                val fEnd = minOf(e0 / frame - 16, midFrame + win)
                while (f <= fEnd) {
                    if (f >= 0 && f < totalFrames && rms[f] < bestV) {
                        bestV = rms[f]
                        best = f
                    }
                    f++
                }
                val splitSample = best * frame
                if (splitSample <= s0 + frame * 16 || splitSample >= e0 - frame * 16) {
                    val hard = s0 + maxFrames * frame
                    chunked.add(intArrayOf(s0, hard))
                    s0 = hard
                } else {
                    chunked.add(intArrayOf(s0, splitSample))
                    s0 = splitSample
                }
            }
            chunked.add(intArrayOf(s0, e0))
        }
        return chunked
    }

    // -----------------------------------------------------------------------
    // v19: sensor-driven rotation + scrub thumbnail strip
    // -----------------------------------------------------------------------

    private var rotateListener: OrientationEventListener? = null
    private var rotateLocked = false

    private fun ensureRotateListener() {
        if (rotateListener != null) return
        rotateListener = object : OrientationEventListener(
            this, SensorManager.SENSOR_DELAY_NORMAL
        ) {
            override fun onOrientationChanged(angle: Int) {
                if (angle == ORIENTATION_UNKNOWN || rotateLocked) return
                // 45-degree quadrants, no upside-down portrait. Explicit
                // requestedOrientation applies even while the phone's
                // system auto-rotate is OFF - that is the whole point.
                val target = when {
                    angle in 45..134 ->
                        android.content.pm.ActivityInfo.SCREEN_ORIENTATION_REVERSE_LANDSCAPE
                    angle in 225..314 ->
                        android.content.pm.ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
                    else ->
                        android.content.pm.ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
                }
                if (requestedOrientation != target) requestedOrientation = target
            }
        }
    }

    /**
     * Builds (or reuses) a strip of 72 small JPEG frames for the scrub
     * preview bubble. Returns the strip directory path, or null for
     * streams / unreadable files. Runs on the executor; reusing a cached
     * strip is instant.
     */
    private fun thumbStripEnsureSync(path: String?): String? {
        if (path.isNullOrEmpty() || path.startsWith("http")) return null
        val src = File(path)
        if (!src.exists()) return null
        val count = 72
        val dir = File(cacheDir, "thumbstrip_" + md5(path))
        try {
            if (dir.isDirectory) {
                val have =
                    dir.listFiles()?.count { it.name.endsWith(".jpg") } ?: 0
                if (have >= count) return dir.absolutePath
            }
            val retriever = android.media.MediaMetadataRetriever()
            try {
                retriever.setDataSource(path)
                val durMs = retriever.extractMetadata(
                    android.media.MediaMetadataRetriever.METADATA_KEY_DURATION
                )?.toLongOrNull() ?: 0L
                if (durMs <= 0L) return null
                dir.mkdirs()
                for (i in 0 until count) {
                    val us = durMs * 1000L * i / (count - 1)
                    val frame = try {
                        retriever.getFrameAtTime(
                            us,
                            android.media.MediaMetadataRetriever.OPTION_CLOSEST_SYNC
                        )
                    } catch (e: Exception) {
                        null
                    }
                    if (frame != null) {
                        val thumb = scaleToWidth(frame, 192)
                        FileOutputStream(File(dir, "f_%03d.jpg".format(i)))
                            .use { out ->
                                thumb.compress(
                                    Bitmap.CompressFormat.JPEG, 72, out
                                )
                            }
                        if (thumb !== frame) thumb.recycle()
                        frame.recycle()
                    }
                }
            } finally {
                retriever.release()
            }
            return dir.absolutePath
        } catch (t: Throwable) {
            return null
        }
    }

    // ------------------------------------------------------------------
    // v26: device-credential check (Private-folder "Forgot PIN" gate)
    // ------------------------------------------------------------------

    /** Pending Dart reply while a device-unlock prompt is on screen. */
    private var pendingCredentialResult: MethodChannel.Result? = null

    /**
     * Shows the phone's own unlock UI (device PIN / pattern / password, or
     * fingerprint/face where enrolled) and answers true only when the owner
     * passes it. A device WITHOUT any screen lock answers true at once -
     * nothing exists to ask for there, and the unlocked phone itself is
     * the proof of possession. Uses only platform classes (works back to
     * the app's minSdk, no androidx.biometric dependency):
     * BiometricPrompt on API 28+, the classic KeyguardManager confirm
     * activity below that.
     */
    private fun confirmDeviceCredential(title: String, result: MethodChannel.Result) {
        if (pendingCredentialResult != null) {
            result.error("busy", "an unlock prompt is already showing", null)
            return
        }
        val km = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
        val secure =
            if (Build.VERSION.SDK_INT >= 23) km.isDeviceSecure else km.isKeyguardSecure
        if (!secure) {
            result.success(true)
            return
        }
        pendingCredentialResult = result
        if (Build.VERSION.SDK_INT >= 28) {
            showBiometricCredentialPrompt(title)
        } else {
            showKeyguardCredentialPrompt(title)
        }
    }

    /** Platform BiometricPrompt (API 28+) including the DEVICE credential. */
    private fun showBiometricCredentialPrompt(title: String) {
        val promptExecutor = java.util.concurrent.Executor { command ->
            mainHandler.post(command)
        }
        val builder = BiometricPrompt.Builder(this).setTitle(title)
        if (Build.VERSION.SDK_INT >= 30) {
            // v27 fix (real device report: instant "unlock failed" on a
            // Samsung tab): on API 30+ a NEGATIVE BUTTON may NOT be combined
            // with DEVICE_CREDENTIAL - the prompt throws before it can show.
            // The system credential screen has its own cancel, and errors
            // arrive in onAuthenticationError instead.
            builder.setAllowedAuthenticators(
                BiometricManager.Authenticators.BIOMETRIC_WEAK or
                    BiometricManager.Authenticators.DEVICE_CREDENTIAL
            )
        } else {
            @Suppress("DEPRECATION")
            builder.setDeviceCredentialAllowed(true)
            builder.setNegativeButton("Cancel", promptExecutor) { _, _ ->
                finishCredentialPrompt(false)
            }
        }
        try {
            builder.build().authenticate(
                CancellationSignal(),
                promptExecutor,
                object : BiometricPrompt.AuthenticationCallback() {
                    override fun onAuthenticationSucceeded(
                        authResult: BiometricPrompt.AuthenticationResult
                    ) {
                        finishCredentialPrompt(true)
                    }

                    override fun onAuthenticationError(
                        errorCode: Int,
                        errString: CharSequence
                    ) {
                        when (errorCode) {
                            // 11 = no biometrics enrolled, 12 = no hardware,
                            // 14 = no device credential: some builds report
                            // these even with DEVICE_CREDENTIAL allowed -
                            // retry via the classic confirm-credential screen.
                            11, 12, 14 -> showKeyguardCredentialPrompt(title)
                            // Everything else (cancel, lockout, hw busy...):
                            // answer "not unlocked" - Dart shows a snackbar.
                            else -> finishCredentialPrompt(false)
                        }
                    }
                    // onAuthenticationFailed intentionally NOT handled:
                    // the system prompt stays open for another attempt.
                },
            )
        } catch (e: Exception) {
            // Prompt could not even be constructed/shown -> classic fallback.
            showKeyguardCredentialPrompt(title)
        }
    }

    /** The classic "confirm your screen lock" activity (works on all APIs). */
    private fun showKeyguardCredentialPrompt(title: String) {
        val km = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
        @Suppress("DEPRECATION")
        val intent = km.createConfirmDeviceCredentialIntent(title, null)
        if (intent == null) {
            finishCredentialPrompt(true)
            return
        }
        try {
            startActivityForResult(intent, REQ_CONFIRM_CREDENTIAL)
        } catch (e: Exception) {
            finishCredentialPrompt(false)
        }
    }

    private fun finishCredentialPrompt(ok: Boolean) {
        val pending = pendingCredentialResult ?: return
        pendingCredentialResult = null
        mainHandler.post { pending.success(ok) }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQ_CONFIRM_CREDENTIAL) {
            finishCredentialPrompt(resultCode == RESULT_OK)
        }
    }

    override fun onDestroy() {
        if (pipReceiverRegistered) {
            try {
                unregisterReceiver(pipReceiver)
            } catch (_: Exception) {
            }
            pipReceiverRegistered = false
        }
        executor.shutdown()
        super.onDestroy()
    }
}
EOF_MARKER_22

mkdir -p "$(dirname 'assets/shaders/mx_enhance.glsl')"
cat > 'assets/shaders/mx_enhance.glsl' <<'EOF_MARKER_23'
// Max Player "Enhance" - a single-pass, GPU-friendly picture booster:
// gentle unsharp masking + contrast + vibrance. Runs in the SCALED hook
// (the frame is already RGB there, and mpv has tone-mapped HDR for us, so
// the pass is safe for SDR and HDR sources alike). Cheap enough for
// real-time playback on phone GPUs - the same role "AI enhance" sliders
// play in gallery players, without the power drain.
//
// Tuning: raise SHARPNESS for a crisper look, CONTRAST/SATURATION closer to
// 1.0 for a subtler one.

//!HOOK SCALED
//!BIND HOOKED
//!DESC Max Player Enhance (sharpen + contrast + vibrance)

#define SHARPNESS  0.35
#define CONTRAST   1.05
#define SATURATION 1.10

vec4 hook()
{
    vec4 c = HOOKED_tex(HOOKED_pos);
    vec3 blur = (HOOKED_texOff(vec2(-1.0,  0.0)).rgb +
                 HOOKED_texOff(vec2( 1.0,  0.0)).rgb +
                 HOOKED_texOff(vec2( 0.0, -1.0)).rgb +
                 HOOKED_texOff(vec2( 0.0,  1.0)).rgb) * 0.25;
    vec3 hi = c.rgb - blur;

    // Contrast-adaptive amount: strong edges get almost no extra boost, so
    // no white halos or ringing on outlines; flat textures get the most.
    float edge = max(abs(hi.r), max(abs(hi.g), abs(hi.b)));
    float k = SHARPNESS / (1.0 + edge * 24.0);
    vec3 col = max(c.rgb + hi * k, vec3(0.0));

    // Slight mid-point contrast...
    col = (col - vec3(0.5)) * CONTRAST + vec3(0.5);
    // ...and a soft vibrance (saturation around luma).
    float luma = dot(col, vec3(0.299, 0.587, 0.114));
    col = mix(vec3(luma), col, SATURATION);

    return vec4(max(col, vec3(0.0)), c.a);
}
EOF_MARKER_23

mkdir -p "$(dirname 'README.md')"
cat > 'README.md' <<'EOF_MARKER_24'
# Max Player

**The offline AI video player for Android.** Plays every local video with a
modern, gesture-driven player - and generates subtitles **on your device**
with AI, even for videos that have none. No account, no ads, no tracking.

Made by **Hyper Tech Labs** (Aryan Shah), Deoria, Uttar Pradesh, India.

## Highlights

- **Every format, hardware decoded** - mpv-based playback engine
  (media_kit) with subtitle & audio track switching, playback speed,
  A-B loop, shuffle/repeat and Picture-in-Picture.
- **AI subtitles, 100% offline** - whisper models run on the phone
  itself; generate subtitles for any video that has none.
- **Karaoke mode** - word-by-word highlighting of the current line.
- **Private folder** - PIN + on-device unlock (biometric / screen lock),
  hidden videos move out of the gallery and out of other players.
- **Advanced Cleaner with graphs** - scans every cache (thumbnails,
  preview strips, AI temp files, gallery cache), draws device-storage
  and reclaimable-space graphs, and frees everything with one
  **Clean cache** button. Largest videos & duplicate copies included.
- **Playlists** - build a queue from picked videos; the player then
  stays inside your selection. Append more with the + button.
- **Statistics** - watch-time graphs, day streaks, most-watched videos.
- **Cleaner library** - folder views, sort/group, list/grid, themes
  (7 accent colours), network streams (http/rtsp/rtmp), DLNA casting.
- **Open with / Share to** from any gallery or file manager.
- **Self-diagnosing** - if the app ever closes unexpectedly ("has stopped"),
  the next launch shows a copyable crash report - no PC or logcat needed.

## Building

```bash
flutter pub get
flutter analyze        # must print: No issues found!
flutter test           # pure-Dart unit tests (no device needed)
flutter build appbundle --release
```

Release builds run on [Codemagic](https://codemagic.io) (see
`codemagic.yaml`); signed Android App Bundle (AAB) for the Play Store.

## Privacy

Everything happens on the device: no servers, no analytics, no internet
permission requirement for playback. See [PRIVACY_POLICY.md](PRIVACY_POLICY.md).

## Source

<https://github.com/Aryanshahx/maxplayer>
EOF_MARKER_24

mkdir -p "$(dirname 'pubspec.yaml')"
cat > 'pubspec.yaml' <<'EOF_MARKER_25'
name: maxplayer
description: "Max Player - a local video library & player."
publish_to: 'none'
version: 1.0.0+35

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

  assets:
    # Real-time Enhance shader loaded into mpv at runtime (v32).
    - assets/shaders/
EOF_MARKER_25

mkdir -p "$(dirname 'test/widget_test.dart')"
cat > 'test/widget_test.dart' <<'EOF_MARKER_26'
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:maxplayer/app_info.dart';
import 'package:maxplayer/cast/cast_support.dart';
import 'package:maxplayer/models/saved_server.dart';
import 'package:maxplayer/models/video_track.dart';
import 'package:maxplayer/services/native_bridge.dart';
import 'package:maxplayer/state/media_player_state.dart';
import 'package:maxplayer/state/player_settings.dart';
import 'package:maxplayer/state/private_vault.dart';
import 'package:maxplayer/state/theme_state.dart';
import 'package:maxplayer/state/video_library_state.dart';
import 'package:maxplayer/utils/ai_subtitles.dart';
import 'package:maxplayer/utils/cleaner_stats.dart';
import 'package:maxplayer/utils/crash_log.dart';
import 'package:maxplayer/utils/formatters.dart';
import 'package:maxplayer/utils/privacy_policy.dart';
import 'package:maxplayer/utils/sha256.dart';
import 'package:maxplayer/utils/srt.dart';
import 'package:maxplayer/widgets/karaoke_subtitle.dart';
import 'package:maxplayer/widgets/about_sheet.dart';
import 'package:maxplayer/widgets/track_selection_sheet.dart';
import 'package:maxplayer/widgets/gesture_illustrations.dart';
import 'package:maxplayer/widgets/user_manual_sheet.dart';

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
      expect(
        formatDuration(const Duration(hours: 1, minutes: 2, seconds: 3)),
        '1:02:03',
      );
    });

    test('detects video extensions case-insensitively', () {
      expect(isVideoFile('clip.MKV'), isTrue);
      expect(isVideoFile('movie.mp4'), isTrue);
      expect(isVideoFile('notes.txt'), isFalse);
    });

    test('covers the extension set advertised in the manifest', () {
      // Keep in sync with the pathPatterns in AndroidManifest.xml.
      for (final ext in [
        'mp4',
        'webm',
        'mkv',
        'avi',
        'mov',
        'wmv',
        'flv',
        'm4v',
        '3gp',
        '3gpp',
        'ogv',
        'ts',
        'mts',
        'm2ts',
        'vob',
        'mpg',
        'mpeg',
        'rmvb',
        'divx',
        'f4v',
      ]) {
        expect(
          isVideoFile('movie.$ext'),
          isTrue,
          reason: '.$ext must scan into the library',
        );
        expect(isVideoFile('movie.${ext.toUpperCase()}'), isTrue);
      }
    });

    test('timeAgo buckets', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      expect(timeAgo(now), 'Just now');
      expect(
        timeAgo(now - const Duration(minutes: 5).inMilliseconds),
        '5m ago',
      );
      expect(timeAgo(now - const Duration(hours: 3).inMilliseconds), '3h ago');
      expect(timeAgo(now - const Duration(days: 2).inMilliseconds), '2d ago');
      expect(timeAgo(0), '');
    });
  });

  group('quality label', () {
    String? q(int? w, int? h) => VideoTrack(
      id: 'x',
      title: 'x',
      path: '/x.mp4',
      width: w,
      height: h,
    ).qualityLabel;

    test('maps the SHORTER side to a resolution badge', () {
      expect(q(1920, 1080), '1080p');
      expect(q(1080, 1920), '1080p'); // portrait video
      expect(q(3840, 2160), '4K');
      expect(q(2560, 1440), '2K');
      expect(q(1280, 720), '720p');
      expect(q(640, 480), '480p');
      expect(q(320, 240), 'SD');
    });

    test('null when dimensions unknown', () {
      expect(q(null, null), isNull);
      expect(q(0, 0), isNull);
    });
  });

  group('equalizer filter builder', () {
    test('all-zero gains produce an empty filter (clears af)', () {
      expect(MediaPlayerState.buildEqualizerFilter([0, 0, 0, 0, 0]), '');
    });

    test('skips flat bands and formats the rest as lavfi', () {
      final f = MediaPlayerState.buildEqualizerFilter([6, 0, -2, 0, 3.5]);
      expect(
        f,
        'lavfi=[equalizer=f=60:t=q:w=1.0:g=6.0,equalizer=f=910:t=q:w=1.0:g=-2.0,equalizer=f=14000:t=q:w=1.0:g=3.5]',
      );
    });
  });

  group('watch stats', () {
    test('stats key is a sortable YYYYMMDD bucket', () {
      expect(
        MediaPlayerState.statsKeyFor(DateTime(2026, 8, 11)),
        'stats.20260811',
      );
      expect(
        MediaPlayerState.statsKeyFor(DateTime(2026, 1, 5)),
        'stats.20260105',
      );
    });

    test('formatWatchTime', () {
      expect(formatWatchTime(30), '30s');
      expect(formatWatchTime(45 * 60), '45m');
      expect(formatWatchTime(2 * 3600 + 15 * 60), '2h 15m');
    });
  });

  group('library sorting', () {
    final videos = [
      _track(
        'banana',
        size: 300,
        modified: 100,
        duration: const Duration(minutes: 3),
      ),
      _track(
        'apple',
        size: 100,
        modified: 300,
        duration: const Duration(minutes: 1),
      ),
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

  group('SRT builder (AI subtitles)', () {
    test('formats numbered cues with HH:MM:SS,mmm times', () {
      final srt = buildSrt(const [
        SrtCue(1200, 3400, 'Hello world'),
        SrtCue(3605000, 3607000, 'second line'),
      ]);
      expect(
        srt,
        '1\n00:00:01,200 --> 00:00:03,400\nHello world\n\n'
        '2\n01:00:05,000 --> 01:00:07,000\nsecond line\n\n',
      );
    });

    test('drops empty cues and bumps zero-length ends', () {
      final srt = buildSrt(const [
        SrtCue(500, 500, 'same'),
        SrtCue(100, 900, '   '),
      ]);
      expect(srt, '1\n00:00:00,500 --> 00:00:01,500\nsame\n\n');
    });

    test('sorts cues by start time', () {
      final srt = buildSrt(const [
        SrtCue(5000, 6000, 'later'),
        SrtCue(1000, 2000, 'first'),
      ]);
      expect(srt.startsWith('1\n00:00:01,000'), isTrue);
    });
  });

  group('player settings (v12 defaults)', () {
    test('new v12 toggles all start ON and persist round-trip', () {
      const s = PlayerSettings();
      expect(s.horizontalSeek, isTrue);
      expect(s.castButton, isTrue);
      expect(s.screenshotButton, isTrue);
      expect(s.lockButton, isTrue);
      // copyWith actually carries them
      final t = s.copyWith(horizontalSeek: false, castButton: false);
      expect(t.horizontalSeek, isFalse);
      expect(t.castButton, isFalse);
      expect(t.screenshotButton, isTrue);
      expect(t.lockButton, isTrue);
    });

    test('load from empty store yields all v12 defaults', () async {
      final s = await PlayerSettings.load();
      expect(s.horizontalSeek, isTrue);
      expect(s.castButton, isTrue);
      expect(s.screenshotButton, isTrue);
      expect(s.lockButton, isTrue);
    });
  });

  group('DLNA cast helpers', () {
    test('SSDP header lookup is case-insensitive and trims', () {
      const dg =
          'HTTP/1.1 200 OK\r\n'
          'CACHE-CONTROL: max-age=1800\r\n'
          'LOCATION: http://192.168.1.10:8080/dd.xml\r\n'
          'location: http://other/x.xml\r\n' // duplicate -> first wins
          'ST: urn:schemas-upnp-org:device:MediaRenderer:1\r\n\r\n';
      expect(ssdpHeader(dg, 'location'), 'http://192.168.1.10:8080/dd.xml');
      expect(
        ssdpHeader(dg, 'ST'),
        'urn:schemas-upnp-org:device:MediaRenderer:1',
      );
      expect(ssdpHeader(dg, 'server'), isNull);
    });

    test('M-SEARCH request is well formed', () {
      final m = buildMSearchRequest('ssdp:all');
      expect(m.startsWith('M-SEARCH * HTTP/1.1\r\n'), isTrue);
      expect(m, contains('ST: ssdp:all\r\n'));
      expect(m.endsWith('\r\n\r\n'), isTrue);
    });

    test('device description: finds AVTransport and resolves relative URL', () {
      const xml = '''
<root xmlns="urn:schemas-upnp-org:device-1-0">
  <device>
    <friendlyName>Living Room TV</friendlyName>
    <serviceList>
      <service>
        <serviceType>urn:schemas-upnp-org:service:RenderingControl:1</serviceType>
        <controlURL>/rc/control</controlURL>
      </service>
      <service>
        <serviceType>urn:schemas-upnp-org:service:AVTransport:1</serviceType>
        <controlURL>/avt/control</controlURL>
      </service>
    </serviceList>
  </device>
</root>''';
      final d = parseDeviceDescription(xml, 'http://192.168.1.10:9000/dd.xml');
      expect(d, isNotNull);
      expect(d!.name, 'Living Room TV');
      expect(d.controlUrl, 'http://192.168.1.10:9000/avt/control');
    });

    test('device description: rejects devices without AVTransport', () {
      const xml =
          '<root><device><friendlyName>Router</friendlyName>'
          '<serviceList><service>'
          '<serviceType>urn:schemas-upnp-org:service:WANIPConnection:1</serviceType>'
          '<controlURL>/wan/control</controlURL>'
          '</service></serviceList></device></root>';
      expect(parseDeviceDescription(xml, 'http://10.0.0.1/d.xml'), isNull);
    });

    test('absolute controlURL kept as-is; xml entities unescaped in name', () {
      const xml =
          '<root><device><friendlyName>A &amp; B TV</friendlyName>'
          '<serviceList><service>'
          '<serviceType>urn:schemas-upnp-org:service:AVTransport:1</serviceType>'
          '<controlURL>http://192.168.1.5:81/avt</controlURL>'
          '</service></serviceList></device></root>';
      final d = parseDeviceDescription(xml, 'http://192.168.1.5:9999/dd');
      expect(d!.name, 'A & B TV');
      expect(d.controlUrl, 'http://192.168.1.5:81/avt');
    });

    test('SOAP envelope carries InstanceID first and escapes args', () {
      final env = buildSoapEnvelope('Play', const [MapEntry('Speed', '1')]);
      expect(
        env,
        contains(
          '<u:Play xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">',
        ),
      );
      expect(
        env.indexOf('<InstanceID>0</InstanceID>'),
        lessThan(env.indexOf('<Speed>1</Speed>')),
      );
      final esc = buildSoapEnvelope('X', const [MapEntry('V', 'a & <b> "q"')]);
      expect(esc, contains('a &amp; &lt;b&gt; &quot;q&quot;'));
    });

    test('soapTag digs values out of responses', () {
      const body =
          '<s:Envelope><s:Body><u:GetPositionInfoResponse>'
          '<Track>1</Track><RelTime>0:06:12</RelTime>'
          '</u:GetPositionInfoResponse></s:Body></s:Envelope>';
      expect(soapTag(body, 'RelTime'), '0:06:12');
      expect(soapTag(body, 'Track'), '1');
      expect(soapTag(body, 'AbsTime'), isNull);
    });

    test('DIDL metadata carries title, res and optional subtitle', () {
      final didl = buildDidlMetadata(
        title: 'My Video <1080p>',
        videoUrl: 'http://p:1/video.mp4',
        mime: 'video/mp4',
        subsUrl: 'http://p:1/subs.srt',
      );
      expect(didl, contains('<dc:title>My Video &lt;1080p&gt;</dc:title>'));
      expect(didl, contains('protocolInfo="http-get:*:video/mp4:*"'));
      expect(didl, contains('<sec:CaptionInfoEx'));
      final noSubs = buildDidlMetadata(
        title: 't',
        videoUrl: 'http://p/v.mp4',
        mime: 'video/mp4',
      );
      expect(noSubs.contains('CaptionInfoEx'), isFalse);
    });

    test('mime map covers the containers we scan for', () {
      expect(mimeForExtension('/x/a.mkv'), 'video/x-matroska');
      expect(mimeForExtension('/x/a.MP4'), 'video/mp4');
      expect(mimeForExtension('/x/a.webm'), 'video/webm');
      expect(mimeForExtension('/x/a.avi'), 'video/x-msvideo');
      expect(mimeForExtension('/x/a.mov'), 'video/quicktime');
      expect(mimeForExtension('/x/a.wmv'), 'video/x-ms-wmv');
      expect(mimeForExtension('/x/a.ts'), 'video/mp2t');
      expect(mimeForExtension('http://s/v.mkv?token=1'), 'video/x-matroska');
      expect(mimeForExtension('/x/a.unknown'), 'video/mp4'); // safe default
    });

    test('DLNA rel-time format/parse round-trips', () {
      expect(
        formatRelTime(const Duration(hours: 1, minutes: 2, seconds: 3)),
        '1:02:03',
      );
      expect(formatRelTime(Duration.zero), '0:00:00');
      expect(parseRelTime('0:06:12'), const Duration(minutes: 6, seconds: 12));
      expect(
        parseRelTime('1:02:03.500'),
        const Duration(hours: 1, minutes: 2, seconds: 3, milliseconds: 500),
      );
      expect(parseRelTime('NOT_IMPLEMENTED'), isNull);
      expect(parseRelTime(null), isNull);
      expect(parseRelTime('garbage'), isNull);
    });
  });

  group('app version', () {
    test('kAppVersion matches the pubspec version name', () {
      final pub = File('pubspec.yaml').readAsStringSync();
      final m = RegExp(
        r'^version:\s*([0-9][0-9.]*)\+',
        multiLine: true,
      ).firstMatch(pub);
      expect(
        m,
        isNotNull,
        reason: 'pubspec.yaml must declare version: x.y.z+N',
      );
      expect(
        m!.group(1),
        kAppVersion,
        reason: 'Keep kAppVersion in lib/app_info.dart in sync',
      );
    });
  });

  group('AI subtitle options & caption filter (v18)', () {
    // v25: only accurate models (user call); speed comes from all-core
    // threading, and any stale "tiny" id from v22-v24 maps to base.
    test('only accurate models remain; stale tiny ids map to base', () {
      expect(AiSubtitleRunner.modelChoices.containsKey('tiny'), isFalse);
      expect(
        AiSubtitleRunner.modelChoices.keys,
        containsAll(<String>['base', 'small']),
      );
      expect(AiSubtitleRunner.normalizeModelId(null), 'base');
      expect(
        AiSubtitleRunner.normalizeModelId('tiny'),
        'base',
        reason: 'a stale v22-24 "tiny" pref must migrate to base',
      );
      expect(AiSubtitleRunner.normalizeModelId('small'), 'small');
      expect(AiSubtitleRunner.normalizeModelId('nonsense'), 'base');
      expect(AiSubtitleRunner.modelSizeLabel('base'), '~142 MB');
      expect(AiSubtitleRunner.modelSizeLabel('small'), '~466 MB');
    });

    test('music-only decoration captions are dropped, speech is kept', () {
      for (final t in [
        '♪',
        '♪ ♪',
        '♪♫♪',
        '[Music]',
        '(MUSIC)',
        'music',
        '( music playing )',
        '♪ Music ♪',
        '[Applause]',
        '(laughter)',
      ]) {
        expect(isMusicOnlyCaption(t), isTrue, reason: '"$t" must be dropped');
      }
      for (final t in [
        'Hello world',
        'I love music',
        'music is life',
        'the background music in this scene',
      ]) {
        expect(isMusicOnlyCaption(t), isFalse, reason: '"$t" must be kept');
      }
    });
  });

  group('privacy policy', () {
    test('in-app text carries the same anchors as PRIVACY_POLICY.md', () {
      final md = File('PRIVACY_POLICY.md').readAsStringSync();
      for (final anchor in [
        '13 August 2026',
        'Hyper Tech Labs',
        'github.com/Aryanshahx/maxplayer',
      ]) {
        expect(md, contains(anchor));
        expect(
          kPrivacyPolicyText,
          contains(anchor),
          reason:
              'keep lib/utils/privacy_policy.dart in sync with '
              'PRIVACY_POLICY.md',
        );
      }
    });
  });

  group('manual & about sheets', () {
    /// The sheets are lazy ListViews - give the test a huge viewport so
    /// every section builds, not just the first screenful.
    void useTallViewport(WidgetTester tester) {
      tester.view.physicalSize = const Size(1200, 6000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    testWidgets('every gesture illustration paints without errors', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  for (final kind in GestureKind.values)
                    SizedBox(
                      width: 320,
                      child: GestureIllustration(kind: kind),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      expect(
        find.byType(GestureIllustration),
        findsNWidgets(GestureKind.values.length),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('user manual renders all sections', (tester) async {
      useTallViewport(tester);
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: UserManualSheet())),
      );
      expect(find.text('User manual'), findsOneWidget);
      expect(find.text('GESTURE CONTROLS'), findsOneWidget);
      expect(
        find.text('Max Player v$kAppVersion  ·  Hyper Tech Labs'),
        findsOneWidget,
      );
      expect(
        find.byType(GestureIllustration),
        findsNWidgets(GestureKind.values.length),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('about sheet renders brand text and version', (tester) async {
      useTallViewport(tester);
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: AboutSheet())),
      );
      expect(find.text('Max Player'), findsOneWidget);
      expect(find.text('by Hyper Tech Labs'), findsOneWidget);
      expect(find.text('Version $kAppVersion'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('about sheet bundles the privacy policy offline', (
      tester,
    ) async {
      useTallViewport(tester);
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: AboutSheet())),
      );
      await tester.tap(find.text('Privacy policy'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('does not collect, store, transmit'),
        findsOneWidget,
      );
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('does not collect, store, transmit'),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  });

  // -------------------------------------------------------------------------
  // v21: SRT parsing (karaoke / skip-intro / transcript groundwork)
  // -------------------------------------------------------------------------
  group('v21 srt parsing', () {
    test('parseSrt round-trips buildSrt output', () {
      final cues = [
        const SrtCue(0, 1500, 'Hello world'),
        const SrtCue(61000, 63500, 'Second caption line'),
      ];
      final parsed = parseSrt(buildSrt(cues));
      expect(parsed.length, 2);
      expect(parsed[0].startMs, 0);
      expect(parsed[0].endMs, 1500);
      expect(parsed[0].text, 'Hello world');
      expect(parsed[1].startMs, 61000);
      expect(parsed[1].text, 'Second caption line');
    });

    test('parseSrt tolerates missing indices and dot-millis', () {
      final parsed = parseSrt(
        '1\n00:00:01.000 --> 00:00:02.500\none two\n\n00:00:03,000 --> 00:00:04,000\nthree\n',
      );
      expect(parsed.length, 2);
      expect(parsed[0].startMs, 1000);
      expect(parsed[0].endMs, 2500);
      expect(parsed[0].text, 'one two');
      expect(parsed[1].startMs, 3000);
    });

    test('computeSkipIntro finds late dialogue start', () {
      expect(
        computeSkipIntro([
          const SrtCue(0, 3000, '♪ opening theme ♪'),
          const SrtCue(92000, 94000, 'Are you ready?'),
        ]),
        const Duration(milliseconds: 91000),
      );
      // Speech right away -> nothing to skip.
      expect(computeSkipIntro([const SrtCue(3000, 5000, 'Hello')]), isNull);
      // First speech after 10 minutes -> not an intro.
      expect(
        computeSkipIntro([const SrtCue(700000, 701000, 'Too late')]),
        isNull,
      );
      expect(computeSkipIntro(const []), isNull);
    });
  });

  // -------------------------------------------------------------------------
  // v21: SHA-256 for the Private-folder PIN (dependency-free implementation)
  // -------------------------------------------------------------------------
  group('v21 sha256', () {
    test('standard test vectors', () {
      expect(
        sha256Hex(''),
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      );
      expect(
        sha256Hex('abc'),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
      expect(
        sha256Hex('1234'),
        '03ac674216f3e15c761ee1a5e255f067953623c8b388b4459e13f978d7c846f4',
      );
    });
  });

  // -------------------------------------------------------------------------
  // v21: karaoke timing helpers
  // -------------------------------------------------------------------------
  group('v21 karaoke timing', () {
    test('karaokeWordIndex walks words proportionally to characters', () {
      const cue = SrtCue(0, 2000, 'aa b');
      expect(karaokeWordIndex(cue, 0), 0);
      expect(karaokeWordIndex(cue, 500), 0);
      expect(karaokeWordIndex(cue, 1900), 1);
      expect(karaokeWordIndex(cue, 2000), 1);
    });

    test('karaokeActiveCue skips music-only cues and quiet gaps', () {
      final cues = [
        const SrtCue(0, 1000, '♪ music ♪'),
        const SrtCue(2000, 3000, 'Hello there'),
      ];
      expect(karaokeActiveCue(cues, 500), isNull);
      expect(karaokeActiveCue(cues, 2500)?.text, 'Hello there');
      expect(karaokeActiveCue(cues, 3400)?.text, 'Hello there'); // grace
      expect(karaokeActiveCue(cues, 5000), isNull);
    });

    // v22: live mpv line -> AI sidecar -> same-name .srt fallback order.
    test('karaokeCueAt picks live, then AI cues, then sidecar cues', () {
      const live = SrtCue(9000, 11000, 'live line');
      final ai = [const SrtCue(9000, 11000, 'ai line')];
      final side = [const SrtCue(9000, 11000, 'sidecar line')];
      expect(karaokeCueAt(live, ai, side, 10000)?.text, 'live line');
      expect(karaokeCueAt(null, ai, side, 10000)?.text, 'ai line');
      expect(karaokeCueAt(null, null, side, 10000)?.text, 'sidecar line');
      expect(karaokeCueAt(null, null, null, 10000), isNull);
      // Stale live cue (past its 600 ms grace) falls through to files.
      final ai2 = [const SrtCue(45000, 55000, 'ai line later')];
      expect(karaokeCueAt(live, ai2, side, 50000)?.text, 'ai line later');
      // Everything expired -> nothing shown.
      expect(karaokeCueAt(live, ai, side, 50000), isNull);
    });
  });

  // -------------------------------------------------------------------------
  // v22: same-name sidecar picking (karaoke / skip-intro on the video's
  // own subtitle file)
  // -------------------------------------------------------------------------
  group('v22 sidecar .srt picking', () {
    test('exact same-name match wins over language variants', () {
      final names = ['movie.eng.srt', 'Movie.SRT', 'movie.maxai.srt', 'x.srt'];
      expect(sidecarSrtCandidates(names, '/sdcard/Movies/Movie.mp4'), [
        'Movie.SRT',
        'movie.eng.srt',
      ]);
    });
    test('AI sidecar is never picked as a plain sidecar', () {
      final names = ['movie.maxai.srt'];
      expect(sidecarSrtCandidates(names, '/a/movie.mkv'), isEmpty);
    });
    test('language variants are sorted and kept in original case', () {
      final names = ['movie.hi.srt', 'movie.en.srt'];
      expect(sidecarSrtCandidates(names, 'movie.mkv'), [
        'movie.en.srt',
        'movie.hi.srt',
      ]);
    });
    test('unrelated files and non-srt are ignored', () {
      final names = ['movie.srt.txt', 'other.srt', 'movie.txt', '.srt'];
      expect(sidecarSrtCandidates(names, '/m/movie.mp4'), isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  // v22: sleep-timer countdown + white-accent contrast
  // -------------------------------------------------------------------------
  group('v22 sleep countdown + accent contrast', () {
    test('formatCountdown renders m:ss and h:mm:ss', () {
      expect(formatCountdown(0), '0:00');
      expect(formatCountdown(9), '0:09');
      expect(formatCountdown(61), '1:01');
      expect(formatCountdown(599), '9:59');
      expect(formatCountdown(3600), '1:00:00');
      expect(formatCountdown(-5), '0:00'); // clamps negatives
    });

    test('contrastColorFor: dark ink on light accents, white on dark', () {
      const darkInk = Color(0xFF16161f);
      expect(contrastColorFor(const Color(0xFFFFFFFF)), darkInk);
      expect(contrastColorFor(const Color(0xFF22D3EE)), darkInk); // cyan
      expect(contrastColorFor(const Color(0xFFA855F7)), Colors.white);
      expect(contrastColorFor(const Color(0xFF60A5FA)), Colors.white);
    });

    test('white is a selectable accent swatch', () {
      expect(
        ThemeState.swatches.any((c) => c.toARGB32() == 0xFFFFFFFF),
        isTrue,
      );
    });
  });

  // -------------------------------------------------------------------------
  // v26: karaoke fix (media_kit's own subtitle layer is off), karaoke switch
  // lives ONLY in the tracks sheet, vault change counter + device-unlock gate
  // for the forgotten-PIN flow.
  // -------------------------------------------------------------------------
  group('v26 polish', () {
    test('vault revision counter exists and starts clean in tests', () {
      // hide()/unhide() do real file IO (not exercised here), so the
      // in-process counter must still be zero.
      expect(PrivateVault.revision, 0);
    });

    test('vault path helpers unchanged', () {
      expect(
        PrivateVault.isPrivatePath(
          '/storage/emulated/0/Android/data/com.hypertechlabs.maxplayer/'
          'files/Private/movie.mp4',
        ),
        isTrue,
      );
      expect(
        PrivateVault.isPrivatePath('/storage/emulated/0/Movies/movie.mp4'),
        isFalse,
      );
    });

    test('karaoke setting survives copyWith (toggle kept, moved)', () {
      const s = PlayerSettings();
      expect(s.karaokeSubs, isFalse);
      expect(s.copyWith(karaokeSubs: true).karaokeSubs, isTrue);
    });
  });

  // -------------------------------------------------------------------------
  // v27: advanced video info + statistics helpers
  // -------------------------------------------------------------------------
  group('v27 advanced info + stats', () {
    test('formatAspectRatio simplifies common ratios', () {
      expect(formatAspectRatio(1920, 1080), '16:9');
      expect(formatAspectRatio(1280, 720), '16:9');
      expect(formatAspectRatio(1440, 1080), '4:3');
      expect(formatAspectRatio(3840, 2160), '16:9');
    });

    test('formatAspectRatio falls back for odd sizes and guards zero', () {
      expect(formatAspectRatio(1000, 423), '2.36:1');
      expect(formatAspectRatio(0, 1080), '');
      expect(formatAspectRatio(1920, 0), '');
    });

    test('statsKeyFor day buckets stay stable', () {
      expect(
        MediaPlayerState.statsKeyFor(DateTime(2026, 8, 14)),
        'stats.20260814',
      );
      expect(
        MediaPlayerState.statsKeyFor(DateTime(2026, 1, 5)),
        'stats.20260105',
      );
    });
  });

  // -------------------------------------------------------------------------
  // v28: home quick tiles - the Folders tile filters the library
  // -------------------------------------------------------------------------
  group('v28 folders tile', () {
    VideoTrack t(String path) =>
        VideoTrack(id: path, title: path.split('/').last, path: path);

    List<VideoTrack> threeVideos() => [
      t('/storage/emulated/0/Movies/a.mp4'),
      t('/storage/emulated/0/Movies/b.mp4'),
      t('/storage/emulated/0/DCIM/c.mp4'),
    ];

    test('folderFilter narrows the visible list and clears again', () {
      final lib = VideoLibraryState();
      lib.debugSetVideos(threeVideos());
      expect(lib.videos.length, 3);
      lib.setFolderFilter('Movies');
      expect(lib.videos.length, 2);
      expect(lib.videos.map((v) => v.folderName).toSet(), {'Movies'});
      lib.setFolderFilter(null);
      expect(lib.videos.length, 3);
    });

    test('folderCounts lists every folder, name-sorted', () {
      final lib = VideoLibraryState();
      lib.debugSetVideos(threeVideos());
      expect(lib.folderCounts, {'DCIM': 1, 'Movies': 2});
      expect(lib.folderCounts.keys.toList(), ['DCIM', 'Movies']);
    });

    test('folder filter composes with search', () {
      final lib = VideoLibraryState();
      lib.debugSetVideos(threeVideos());
      lib.setFolderFilter('Movies');
      lib.setSearchQuery('b.mp4');
      expect(lib.videos.length, 1);
      expect(lib.videos.single.path, endsWith('/Movies/b.mp4'));
    });
  });

  // -------------------------------------------------------------------------
  // v29: device cleaner data + playlist/picker backing + white default theme
  // -------------------------------------------------------------------------
  group('v29 cleaner data + theme default', () {
    VideoTrack sized(String path, int size, int secs) => VideoTrack(
      id: path,
      title: path.split('/').last,
      path: path,
      sizeBytes: size,
      duration: Duration(seconds: secs),
    );

    test('largestVideos sorts biggest first and limits', () {
      final lib = VideoLibraryState();
      lib.debugSetVideos([
        sized('/s/Movies/small.mp4', 100, 60),
        sized('/s/Movies/big.mp4', 9000, 900),
        sized('/s/DCIM/mid.mp4', 500, 120),
      ]);
      final top = lib.largestVideos(n: 2);
      expect(top.length, 2);
      expect(top.first.path, endsWith('big.mp4'));
      expect(top.last.path, endsWith('mid.mp4'));
    });

    test('duplicateGroups finds same size+duration copies only', () {
      final lib = VideoLibraryState();
      lib.debugSetVideos([
        sized('/s/Movies/a.mp4', 700, 300),
        sized('/s/DCIM/a-copy.mp4', 700, 300), // same size+length = dupe
        sized('/s/Movies/a-lookalike.mp4', 700, 301), // different length
        sized('/s/Movies/unique.mp4', 42, 10),
      ]);
      final groups = lib.duplicateGroups;
      expect(groups.length, 1);
      expect(groups.single.length, 2);
      expect(
        groups.single.map((v) => v.path),
        containsAll(['/s/Movies/a.mp4', '/s/DCIM/a-copy.mp4']),
      );
    });

    test('removeVideo drops an entry in place', () {
      final lib = VideoLibraryState();
      lib.debugSetVideos([
        sized('/s/Movies/a.mp4', 700, 300),
        sized('/s/Movies/b.mp4', 500, 300),
      ]);
      lib.removeVideo('/s/Movies/a.mp4');
      expect(lib.videos.length, 1);
      expect(lib.videos.single.path, endsWith('b.mp4'));
    });

    test('white is the default theme colour (existing picks kept)', () {
      expect(ThemeState().accent.toARGB32(), 0xFFFFFFFF);
      expect(ThemeState.defaultAccent.toARGB32(), 0xFFFFFFFF);
      // purple and the others remain selectable
      expect(ThemeState.swatches.length, 7);
    });
  });

  group('v30 playlist add-to-queue', () {
    VideoTrack vt(String path) =>
        VideoTrack(id: path, title: path.split('/').last, path: path);

    test('mergeQueueVideos appends new, skips duplicates, keeps order', () {
      final merged = mergeQueueVideos(
        [vt('/s/a.mp4'), vt('/s/b.mp4')],
        [vt('/s/b.mp4'), vt('/s/c.mp4'), vt('/s/a.mp4')],
      );
      expect(merged.map((v) => v.path).toList(), [
        '/s/a.mp4',
        '/s/b.mp4',
        '/s/c.mp4',
      ]);
    });

    test('mergeQueueVideos into an empty queue returns the picks', () {
      final merged = mergeQueueVideos(const [], [vt('/s/x.mp4')]);
      expect(merged.single.path, '/s/x.mp4');
    });

    test('mergeQueueVideos does not mutate the original queue', () {
      final queue = [vt('/s/a.mp4')];
      mergeQueueVideos(queue, [vt('/s/b.mp4')]);
      expect(queue.length, 1);
    });
  });

  group('v31 cleaner stats', () {
    test('segments drop empty kinds and keep a stable order', () {
      final segs = cleanerSegments(
        thumbs: 100,
        strips: 0,
        temp: 50,
        models: 0,
        deviceCache: 25,
      );
      expect(segs.map((s) => s.label).toList(), [
        'App thumbnails',
        'Temporary AI files',
        'Gallery cache',
      ]);
    });

    test('segment colours are stable per kind', () {
      final segs = cleanerSegments(
        thumbs: 1,
        strips: 2,
        temp: 3,
        models: 4,
        deviceCache: 5,
      );
      expect(segs[0].colorValue, cleanerKindColors['thumbs']);
      expect(segs[3].colorValue, cleanerKindColors['models']);
      // AI models keep their colour even when earlier kinds are empty.
      final lonely = cleanerSegments(
        thumbs: 0,
        strips: 0,
        temp: 0,
        models: 9,
        deviceCache: 0,
      );
      expect(lonely.single.colorValue, cleanerKindColors['models']);
    });

    test('clean cache total excludes models, grand total includes them', () {
      final cache = cleanerCacheTotal(
        thumbs: 10,
        strips: 10,
        temp: 10,
        deviceCache: 10,
      );
      final grand = cleanerGrandTotal(
        thumbs: 10,
        strips: 10,
        temp: 10,
        models: 7,
        deviceCache: 10,
      );
      expect(cache, 40);
      expect(grand, 47);
    });

    test('fractionOf guards an empty graph', () {
      const seg = CleanerSegment('x', 5, 0xFF000000);
      expect(seg.fractionOf(0), 0);
      expect(seg.fractionOf(20), 0.25);
    });

    test('DeviceStorage used + usedFraction are sane', () {
      const s = DeviceStorage(total: 100, free: 25);
      expect(s.used, 75);
      expect(s.usedFraction, 0.75);
    });
  });

  group('v32 picture settings, HDR labels and saved servers', () {
    test('hdrLabelFor maps known formats, hides SDR/unknown', () {
      expect(hdrLabelFor('hdr10'), 'HDR10');
      expect(hdrLabelFor('hdr10+'), 'HDR10+');
      expect(hdrLabelFor('hlg'), 'HLG');
      expect(hdrLabelFor('dolby-vision'), 'Dolby Vision (HDR mode)');
      expect(hdrLabelFor('sdr'), isNull);
      expect(hdrLabelFor(null), isNull);
      expect(hdrLabelFor('nonsense'), isNull);
    });

    test('picture settings default to off/auto and survive copyWith', () {
      const s = PlayerSettings();
      expect(s.enhanceVideo, isFalse);
      expect(s.toneMapping, 'auto');
      expect(PlayerSettings.kToneMappingModes, contains('bt.2390'));
      final on = s.copyWith(enhanceVideo: true, toneMapping: 'mobius');
      expect(on.enhanceVideo, isTrue);
      expect(on.toneMapping, 'mobius');
      expect(on.doubleTapSeek, isTrue); // untouched keys preserved
    });

    test('saved servers parse, round-trip, and junk is dropped', () {
      expect(parseServersJson(null), isEmpty);
      expect(parseServersJson(''), isEmpty);
      expect(parseServersJson('not json'), isEmpty);
      expect(parseServersJson('{"oops":true}'), isEmpty);
      const s = SavedServer(
        name: 'nas.local:5005',
        url: 'http://nas.local:5005/film.mkv',
      );
      final raw = serversToJson([s]);
      final back = parseServersJson(raw);
      expect(back.single.name, s.name);
      expect(back.single.url, s.url);
      // entries without a url are skipped, good ones kept
      final messy = parseServersJson(
        '[{"name":"x"},{"url":"rtsp://cam.local/live"}]',
      );
      expect(messy.single.url, 'rtsp://cam.local/live');
    });

    test('addSavedServer dedupes by url', () {
      const a = SavedServer(name: 'a', url: 'http://n.local/a.mkv');
      const dup = SavedServer(name: 'a2', url: 'http://n.local/a.mkv');
      final list = addSavedServer(addSavedServer(const [], a), dup);
      expect(list.length, 1);
      expect(list.single.name, 'a');
    });
  });

  group('v34 native crash reporter and track sheet sizing', () {
    test('trackSheetInitialSize never leaves the safe 0.4..0.8 band', () {
      for (final h in [320.0, 640.0, 800.0, 1280.0, 2400.0]) {
        for (var rows = 0; rows <= 40; rows++) {
          final f = trackSheetInitialSize(rows, h);
          expect(f, greaterThanOrEqualTo(0.4));
          expect(f, lessThanOrEqualTo(0.8));
        }
      }
    });

    test('trackSheetInitialSize grows with rows, guards bad heights', () {
      // Few rows on a tall screen -> the 40% floor (compact sheet).
      expect(trackSheetInitialSize(2, 2400), 0.4);
      // Many rows on a small/old phone -> the 80% cap; the sheet then
      // scrolls and can still be dragged up to 92%.
      expect(trackSheetInitialSize(30, 640), 0.8);
      // Degenerate heights can never produce NaN / Infinity.
      expect(trackSheetInitialSize(5, 0), 0.6);
      expect(trackSheetInitialSize(5, -1), 0.6);
    });

    test('takeLastIncludingNative simply finds nothing without a device',
        () async {
      // Unit tests have no method-channel native side: nativeCrashGet and
      // the settings store both guard, so the result is null - and it can
      // never throw, which is what matters at app start.
      expect(await CrashLog.takeLastIncludingNative(), isNull);
    });
  });

  group('v35 tune sheet (subtitles/audio/A-B/karaoke) opens fully', () {
    test('four rows size sanely in portrait AND landscape', () {
      // Small portrait phone: compact ~46% open, rows all visible.
      final portrait = trackSheetInitialSize(4, 800);
      expect(portrait, greaterThan(0.4));
      expect(portrait, lessThan(0.6));
      // Landscape/short screens (where the old half-height sheet cut the
      // A-B loop and karaoke rows): clamps to 80%, and everything stays
      // reachable because the sheet scrolls + drags up to 92%.
      expect(trackSheetInitialSize(4, 380), 0.8);
      expect(trackSheetInitialSize(4, 320), 0.8);
    });
  });
}
EOF_MARKER_26


echo "==> Files written. Quick sanity check..."
S=0
grep -qF "CrashCrumbs" android/app/src/main/kotlin/com/hypertechlabs/maxplayer/MaxPlayerApp.kt && echo "  OK startup trace" || { echo "  FAIL trace"; S=1; }
grep -qF "maxplayer_start.log" android/app/src/main/kotlin/com/hypertechlabs/maxplayer/MaxPlayerApp.kt && echo "  OK trace file" || { echo "  FAIL trace file"; S=1; }
grep -qF "\"crumb\" ->" android/app/src/main/kotlin/com/hypertechlabs/maxplayer/MainActivity.kt && echo "  OK crumb channel" || { echo "  FAIL crumb channel"; S=1; }
grep -qF "CrashCrumbs.mark" android/app/src/main/kotlin/com/hypertechlabs/maxplayer/MainActivity.kt && echo "  OK activity marks" || { echo "  FAIL marks"; S=1; }
grep -qF "_StartupFailureScreen" lib/main.dart && echo "  OK engine guard" || { echo "  FAIL guard"; S=1; }
grep -qF "player_FAIL" lib/main.dart && echo "  OK player crumb" || { echo "  FAIL player crumb"; S=1; }
grep -qF "scan_permission_threw" lib/state/video_library_state.dart && echo "  OK permission guard" || { echo "  FAIL permission"; S=1; }
grep -qF "crumb" lib/services/native_bridge.dart && echo "  OK bridge crumb" || { echo "  FAIL bridge"; S=1; }
grep -qF "nativeCrashGet" lib/services/native_bridge.dart && echo "  OK crash calls kept" || { echo "  FAIL crash calls"; S=1; }
grep -qF "takeLastIncludingNative" lib/utils/crash_log.dart && echo "  OK crash log kept" || { echo "  FAIL crash log"; S=1; }
grep -qF "android:name=\".MaxPlayerApp\"" android/app/src/main/AndroidManifest.xml && echo "  OK manifest app" || { echo "  FAIL manifest"; S=1; }
grep -qF "EnableImpeller" android/app/src/main/AndroidManifest.xml && echo "  OK impeller flag kept" || { echo "  FAIL impeller"; S=1; }
grep -qF "DraggableScrollableSheet" lib/widgets/player_controls_overlay.dart && echo "  OK tune sheet kept" || { echo "  FAIL tune sheet"; S=1; }
grep -qF "DraggableScrollableSheet" lib/widgets/track_selection_sheet.dart && echo "  OK cc sheet kept" || { echo "  FAIL cc sheet"; S=1; }
grep -qF "setEnhanceVideo" lib/state/media_player_state.dart && echo "  OK enhance kept" || { echo "  FAIL enhance"; S=1; }
grep -qF "cleanerSegments" lib/utils/cleaner_stats.dart && echo "  OK cleaner kept" || { echo "  FAIL cleaner"; S=1; }
grep -qF "kServersSettingKey" lib/models/saved_server.dart && echo "  OK servers kept" || { echo "  FAIL servers"; S=1; }
grep -qF "v35 tune sheet" test/widget_test.dart && echo "  OK tests kept" || { echo "  FAIL tests"; S=1; }
grep -qF "1.0.0+35" pubspec.yaml && echo "  OK pubspec (1.0.0+35)" || { echo "  FAIL pubspec"; S=1; }
if [ "$S" -ne 0 ]; then echo "SANITY CHECK FAILED - do not push; report the FAIL lines."; exit 1; fi

if command -v flutter >/dev/null 2>&1; then
  echo "==> flutter analyze (should print: No issues found!)"
  set +e; flutter analyze; A=$?; set -e
else
  echo "==> flutter not on PATH - Codemagic will build it"
fi

echo "==> Removing old update_maxplayer_v*.sh helper scripts ..."
rm -f update_maxplayer_v*.sh

echo ''
echo '=============================================================='
echo ' v37 applied.  VERIFY (must print 1.0.0+35):  grep ^version pubspec.yaml'
echo ' Push:  git add -A && git commit -m "v37: startup trace + engine'
echo ' guard + permission hardening (1.0.0+35)" && git push'
echo ''
echo 'THEN ON A PHONE THAT CRASHES AT OPEN:'
echo '  1. Install the new (v37) build, tap Max Player, let it die.'
echo '  2. Open any FILE MANAGER on that phone, go to:'
echo '       Android > data > com.hypertechlabs.maxplayer > files'
echo '  3. Send me BOTH files found there (or a photo of them):'
echo '       maxplayer_start.log   <- shows the LAST stage it reached'
echo '       maxplayer_crash.txt   <- the exact error (if it is there)'
echo '     The last stage line names the broken component for that phone'
echo '     (engine / channel / dart / media engine / permission / scan).'
echo '  4. If instead a red "video engine failed to start" screen shows,'
echo '     tap "Copy error" and send that text.'
echo '  (If there are NO files at all after the crash, say so - that is'
echo '   also an answer: the crash is before our code runs at all.)'
echo '  On your own Samsung everything should behave exactly as before.'
echo '=============================================================='
