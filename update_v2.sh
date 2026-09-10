#!/usr/bin/env bash
# ============================================================
#  update_v2.sh — MaxPlayer v0.3.0+3: RESUME
#
#  Resume-from-where-you-left, survives process kill:
#    • position saved per video every 5s, on pause, on app
#      background, and on close
#    • reopening mid-video asks "Resume from 12:34?"
#      (Start over clears the saved point)
#    • finishing a video clears its point - replays start fresh
#    • 9 new pin tests (19 total)
#
#  USAGE (in the project folder that already has v1 applied):
#    bash update_v2.sh
#    git add -A && git commit -m "v0.3: resume" && git push
#    -> GitHub Actions builds the new APK automatically
# ============================================================
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
[ -f pubspec.yaml ] || { echo "ERROR: no project here - apply update_v1.sh first."; exit 1; }
echo ">> Writing v0.3 files ..."
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
version: 0.3.0+3

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
mkdir -p "$(dirname "lib/utils/resume.dart")"
cat > "lib/utils/resume.dart" <<'MP_EOF_lib_utils_resume_dart'
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

const _kResumeKey = 'resume.positions.v1';
const minPromptMs = 10000; // positions under 10s: not worth prompting
const endMarginMs = 10000; // last 10s of a video counts as "finished"

/// Pure resume decision (unit-tested).
///
/// Returns the position to offer resuming at, or null to start from 0.
/// [savedMs] was persisted earlier; [durationMs] may be 0 when unknown.
int? resumeTargetMs(int savedMs, int durationMs) {
  if (savedMs < minPromptMs) return null;
  if (durationMs > 0 && savedMs > durationMs - endMarginMs) return null;
  return savedMs;
}

/// Pure finish check (unit-tested): position within the end margin?
bool isFinishedMs(int posMs, int durationMs) {
  return durationMs > 0 && posMs > durationMs - endMarginMs;
}

/// Per-path last-watch positions, persisted in shared_preferences as a
/// JSON map. Survives process kill (written periodically + on pause +
/// on background + on player dispose).
class ResumeStore {
  Future<Map<String, int>> _readAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kResumeKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return map.map((k, v) => MapEntry(k, (v as num).toInt()));
    } catch (_) {
      return {}; // corrupt blob -> start empty, never crash
    }
  }

  Future<int?> readMs(String path) async => (await _readAll())[path];

  Future<void> writeMs(String path, int ms) async {
    final prefs = await SharedPreferences.getInstance();
    final all = await _readAll();
    all[path] = ms;
    await prefs.setString(_kResumeKey, jsonEncode(all));
  }

  Future<void> clear(String path) async {
    final prefs = await SharedPreferences.getInstance();
    final all = await _readAll()..remove(path);
    await prefs.setString(_kResumeKey, jsonEncode(all));
  }
}
MP_EOF_lib_utils_resume_dart
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
import '../utils/resume.dart';

/// Single-engine player: MPV (libmpv + FFmpeg) via media_kit.
///
/// v0.2 gestures:
///   • single tap          → show/hide controls
///   • double tap L/R      → seek −10s / +10s (with flash indicator)
///   • long press hold     → 2× speed, release restores 1×
///   • wakelock held while playing
///
/// v0.3 resume: position saved per video every 5s, on pause, on app
/// background, and on close — survives process kill. Reopening a video
/// mid-way offers "Resume from 12:34?" (start-over clears it). Watching
/// to the end clears the saved point so replays start fresh.
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

class _PlayerScreenState extends State<PlayerScreen>
    with WidgetsBindingObserver {
  static const _seekStepSecs = 10;
  static const _boostRate = 2.0;
  static const _saveInterval = Duration(seconds: 5);

  late final Player _player;
  late final VideoController _controller;
  final ResumeStore _resume = ResumeStore();
  StreamSubscription<bool>? _playingSub;

  bool _ready = false;
  bool _failed = false;
  bool _controlsVisible = true;
  bool _boost = false;
  int? _seekFlash; // +N or -N seconds, shown briefly
  bool _seekFlashLeft = false;
  Timer? _hideTimer;
  Timer? _flashTimer;
  Timer? _saveTimer;

  // ---------------- lifecycle ----------------

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
        unawaited(_savePosition()); // pausing persists the spot
      }
    });
    _saveTimer = Timer.periodic(_saveInterval, (_) => _savePosition());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      unawaited(_savePosition()); // going to background persists the spot
    }
  }

  Future<void> _open() async {
    CrashLog.crumb('player.open', {'path': widget.path});
    try {
      await _player.open(Media(widget.path), play: true);
      // MPV reports hard failures asynchronously through the error stream.
      _player.stream.error.listen(_onError);
      if (mounted) setState(() => _ready = true);
      unawaited(_offerResume());
    } catch (e) {
      _onError(e);
    }
  }

  // ---------------- resume ----------------

  Future<void> _offerResume() async {
    try {
      final saved = await _resume.readMs(widget.path);
      if (saved == null || !mounted) return;
      var dur = _player.state.duration;
      if (dur <= Duration.zero) {
        dur = await _player.stream.duration
            .firstWhere((d) => d > Duration.zero)
            .timeout(const Duration(seconds: 5),
                onTimeout: () => Duration.zero);
      }
      final targetMs = resumeTargetMs(saved, dur.inMilliseconds);
      if (targetMs == null || !mounted) return;
      CrashLog.crumb('resume.offer', {'path': widget.path, 'ms': targetMs});
      final resume = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppColors.border),
          ),
          title: const Text('Resume playback?',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 17)),
          content: Text(
            'Continue from ${formatDuration(Duration(milliseconds: targetMs))}?',
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Start over',
                  style: TextStyle(color: AppColors.textSecondary)),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accent,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Resume'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (resume == true) {
        _player.seek(Duration(milliseconds: targetMs));
        CrashLog.crumb('resume.accepted', {'ms': targetMs});
      } else if (resume == false) {
        await _resume.clear(widget.path);
        CrashLog.crumb('resume.declined', {'path': widget.path});
      }
    } catch (e) {
      CrashLog.error('resume.offer_failed', e, {'path': widget.path});
    }
  }

  Future<void> _savePosition() async {
    if (!_ready || _failed) return;
    try {
      final pos = _player.state.position;
      final dur = _player.state.duration;
      if (pos <= Duration.zero) return;
      if (isFinishedMs(pos.inMilliseconds, dur.inMilliseconds)) {
        await _resume.clear(widget.path); // finished → replay starts fresh
        return;
      }
      await _resume.writeMs(widget.path, pos.inMilliseconds);
    } catch (e) {
      CrashLog.error('resume.save_failed', e, {'path': widget.path});
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
    _saveTimer?.cancel();
    _playingSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    WakelockPlus.disable();
    unawaited(_savePosition()); // closing persists the spot
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
import 'package:maxplayer/utils/resume.dart';

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

  group('resumeTargetMs (v0.3 resume)', () {
    test('under 10s saved -> no prompt', () {
      expect(resumeTargetMs(5000, 600000), isNull);
    });
    test('boundary: exactly 10s saved -> prompt', () {
      expect(resumeTargetMs(minPromptMs, 600000), minPromptMs);
    });
    test('mid-video -> prompt at saved spot', () {
      expect(resumeTargetMs(754000, 3600000), 754000);
    });
    test('inside end margin -> treated as finished, no prompt', () {
      expect(resumeTargetMs(3600000 - endMarginMs + 1, 3600000), isNull);
    });
    test('just outside end margin -> prompt', () {
      expect(resumeTargetMs(3600000 - endMarginMs, 3600000),
          3600000 - endMarginMs);
    });
    test('unknown duration (0) -> prompt for big save', () {
      expect(resumeTargetMs(60000, 0), 60000);
    });
  });

  group('isFinishedMs (v0.3 resume)', () {
    test('near end -> finished', () {
      expect(isFinishedMs(3595000, 3600000), isTrue);
    });
    test('mid -> not finished', () {
      expect(isFinishedMs(1800000, 3600000), isFalse);
    });
    test('unknown duration -> not finished', () {
      expect(isFinishedMs(999999, 0), isFalse);
    });
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
echo ">> Resolving packages ..."
flutter pub get > /dev/null
echo ">> Analyzer ..."
if dart analyze; then
  echo
  echo "==============================================="
  echo "  v0.3 applied cleanly (resume)."
  echo "  Ship the APK:"
  echo "    git add -A"
  echo "    git commit -m \"v0.3: resume\""
  echo "    git push"
  echo "  -> Actions tab -> Artifacts -> new APK"
  echo "==============================================="
else
  echo "v0.3 applied but analyzer reported issues - paste them in chat."
  exit 1
fi
