#!/usr/bin/env bash
# ============================================================
#  update_v1.sh — MaxPlayer rebuild, v1 drop (v0.2 codebase)
#
#  Generates the FULL project in one run:
#    • MPV (libmpv + FFmpeg) single engine, guarded playback
#    • Dark UI (near-black slate, hairline cards, blue accent)
#    • Video grid library (MediaStore scan, permission flow)
#    • Player gestures: double-tap ±10s, long-press 2x, wakelock
#    • Crash log (events.jsonl + report.last)
#    • 10 pin tests
#    • GitHub Actions workflow: builds app-release.apk every push
#    • codemagic.yaml + key.properties.template (for later)
#
#  USAGE:
#    1. Put update_v1.sh in your project folder (empty is fine:
#       it runs flutter create when no pubspec is found; over an
#       existing extract it overwrites the app files).
#    2. bash update_v1.sh
#    3. flutter run --release           # test on your phone
#    4. bash scripts/connect_repo.sh <your-new-repo-url>
#       → from then on, GitHub builds the APK on every push
# ============================================================
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
command -v flutter >/dev/null 2>&1 || { echo "ERROR: flutter not on PATH"; exit 1; }
if [ ! -f pubspec.yaml ]; then
  echo ">> No project found here - running flutter create ..."
  flutter create --project-name maxplayer --org com.maxplayer --platforms android . > /dev/null
fi
echo ">> Writing app files ..."
mkdir -p "$(dirname "pubspec.yaml")"
cat > "pubspec.yaml" <<'MP_EOF_pubspec_yaml'
name: maxplayer
description: "MaxPlayer — local-first MPV video player."
# The following line prevents the package from being accidentally published to
# pub.dev using `flutter pub publish`. This is preferred for private packages.
publish_to: 'none' # Remove this line if you wish to publish to pub.dev

# The following defines the version and build number for your application.
# A version number is three numbers separated by dots, like 1.2.43
# followed by an optional build number separated by a +.
# Both the version and the builder number may be overridden in flutter
# build by specifying --build-name and --build-number, respectively.
# In Android, build-name is used as versionName while build-number used as versionCode.
# Read more about Android versioning at https://developer.android.com/studio/publish/versioning
# In iOS, build-name is used as CFBundleShortVersionString while build-number is used as CFBundleVersion.
# Read more about iOS versioning at
# https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/CoreFoundationKeys.html
# In Windows, build-name is used as the major, minor, and patch parts
# of the product and file versions while build-number is used as the build suffix.
version: 0.2.0+2

environment:
  sdk: ^3.12.0

# Dependencies specify other packages that your package needs in order to work.
# To automatically upgrade your package dependencies to the latest versions
# consider running `flutter pub upgrade --major-versions`. Alternatively,
# dependencies can be manually updated by changing the version numbers below to
# the latest version available on pub.dev. To see which dependencies have newer
# versions available, run `flutter pub outdated`.
dependencies:
  flutter:
    sdk: flutter

  # The following adds the Cupertino Icons font to your application.
  # Use with the CupertinoIcons class for iOS style icons.
  cupertino_icons: ^1.0.8
  media_kit: ^1.2.6
  media_kit_video: ^2.0.1
  media_kit_libs_video: ^1.0.7
  shared_preferences: ^2.5.5
  path_provider: ^2.1.6
  photo_manager: ^3.12.0
  wakelock_plus: ^1.8.0

dev_dependencies:
  flutter_test:
    sdk: flutter

  # The "flutter_lints" package below contains a set of recommended lints to
  # encourage good coding practices. The lint set provided by the package is
  # activated in the `analysis_options.yaml` file located at the root of your
  # package. See that file for information about deactivating specific lint
  # rules and activating additional ones.
  flutter_lints: ^6.0.0

# For information on the generic Dart part of this file, see the
# following page: https://dart.dev/tools/pub/pubspec

# The following section is specific to Flutter packages.
flutter:

  # The following line ensures that the Material Icons font is
  # included with your application, so that you can use the icons in
  # the material Icons class.
  uses-material-design: true

  # To add assets to your application, add an assets section, like this:
  # assets:
  #   - images/a_dot_burr.jpeg
  #   - images/a_dot_ham.jpeg

  # An image asset can refer to one or more resolution-specific "variants", see
  # https://flutter.dev/to/resolution-aware-images

  # For details regarding adding assets from package dependencies, see
  # https://flutter.dev/to/asset-from-package

  # To add custom fonts to your application, add a fonts section here,
  # in this "flutter" section. Each entry in this list should have a
  # "family" key with the font family name, and a "fonts" key with a
  # list giving the asset and other descriptors for the font. For
  # example:
  # fonts:
  #   - family: Schyler
  #     fonts:
  #       - asset: fonts/Schyler-Regular.ttf
  #       - asset: fonts/Schyler-Italic.ttf
  #         style: italic
  #   - family: Trajan Pro
  #     fonts:
  #       - asset: fonts/TrajanPro.ttf
  #       - asset: fonts/TrajanPro_Bold.ttf
  #         weight: 700
  #
  # For details regarding fonts from package dependencies,
  # see https://flutter.dev/to/font-from-package
MP_EOF_pubspec_yaml
mkdir -p "$(dirname "lib/main.dart")"
cat > "lib/main.dart" <<'MP_EOF_lib_main_dart'
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'screens/library_screen.dart';
import 'theme.dart';
import 'utils/crash_log.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized(); // MPV core
  await CrashLog.init(); // forensics armed before first frame
  CrashLog.crumb('app.start');
  runApp(const MaxPlayerApp());
}

class MaxPlayerApp extends StatelessWidget {
  const MaxPlayerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MaxPlayer',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const LibraryScreen(),
    );
  }
}
MP_EOF_lib_main_dart
mkdir -p "$(dirname "lib/theme.dart")"
cat > "lib/theme.dart" <<'MP_EOF_lib_theme_dart'
import 'package:flutter/material.dart';

/// MaxPlayer dark design language — near-black slate surfaces,
/// hairline borders, cool blue accent. Dark-first, no light mode for v0.
class AppColors {
  AppColors._();

  static const background = Color(0xFF0B0E14); // app canvas
  static const surface = Color(0xFF131826); // cards / inputs
  static const surfaceAlt = Color(0xFF181E2E); // raised elements
  static const border = Color(0xFF262E42); // 1px hairlines
  static const textPrimary = Color(0xFFF2F5FA);
  static const textSecondary = Color(0xFF8B94A7);
  static const accent = Color(0xFF3D6BFF); // primary blue
  static const accentSoft = Color(0xFF2A3CFF);
  static const danger = Color(0xFFE5484D);
}

ThemeData buildAppTheme() {
  const radius = Radius.circular(16);
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.background,
    colorScheme: const ColorScheme.dark(
      surface: AppColors.surface,
      primary: AppColors.accent,
      onPrimary: Colors.white,
      onSurface: AppColors.textPrimary,
      error: AppColors.danger,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.background,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: AppColors.textPrimary,
        fontSize: 22,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
      ),
      iconTheme: IconThemeData(color: AppColors.textPrimary),
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.all(radius),
        side: const BorderSide(color: AppColors.border, width: 1),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.surfaceAlt,
      contentTextStyle: const TextStyle(color: AppColors.textPrimary),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
    ),
    iconTheme: const IconThemeData(color: AppColors.textPrimary),
    textTheme: const TextTheme(
      bodyMedium: TextStyle(color: AppColors.textPrimary),
      bodySmall: TextStyle(color: AppColors.textSecondary),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.border, thickness: 1),
  );
}
MP_EOF_lib_theme_dart
mkdir -p "$(dirname "lib/utils/format.dart")"
cat > "lib/utils/format.dart" <<'MP_EOF_lib_utils_format_dart'
// Small pure formatting helpers (unit-tested).

/// 0 -> "0:00", 65 -> "1:05", 3723 -> "1:02:03"
String formatDuration(Duration d) {
  if (d.isNegative) d = Duration.zero;
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '${int.parse(m)}:$s';
}

/// 1536 -> "1.5 KB", 734003200 -> "700.0 MB"
String formatBytes(int bytes) {
  if (bytes < 0) bytes = 0;
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return unit == 0 ? '${bytes}B' : '${value.toStringAsFixed(1)} ${units[unit]}';
}
MP_EOF_lib_utils_format_dart
mkdir -p "$(dirname "lib/utils/crash_log.dart")"
cat > "lib/utils/crash_log.dart" <<'MP_EOF_lib_utils_crash_log_dart'
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Crash forensics from day one (non-negotiable #3).
///
/// Appends JSONL events to `<docs>/logs/events.jsonl` and mirrors the
/// latest report-worthy event to `<docs>/logs/report.last`. Evidence must
/// survive even if no dialog ever appears.
class CrashLog {
  CrashLog._();

  static File? _eventsFile;
  static File? _reportFile;

  static Future<void> init() async {
    final dir = await getApplicationDocumentsDirectory();
    final logs = Directory('${dir.path}/logs');
    if (!logs.existsSync()) logs.createSync(recursive: true);
    _eventsFile = File('${logs.path}/events.jsonl');
    _reportFile = File('${logs.path}/report.last');
  }

  /// Log a breadcrumb (tap, route decision, engine error, ...).
  static void crumb(String event, [Map<String, Object?> data = const {}]) {
    _write({'t': DateTime.now().toIso8601String(), 'event': event, ...data});
  }

  /// Log an error worth investigating later. Also persisted to report.last
  /// so the evidence cannot be lost even when nothing visibly crashes.
  static void error(String event, Object e,
      [Map<String, Object?> data = const {}]) {
    final report = jsonEncode({
      't': DateTime.now().toIso8601String(),
      'event': event,
      'error': e.toString(),
      ...data,
    });
    _writeRaw(report);
    unawaited(Future(() async {
      try {
        await _reportFile?.writeAsString('$report\n');
      } catch (_) {/* never throw from logging */}
    }));
  }

  static void _write(Map<String, Object?> entry) => _writeRaw(jsonEncode(entry));

  static void _writeRaw(String line) {
    unawaited(Future(() async {
      try {
        await _eventsFile?.writeAsString('$line\n', mode: FileMode.append);
      } catch (_) {/* never throw from logging */}
    }));
  }
}
MP_EOF_lib_utils_crash_log_dart
mkdir -p "$(dirname "lib/screens/library_screen.dart")"
cat > "lib/screens/library_screen.dart" <<'MP_EOF_lib_screens_library_screen_dart'
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../theme.dart';
import '../utils/crash_log.dart';
import '../utils/format.dart';
import 'player_screen.dart';

/// Video library: scans device videos via MediaStore (photo_manager),
/// permission-gated, glass grid. Never auto-plays (non-negotiable #7).
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  static const _pageSize = 60;

  bool _loading = true;
  bool _denied = false;
  final List<AssetEntity> _videos = [];
  AssetPathEntity? _allPath;
  int _page = 0;
  bool _exhausted = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _denied = false;
    });
    try {
      final ps = await PhotoManager.requestPermissionExtend();
      if (!ps.isAuth && !ps.hasAccess) {
        CrashLog.crumb('library.permission_denied');
        setState(() {
          _loading = false;
          _denied = true;
        });
        return;
      }
      final paths = await PhotoManager.getAssetPathList(
        type: RequestType.video,
        onlyAll: true,
      );
      if (paths.isEmpty) {
        setState(() => _loading = false);
        return;
      }
      _allPath = paths.first;
      _page = 0;
      _videos.clear();
      _exhausted = false;
      await _loadMore();
      CrashLog.crumb('library.scanned', {'count': _videos.length});
    } catch (e) {
      CrashLog.error('library.scan_failed', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not scan videos on this device')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    final path = _allPath;
    if (path == null || _exhausted) return;
    final batch = await path.getAssetListPaged(page: _page, size: _pageSize);
    if (batch.length < _pageSize) _exhausted = true;
    _page++;
    _videos.addAll(batch.where((a) => a.type == AssetType.video));
    if (mounted) setState(() {});
  }

  Future<void> _openVideo(AssetEntity asset) async {
    CrashLog.crumb('library.tap', {'id': asset.id, 'title': asset.title});
    // Guarded preflight (non-negotiable #2): a tap must play or say why.
    try {
      final file = await asset.file;
      if (!mounted) return;
      if (file == null || !file.existsSync()) {
        throw StateError('video file unavailable: ${asset.title}');
      }
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PlayerScreen(
            path: file.path,
            title: asset.title ?? 'Video',
          ),
        ),
      );
    } catch (e) {
      CrashLog.error('library.open_failed', e, {'id': asset.id});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open this video')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MaxPlayer'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _load,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.accent),
      );
    }
    if (_denied) {
      return _CenteredHint(
        icon: Icons.lock_outline_rounded,
        title: 'Permission needed',
        message: 'MaxPlayer needs access to your videos to show the library.',
        actionLabel: 'Grant access',
        onAction: _load,
      );
    }
    if (_videos.isEmpty) {
      return _CenteredHint(
        icon: Icons.video_library_outlined,
        title: 'No videos found',
        message: 'Videos on this device will appear here.',
        actionLabel: 'Rescan',
        onAction: _load,
      );
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.pixels > n.metrics.maxScrollExtent - 600) _loadMore();
        return false;
      },
      child: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 14,
          crossAxisSpacing: 14,
          childAspectRatio: 0.78,
        ),
        itemCount: _videos.length,
        itemBuilder: (context, i) =>
            _VideoCard(asset: _videos[i], onTap: () => _openVideo(_videos[i])),
      ),
    );
  }
}

class _VideoCard extends StatelessWidget {
  const _VideoCard({required this.asset, required this.onTap});

  final AssetEntity asset;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  FutureBuilder<Uint8List?>(
                    future: asset.thumbnailDataWithSize(
                      const ThumbnailSize(480, 480),
                    ),
                    builder: (context, snap) {
                      final bytes = snap.data;
                      if (bytes == null) {
                        return const ColoredBox(color: AppColors.surfaceAlt);
                      }
                      return Image.memory(bytes, fit: BoxFit.cover);
                    },
                  ),
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        formatDuration(Duration(seconds: asset.duration)),
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.textPrimary),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    asset.title ?? 'Untitled',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${asset.modifiedDateTime.year}-'
                    '${asset.modifiedDateTime.month.toString().padLeft(2, '0')}-'
                    '${asset.modifiedDateTime.day.toString().padLeft(2, '0')}',
                    style: const TextStyle(
                        fontSize: 11.5, color: AppColors.textSecondary),
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

class _CenteredHint extends StatelessWidget {
  const _CenteredHint({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 52, color: AppColors.textSecondary),
            const SizedBox(height: 16),
            Text(title,
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 8),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 20),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accent,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: onAction,
              child: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}
MP_EOF_lib_screens_library_screen_dart
mkdir -p "$(dirname "lib/screens/player_screen.dart")"
cat > "lib/screens/player_screen.dart" <<'MP_EOF_lib_screens_player_screen_dart'
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../theme.dart';
import '../utils/crash_log.dart';
import '../utils/format.dart';

/// Single-engine player: MPV (libmpv + FFmpeg) via media_kit.
///
/// v0.2 gestures:
///   • single tap          → show/hide controls
///   • double tap L/R      → seek −10s / +10s (with flash indicator)
///   • long press hold     → 2× speed, release restores 1×
///   • wakelock held while playing
///
/// Preflight is fully guarded: any open failure is crumbed, persisted to
/// report.last, surfaced via snackbar, and pops — a tap never dies silently.
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key, required this.path, required this.title});

  final String path;
  final String title;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  static const _seekStepSecs = 10;
  static const _boostRate = 2.0;

  late final Player _player;
  late final VideoController _controller;
  StreamSubscription<bool>? _playingSub;

  bool _ready = false;
  bool _failed = false;
  bool _controlsVisible = true;
  bool _boost = false;
  int? _seekFlash; // +N or -N seconds, shown briefly
  bool _seekFlashLeft = false;
  Timer? _hideTimer;
  Timer? _flashTimer;

  // ---------------- lifecycle ----------------

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _player = Player();
    _controller = VideoController(_player);
    _open();
    _playingSub = _player.stream.playing.listen((playing) {
      if (playing) {
        WakelockPlus.enable();
        _scheduleHide();
      } else {
        WakelockPlus.disable();
      }
    });
  }

  Future<void> _open() async {
    CrashLog.crumb('player.open', {'path': widget.path});
    try {
      await _player.open(Media(widget.path), play: true);
      // MPV reports hard failures asynchronously through the error stream.
      _player.stream.error.listen(_onError);
      if (mounted) setState(() => _ready = true);
    } catch (e) {
      _onError(e);
    }
  }

  void _onError(Object e) {
    if (_failed) return;
    _failed = true;
    CrashLog.error('player.open_failed', e, {'path': widget.path});
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("This video can't be played by MPV")),
    );
    Navigator.of(context).maybePop();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _flashTimer?.cancel();
    _playingSub?.cancel();
    WakelockPlus.disable();
    CrashLog.crumb('player.close', {'path': widget.path});
    unawaited(_player.dispose());
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  // ---------------- gestures ----------------

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) _scheduleHide();
  }

  void _onDoubleTap(TapDownDetails d) {
    final half = MediaQuery.of(context).size.width / 2;
    final left = d.globalPosition.dx < half;
    _seekRelative(left ? -_seekStepSecs : _seekStepSecs, flashLeft: left);
  }

  void _seekRelative(int seconds, {required bool flashLeft}) {
    final pos = _player.state.position;
    final dur = _player.state.duration;
    var target = pos + Duration(seconds: seconds);
    if (target < Duration.zero) target = Duration.zero;
    if (dur > Duration.zero && target > dur) target = dur;
    _player.seek(target);
    CrashLog.crumb('player.seek', {'delta': seconds});
    _flashTimer?.cancel();
    setState(() {
      _seekFlash = seconds;
      _seekFlashLeft = flashLeft;
    });
    _flashTimer = Timer(const Duration(milliseconds: 650), () {
      if (mounted) setState(() => _seekFlash = null);
    });
  }

  void _setBoost(bool on) {
    if (_boost == on) return;
    setState(() => _boost = on);
    _player.setRate(on ? _boostRate : 1.0);
    CrashLog.crumb('player.rate', {'rate': on ? _boostRate : 1.0});
  }

  // ---------------- controls visibility ----------------

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _player.state.playing && !_boost) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  // ---------------- build ----------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggleControls,
        onDoubleTapDown: _onDoubleTap,
        onLongPressStart: (_) => _setBoost(true),
        onLongPressEnd: (_) => _setBoost(false),
        onLongPressCancel: () => _setBoost(false),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_ready && !_failed)
              Video(
                controller: _controller,
                controls: NoVideoControls, // we draw our own
              )
            else
              const Center(
                child: CircularProgressIndicator(color: AppColors.accent),
              ),

            // seek flash indicator
            if (_seekFlash != null)
              Align(
                alignment: _seekFlashLeft
                    ? Alignment.centerLeft
                    : Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 36),
                  child: _SeekPill(seconds: _seekFlash!),
                ),
              ),

            // speed boost badge
            if (_boost)
              const Align(
                alignment: Alignment(0, -0.55),
                child: _SpeedBadge(),
              ),

            if (_controlsVisible) ...[
              _TopBar(title: widget.title),
              _BottomBar(player: _player),
              _CenterControls(player: _player),
            ],
          ],
        ),
      ),
    );
  }
}

class _SeekPill extends StatelessWidget {
  const _SeekPill({required this.seconds});

  final int seconds;

  @override
  Widget build(BuildContext context) {
    final back = seconds < 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            back
                ? Icons.replay_10_rounded
                : Icons.forward_10_rounded,
            color: Colors.white,
            size: 26,
          ),
          const SizedBox(width: 6),
          Text(
            '${back ? '' : '+'}${seconds}s',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _SpeedBadge extends StatelessWidget {
  const _SpeedBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Text(
        '2×',
        style: TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + 8,
          left: 4,
          right: 16,
          bottom: 12,
        ),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black87, Colors.transparent],
          ),
        ),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CenterControls extends StatelessWidget {
  const _CenterControls({required this.player});

  final Player player;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: StreamBuilder<bool>(
        stream: player.stream.playing,
        initialData: player.state.playing,
        builder: (context, snap) {
          final playing = snap.data ?? false;
          return IconButton(
            iconSize: 68,
            color: Colors.white,
            icon: Icon(playing
                ? Icons.pause_circle_filled_rounded
                : Icons.play_circle_filled_rounded),
            onPressed: player.playOrPause,
          );
        },
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.player});

  final Player player;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 12,
          bottom: MediaQuery.of(context).padding.bottom + 16,
        ),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Colors.black87, Colors.transparent],
          ),
        ),
        child: StreamBuilder<Duration>(
          stream: player.stream.position,
          initialData: player.state.position,
          builder: (context, posSnap) {
            final position = posSnap.data ?? Duration.zero;
            return StreamBuilder<Duration>(
              stream: player.stream.duration,
              initialData: player.state.duration,
              builder: (context, durSnap) {
                final duration = durSnap.data ?? Duration.zero;
                final maxMs =
                    duration.inMilliseconds > 0 ? duration.inMilliseconds : 1;
                final valueMs = position.inMilliseconds.clamp(0, maxMs);
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: AppColors.accent,
                        inactiveTrackColor: Colors.white24,
                        thumbColor: Colors.white,
                        trackHeight: 2.5,
                        thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 6),
                        overlayShape: SliderComponentShape.noOverlay,
                      ),
                      child: Slider(
                        value: valueMs.toDouble(),
                        max: maxMs.toDouble(),
                        onChanged: (ms) => player
                            .seek(Duration(milliseconds: ms.round())),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(formatDuration(position),
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 12)),
                          Text(formatDuration(duration),
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}
MP_EOF_lib_screens_player_screen_dart
mkdir -p "$(dirname "test/widget_test.dart")"
cat > "test/widget_test.dart" <<'MP_EOF_test_widget_test_dart'
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maxplayer/theme.dart';
import 'package:maxplayer/utils/format.dart';

void main() {
  group('formatDuration', () {
    test('zero', () => expect(formatDuration(Duration.zero), '0:00'));
    test('seconds', () {
      expect(formatDuration(const Duration(seconds: 7)), '0:07');
    });
    test('minutes', () {
      expect(formatDuration(const Duration(minutes: 1, seconds: 5)), '1:05');
    });
    test('hours', () {
      expect(formatDuration(const Duration(hours: 1, minutes: 2, seconds: 3)),
          '1:02:03');
    });
    test('negative clamps to zero', () {
      expect(formatDuration(const Duration(seconds: -5)), '0:00');
    });
  });

  group('formatBytes', () {
    test('bytes', () => expect(formatBytes(512), '512B'));
    test('kilobytes', () => expect(formatBytes(1536), '1.5 KB'));
    test('megabytes', () => expect(formatBytes(734003200), '700.0 MB'));
    test('negative clamps', () => expect(formatBytes(-1), '0B'));
  });

  testWidgets('theme applies dark design language', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: const Scaffold(body: Text('ok')),
    ));
    expect(find.text('ok'), findsOneWidget);
    final theme = Theme.of(tester.element(find.text('ok')));
    expect(theme.scaffoldBackgroundColor, AppColors.background);
    expect(theme.brightness, Brightness.dark);
  });
}
MP_EOF_test_widget_test_dart
mkdir -p "$(dirname "BLUEPRINT.md")"
cat > "BLUEPRINT.md" <<'MP_EOF_BLUEPRINT_md'
# MaxPlayer — Rebuild Blueprint

Fresh start. Same app, clean foundation. This document is the contract for the rebuild:
what we keep as *decisions* (not code), the target architecture, and the build order.

---

## 1. Non-negotiables (carried forward from v148)

These were earned through months of device firefighting. The rebuild keeps all of them:

1. **Local-first, ad-free.** No accounts, no analytics, no tracking. Internet permission never abused.
2. **Multi-engine from day one** — not bolted on later:
   - **MPV (media_kit) = the default workhorse.** libmpv/ffmpeg underneath.
   - **ExoPlayer (video_player) = secondary route** only when it proves safe per-device.
   - Every engine route's preflight is **wrapped in try/catch** → crumb → snackbar → failover.
   - **No silent tap failures, ever.** A tap must either play or visibly report why not. *(v148 lesson)*
3. **Crash forensics from day one:** crash_log with play-stones, strike tracking, and `report.last`
   persistence — evidence must survive even when the reopen dialog doesn't. *(v140–v148 lesson)*
4. **Resume must survive process kill** (position stone persisted on pause/track-end/tick).
5. **System-consent deletes only** (MediaStore deleteRequest on Android 11+).
6. **Glassmorphism UI** aesthetic, dark-first.
7. **Never auto-start playback on launch.**
8. **Tests from day one** — every shipped fix gets a pin test. No reaching 148 versions before a
   test suite exists.

## 2. Hard-won device knowledge (design inputs, not code)

- Realme/MTK and Samsung/Exynos MediaCodec stacks have different HW-decode quirks; OEM
  task-killers reap background/headless work. Any engine choice logic must be per-device
  learned (strikes) rather than assumed.
- "Tap → nothing, no dialog, all devices" = Dart-level silent abort, not native crash.
  Guard every async preflight.
- First-play on a fresh install may need a "learning probe" strategy before trusting a codec path.
- Unfiltered logcat is useless; structured crumbs + persisted reports are the diagnostics.

## 3. Target architecture

```
lib/
├── main.dart              # bootstrap: media_kit init, crash_log arm, routing
├── screens/               # library (grid), player, settings  (glass UI, dark-first)
├── engines/               # EngineRouter (pure decision fn) + per-engine adapters
│                          #   MpvEngine, ExoEngine — behind one PlayerEngine interface
├── models/                # Track, ResumePoint, EngineChoice, CrashReport
├── utils/                 # crash_log, prefs, file_scanner, thumbnails
└── widgets/               # glass cards, player controls, snackbar reporter
```

Rules:
- **EngineRouter is a pure function** (inputs: path, codec, strikes, flags → EngineChoice). Unit-testable, no I/O.
- **PlayerEngine interface** so engines are swappable; screens never touch engine APIs directly.
- **State management:** plain `ChangeNotifier`/ValueNotifier until proven insufficient — no BLoC ceremony for v0.1.
- All persistent state via shared_preferences + JSONL crash log in app documents dir.

## 4. Dependencies (already in pubspec)

| Package | Role |
|---|---|
| media_kit / media_kit_video / media_kit_libs_video | MPV core engine |
| video_player | ExoPlayer route |
| shared_preferences | strikes, settings, resume index |
| path_provider | crash log + thumbnails dir |

Add later (only when needed): file scanning, thumbnails, permission handler, wakelock,
volume/brightness gesture helpers.

## 5. Build order (each step = shippable + tested)

1. **v0.1  Skeleton:** library screen lists videos (MediaStore scan), tap → MPV plays. Crash log armed. ~5 tests.
2. **v0.2  Glass player UI:** controls, seek, gestures (brightness/volume), wakelock.
3. **v0.3  Resume:** position stones, survive kill, "resume from X?" affordance.
4. **v0.4  Forensics:** strikes, report.last, reopen dialog.
5. **v0.5  Multi-engine:** EngineRouter + Exo route + failover, guarded preflights.
6. **v0.6  Gallery polish:** thumbnails, folders, sort/filter, delete with consent.
7. **v0.7  Settings + edge formats** (avi/flv/ts → MPV forced), network streams (later).
8. **v1.0  Play Store hardening:** release build, both-device soak test, listing.

## 6. Release checklist (before any user install)

- [ ] analyzer clean
- [ ] all tests pass
- [ ] release APK installed on Realme **and** Samsung
- [ ] tap every playable format once
- [ ] kill mid-play → reopen → resume offered
- [ ] crash report written to report.last when forced
MP_EOF_BLUEPRINT_md
mkdir -p "$(dirname "codemagic.yaml")"
cat > "codemagic.yaml" <<'MP_EOF_codemagic_yaml'
# Codemagic CI — Android release for MaxPlayer.
# All secrets come from the environment group "keystore_credentials":
#   CM_KEYSTORE            (base64 of upload-keystore.jks)
#   CM_KEYSTORE_PASSWORD
#   CM_KEY_ALIAS
#   CM_KEY_ALIAS_PASSWORD
#   TMDB_API_KEY           (injected via --dart-define, future metadata feature)
#   OPENROUTER_API_KEY     (injected via --dart-define, future AI feature)
workflows:
  android-release:
    name: Android release
    max_build_duration: 60
    environment:
      groups:
        - keystore_credentials
      flutter: stable
      xcode: latest
    scripts:
      - name: Set up keystore from env vars
        script: |
          echo "$CM_KEYSTORE" | base64 --decode > "$CM_BUILD_DIR/android/app/upload-keystore.jks"
          cat > "$CM_BUILD_DIR/android/key.properties" <<EOF
          storePassword=$CM_KEYSTORE_PASSWORD
          keyPassword=$CM_KEY_ALIAS_PASSWORD
          keyAlias=$CM_KEY_ALIAS
          storeFile=upload-keystore.jks
          EOF
          chmod 600 "$CM_BUILD_DIR/android/app/upload-keystore.jks" \
                    "$CM_BUILD_DIR/android/key.properties"
      - name: Get packages
        script: flutter packages pub get
      - name: Analyze
        script: flutter analyze
      - name: Test
        script: flutter test
      - name: Build AAB (release, signed)
        script: |
          flutter build appbundle --release \
            --dart-define=TMDB_API_KEY="$TMDB_API_KEY" \
            --dart-define=OPENROUTER_API_KEY="$OPENROUTER_API_KEY"
      - name: Clean up secrets from build machine
        script: |
          rm -f "$CM_BUILD_DIR/android/key.properties" \
                "$CM_BUILD_DIR/android/app/upload-keystore.jks"
        ignore_failure: true
    artifacts:
      - build/app/outputs/bundle/release/app-release.aab
    publishing:
      email:
        recipients:
          - you@example.com
MP_EOF_codemagic_yaml
mkdir -p "$(dirname "android/key.properties.template")"
cat > "android/key.properties.template" <<'MP_EOF_android_key_properties_template'
# ============================================================
#  LOCAL SIGNING CONFIG  —  copy this file to  android/key.properties
#  and fill in YOUR real values. key.properties is gitignored.
#  NEVER commit the real file or the .jks to git.
#
#  In CI (Codemagic) these same four values come from the
#  environment group "keystore_credentials":
#    CM_KEYSTORE_PASSWORD  -> storePassword
#    CM_KEY_ALIAS          -> keyAlias
#    CM_KEY_ALIAS_PASSWORD -> keyPassword
#    CM_KEYSTORE           -> base64 of the .jks (decoded by CI to storeFile)
# ============================================================
storePassword=YOUR_STORE_PASSWORD
keyPassword=YOUR_KEY_PASSWORD
keyAlias=YOUR_KEY_ALIAS
storeFile=upload-keystore.jks
MP_EOF_android_key_properties_template
mkdir -p "$(dirname ".github/workflows/android-apk.yml")"
cat > ".github/workflows/android-apk.yml" <<'MP_EOF__github_workflows_android-apk_yml'
# GitHub Actions — build the release APK on every push to main.
# The runner is standard x64 Ubuntu with the official Flutter stable,
# so the Pi's older local SDK never blocks anything. Download the APK
# from the workflow run's "Artifacts" section (sign in from any device).
name: Android APK

on:
  push:
    branches: [main]
  workflow_dispatch: {}   # "Run workflow" button in the Actions tab

jobs:
  build:
    name: Build release APK
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: '17'

      - uses: subosito/flutter-action@v2
        with:
          channel: stable   # latest stable Flutter (Dart >= 3.13)
          cache: true

      - run: flutter --version
      - run: flutter pub get
      - run: flutter analyze
      - run: flutter test

      # Signed with the debug-key fallback for now (installable on your
      # phone for testing). Real Play signing arrives when we wire the
      # keystore secrets in the v1.0 release phase.
      - run: flutter build apk --release

      - uses: actions/upload-artifact@v4
        with:
          name: maxplayer-release-apk
          path: build/app/outputs/flutter-apk/app-release.apk
          retention-days: 14
MP_EOF__github_workflows_android-apk_yml
mkdir -p "$(dirname "scripts/connect_repo.sh")"
cat > "scripts/connect_repo.sh" <<'MP_EOF_scripts_connect_repo_sh'
#!/usr/bin/env bash
# ============================================================
#  connect_repo.sh — connect the fresh MaxPlayer project to git
#
#  Usage:
#    bash scripts/connect_repo.sh <git-remote-url>
#    bash scripts/connect_repo.sh <git-remote-url> --force-overwrite
#
#  --force-overwrite : replaces the remote's ENTIRE old history
#    with this fresh tree (what "fully clean the repo" means).
#    The old code is gone from the remote after this. If you want
#    a safety copy, tag/zip the old repo BEFORE running this.
# ============================================================
set -euo pipefail

REMOTE_URL="${1:-}"
MODE="${2:-}"

[[ -n "$REMOTE_URL" ]] || {
  echo "Usage: bash scripts/connect_repo.sh <git-remote-url> [--force-overwrite]"
  echo "Example: bash scripts/connect_repo.sh https://github.com/you/maxplayer.git"
  exit 1
}

cd "$(dirname "$0")/.."   # project root

# sanity: secrets must never be committed
if git ls-files --others --exclude-standard 2>/dev/null | grep -qE '\.jks$|key\.properties$'; then
  echo "ABORT: a .jks or key.properties is present and not gitignored."
  echo "Check .gitignore before connecting a repo."
  exit 1
fi

[[ -d .git ]] || git init
git add -A
git commit -m "v0.1: fresh start - MPV(libmpv+FFmpeg) engine, dark UI, env-var signing" \
  || echo "(nothing new to commit)"
git branch -M main

if git remote get-url origin >/dev/null 2>&1; then
  git remote set-url origin "$REMOTE_URL"
else
  git remote add origin "$REMOTE_URL"
fi

if [[ "$MODE" == "--force-overwrite" ]]; then
  echo ">> Force-pushing: old remote history will be REPLACED."
  git push --force -u origin main
else
  echo ">> Normal push (will fail if remote has old history; then re-run with --force-overwrite)."
  git push -u origin main
fi

echo "Repo connected: $REMOTE_URL (branch: main)"
MP_EOF_scripts_connect_repo_sh
mkdir -p "$(dirname "scripts/backup_keystore.sh")"
cat > "scripts/backup_keystore.sh" <<'MP_EOF_scripts_backup_keystore_sh'
#!/usr/bin/env bash
# ============================================================
#  backup_keystore.sh — export & back up your Play signing key
#
#  Backs up:
#    • the .jks keystore file
#    • key.properties (contains store/key passwords + alias)
#    • SHA-1 / SHA-256 / MD5 fingerprints (Play Console needs these)
#    • cm_keystore_base64.txt  → paste into Codemagic CM_KEYSTORE
#
#  Run from anywhere:   bash scripts/backup_keystore.sh [path/to.jks]
#  Output: ~/keystore-backup-<timestamp>/  + a tar.gz of it
# ============================================================
set -euo pipefail

STAMP="$(date +%Y%m%d-%H%M%S)"
OUT_DIR="$HOME/keystore-backup-$STAMP"
mkdir -p "$OUT_DIR"

echo "== Keystore backup =="

# ---- 1. Locate the keystore ------------------------------------------
JKS="${1:-}"
KEY_PROPS=""

find_key_properties() {
  local candidates=(
    "android/key.properties"
    "../android/key.properties"
    "$HOME/android/key.properties"
  )
  for c in "${candidates[@]}"; do
    [[ -f "$c" ]] && { KEY_PROPS="$(cd "$(dirname "$c")" && pwd)/$(basename "$c")"; return 0; }
  done
  return 1
}

if [[ -z "$JKS" ]]; then
  if find_key_properties; then
    echo "Found key.properties: $KEY_PROPS"
    STORE_FILE_PROP="$(grep -E '^storeFile=' "$KEY_PROPS" | cut -d= -f2- || true)"
    if [[ -n "${STORE_FILE_PROP:-}" ]]; then
      CAND="$(dirname "$KEY_PROPS")/app/$STORE_FILE_PROP"
      [[ -f "$CAND" ]] && JKS="$CAND"
    fi
  fi
fi

if [[ -z "$JKS" ]]; then
  # last resort: common locations
  for c in android/app/*.jks android/*.jks "$HOME"/*.jks; do
    [[ -f "$c" ]] && { JKS="$c"; break; }
  done
fi

[[ -f "${JKS:-}" ]] || {
  echo "ERROR: no .jks found. Pass it explicitly:"
  echo "  bash scripts/backup_keystore.sh /full/path/upload-keystore.jks"
  exit 1
}
JKS="$(cd "$(dirname "$JKS")" && pwd)/$(basename "$JKS")"
echo "Keystore: $JKS"

# ---- 2. Pull credentials (never echoed) -------------------------------
STORE_PASS=""; KEY_ALIAS=""; KEY_PASS=""
if [[ -n "$KEY_PROPS" ]]; then
  STORE_PASS="$(grep -E '^storePassword=' "$KEY_PROPS" | cut -d= -f2- || true)"
  KEY_ALIAS="$(grep -E '^keyAlias='       "$KEY_PROPS" | cut -d= -f2- || true)"
  KEY_PASS="$(grep -E '^keyPassword='     "$KEY_PROPS" | cut -d= -f2- || true)"
fi
if [[ -z "$STORE_PASS" ]]; then
  read -rsp "Keystore store password: " STORE_PASS; echo
fi
if [[ -z "$KEY_ALIAS" ]]; then
  read -rp  "Key alias: " KEY_ALIAS
fi

# ---- 3. Verify the keystore + capture fingerprints ---------------------
echo "Verifying keystore integrity..."
if command -v keytool >/dev/null 2>&1; then
  keytool -list -v -keystore "$JKS" -storepass "$STORE_PASS" -alias "$KEY_ALIAS" \
    > "$OUT_DIR/keytool_listing.txt" 2>/dev/null || {
      echo "ERROR: keytool rejected the keystore/password/alias — backup aborted."
      exit 1
    }
  grep -E "SHA1:|SHA256:|MD5:" "$OUT_DIR/keytool_listing.txt" \
    > "$OUT_DIR/fingerprints.txt" || true
  echo "Fingerprints saved to fingerprints.txt"
else
  echo "WARNING: keytool not found — skipping verification & fingerprints"
fi

# ---- 4. Copy artifacts -------------------------------------------------
cp "$JKS" "$OUT_DIR/upload-keystore.jks"
[[ -n "$KEY_PROPS" ]] && cp "$KEY_PROPS" "$OUT_DIR/key.properties" || {
  cat > "$OUT_DIR/key.properties" <<EOF
storePassword=$STORE_PASS
keyPassword=$KEY_PASS
keyAlias=$KEY_ALIAS
storeFile=upload-keystore.jks
EOF
}

# base64 for Codemagic CM_KEYSTORE env var
base64 -i "$JKS" > "$OUT_DIR/cm_keystore_base64.txt" 2>/dev/null \
  || base64 "$JKS" > "$OUT_DIR/cm_keystore_base64.txt"
chmod 600 "$OUT_DIR"/*

cat > "$OUT_DIR/README_RESTORE.txt" <<'EOF'
RESTORE INSTRUCTIONS
====================
1. Put upload-keystore.jks into:  <project>/android/app/upload-keystore.jks
2. Put key.properties      into:  <project>/android/key.properties
   (keys: storePassword, keyPassword, keyAlias, storeFile)
3. Codemagic: upload these env vars in group "keystore_credentials":
     CM_KEYSTORE          = contents of cm_keystore_base64.txt
     CM_KEYSTORE_PASSWORD = storePassword
     CM_KEY_ALIAS         = keyAlias
     CM_KEY_ALIAS_PASSWORD= keyPassword
4. Keep fingerprints.txt — Play Console app signing page needs the
   SHA-1 / SHA-256 if you ever re-enroll or add API credentials.
NEVER commit the .jks or key.properties to git. Store this folder
(or the tar.gz) in at least TWO safe places (drive + offline).
EOF

# ---- 5. Pack it ---------------------------------------------------------
TARBALL="$HOME/keystore-backup-$STAMP.tar.gz"
tar -czf "$TARBALL" -C "$HOME" "$(basename "$OUT_DIR")"
chmod 600 "$TARBALL"

echo
echo "DONE."
echo "  Folder : $OUT_DIR"
echo "  Tarball: $TARBALL"
echo
echo "Next:"
echo "  1. Copy cm_keystore_base64.txt content into Codemagic CM_KEYSTORE"
echo "  2. Move the tarball to cloud drive + an offline disk"
echo "  3. Test restore once: keytool -list -keystore <restored.jks>"
MP_EOF_scripts_backup_keystore_sh
echo ">> Gitignore safety net ..."
for line in "android/key.properties" "**/*.jks" "**/*.keystore" ".env"; do
  grep -qxF "$line" .gitignore 2>/dev/null || echo "$line" >> .gitignore
done
chmod +x scripts/*.sh
rm -f pubspec.lock   # let YOUR Flutter resolve compatible versions
echo ">> Resolving packages ..."
flutter pub get
echo ">> Analyzer ..."
if dart analyze; then
  echo
  echo "==============================================="
  echo "  v1 applied cleanly."
  echo "  Next:"
  echo "    flutter run --release        # phone test"
  echo "    bash scripts/connect_repo.sh <repo-url>"
  echo "  Then every git push builds an APK on GitHub"
  echo "  (Actions tab -> Artifacts -> download)."
  echo "==============================================="
else
  echo "v1 applied but analyzer reported issues - paste them in chat."
  exit 1
fi
