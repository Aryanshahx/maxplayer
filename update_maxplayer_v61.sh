#!/usr/bin/env bash
# =============================================================================
#  Max Player  -  v61  (1.0.0+57)
#  "toggle OFF = fit loop (never zooms); toggle ON = free zoom (works now);
#   one Languages line; every filter keeps loading pages automatically"
#
#  Run this from the repo root:   bash update_maxplayer_v61.sh
#  (It is idempotent - run it twice; both runs must end "N/N checks OK".)
#
#  v61 changes (only these 6 files, minimal targeted diffs):
#   1. GESTURE TOGGLE SEMANTICS (rewrite, not retune)
#      - lib/state/video_zoom.dart : removed the v59/v60 continuous ladder
#        that hid zoom at the END behind a ~2.6x spread (why "zoom still not
#        working"). New pure helpers:
#          * fitLadderPosFor(basePos, scale) -> unbounded ladder position
#          * wrapFitLadderPos(pos, fitCount) -> 0..n-1 with wrap-around
#            (Original -> Fit loops)
#          * freeZoomFor(baseZoom, scale) -> clamp(base*scale, 1x..4x)
#      - lib/screens/player_screen.dart : two-finger branch now does ONE thing
#        per mode:
#          * twoFingerMode == 'fit' (toggle OFF): spread/pinch cycles the 6
#            fits in a LOOP, wrap-around, zoom is FORCED to 1.0 (never zooms);
#          * twoFingerMode == 'zoom' (toggle ON): pinch = direct free zoom
#            1.0x..4.0x from the first millimetre (map-app style), no ladder;
#            a quick two-finger tap still resets to 1.0x.
#   2. DUPLICATE LANGUAGES in the movie/series detail sheet
#      - lib/widgets/movie_detail_sheet.dart : removed the bloated
#        "Languages supported (N)" chip wrap (it listed every TMDB
#        *translation* language - often 30+). The single concise
#        "Languages: English - Hindi" spoken-audio line stays. Cast, watch
#        providers, reviews and seasons are untouched.
#   3. INFINITE CONTENT IN EVERY FILTER
#      - lib/screens/discover_screen.dart : v60's single post-frame
#        _maybeLoadMore() only pulled ONE extra page. Now after EVERY page
#        lands a chained auto-fill (_scheduleEndlessFill) keeps fetching
#        until the grid fills the viewport / is scrollable or a 5-page
#        burst cap is hit; the scroll listener at maxScrollExtent-350 then
#        pages forever. Per-filter token + in-flight guard prevent
#        duplicate requests. Cached first paint is unchanged.
#   4. test/widget_test.dart : old v60 ladder test replaced with 3 v61
#      tests (fit loop never zooms + wraps Original->Fit; free-zoom map
#      clamps at 4.0x). 145 tests total.
#   5. pubspec.yaml : 1.0.0+56 -> 1.0.0+57  (kAppVersion stays 1.0.0).
#
#  OUT OF SCOPE / UNTOUCHED (do not re-litigate): hwdec blacklist + GLES2
#  degrade, PiP, sleep timer, sub-delay, subtitle translation, Chromecast,
#  Play Store prep, monetization, the low-end plan cache/thumb sections.
#
#  AFTER IT PRINTS "N/N checks OK":
#     git add -A && git commit -m "v61: fit-loop vs free-zoom toggle, single
#     Languages line, endless discover paging (1.0.0+57)" && git push
#  Codemagic builds the APK/AAB. Install and phone-test (checklist at end).
#
#  RUN AS-IS. Do not hand-edit files before pushing.
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")"
echo "============================================================"
echo " Max Player v61 (1.0.0+57) update"
echo " Running from: $(pwd)"
echo "============================================================"
mkdir -p "$(dirname "lib/state/video_zoom.dart")"
cat > "lib/state/video_zoom.dart" <<'MAXV61_EOF_VIDEO_ZOOM_DART'
/// Pure pinch-zoom + fit-ladder math shared by the player screen and unit
/// tests.
library;

import 'dart:math' as math;

/// Pinch range: 1.0 = fit screen (the DEFAULT), up to 4x zoomed in.
const double kMinVideoZoom = 1.0;
const double kMaxVideoZoom = 4.0;

/// Keeps a pinch result inside [kMinVideoZoom]..[kMaxVideoZoom].
double clampVideoZoom(double v) => v.clamp(kMinVideoZoom, kMaxVideoZoom);

/// A quick two-finger TAP (both fingers down and up fast, with no real
/// pinch movement) means "snap back to fit screen" - the gesture MX/VLC
/// users expect. Anything with genuine scale change or long travel is a
/// real pinch, not a tap.
bool isTwoFingerTapReset({
  required int durationMs,
  required double travelPx,
  required bool scaled,
}) =>
    !scaled && travelPx < 24 && durationMs <= 400;

/// v61 (user's final design, after phone-testing v59/v60): what a finished
/// two-finger gesture does depends ONLY on whether it was a quick tap.
///
///   - a quick two-finger TAP always snaps back to the default fit screen
///     (so you are never stuck zoomed in / on a weird fit);
///   - a real pinch is NEVER undone - the player keeps whatever fit/zoom
///     the fingers landed on.
///
/// Works identically in BOTH toggle modes ('fit' loop and 'zoom' free
/// zoom). Legacy/unknown stored values conservatively snap home.
bool twoFingerSnapsToFit({required String mode, required bool wasTap}) {
  if (mode == 'fit' || mode == 'zoom') return wasTap;
  return true; // legacy/unknown stored value
}

// ---------------------------------------------------------------------------
// v61 THE TWO-FINGER TOGGLE - "when toggle is off then only fit screens in
// loop; when toggle is on then only zoom". The old v59/v60 continuous
// ladder (Fit -> ... -> Original -> smooth ZOOM) is GONE: it buried zoom at
// the top behind a ~2.6x spread, so on a real phone zoom was effectively
// unreachable. Now the two modes are cleanly separate:
//
//   TOGGLE OFF ('fit'): a spread walks the six fit modes in a LOOP -
//     Fit -> Crop -> Stretch -> 16:9 -> 4:3 -> Original -> back to Fit ->
//     ... and a pinch walks back down the same loop. It NEVER zooms
//     (zoom stays exactly 1.0 the whole time).
//
//   TOGGLE ON ('zoom'): a pinch does ONLY free zoom, 1.0x..4.0x, exactly
//     like a map app: zoom = clamp(baseZoom * scale). No fit cycling at
//     all. A quick two-finger tap resets to 1.0x.
// ---------------------------------------------------------------------------

/// Spreading the fingers by this factor climbs exactly ONE fit step in the
/// toggle-OFF loop. Kept moderate so all six fits are reachable inside a
/// normal phone pinch; the wrap-around means a firm spread just loops.
const double kFitLadderStepScale = 1.20;

double _log2(double v) => math.log(v) / math.ln2;

/// v61 toggle-OFF: maps a live pinch [scale] to a fit-ladder position,
/// given the [basePos] (integer fit index) captured when the fingers
/// landed. The position is UNBOUNDED on purpose - callers wrap it with
/// [wrapFitLadderPos] so the ladder loops Original -> Fit. Pure for tests.
double fitLadderPosFor({
  required double basePos,
  required double scale,
}) {
  if (scale <= 0) return basePos;
  return basePos + _log2(scale) / _log2(kFitLadderStepScale);
}

/// Wraps an unbounded ladder position into 0..[fitCount]-1 with
/// wrap-around (pos fitCount wraps back to 0; pos -1 wraps to
/// fitCount-1). This is what makes Original -> Fit loop.
int wrapFitLadderPos(double pos, int fitCount) {
  if (fitCount <= 0) return 0;
  var rounded = pos.round();
  rounded = rounded % fitCount;
  if (rounded < 0) rounded += fitCount;
  return rounded;
}

/// v61 toggle-ON: the direct free-zoom map. Zoom = the zoom level captured
/// when the fingers landed ([baseZoom]) times the live pinch [scale],
/// clamped to 1.0x..4.0x. This is the whole map-app behavior in one line;
/// it makes zoom work from the FIRST millimetre of the pinch instead of
/// being hidden at the top of a ladder.
double freeZoomFor({
  required double baseZoom,
  required double scale,
}) =>
    clampVideoZoom(baseZoom * scale);
MAXV61_EOF_VIDEO_ZOOM_DART
echo "  wrote lib/state/video_zoom.dart"
mkdir -p "$(dirname "lib/screens/player_screen.dart")"
cat > "lib/screens/player_screen.dart" <<'MAXV61_EOF_PLAYER_SCREEN_DART'
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../cast/cast_state.dart';
import '../services/native_bridge.dart';
import '../state/media_player_state.dart';
import '../state/player_settings.dart';
import '../state/video_zoom.dart';
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

/// v41: which Android system-UI mode the player should show right now.
///
/// Report: "when we play video the upper side time, notification bar and
/// on the right side back, home, buttons are showing as black bar - these
/// are not removed". The bars were only hidden when the user pressed the
/// fullscreen BUTTON; simply ROTATING the phone (the normal way people
/// watch) left the status bar and the back/home navigation buttons
/// painted as black bars.
///
/// New rule (VLC / MX Player behavior): the video gets the whole screen
/// whenever it has real room - MANUAL fullscreen OR landscape; portrait
/// portrait keeps the bars so the time and notifications stay visible.
/// Top-level + pure so the widget test can pin all four combinations.
SystemUiMode playerSystemUiModeFor({
  required bool fullscreen,
  required bool landscape,
}) =>
    (fullscreen || landscape)
        ? SystemUiMode.immersiveSticky
        : SystemUiMode.edgeToEdge;

/// v44: what to restore when LEAVING the player. v41 restored
/// edgeToEdge, which keeps the window laid out UNDER the status bar -
/// back in the library the status bar sat ON TOP of the app content
/// (the overlap bug). Manual mode with both overlays = the normal,
/// never-overlapping Android layout.
const SystemUiMode playerRestoreSystemUiMode = SystemUiMode.manual;

/// v44: both bars (status + navigation) must be back after the player.
const List<SystemUiOverlay> playerRestoreOverlays = SystemUiOverlay.values;

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

  // v52: two-finger TAP = snap back to fit screen. We measure the pinch
  // gesture's total travel / whether any real scaling happened.
  // v61: the fit LOOP's anchor - which fit index was showing when the two
  // fingers landed (see video_zoom.dart). The loop never zooms.
  int _ladderBaseIndex = 0;
  int _scaleStartMs = 0;
  double _pinchTravelPx = 0;
  bool _pinchScaled = false;
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
        if (!mounted) return;
        setState(() => _isPip = isPip);
        // v41: re-assert the bars after a PiP round-trip (while in PiP the
        // OS owns the system UI; coming back must not leave bars stuck on
        // top of a landscape video).
        _syncSystemUiMode();
      },
    );
    _reloadSettings();
    widget.player.currentBrightness(); // sync once for the swipe gesture
    widget.player.currentVolume(); // start swipe from REAL device volume
    _startHideTimer();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // v41: MediaQuery changes - in particular the phone ROTATING - land
    // here because build() reads MediaQuery.of(context).orientation. This
    // is the fix for "black bars are not removed when playing video":
    // hiding the bars was wired ONLY to the fullscreen button, never to
    // simply holding the phone sideways.
    _syncSystemUiMode();
  }

  /// v41: THE one spot that decides the bars (status bar + back/home
  /// buttons): hidden while the video has real room (manual fullscreen OR
  /// landscape), restored in portrait so the time/notifications stay
  /// visible. Idempotent, so every lifecycle hook can re-assert it.
  void _syncSystemUiMode() {
    if (!mounted) return;
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    SystemChrome.setEnabledSystemUIMode(
      playerSystemUiModeFor(fullscreen: _isFullscreen, landscape: landscape),
    );
  }

  @override
  void dispose() {
    _castState.dispose(); // stops casting + the embedded file server
    WidgetsBinding.instance.removeObserver(this);
    _hideTimer?.cancel();
    _indicatorTimer?.cancel();
    _noticeSub?.cancel();
    // v41: ALWAYS bring the bars back on the way out - landscape playback
    // now hides them even when manual fullscreen was never pressed, so the
    // old `if (_isFullscreen)` guard could leave the LIBRARY screen
    // without a status bar / back button after just rotating the phone.
    // v44: manual overlays (edgeToEdge overlapped the library's
    // status bar when coming back from the player).
    SystemChrome.setEnabledSystemUIMode(
      playerRestoreSystemUiMode,
      overlays: playerRestoreOverlays,
    );
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
    if (mounted) {
      setState(() {
        _settings = s;
        // v52: start every session in the fit mode chosen in Settings
        // (default: fit screen). In-session cycling still works.
        _fitIndex = s.defaultFitIndex.clamp(0, _fits.length - 1);
      });
    }
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
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      _syncSystemUiMode(); // v41: one decision point for the bars
    } else {
      _exitFullscreen();
    }
    _onUserInteraction();
  }

  void _exitFullscreen() {
    // v41: restore the bars per the CURRENT orientation (leaving fullscreen
    // while the phone is still sideways keeps them hidden - landscape is
    // full-bleed now; rotating back to portrait brings them back via
    // didChangeDependencies). From dispose() `context` is off-limits, so
    // restore them unconditionally there.
    if (mounted) {
      _syncSystemUiMode();
    } else {
      // v44: from dispose() - manual overlays, never edgeToEdge.
      SystemChrome.setEnabledSystemUIMode(
        playerRestoreSystemUiMode,
        overlays: playerRestoreOverlays,
      );
    }
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

  /// v60: forces the 16:9 / 4:3 FRAME inside the screen like VLC's
  /// resize button (Center + AspectRatio, engine-independent, identical
  /// in landscape and portrait). Other fit modes pass straight through.
  Widget _fitFrame({required Widget child}) {
    final asp = _fitAspects[_fitIndex];
    if (asp == null) return child;
    return Center(child: AspectRatio(aspectRatio: asp, child: child));
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
    _scaleStartMs = DateTime.now().millisecondsSinceEpoch;
    _pinchTravelPx = 0;
    _pinchScaled = false;
    // v61: the fit LOOP starts from whatever fit is currently showing.
    _ladderBaseIndex = _fitIndex;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    // Two+ fingers -> pinch zoom (focal-anchored).
    if (details.pointerCount >= 2) {
      _scaleMode = _ScaleMode.zoom;
      _pinchTravelPx += details.focalPointDelta.distance;
      if ((details.scale - 1.0).abs() > 0.05) _pinchScaled = true;
      // v61 (user's final design): the two-finger toggle does ONE thing,
      // never both:
      //
      //   TOGGLE OFF ('fit') -> two fingers cycle the fit modes in a
      //     LOOP (Fit -> Crop -> Stretch -> 16:9 -> 4:3 -> Original ->
      //     back to Fit ...). It NEVER zooms - zoom stays at 1.0x the
      //     whole time. A quick two-finger tap still snaps home.
      //
      //   TOGGLE ON ('zoom') -> two fingers do ONLY free zoom, 1.0x..4x,
      //     from the FIRST millimetre of the pinch (zoom = clamp(baseZoom
      //     * scale)), exactly like a map app. The fit never changes.
      //
      // The old v59/v60 continuous ladder put zoom at the END behind a
      // ~2.6x spread, which is why on a real phone "zoom is not working".
      if (_settings.twoFingerMode == 'fit') {
        final pos = fitLadderPosFor(
            basePos: _ladderBaseIndex.toDouble(), scale: details.scale);
        final nextIndex = wrapFitLadderPos(pos, _fits.length);
        if (nextIndex != _fitIndex) {
          setState(() {
            _fitIndex = nextIndex;
            // The fit loop never zooms - keep any stray zoom/pan reset so
            // the frame stays exactly the chosen fit.
            _zoom = kMinVideoZoom;
            _pan = Offset.zero;
          });
          _showIndicator('Fit: ${_fitNames[nextIndex]}', _fitIcons[nextIndex]);
        }
        return;
      }
      // TOGGLE ON: pure free zoom, no fit cycling, no ladder.

      // Focal-anchored transform: the content point that was under the
      // fingers when the pinch started stays glued to the CURRENT focal
      // point. Because we track the live focal point, moving both fingers
      // together pans the zoomed video for free.
      final z = freeZoomFor(baseZoom: _zoomBase, scale: details.scale);
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
    // v59: a finished two-finger gesture snaps home ONLY on a quick
    // tap - the expand ladder keeps the fit/zoom your pinch landed on
    // (this is what "zooming is not working" meant: don't undo it!).
    if (mode == _ScaleMode.zoom &&
        twoFingerSnapsToFit(
          mode: _settings.twoFingerMode,
          wasTap: isTwoFingerTapReset(
            durationMs:
                DateTime.now().millisecondsSinceEpoch - _scaleStartMs,
            travelPx: _pinchTravelPx,
            scaled: _pinchScaled,
          ),
        )) {
      _resetToFitScreen();
      return;
    }
    if (mode == _ScaleMode.zoom && _settings.twoFingerMode != 'zoom' &&
        !_settings.pinchZoom) {
      return;
    }
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

  /// v52: two-finger tap target - back to the user's default fit mode
  /// ("fit screen" out of the box) with any pinch zoom/pan undone.
  void _resetToFitScreen() {
    final fit = _settings.defaultFitIndex.clamp(0, _fits.length - 1);
    if (_zoom != 1.0 || _pan != Offset.zero || _fitIndex != fit) {
      setState(() {
        _zoom = 1.0;
        _pan = Offset.zero;
        _fitIndex = fit;
      });
    }
    _showIndicator('Fit: ${_fitNames[fit]}', _fitIcons[fit]);
    _onUserInteraction();
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
                                          // v40: karaoke now lives INSIDE a
                                          // Stack sized to the video's own
                                          // box, at the exact spot mpv's
                                          // subtitle renderer uses
                                          // (SubtitleView: bottom-center,
                                          // 24px above the video edge) -
                                          // requested: "when we enable
                                          // karaoke subtitle then show it at
                                          // the exact place of default or AI
                                          // generated subtitle". Before, it
                                          // floated 120px above the SCREEN
                                          // bottom, near the seek bar.
                                          child: Stack(
                                            children: [
                                              // v60 (user: "fit button does
                                              // not resize like VLC"): the
                                              // 16:9 / 4:3 modes force the
                                              // FRAME inside the screen with
                                              // OUR OWN Center+AspectRatio
                                              // wrapper - engine-independent,
                                              // identical in landscape and
                                              // portrait on every build.
                                              _fitFrame(
                                                child: Video(
                                                  controller: _controller,
                                                  controls: NoVideoControls,
                                                  fit: _fits[_fitIndex],
                                                  aspectRatio: null,
                                                // v26/v27: karaoke <=>
                                                // normal subtitles. The
                                                // engine's own Flutter
                                                // subtitle layer IS the
                                                // normal subtitle display on
                                                // Android (this mpv build
                                                // does not paint subs into
                                                // the video frame) - so it
                                                // must be ON for normal
                                                // playback and OFF only
                                                // while karaoke is on (v26:
                                                // it ignored mpv's hide flag
                                                // and drew next to karaoke;
                                                // v27: fully hiding it also
                                                // hid the normal subs).
                                                subtitleViewConfiguration:
                                                    SubtitleViewConfiguration(
                                                      visible: !_settings
                                                          .karaokeSubs,
                                                    ),
                                                  ),
                                              ),
                                              if (_settings.karaokeSubs &&
                                                  !_isPip)
                                                Positioned(
                                                  left: 0,
                                                  right: 0,
                                                  bottom: 24,
                                                  child: KaraokeSubtitle(
                                                    player: widget.player,
                                                  ),
                                                ),
                                            ],
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
                          // v21-v39 the karaoke overlay lived here, pinned
                          // 120px above the screen bottom. v40 moved it
                          // INTO the video's own box at the exact subtitle
                          // spot (see the Stack around the Video widget).
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
MAXV61_EOF_PLAYER_SCREEN_DART
echo "  wrote lib/screens/player_screen.dart"
mkdir -p "$(dirname "lib/widgets/movie_detail_sheet.dart")"
cat > "lib/widgets/movie_detail_sheet.dart" <<'MAXV61_EOF_MOVIE_DETAIL_SHEET_DART'
import 'dart:io';

import 'package:flutter/material.dart';

import '../models/video_track.dart';
import '../screens/player_screen.dart';
import '../services/native_bridge.dart';
import '../services/tmdb_client.dart';
import '../state/media_player_state.dart';
import '../state/theme_state.dart';
import '../services/subtitle_langs.dart';
import 'ask_ai_sheet.dart';
import 'tmdb_image.dart';

/// v44: the Discover detail sheet - poster, TMDB rating (with credit),
/// and now the FULL story: tagline, runtime, genres, director, cast,
/// vote count, plus the same two actions:
///
///  - "Watch trailer on YouTube": opens the official YouTube app on the
///    trailer (Play-policy-safe; we never stream YouTube in-app).
///  - "In my library": shown ONLY when the movie is already on the phone -
///    then Max Player plays it instantly, offline.
///
/// DraggableScrollableSheet like every other sheet since v35 (landscape
/// safe, every control stays reachable).
class MovieDetailSheet extends StatefulWidget {
  final TmdbMovie movie;
  final VideoTrack? localMatch;
  final MediaPlayerState player;

  /// Lazily resolves trailer + extras in ONE call (detail is cached 24h).
  final Future<TmdbFull?> Function() detailLoader;

  const MovieDetailSheet({
    super.key,
    required this.movie,
    required this.localMatch,
    required this.player,
    required this.detailLoader,
  });

  static Future<void> show(
    BuildContext context, {
    required TmdbMovie movie,
    required VideoTrack? localMatch,
    required MediaPlayerState player,
    required Future<TmdbFull?> Function() detailLoader,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1a1a24),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.62,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (_, controller) => SingleChildScrollView(
          controller: controller,
          child: MovieDetailSheet(
            movie: movie,
            localMatch: localMatch,
            player: player,
            detailLoader: detailLoader,
          ),
        ),
      ),
    );
  }

  @override
  State<MovieDetailSheet> createState() => _MovieDetailSheetState();
}

class _MovieDetailSheetState extends State<MovieDetailSheet> {
  // Fired once - never inside build(), so no refetch on every rebuild.
  // v45: NOT final - a failed load (was common on slow networks) now has
  // a visible Retry instead of needing sheet close/open rounds.
  late Future<TmdbFull?> _detailFuture = widget.detailLoader();

  void _retryDetail() {
    setState(() {
      _detailFuture = widget.detailLoader();
    });
  }

  Future<void> _playLocal(BuildContext context) async {
    final track = widget.localMatch;
    if (track == null) return;
    await widget.player.setPlaylistAndPlay([track], 0);
    if (!context.mounted) return;
    Navigator.of(context).pop();
    Navigator.of(context).push(
      MaterialPageRoute(
          builder: (_) => PlayerScreen(player: widget.player)),
    );
  }

  Future<void> _openTrailer(String key) async {
    final ok = await NativeBridge.openYouTube(key);
    if (!ok) {
      // Exceptionally rare (no browser?!) - keep it silent, the button
      // simply does nothing visible instead of crashing the sheet.
    }
  }

  @override
  Widget build(BuildContext context) {
    final movie = widget.movie;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 110,
                height: 165,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: TmdbImage(
                      url: tmdbPosterUrl(movie.posterPath, big: true)),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      movie.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      [
                        if (movie.year != null) '${movie.year}',
                        '⭐ ${tmdbRatingText(movie.rating)} / 10',
                      ].join('  ·  '),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Rating & data: TMDB',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.35),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          // v44: the extra facts arrive with the trailer lookup (one call).
          // v45: that same call also brings the screenshots row, and a
          // failure offers Retry instead of a dead sheet.
          FutureBuilder<TmdbFull?>(
            future: _detailFuture,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'Loading details...',
                    style: TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                );
              }
              final full = snap.data;
              if (full == null) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Details could not load (network was busy).',
                          style:
                              TextStyle(color: Colors.white38, fontSize: 12),
                        ),
                      ),
                      TextButton(
                        onPressed: _retryDetail,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (full.screenshots.isNotEmpty)
                    _ScreenshotsRow(paths: full.screenshots),
                  _ExtrasBlock(extras: full.extras),
                  // v59 (user): web series must mention ALL their parts.
                  if (full.seasons.isNotEmpty)
                    _SeasonsBlock(seasons: full.seasons),
                  if (!full.watch.isEmpty) _WatchBlock(info: full.watch),
                  _AllDataBlock(extras: full.extras, movieId: movie.id),
                ],
              );
            },
          ),
          if (movie.overview.isNotEmpty)
            Text(
              movie.overview,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
                height: 1.5,
              ),
            )
          else
            Text(
              'No story summary available for this movie yet.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 13,
                height: 1.5,
              ),
            ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FutureBuilder<TmdbFull?>(
              future: _detailFuture,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return OutlinedButton.icon(
                    onPressed: null,
                    icon: const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    label: const Text('Finding trailer...'),
                  );
                }
                final key = snap.data?.movie.trailerKey;
                if (key == null || key.isEmpty) {
                  return const Text(
                    'No official trailer is available for this one.',
                    style: TextStyle(color: Colors.white38, fontSize: 12),
                  );
                }
                return FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: themeState.accent,
                    foregroundColor: themeState.onAccent,
                  ),
                  onPressed: () => _openTrailer(key),
                  icon: const Icon(Icons.smart_display),
                  label: const Text('Watch trailer on YouTube'),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          // v45: movie-restricted AI chat (free OpenRouter models).
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              onPressed: () =>
                  AskAiSheet.show(context, movie: widget.movie),
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Ask with AI about this movie'),
            ),
          ),
          if (widget.localMatch != null) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: () => _playLocal(context),
                icon: const Icon(Icons.video_library),
                label: Text(
                    'In my library - play "${widget.localMatch!.title}" now',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
            ),
          ],
          // v46: real TMDB user reviews (was asked: "real reviews").
          FutureBuilder<TmdbFull?>(
            future: _detailFuture,
            builder: (context, snap) {
              final full = snap.data;
              if (snap.connectionState != ConnectionState.done ||
                  full == null ||
                  full.reviews.isEmpty) {
                return const SizedBox.shrink();
              }
              return _ReviewsBlock(reviews: full.reviews);
            },
          ),
          const SizedBox(height: 14),
          Center(
            child: Text(
              // v46: short attribution line (the full legal phrasing lives
              // in the README and the Play listing, as TMDB requires).
              'Movie data & ratings: TMDB',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.3),
                fontSize: 10,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// v45: a horizontal strip of scene "screenshots" (TMDB backdrops) so the
/// sheet shows the movie, not just tells it.
class _ScreenshotsRow extends StatelessWidget {
  final List<String> paths;

  const _ScreenshotsRow({required this.paths});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: SizedBox(
        height: 104,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: paths.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, i) => ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 176,
              child: TmdbImage(url: tmdbScreenshotUrl(paths[i])),
            ),
          ),
        ),
      ),
    );
  }
}

/// v44: tagline, runtime, genres, votes, director, cast - everything TMDB
/// gives us beyond the poster. Any missing piece is simply skipped.
class _ExtrasBlock extends StatelessWidget {
  final TmdbDetailExtras extras;

  const _ExtrasBlock({required this.extras});

  @override
  Widget build(BuildContext context) {
    final meta = <String>[
      if (formatRuntime(extras.runtimeMinutes).isNotEmpty)
        formatRuntime(extras.runtimeMinutes),
      if (extras.voteCount > 0) '${formatVoteCount(extras.voteCount)} votes',
      if (extras.status.isNotEmpty && extras.status != 'Released')
        extras.status,
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (extras.tagline.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '"${extras.tagline}"',
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 13,
                  fontStyle: FontStyle.italic,
                  height: 1.4,
                ),
              ),
            ),
          if (meta.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                meta.join('  ·  '),
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ),
          // v46: audio languages + our own subtitle capability line.
          if (extras.spokenLanguages.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                'Languages: ${extras.spokenLanguages.join(' · ')}',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
          if (extras.genres.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final g in extras.genres.take(4))
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        g,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 11),
                      ),
                    ),
                ],
              ),
            ),
          if (extras.director.isNotEmpty)
            Text(
              'Director: ${extras.director}',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          if (extras.cast.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                'Cast: ${extras.cast.join(', ')}',
                style: const TextStyle(
                    color: Colors.white54, fontSize: 12, height: 1.4),
              ),
            ),
        ],
      ),
    );
  }
}

/// v46: "Where to watch" (India) with the compare split - Stream / Rent /
/// Buy provider names from TMDB's JustWatch-powered data.
/// v59: "in web series, when we select a content mention ALL parts of
/// the series in the detail" - every season as one clean line:
/// Season 1 · 8 episodes · 2011.
class _SeasonsBlock extends StatelessWidget {
  final List<TmdbSeason> seasons;

  const _SeasonsBlock({required this.seasons});

  @override
  Widget build(BuildContext context) {
    final totalEps = seasons.fold<int>(0, (a, s) => a + s.episodes);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Seasons & parts - ${seasons.length} season'
            '${seasons.length == 1 ? '' : 's'}, $totalEps episodes total',
            style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          for (final s in seasons)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      s.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 13),
                    ),
                  ),
                  Text(
                    '${s.episodes} ep'
                    '${s.year != null ? '  ·  ${s.year}' : ''}',
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _WatchBlock extends StatelessWidget {
  final TmdbWatchInfo info;

  const _WatchBlock({required this.info});

  @override
  Widget build(BuildContext context) {
    Widget row(String label, List<String> names, Color color) {
      if (names.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 56,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: color, fontSize: 10, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                names.join(' · '),
                style: const TextStyle(color: Colors.white70, fontSize: 12,
                    height: 1.4),
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Where to watch (India)',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.75),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          row('Stream', info.stream, const Color(0xFF4ade80)),
          row('Rent', info.rent, const Color(0xFFfacc15)),
          row('Buy', info.buy, const Color(0xFF60a5fa)),
        ],
      ),
    );
  }
}

/// v46: real TMDB user reviews, trimmed, with the author's rating.
class _ReviewsBlock extends StatelessWidget {
  final List<TmdbReview> reviews;

  const _ReviewsBlock({required this.reviews});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'User reviews',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.75),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          for (final r in reviews)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    [
                      if (r.author.isNotEmpty) r.author else 'TMDB user',
                      if (r.rating != null)
                        '⭐ ${tmdbRatingText(r.rating!)}',
                    ].join('  ·  '),
                    style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    r.text,
                    style: const TextStyle(
                        color: Colors.white54, fontSize: 12, height: 1.45),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// v47: EVERYTHING TMDB knows - dates, certificate, money, companies,
/// countries and ALL supported languages.
class _AllDataBlock extends StatelessWidget {
  final TmdbDetailExtras extras;
  final int movieId;
  const _AllDataBlock({required this.extras, required this.movieId});
  @override
  Widget build(BuildContext context) {
    Widget row(String l, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 78, child: Text(l, style: TextStyle(
              color: Colors.white.withValues(alpha: 0.4), fontSize: 11))),
          Expanded(child: Text(v, style: const TextStyle(
              color: Colors.white70, fontSize: 12))),
        ]));
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (extras.releaseDate.isNotEmpty) row('Release', extras.releaseDate),
        if (extras.certification.isNotEmpty) row('Certificate', extras.certification),
        if (extras.originalTitle.isNotEmpty) row('Original', extras.originalTitle),
        if (extras.budgetUsd > 0) row('Budget', '\$${formatVoteCount(extras.budgetUsd)}'),
        if (extras.revenueUsd > 0) row('Revenue', '\$${formatVoteCount(extras.revenueUsd)}'),
        if (extras.companies.isNotEmpty) row('Studio', extras.companies.join('  ')),
        if (extras.countries.isNotEmpty) row('Country', extras.countries.join('  ')),
        // v61 (user: "why you showing two languages section in details"):
        // the spoken-audio "Languages: ..." line already lives in
        // _ExtrasBlock above. The old chip-wrap that listed every TMDB
        // *translation* language (often 30+ chips) read as a duplicate,
        // so it is removed - there is now exactly ONE language line.
        // Cast / watch / reviews / seasons all stay untouched.
        _RealSubtitlesBlock(movieId: movieId),
      ]),
    );
  }
}

/// v47: REAL subtitle availability (OpenSubtitles).
class _RealSubtitlesBlock extends StatefulWidget {
  final int movieId;
  const _RealSubtitlesBlock({required this.movieId});
  @override
  State<_RealSubtitlesBlock> createState() => _RealSubtitlesBlockState();
}

class _RealSubtitlesBlockState extends State<_RealSubtitlesBlock> {
  final _client = OpenSubtitlesClient();
  List<String>? _langs;
  @override
  void initState() { super.initState(); _boot(); }
  Future<void> _boot() async {
    final cachePath = await NativeBridge.cacheDirPath();
    if (cachePath != null) _client.cacheDir = Directory(cachePath);
    final langs = await _client.languagesFor(widget.movieId);
    if (mounted) setState(() => _langs = langs);
  }
  @override
  Widget build(BuildContext context) {
    if (kOpenSubtitlesApiKey.isEmpty) return const SizedBox.shrink();
    final langs = _langs;
    if (langs == null || langs.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text('Subtitles available: ${langs.join('  ')}',
          style: const TextStyle(color: Colors.white54, fontSize: 11)),
    );
  }
}
MAXV61_EOF_MOVIE_DETAIL_SHEET_DART
echo "  wrote lib/widgets/movie_detail_sheet.dart"
mkdir -p "$(dirname "lib/screens/discover_screen.dart")"
cat > "lib/screens/discover_screen.dart" <<'MAXV61_EOF_DISCOVER_SCREEN_DART'
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../services/native_bridge.dart';
import '../services/tmdb_client.dart';
import '../state/media_player_state.dart';
import '../state/theme_state.dart';
import '../state/video_library_state.dart';
import '../utils/movie_match.dart';
import '../widgets/ai_suggest_sheet.dart';
import '../widgets/movie_detail_sheet.dart';
import '../widgets/tmdb_image.dart';

/// v44 "Discover": a legal movie-discovery section, now MUCH bigger.
///
/// - MANY filters (Trending, Hollywood, Bollywood, Tamil, Telugu, Action,
///   Comedy, Drama, Horror, Romance, Thriller, Sci-Fi) instead of v43's 3.
/// - Its own SEARCH bar -> TMDB's whole catalogue.
/// - INFINITE SCROLL: every section pages through thousands of movies
///   (TMDB serves up to 500 pages per query, 20 per page).
/// - Pull-to-refresh REALLY reloads (and v44 fixes wrong/stale posters).
///
/// SOURCE: TMDB's free API (licensed for this, needs only the credit line -
/// we do NOT copy IMDb numbers). Posters + data cache on disk for 24h, so
/// the section refreshes itself daily and works fully offline in between.
///
/// TRAILERS: a tap opens the official YouTube app (Play-policy-safe). We
/// never play YouTube streams through our own player.
/// v58 grew it further: WEB SERIES got their own shelf (Movies | Series
/// switch + /tv endpoints), the grid paints INSTANTLY from the disk cache
/// on slow networks (live data then replaces it), and the ✨ AI Suggestor
/// turns "funny action like Dhoom" into real, tappable posters.
class DiscoverScreen extends StatefulWidget {
  final VideoLibraryState library;
  final MediaPlayerState player;

  const DiscoverScreen({
    super.key,
    required this.library,
    required this.player,
  });

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  final _client = TmdbClient();
  final _scroll = ScrollController();
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  DiscoverFilter _filter = kAllFilters.first;
  final List<TmdbMovie> _movies = [];
  final Set<int> _seenIds = {};
  int _page = 0;
  int _totalPages = 1;
  int _totalResults = 0;
  bool _initialLoading = true;
  bool _loadingMore = false;
  String? _error;
  bool _keyMissing = false;

  // v61 (user: "show infinite contents in EVERY filter"): page 1 alone
  // rarely fills a tall phone, and v60's single post-frame
  // _maybeLoadMore() only pulled ONE extra page. We now CHAIN page loads
  // after each page lands, until the grid is scrollable/fills the
  // viewport OR we hit the safety cap - then the normal scroll listener
  // at maxScrollExtent-350 takes over for "forever" paging.
  //
  // [_endlessPaging] is the in-flight guard (never two page requests at
  // once); [_endlessBurst] counts chained auto-loads so one burst can't
  // spin forever. Each chain captures the current [_loadToken], so
  // switching filters/search drops a stale chain on the next frame.
  bool _endlessPaging = false;
  int _endlessBurst = 0;
  static const int _kEndlessBurstCap = 5;

  /// v45: "search is poor - show related movies": similar titles of the
  /// top search hit, shown under the results in search mode.
  List<TmdbMovie> _related = const [];

  /// Bumped every time the MODE (filter/search) changes; stale in-flight
  /// page loads check it and drop their results (no mixed-up grids).
  int _loadToken = 0;
  String _searchQuery = '';
  bool get _searching => _searchQuery.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_maybeLoadMore);
    _boot();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scroll.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    final cachePath = await NativeBridge.cacheDirPath();
    TmdbImage.configure(cachePath);
    if (cachePath != null) _client.cacheDir = Directory(cachePath);
    if (!mounted) return;
    if (kTmdbApiKey.isEmpty) {
      setState(() {
        _keyMissing = true;
        _initialLoading = false;
      });
      return;
    }
    await _loadPage(1, force: true);
  }

  /// Loads ONE page of the current mode and appends it (deduped by id).
  Future<void> _loadPage(int page, {bool force = false}) async {
    final token = _loadToken;
    if (page == 1) {
      if (mounted) setState(() => _initialLoading = true);
      // v58: instant first paint on bad networks - show the cached page
      // from disk RIGHT AWAY; the live fetch below replaces it.
      if (!_searching && _movies.isEmpty) {
        final cached = await _client.cachedBrowseFirstPage(_filter);
        if (!mounted || token != _loadToken) return;
        if (cached != null && _movies.isEmpty) {
          setState(() {
            for (final m in cached.items) {
              if (_seenIds.add(m.id)) _movies.add(m);
            }
            _error = null;
          });
        }
      }
    } else {
      if (mounted) setState(() => _loadingMore = true);
    }
    TmdbPage result;
    try {
      // v59: multi-search finds it in ALL shelves - movies AND series.
      result = _searching
          ? await _client.searchMulti(_searchQuery, page: page, force: force)
          : await _client.browse(_filter, page: page, force: force);
    } catch (_) {
      result = const TmdbPage();
    }
    if (!mounted || token != _loadToken) return;
    setState(() {
      _initialLoading = false;
      _loadingMore = false;
      _page = result.page;
      _totalPages = result.totalPages;
      _totalResults = result.totalResults;
      for (final m in result.items) {
        if (_seenIds.add(m.id)) _movies.add(m);
      }
      if (page == 1 && _movies.isEmpty) {
        _error = _searching
            ? 'No movies or series match "$_searchQuery" on TMDB.'
            : 'Could not load movies or series - connect the internet once, '
                'then pull down to retry.';
      } else if (_movies.isNotEmpty) {
        _error = null;
      }
    });
    // v45: in search mode, also fetch "you may also like" from the top
    // hit - a plain search word finds few direct matches otherwise.
    if (_searching && page == 1 && result.items.isNotEmpty) {
      _loadRelated(result.items.first.id, token,
          kind: result.items.first.kind);
    }
    // v61: "show infinite contents in EVERY filter" - after EVERY page
    // lands (not just page 1), schedule a post-frame check that keeps
    // loading the next page until the grid fills the viewport / becomes
    // scrollable or we hit the burst cap. The existing scroll listener
    // (_maybeLoadMore at maxScrollExtent-350) then keeps paging forever
    // as the user scrolls. [token] ties the chain to this filter/search.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && token == _loadToken) _scheduleEndlessFill(token);
    });
  }

  /// v61: chained auto-fill. Called after each page paints; if the grid
  /// still doesn't fill the viewport (or the user is already near the
  /// bottom) and more pages exist, fetch the next one - looping up to
  /// [_kEndlessBurstCap] pages per burst so we never fire unbounded
  /// requests. The in-flight [_loadingMore] guard plus [_endlessPaging]
  /// makes duplicate requests impossible.
  void _scheduleEndlessFill(int token) {
    if (!mounted || token != _loadToken) return;
    if (_initialLoading || _loadingMore || _endlessPaging) return;
    if (_page >= _totalPages) return; // nothing more to fetch
    if (_searching) {
      // Search keeps its single related-fetch behavior; no auto-chain
      // (results are usually specific enough to fill the screen).
      if (_endlessBurst != 0) _endlessBurst = 0;
      return;
    }
    // Decide whether the current content still needs more.
    var needsMore = true;
    if (_scroll.hasClients) {
      final pos = _scroll.position;
      // Content already comfortably fills / overflows the viewport AND
      // we're not near the bottom -> the scroll listener will take over,
      // so stop the auto-chain.
      needsMore = pos.maxScrollExtent <= pos.viewportDimension + 24 ||
          pos.pixels >= pos.maxScrollExtent - 350;
    }
    if (!needsMore) {
      _endlessBurst = 0; // screen is full; hand off to the scroll listener
      return;
    }
    if (_endlessBurst >= _kEndlessBurstCap) {
      // Safety stop for one burst; the next real scroll resumes paging.
      _endlessBurst = 0;
      return;
    }
    _endlessPaging = true;
    _endlessBurst++;
    _loadPage(_page + 1).whenComplete(() {
      if (mounted) _endlessPaging = false;
    });
  }

  Future<void> _loadRelated(int movieId, int token,
      {String kind = 'movie'}) async {
    List<TmdbMovie> rel;
    try {
      rel = await _client.similar(movieId, kind: kind);
    } catch (_) {
      rel = const [];
    }
    if (!mounted || token != _loadToken || !_searching) return;
    setState(() => _related = rel.take(12).toList());
  }

  /// Hard switch of browse/search mode: clears the grid, invalidates any
  /// in-flight loads, then fetches page 1. [force] skips the 24h cache.
  void _switchTo({DiscoverFilter? filter, String? query, bool force = false}) {
    _loadToken++;
    _endlessPaging = false; // v61: cancel any in-flight auto-fill chain
    _endlessBurst = 0;
    setState(() {
      if (filter != null) _filter = filter;
      if (query != null) _searchQuery = query;
      _movies.clear();
      _seenIds.clear();
      _page = 0;
      _totalPages = 1;
      _totalResults = 0;
      _error = null;
      _related = const [];
    });
    _loadPage(1, force: force);
  }

  void _selectFilter(DiscoverFilter f) {
    if (!_searching && _filter == f) return;
    _searchCtrl.clear(); // leaving search mode when a chip is tapped
    _switchTo(filter: f, query: '');
  }

  void _onSearchChanged(String v) {
    setState(() {}); // show/hide the clear (x) button immediately
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      final q = v.trim();
      if (q == _searchQuery) return;
      _switchTo(query: q);
    });
  }

  /// v44: infinite scroll - near the bottom? fetch the next page.
  /// v61: a real user scroll resets the auto-fill burst counter so
  /// scrolling can keep paging "forever" (the cap only bounds the
  /// automatic burst right after a filter is opened).
  void _maybeLoadMore() {
    if (!_scroll.hasClients || _initialLoading || _loadingMore) return;
    if (_page >= _totalPages) return;
    final pos = _scroll.position;
    if (pos.pixels >= pos.maxScrollExtent - 350) {
      _endlessBurst = 0;
      _loadPage(_page + 1);
    }
  }

  Future<void> _refresh() async {
    _switchTo(force: true);
    // Let RefreshIndicator stay up until page 1 actually finished.
    while (_initialLoading && mounted) {
      await Future<void>.delayed(const Duration(milliseconds: 60));
    }
  }

  void _openMovie(TmdbMovie movie) {
    // Match against the ALREADY-scanned library (read-only - the video
    // scan is not touched by Discover at all).
    final match =
        findLocalMovie(movie.title, movie.year, widget.library.allVideos);
    MovieDetailSheet.show(
      context,
      movie: movie,
      localMatch: match,
      player: widget.player,
      detailLoader: () => _client.fullDetail(movie.id, kind: movie.kind),
    );
  }

  /// v58/v59: the AI Suggestor - "describe your movie type" -> real
  /// posters. Lives in the AppBar (user: "move AI suggest to the top").
  Future<void> _openAiSuggest() async {
    final pick = await AiSuggestSheet.show(context);
    if (!mounted || pick == null) return;
    _openMovie(pick);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF12121a),
      appBar: AppBar(
        backgroundColor: const Color(0xFF12121a),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Discover', style: TextStyle(fontSize: 18)),
            if (_totalResults > 0)
              Text(
                _searching
                    ? '${_movies.length} of ~${formatVoteCount(_totalResults)} results'
                    : '${formatVoteCount(_totalResults)} titles - scroll for more',
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
          ],
        ),
        // v59 (user): AI Suggest moved to the TOP.
        actions: [
          IconButton(
            tooltip: 'AI Suggest - describe your movie type',
            icon: Icon(Icons.auto_awesome, color: themeState.accent),
            onPressed: _openAiSuggest,
          ),
        ],
      ),
      body: _keyMissing
          ? const _SetupNote()
          : Column(
              children: [
                // v44: the section's own search bar (TMDB-wide).
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: _onSearchChanged,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Search movies & series...',
                      hintStyle: const TextStyle(color: Colors.white38),
                      prefixIcon: Icon(Icons.search,
                          color: themeState.accent, size: 20),
                      suffixIcon: _searchCtrl.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close,
                                  color: Colors.white54, size: 18),
                              onPressed: () {
                                _searchCtrl.clear();
                                _switchTo(query: '');
                              },
                            ),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.06),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                // v59 (user): ONE filter row with EVERYTHING - movie
                // chips AND web series chips side by side (the old
                // Movies|Series toggle is gone).
                SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: [
                      for (final f in kAllFilters) ...[
                        _FilterChip(
                          label: f.label,
                          selected: !_searching && _filter == f,
                          onTap: () => _selectFilter(f),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: RefreshIndicator(
                    color: themeState.accent,
                    onRefresh: _refresh,
                    child: _buildBody(),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildBody() {
    if (_initialLoading && _movies.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_movies.isEmpty) {
      // Kept scrollable so pull-to-refresh always works.
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 120),
          Icon(Icons.cloud_off_outlined,
              size: 44, color: Colors.white.withValues(alpha: 0.3)),
          const SizedBox(height: 14),
          Text(
            _error ?? 'No movies to show yet.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white54, height: 1.4),
          ),
        ],
      );
    }
    return Stack(
      children: [
        CustomScrollView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.all(10),
              sliver: SliverGrid.builder(
                // v45: BIGGER cards (150 -> 200 wide) so posters actually
                // read like a movie app, not stamps.
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 200,
                  childAspectRatio: 0.60,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                ),
                itemCount: _movies.length,
                itemBuilder: (context, i) {
                  final movie = _movies[i];
                  return _PosterCard(
                    // v44: stable per-MOVIE key -> a recycled cell never
                    // flashes the previous movie's poster after refresh.
                    key: ValueKey(movie.id),
                    movie: movie,
                    onTap: () => _openMovie(movie),
                  );
                },
              ),
            ),
            // v45: related movies under search results.
            if (_searching && _related.isNotEmpty) ...[
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(12, 10, 12, 8),
                  child: Text(
                    'Related to your search',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 224,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _related.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (context, i) => SizedBox(
                      width: 128,
                      child: _PosterCard(
                        key: ValueKey('rel_${_related[i].id}'),
                        movie: _related[i],
                        onTap: () => _openMovie(_related[i]),
                      ),
                    ),
                  ),
                ),
              ),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 16)),
          ],
        ),
        if (_loadingMore)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: LinearProgressIndicator(
              minHeight: 3,
              color: themeState.accent,
              backgroundColor: Colors.transparent,
            ),
          ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? themeState.accent
              : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? themeState.onAccent : Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _PosterCard extends StatelessWidget {
  final TmdbMovie movie;
  final VoidCallback onTap;

  const _PosterCard({super.key, required this.movie, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  TmdbImage(url: tmdbPosterUrl(movie.posterPath)),
                  Positioned(
                    top: 6,
                    left: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '⭐ ${tmdbRatingText(movie.rating)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            movie.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
          if (movie.year != null)
            Text(
              '${movie.year}',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 11,
              ),
            ),
        ],
      ),
    );
  }
}

/// Shown in local/dev builds where no TMDB key was injected (the store /
/// testers' builds from Codemagic have it). Never a crash, always a note.
class _SetupNote extends StatelessWidget {
  const _SetupNote();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.movie_filter,
                size: 44, color: Colors.white.withValues(alpha: 0.3)),
            const SizedBox(height: 14),
            const Text(
              'Discover starts in the store build.\n\n'
              '(Developer note: pass the TMDB key via\n'
              '--dart-define=TMDB_API_KEY=... - see README. '
              'Everything else in the app works without it.)',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}
MAXV61_EOF_DISCOVER_SCREEN_DART
echo "  wrote lib/screens/discover_screen.dart"
mkdir -p "$(dirname "test/widget_test.dart")"
cat > "test/widget_test.dart" <<'MAXV61_EOF_WIDGET_TEST_DART'
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:maxplayer/app_info.dart';
import 'package:maxplayer/cast/cast_support.dart';
import 'package:maxplayer/screens/player_screen.dart';
import 'package:maxplayer/models/playlist.dart';
import 'package:maxplayer/models/saved_server.dart';
import 'package:maxplayer/models/video_track.dart';
import 'package:maxplayer/services/native_bridge.dart';
import 'package:maxplayer/services/tmdb_client.dart';
import 'package:maxplayer/widgets/tmdb_image.dart';
import 'package:maxplayer/services/movie_ai.dart';
import 'package:maxplayer/services/ai_suggest.dart';
import 'package:maxplayer/services/subtitle_langs.dart';
import 'package:maxplayer/widgets/video_search_delegate.dart';
import 'package:maxplayer/widgets/video_thumb.dart';
import 'package:maxplayer/state/media_player_state.dart';
import 'package:maxplayer/state/video_zoom.dart';
import 'package:maxplayer/state/player_settings.dart';
import 'package:maxplayer/state/playlist_store.dart';
import 'package:maxplayer/utils/movie_match.dart';
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
    // v54: back on-device - accurate whisper models; stale ids migrate.
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

  group('v38 enhance decode mode + legacy storage permission', () {
    test('enhance ON switches to copy-back decode, OFF restores auto', () {
      // Direct hardware rendering silently skips user shaders (the "not
      // effective" bug); copy-back routes frames through the shader.
      expect(MediaPlayerState.enhanceHwdecFor(true), 'mediacodec-copy');
      expect(MediaPlayerState.enhanceHwdecFor(false), 'auto');
    });

    test('enhance hwdec constant matches the preference function', () {
      expect(
        MediaPlayerState.enhanceHwdecFor(true),
        MediaPlayerState.kEnhanceHwdec,
      );
    });
  });

  group('v40 named playlists + SD-card scanning', () {
    test('Playlist json round-trips (persistence format)', () {
      const pl = Playlist(
        id: '1712345678901234',
        name: 'Movies',
        videoPaths: ['/s/a.mp4', '/s/b.mkv'],
      );
      final back = Playlist.fromJson(pl.toJson());
      expect(back.id, pl.id);
      expect(back.name, pl.name);
      expect(back.videoPaths, ['/s/a.mp4', '/s/b.mkv']);
    });

    test('Playlist json survives junk (missing fields, garbage list)', () {
      final back = Playlist.fromJson(const {'name': 'Songs'});
      expect(back.name, 'Songs');
      expect(back.videoPaths, isEmpty);
      final withJunk = Playlist.fromJson(const {
        'id': 'x',
        'name': 'N',
        'videoPaths': ['/ok.mp4', 7, null],
      });
      expect(withJunk.videoPaths.first, '/ok.mp4');
      expect(withJunk.videoPaths.length, 3); // garbage stringifies, never throws
    });

    test('mergePlaylistPaths appends new, skips duplicates, keeps order', () {
      final merged = mergePlaylistPaths(
        ['/s/a.mp4', '/s/b.mp4'],
        ['/s/b.mp4', '/card/c.mp4', '/s/a.mp4'],
      );
      expect(merged, ['/s/a.mp4', '/s/b.mp4', '/card/c.mp4']);
    });

    test('mergePlaylistPaths does not mutate the input list', () {
      final existing = ['/s/a.mp4'];
      mergePlaylistPaths(existing, ['/s/b.mp4']);
      expect(existing.length, 1);
    });

    test('validatePlaylistName trims, rejects blank/too long, accepts names', () {
      expect(validatePlaylistName('   '), isNotNull);
      expect(validatePlaylistName(''), isNotNull);
      expect(validatePlaylistName('x' * 41), isNotNull);
      expect(validatePlaylistName('  Movies  '), isNull);
      expect(validatePlaylistName('Bhakti Songs'), isNull);
    });

    test('normalizeStorageRoots dedupes, strips slashes, keeps order', () {
      final roots = normalizeStorageRoots([
        '/storage/emulated/0/',
        '/storage/1C4B-9A2F',
        '/storage/emulated/0', // same as first after slash-strip
        '',
        '/',
        '  /storage/1C4B-9A2F  ', // same as second after trim
      ]);
      expect(roots, ['/storage/emulated/0', '/storage/1C4B-9A2F']);
    });

    test('normalizeStorageRoots falls back to internal storage when empty', () {
      expect(normalizeStorageRoots(const []), ['/storage/emulated/0']);
      expect(normalizeStorageRoots(const ['', '/']), ['/storage/emulated/0']);
    });
  });

  group('v41 system bars follow the video', () {
    test('landscape hides the bars even when fullscreen was never pressed', () {
      expect(
        playerSystemUiModeFor(fullscreen: false, landscape: true),
        SystemUiMode.immersiveSticky,
      );
    });

    test('manual fullscreen hides the bars in any orientation', () {
      expect(
        playerSystemUiModeFor(fullscreen: true, landscape: false),
        SystemUiMode.immersiveSticky,
      );
      expect(
        playerSystemUiModeFor(fullscreen: true, landscape: true),
        SystemUiMode.immersiveSticky,
      );
    });

    test('portrait without fullscreen keeps the bars (time, notifications)',
        () {
      expect(
        playerSystemUiModeFor(fullscreen: false, landscape: false),
        SystemUiMode.edgeToEdge,
      );
    });
  });

  group('v42 compatibility manifest', () {
    // These guards read the REAL AndroidManifest.xml (test CWD = package
    // root) so a future edit can never silently drop the compatibility
    // fixes again.
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

    test('Android 10 raw-path storage: legacy flag + WRITE permission', () {
      expect(
        manifest.contains('android:requestLegacyExternalStorage="true"'),
        isTrue,
      );
      expect(
        manifest.contains('android.permission.WRITE_EXTERNAL_STORAGE'),
        isTrue,
      );
      // WRITE applies to Android 10 and older; newer versions use
      // All-files-access / per-app dirs instead.
      expect(manifest.contains('android:maxSdkVersion="29"'), isTrue);
    });

    test('http video streams: cleartext traffic explicitly allowed', () {
      expect(manifest.contains('android:usesCleartextTraffic="true"'), isTrue);
    });

    test('installable on Android TV / non-touch devices', () {
      expect(manifest.contains('android.hardware.touchscreen'), isTrue);
      expect(manifest.contains('android:required="false"'), isTrue);
    });
  });

  group('v43 Discover (TMDB) - legal movie discovery', () {
    const trendingJson = '{"results":['
        '{"id":27205,"title":"Inception","release_date":"2010-07-15",'
        '"vote_average":8.365,"poster_path":"/abc.jpg","overview":"Dreams."},'
        '{"id":"bad","title":"","vote_average":"x"},'
        '{"id":603,"title":"The Matrix","release_date":"1999-03-30",'
        '"vote_average":8.2,"poster_path":null,"overview":"Neo."}'
        ']}';

    test('parseTmdbList keeps good rows, skips junk, never throws', () {
      final movies = parseTmdbList(trendingJson);
      expect(movies.length, 2);
      expect(movies.first.title, 'Inception');
      expect(movies.first.year, 2010);
      expect(movies.first.rating, closeTo(8.365, 0.001));
      expect(movies.last.posterPath, isNull);
      expect(parseTmdbList('not json at all'), isEmpty);
      expect(parseTmdbList('{"results": 42}'), isEmpty);
    });

    test('pickTrailerKey prefers official YouTube trailer, falls back well',
        () {
      final videos = {
        'results': [
          {'site': 'Vimeo', 'type': 'Trailer', 'key': 'vimeo1'},
          {'site': 'YouTube', 'type': 'Teaser', 'key': 'teaser1'},
          {
            'site': 'YouTube',
            'type': 'Trailer',
            'official': true,
            'key': 'official1'
          },
        ]
      };
      expect(pickTrailerKey(videos), 'official1');
      expect(
        pickTrailerKey({
          'results': [
            {'site': 'YouTube', 'type': 'Clip', 'key': 'clip1'}
          ]
        }),
        'clip1',
      );
      expect(pickTrailerKey({'results': []}), isNull);
      expect(pickTrailerKey('garbage'), isNull);
    });

    test('rating badge + poster url formatting', () {
      expect(tmdbRatingText(8.365), '8.4');
      expect(tmdbRatingText(7.0), '7.0');
      expect(
        tmdbPosterUrl('/abc.jpg'),
        'https://image.tmdb.org/t/p/w342/abc.jpg',
      );
      expect(
        tmdbPosterUrl('/abc.jpg', big: true),
        'https://image.tmdb.org/t/p/w500/abc.jpg',
      );
      expect(tmdbPosterUrl(null), isEmpty);
    });

    test('normalizeMovieTitle strips quality/codec junk and years', () {
      expect(
        normalizeMovieTitle('Interstellar.2014.1080p.BluRay.x265'),
        'interstellar',
      );
      expect(normalizeMovieTitle('3_Idiots_2009_HD'), '3 idiots');
      expect(normalizeMovieTitle('The Dark Knight (2008) [1080p]'),
          'the dark knight');
    });

    test('findLocalMovie prefers the year-matching copy, falls back by title',
        () {
      VideoTrack vt(String path) => VideoTrack(
            id: path,
            title: path.split('/').last.replaceAll('.mkv', ''),
            path: path,
          );
      final lib = [
        vt('/s/Dune.Part.One.1080p.WEB-DL.mkv'),
        vt('/s/Interstellar.2014.1080p.BluRay.x265.mkv'),
      ];
      expect(
        findLocalMovie('Interstellar', 2014, lib)?.path,
        '/s/Interstellar.2014.1080p.BluRay.x265.mkv',
      );
      // Year mismatch / unknown year still falls back to the title hit.
      expect(findLocalMovie('Interstellar', null, lib), isNotNull);
      expect(findLocalMovie('Dune Part One', null, lib)?.path,
          '/s/Dune.Part.One.1080p.WEB-DL.mkv');
      // STRICT title match: "Dune" must NOT match "Dune Part One" (they are
      // different movies - false positives would be worse than no match).
      expect(findLocalMovie('Dune', 2021, lib), isNull);
      expect(findLocalMovie('Titanic', 1997, lib), isNull);
    });
  });

  group('v44 Discover upgrades + status-bar overlap fix', () {
    test('tmdbImageCacheName is deterministic and collision-safe', () {
      const a = 'https://image.tmdb.org/t/p/w342/abc123.jpg';
      final name = tmdbImageCacheName(a);
      expect(tmdbImageCacheName(a), name); // stable across calls
      // Same photo, different SIZE folder -> different cache entry.
      expect(tmdbImageCacheName('https://image.tmdb.org/t/p/w500/abc123.jpg'),
          isNot(name));
      // Different photo -> different cache entry.
      expect(tmdbImageCacheName('https://image.tmdb.org/t/p/w342/xyz999.jpg'),
          isNot(name));
      expect(name.contains('abc123.jpg'), isTrue); // human-readable
    });

    test('kDiscoverFilters: many more filters than v43 (3 -> 12)', () {
      expect(kDiscoverFilters.length, greaterThan(10));
      expect(kDiscoverFilters.first.trending, isTrue);
      expect(
          kDiscoverFilters
              .any((f) => f.key == 'hollywood' && f.language == 'en'),
          isTrue);
      expect(
          kDiscoverFilters
              .any((f) => f.key == 'bollywood' && f.language == 'hi'),
          isTrue);
      expect(kDiscoverFilters.where((f) => f.genreId != null).length,
          greaterThanOrEqualTo(7));
    });

    test('tmdbDiscoverQuery: language filter vs genre filter, with paging', () {
      final hw = kDiscoverFilters.firstWhere((f) => f.key == 'hollywood');
      final q1 = tmdbDiscoverQuery(hw, 2);
      expect(q1['with_original_language'], 'en');
      expect(q1['page'], '2');
      expect(q1.containsKey('with_genres'), isFalse);
      final action = kDiscoverFilters.firstWhere((f) => f.key == 'action');
      final q2 = tmdbDiscoverQuery(action, 1);
      expect(q2['with_genres'], '28');
      expect(q2.containsKey('with_original_language'), isFalse);
      expect(q2['include_adult'], 'false');
    });

    test('tmdbSearchQuery + cache name: stable, distinct, safe', () {
      final q = tmdbSearchQuery('Dune Part Two', 3);
      expect(q['query'], 'Dune Part Two');
      expect(q['page'], '3');
      expect(q['include_adult'], 'false');
      final n1 = tmdbSearchCacheName('dune 2', 1);
      expect(tmdbSearchCacheName('dune 2', 1), n1);
      expect(tmdbSearchCacheName('dune 2', 2), isNot(n1)); // page matters
      expect(tmdbSearchCacheName('dune 3', 1), isNot(n1)); // query matters
    });

    test('parseTmdbPage paginates and caps TMDB at 500 pages (thousands)', () {
      const body = '{"page":2,"total_pages":99999,"total_results":1999800,'
          '"results":[{"id":5,"title":"X","vote_average":7.2,'
          '"poster_path":"/p.jpg","release_date":"2020-01-01"}]}';
      final page = parseTmdbPage(body);
      expect(page.items.single.title, 'X');
      expect(page.page, 2);
      expect(page.totalPages, 500); // TMDB's own maximum depth
      expect(page.totalResults, 1999800);
      final bad = parseTmdbPage('garbage');
      expect(bad.items, isEmpty);
      expect(bad.totalPages, 1);
    });

    test('parseTmdbExtras: director + cast + runtime + genres + votes', () {
      const body = '{"id":1,"title":"X","runtime":136,"tagline":"Dream.",'
          '"status":"Released","vote_count":24513,'
          '"genres":[{"name":"Sci-Fi"},{"name":"Adventure"}],'
          '"credits":{"crew":[{"job":"Director","name":"Christopher Nolan"}],'
          '"cast":[{"name":"Leonardo DiCaprio"},'
          '{"name":"Joseph Gordon-Levitt"}]}}';
      final x = parseTmdbExtras(body);
      expect(x.director, 'Christopher Nolan');
      expect(x.cast, ['Leonardo DiCaprio', 'Joseph Gordon-Levitt']);
      expect(x.runtimeMinutes, 136);
      expect(x.genres, ['Sci-Fi', 'Adventure']);
      expect(x.tagline, 'Dream.');
      expect(x.voteCount, 24513);
      expect(parseTmdbExtras('{}').director, isEmpty);
      expect(parseTmdbExtras('not json').cast, isEmpty);
    });

    test('formatRuntime + formatVoteCount', () {
      expect(formatRuntime(136), '2h 16m');
      expect(formatRuntime(45), '45m');
      expect(formatRuntime(120), '2h');
      expect(formatRuntime(0), '');
      expect(formatVoteCount(24513), '24,513');
      expect(formatVoteCount(8), '8');
    });

    test('filterLibraryItems: the pure filter behind the new search icon', () {
      const titles = ['Dune Part Two.mkv', 'Interstellar.mp4', 'dune trailer.mp4'];
      expect(filterLibraryItems(titles, 'dune', (t) => t).length, 2);
      expect(filterLibraryItems(titles, '  INTER ', (t) => t),
          ['Interstellar.mp4']);
      expect(filterLibraryItems(titles, '', (t) => t).length, 3);
    });

    test('leaving the player restores MANUAL bars (no status-bar overlap)', () {
      expect(playerRestoreSystemUiMode, SystemUiMode.manual);
      expect(playerRestoreOverlays, containsAll(SystemUiOverlay.values));
    });
  });

  group('v45 Discover reliability + screenshots + Ask with AI', () {
    test('parseTmdbScreenshots picks backdrop paths, caps count, never throws', () {
      const body = '{"id":1,"images":{"backdrops":['
          '{"file_path":"/s1.jpg"},{"file_path":"/s2.jpg"},'
          '{"file_path":""},{"file_path":"/s3.jpg"}]}}';
      final shots = parseTmdbScreenshots(body);
      expect(shots, ['/s1.jpg', '/s2.jpg', '/s3.jpg']); // empty skipped
      expect(parseTmdbScreenshots(body, count: 2), ['/s1.jpg', '/s2.jpg']);
      expect(parseTmdbScreenshots('{}'), isEmpty);
      expect(parseTmdbScreenshots('junk'), isEmpty);
    });

    test('tmdbScreenshotUrl builds the w500 backdrop URL', () {
      expect(tmdbScreenshotUrl('/abc.jpg'),
          'https://image.tmdb.org/t/p/w500/abc.jpg');
      expect(tmdbScreenshotUrl(''), '');
    });

    test('openRouterChatBody: model + restricted system + user question', () {
      final body = openRouterChatBody(
        model: kOpenRouterModels.first,
        system: movieAiSystemPrompt(const TmdbMovie(
            id: 1, title: 'Dune', rating: 8, year: 2021)),
        question: 'Is it worth watching?',
      );
      expect(body['model'], kOpenRouterModels.first);
      final messages = body['messages'] as List;
      expect((messages.first as Map)['role'], 'system');
      expect('${messages.first['content']}'.contains('ONLY'), isTrue);
      expect('${messages.first['content']}'.contains('Dune'), isTrue);
      expect((messages.last as Map)['role'], 'user');
    });

    test('parseOpenRouterAnswer extracts the text, null on junk', () {
      const ok = '{"choices":[{"message":{"role":"assistant",'
          '"content":"  Watch it in IMAX.  "}}]}';
      expect(parseOpenRouterAnswer(ok), 'Watch it in IMAX.');
      expect(parseOpenRouterAnswer('{"choices":[]}'), isNull);
      expect(parseOpenRouterAnswer('not json'), isNull);
    });

    test('Ask-with-AI stays FREE: 4 fallback models + many templates', () {
      expect(kOpenRouterModels.length, greaterThanOrEqualTo(4));
      for (final m in kOpenRouterModels) {
        expect(m.endsWith(':free'), isTrue);
      }
      expect(kMovieAiTemplates.length, greaterThanOrEqualTo(5));
    });
  });

  group('v46 watch providers + reviews + upcoming + ai cache', () {
    test('tmdbEndpointPath: trending vs upcoming vs discover', () {
      const tr =
          DiscoverFilter(key: 't', label: 'T', trending: true);
      const up = DiscoverFilter(key: 'u', label: 'U', upcoming: true);
      const hw =
          DiscoverFilter(key: 'hollywood', label: 'H', language: 'en');
      expect(tmdbEndpointPath(tr), '/3/trending/movie/week');
      expect(tmdbEndpointPath(up), '/3/movie/upcoming');
      expect(tmdbEndpointPath(hw), '/3/discover/movie');
      expect(kDiscoverFilters.any((f) => f.upcoming), isTrue);
    });

    test('parseTmdbWatchProviders splits stream/rent/buy for IN', () {
      const body = '{"watch/providers":{"results":{"IN":{'
          '"flatrate":[{"provider_name":"Netflix"},'
          '{"provider_name":"Amazon Prime Video"}],'
          '"rent":[{"provider_name":"YouTube"}],'
          '"buy":[{"provider_name":"Google Play Movies"}]},'
          '"US":{"flatrate":[{"provider_name":"Hulu"}]}}}}';
      final w = parseTmdbWatchProviders(body);
      expect(w.stream, ['Netflix', 'Amazon Prime Video']);
      expect(w.rent, ['YouTube']);
      expect(w.buy, ['Google Play Movies']);
      expect(w.isEmpty, isFalse);
      expect(parseTmdbWatchProviders(body, region: 'XX').isEmpty, isTrue);
      expect(parseTmdbWatchProviders('junk').isEmpty, isTrue);
    });

    test('parseTmdbReviews: real text, rating, caps, junk-safe', () {
      const body = '{"reviews":{"results":[{"author":"Aryan",'
          '"content":"  Loved   every   minute.  ",'
          '"author_details":{"rating":9}},'
          '{"author":"Second","content":"Decent timepass.",'
          '"author_details":{}}]}}';
      final r = parseTmdbReviews(body);
      expect(r.length, 2);
      expect(r.first.text, 'Loved every minute.'); // whitespace collapsed
      expect(r.first.rating, 9.0);
      expect(r.last.rating, isNull);
      expect(parseTmdbReviews('{}'), isEmpty);
      expect(parseTmdbReviews('junk'), isEmpty);
    });

    test('parseTmdbExtras includes spoken languages', () {
      const body = '{"id":1,"title":"X","spoken_languages":['
          '{"english_name":"English"},{"english_name":"Hindi"}]}';
      expect(parseTmdbExtras(body).spokenLanguages, ['English', 'Hindi']);
      expect(parseTmdbExtras('{}').spokenLanguages, isEmpty);
    });

    test('movieAiCacheName is deterministic per movie+question', () {
      final a = movieAiCacheName(693134, 'Is it good?');
      expect(movieAiCacheName(693134, 'Is it good?'), a);
      expect(movieAiCacheName(693134, 'is it good?'), a); // case/trim-safe
      expect(movieAiCacheName(693134, 'ending?'), isNot(a));
      expect(movieAiCacheName(550, 'Is it good?'), isNot(a));
      expect(a.startsWith('ai_answer_693134_'), isTrue);
    });
  });

  group('v47 real subtitles + all TMDB data + thumbnails', () {
    test('parseOpenSubLanguages: unique sorted codes, junk-safe', () {
      const body = '{"data":[{"attributes":{"language":"en"}},'
          '{"attributes":{"language":"hi"}},'
          '{"attributes":{"language":"en"}},'
          '{"attributes":{}}]}';
      expect(parseOpenSubLanguages(body), ['en', 'hi']);
      expect(parseOpenSubLanguages('{}'), isEmpty);
      expect(parseOpenSubLanguages('junk'), isEmpty);
    });

    test('tmdbLanguageName maps codes, uppercases unknowns', () {
      expect(tmdbLanguageName('hi'), 'Hindi');
      expect(tmdbLanguageName('ta'), 'Tamil');
      expect(tmdbLanguageName('xx'), 'XX');
    });

    test('parseTmdbExtras v47: budget, revenue, companies, cert, languages', () {
      const body = '{"id":1,"title":"X","release_date":"2024-06-14",'
          '"original_title":"X Orig","budget":165000000,'
          '"revenue":711000000,'
          '"production_companies":[{"name":"Legendary"}],'
          '"production_countries":[{"name":"United States"}],'
          '"release_dates":{"results":[{"iso_3166_1":"US",'
          '"release_dates":[{"certification":"PG-13"}]}]},'
          '"translations":{"translations":[{"iso_639_1":"en"},'
          '{"iso_639_1":"hi"},{"iso_639_1":"ta"}]}}';
      final x = parseTmdbExtras(body);
      expect(x.releaseDate, '2024-06-14');
      expect(x.originalTitle, 'X Orig');
      expect(x.budgetUsd, 165000000);
      expect(x.revenueUsd, 711000000);
      expect(x.companies, ['Legendary']);
      expect(x.countries, ['United States']);
      expect(x.certification, 'PG-13');
      expect(x.allLanguages, ['English', 'Hindi', 'Tamil']);
    });
  });

  group('v52 two-finger zoom + default fit', () {
    test('clampVideoZoom keeps pinch inside 1x..4x (1x = fit screen)', () {
      expect(clampVideoZoom(0.4), 1.0);
      expect(clampVideoZoom(1.0), 1.0);
      expect(clampVideoZoom(2.5), 2.5);
      expect(clampVideoZoom(9), 4.0);
    });

    test('two-finger TAP resets to fit; a real pinch does not', () {
      // Quick tap with almost no travel and no scaling -> reset.
      expect(
        isTwoFingerTapReset(durationMs: 180, travelPx: 6, scaled: false),
        isTrue,
      );
      // User actually pinched -> do NOT snap home.
      expect(
        isTwoFingerTapReset(durationMs: 180, travelPx: 6, scaled: true),
        isFalse,
      );
      // Slow two-finger hold is not a tap.
      expect(
        isTwoFingerTapReset(durationMs: 900, travelPx: 6, scaled: false),
        isFalse,
      );
      // Big movement is a pan-ish pinch, not a tap.
      expect(
        isTwoFingerTapReset(durationMs: 180, travelPx: 60, scaled: false),
        isFalse,
      );
    });

    test('default fit is FIT SCREEN and cycles stay wired', () {
      const s = PlayerSettings();
      expect(s.defaultFitIndex, 0);
      expect(PlayerSettings.kFitModeNames.first, 'Fit');
      expect(PlayerSettings.kFitModeNames.length, 6);
      // copyWith carries the choice through (Settings sheet writes this).
      expect(s.copyWith(defaultFitIndex: 1).defaultFitIndex, 1);
    });

    test('v57 two-finger: FIT is default, switchable to zoom, one at a time', () {
      const s = PlayerSettings();
      // The user's rule: two fingers = FIT SCREEN by default.
      expect(s.twoFingerMode, 'fit');
      expect(PlayerSettings.kTwoFingerModes.keys, ['fit', 'zoom']);
      expect(s.copyWith(twoFingerMode: 'zoom').twoFingerMode, 'zoom');
      // Legacy/unknown stored values fall back to the fit default.
      expect(PlayerSettings.normalizeTwoFingerMode('both'), 'fit');
      expect(PlayerSettings.normalizeTwoFingerMode('pinch'), 'fit');
      expect(PlayerSettings.normalizeTwoFingerMode('junk'), 'fit');
      expect(PlayerSettings.normalizeTwoFingerMode(null), 'fit');
      expect(PlayerSettings.normalizeTwoFingerMode('zoom'), 'zoom');
      // ...while pinch zoom stays its own independent master toggle.
      expect(s.pinchZoom, isTrue);
    });

    test('v59 twoFingerSnapsToFit: only a TAP snaps home, pinch stays', () {
      // v59 (his v58 phone report "zooming is not working"): a real
      // pinch is NEVER undone - the ladder keeps its fit/zoom; only a
      // quick two-finger tap snaps back to fit, in BOTH modes.
      expect(twoFingerSnapsToFit(mode: 'fit', wasTap: true), isTrue);
      expect(twoFingerSnapsToFit(mode: 'fit', wasTap: false), isFalse);
      expect(twoFingerSnapsToFit(mode: 'zoom', wasTap: true), isTrue);
      expect(twoFingerSnapsToFit(mode: 'zoom', wasTap: false), isFalse);
      // unknown stored value conservatively snaps home.
      expect(twoFingerSnapsToFit(mode: 'junk', wasTap: false), isTrue);
    });

    // v61 (user: "when toggle is off then only fit screens in loop; when
    // toggle is on then only zoom ... zoom is still not working"). The old
    // continuous ladder put zoom at the END behind a ~2.6x spread, which
    // made it unreachable on a phone. The two modes are now split: toggle
    // OFF = fit loop (never zooms, wraps around); toggle ON = pure free
    // zoom from the first millimetre (1.0x..4.0x).
    test('v61 toggle OFF: fit loop steps one per spread and NEVER zooms', () {
      const n = 6; // Fit, Crop, Stretch, 16:9, 4:3, Original
      double posAt(int base, double scale) =>
          fitLadderPosFor(basePos: base.toDouble(), scale: scale);

      // One kFitLadderStepScale spread from Fit lands on Crop (index 1).
      expect(wrapFitLadderPos(posAt(0, kFitLadderStepScale), n), 1);
      // Two spreads -> Stretch (index 2).
      expect(
          wrapFitLadderPos(
              posAt(0, kFitLadderStepScale * kFitLadderStepScale), n),
          2);
      // Walking all SIX fits from Fit brings us back to Fit (the loop).
      var p = 0.0;
      for (var i = 0; i < n; i++) {
        p = posAt(p.round(), kFitLadderStepScale);
      }
      expect(wrapFitLadderPos(p, n), 0);
      // The CRITICAL rule: spreading ALL the way (even a huge 10x gesture)
      // only ever produces a fit index 0..n-1 - it can NEVER enter zoom,
      // because the loop wraps. There is no zoom value produced here at all.
      final huge = wrapFitLadderPos(posAt(0, 10.0), n);
      expect(huge, inInclusiveRange(0, n - 1));
      // ...and pinching IN walks back down (Fit -> Original via wrap).
      final in1 = wrapFitLadderPos(posAt(0, 1 / kFitLadderStepScale), n);
      expect(in1, n - 1); // Original
      final in2 = wrapFitLadderPos(
          posAt(0, 1 / (kFitLadderStepScale * kFitLadderStepScale)), n);
      expect(in2, n - 2); // 4:3
    });

    test('v61 toggle OFF: wrap-around Original -> Fit is explicit', () {
      const n = 6;
      // Just past the last fit (index 5 == Original) wraps straight to
      // index 0 (Fit) - this is the "loop" the user asked for.
      expect(wrapFitLadderPos(5.6, n), 0);
      expect(wrapFitLadderPos(6.0, n), 0);
      expect(wrapFitLadderPos(11.4, n), 5); // two full loops + Original
      // Negative positions (pinch in from Fit) wrap to the top.
      expect(wrapFitLadderPos(-0.6, n), 5); // -1 mod 6 -> Original
      expect(wrapFitLadderPos(-1.6, n), 4); // -2 mod 6 -> 4:3
      // Staying inside a step keeps the same fit.
      expect(wrapFitLadderPos(0.4, n), 0);
      expect(wrapFitLadderPos(2.4, n), 2);
    });

    test('v61 toggle ON: free zoom maps directly and clamps at 4.0x', () {
      // Zoom works from the FIRST millimetre - no ladder to climb.
      expect(freeZoomFor(baseZoom: 1.0, scale: 1.0), 1.0);
      expect(freeZoomFor(baseZoom: 1.0, scale: 1.5), closeTo(1.5, 0.001));
      expect(freeZoomFor(baseZoom: 1.0, scale: 2.0), closeTo(2.0, 0.001));
      // A tiny spread already zooms (this is what was broken before).
      expect(freeZoomFor(baseZoom: 1.0, scale: 1.05), closeTo(1.05, 0.001));
      // Clamps at the 4.0x ceiling, no matter how hard you spread.
      expect(freeZoomFor(baseZoom: 1.0, scale: 5.0), kMaxVideoZoom);
      expect(freeZoomFor(baseZoom: 1.0, scale: 100.0), kMaxVideoZoom);
      // Pinching in from 1.0 clamps at the 1.0x floor (fit screen).
      expect(freeZoomFor(baseZoom: 1.0, scale: 0.1), kMinVideoZoom);
      // Zooming on top of an already-zoomed base multiplies.
      expect(freeZoomFor(baseZoom: 2.0, scale: 1.5), closeTo(3.0, 0.001));
      expect(freeZoomFor(baseZoom: 2.0, scale: 3.0), kMaxVideoZoom);
    });

    test('v59 kAllFilters: ONE row, movies AND web series together', () {
      expect(kAllFilters.length,
          kDiscoverFilters.length + kSeriesFilters.length);
      expect(kAllFilters.first.trending, isTrue);
      expect(kAllFilters.any((f) => f.tv), isTrue);
      expect(kAllFilters.any((f) => !f.tv), isTrue);
      // every chip still resolves to a valid endpoint + cache name
      for (final f in kAllFilters) {
        expect(tmdbEndpointPath(f), startsWith('/3/'));
        expect(discoverCacheName(f, 1), endsWith('_p1.json'));
      }
    });

    test('v59 tmdbDiscoverQuery loads TONS more (vote bar relaxed)', () {
      final q = tmdbDiscoverQuery(kDiscoverFilters.first, 1);
      expect(q['vote_count.gte'], '8'); // was 25 - cut regional/series
    });

    test('v59 parseTmdbMultiPage: movies+series in, people out', () {
      final page = parseTmdbMultiPage(
          '{"page":1,"total_pages":4,"total_results":3,"results":['
          '{"id":1,"media_type":"movie","title":"Dhoom","release_date":"2004-01-01"},'
          '{"id":2,"media_type":"tv","name":"Mirzapur","first_air_date":"2018-11-16"},'
          '{"id":3,"media_type":"person","name":"Some Actor"}]}');
      expect(page.items.length, 2);
      expect(page.items[0].kind, 'movie');
      expect(page.items[1].kind, 'tv');
      expect(page.items[1].title, 'Mirzapur');
      expect(page.items[1].year, 2018);
    });

    test('v59 parseTmdbSeasons: all parts of a series', () {
      final seasons = parseTmdbSeasons('{"seasons":['
          '{"season_number":0,"name":"Specials","episode_count":2,"air_date":null},'
          '{"season_number":1,"name":"Season 1","episode_count":9,"air_date":"2018-11-16"},'
          '{"season_number":2,"episode_count":10,"air_date":"2020-10-23"}]}');
      expect(seasons.length, 3);
      expect(seasons[0].name, 'Specials');
      expect(seasons[1].episodes, 9);
      expect(seasons[1].year, 2018);
      expect(seasons[2].name, 'Season 2'); // fallback naming
      expect(parseTmdbSeasons('garbage'), isEmpty);
    });

    test('v60 parseTmdbSeasons falls back to the counters line', () {
      // some /tv payloads carry ONLY counters, no seasons array
      final s = parseTmdbSeasons(
          '{"seasons":[],"number_of_seasons":3,"number_of_episodes":24}');
      expect(s.single.name, contains('3 seasons'));
      expect(s.single.episodes, 24);
      expect(parseTmdbSeasons('{"seasons":[],"number_of_seasons":0}'),
          isEmpty);
    });

    test('v60 thumbnail slots cap at 2 and hand over in order', () async {
      await VideoThumb.acquireThumbSlot();
      await VideoThumb.acquireThumbSlot();
      var thirdDone = false;
      final third =
          VideoThumb.acquireThumbSlot().then((_) => thirdDone = true);
      await Future<void>.delayed(Duration.zero);
      expect(thirdDone, isFalse); // third waits - the cap holds
      VideoThumb.releaseThumbSlot(); // frees -> third gets the slot
      await third;
      expect(thirdDone, isTrue);
      VideoThumb.releaseThumbSlot();
    });

    test('v58 series filters drive the TMDB /tv endpoints', () {
      final t = kSeriesFilters.firstWhere((f) => f.key == 'tv_hindi');
      expect(kSeriesFilters.every((f) => f.tv), isTrue);
      expect(kDiscoverFilters.every((f) => !f.tv), isTrue);
      expect(tmdbEndpointPath(kSeriesFilters.first), '/3/trending/tv/week');
      expect(tmdbEndpointPath(t), '/3/discover/tv');
      expect(tmdbDiscoverQuery(t, 2)['with_original_language'], 'hi');
      // series get their own cache files, movie cache names unchanged
      expect(discoverCacheName(t, 1), contains('_tv_'));
      expect(discoverCacheName(kDiscoverFilters.first, 1),
          'tmdb_disc_trending_p1.json');
    });

    test('v58 parseTmdbPage reads SERIES (name/first_air_date, kind tv)', () {
      final page = parseTmdbPage(
          '{"page":1,"total_pages":3,"total_results":1,"results":['
          '{"id":1399,"name":"Game of Thrones","first_air_date":"2011-04-17",'
          '"vote_average":8.4,"poster_path":"/x.jpg"}]}',
          kind: 'tv');
      expect(page.items.single.title, 'Game of Thrones');
      expect(page.items.single.year, 2011);
      expect(page.items.single.kind, 'tv');
      // movies stay kind 'movie' by default
      expect(
          parseTmdbPage('{"results":[{"id":1,"title":"X",'
                  '"release_date":"2020-05-06"}]}')
              .items
              .single
              .kind,
          'movie');
    });

    test('v58 parseAiSuggestionJson tolerates prose, fences, garbage', () {
      final picks = parseAiSuggestionJson(
          'Sure! Here you go:\n```json\n[{"title":"3 Idiots","year":2009},'
          '{"title":"Dangal"},{"no":"title"},{"title":""}]\n```');
      expect(picks.map((p) => p.title), ['3 Idiots', 'Dangal']);
      expect(picks.first.year, 2009);
      expect(picks[1].year, isNull);
      expect(parseAiSuggestionJson('no json at all'), isEmpty);
      expect(parseAiSuggestionJson('[1,2,3]'), isEmpty);
      expect(parseAiSuggestionJson('[]'), isEmpty);
    });
  });
}
MAXV61_EOF_WIDGET_TEST_DART
echo "  wrote test/widget_test.dart"
mkdir -p "$(dirname "pubspec.yaml")"
cat > "pubspec.yaml" <<'MAXV61_EOF_PUBSPEC_YAML'
name: maxplayer
description: "Max Player - a local video library & player."
publish_to: 'none'
version: 1.0.0+57

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
MAXV61_EOF_PUBSPEC_YAML
echo "  wrote pubspec.yaml"

# ---- marker checks (proves the v61 content actually landed) -------------
echo "==> Checking v61 markers..."
ok=0; total=0
# present: the grep pattern MUST exist in the file.
present() { # desc; grep pattern; file
  total=$((total+1))
  if grep -q "$2" "$3" 2>/dev/null; then
    echo "  [OK] $1"; ok=$((ok+1))
  else
    echo "  [!!] MISSING: $1"
  fi
}
# absent: the grep pattern MUST NOT exist in the file.
absent() { # desc; grep pattern; file
  total=$((total+1))
  if grep -q "$2" "$3" 2>/dev/null; then
    echo "  [!!] STILL PRESENT (should be gone): $1"
  else
    echo "  [OK] $1"; ok=$((ok+1))
  fi
}
present "video_zoom: fit-loop wrap helper"        "int wrapFitLadderPos"          lib/state/video_zoom.dart
present "video_zoom: pure free-zoom map"          "double freeZoomFor"            lib/state/video_zoom.dart
absent  "video_zoom: old continuous-ladder slope removed" "kFitLadderZoomSlope"  lib/state/video_zoom.dart
absent  "video_zoom: old fitLadderPosOf removed"  "fitLadderPosOf"                lib/state/video_zoom.dart
absent  "video_zoom: old fitLadderDecode removed" "fitLadderDecode"              lib/state/video_zoom.dart
present "player: ladder anchor is an int"         "_ladderBaseIndex"              lib/screens/player_screen.dart
present "player: freeZoomFor wired"               "freeZoomFor(baseZoom"          lib/screens/player_screen.dart
present "player: wrap ladder wired"               "wrapFitLadderPos(pos"          lib/screens/player_screen.dart
absent  "player: old _ladderBasePos removed"      "_ladderBasePos"                lib/screens/player_screen.dart
absent  "player: old fitLadderDecode call removed" "fitLadderDecode"             lib/screens/player_screen.dart
absent  "detail: duplicate 'Languages supported' chips removed" "Languages supported" lib/widgets/movie_detail_sheet.dart
present "detail: single spoken 'Languages:' line kept" "Languages: "              lib/widgets/movie_detail_sheet.dart
present "discover: endless-fill chain"            "_scheduleEndlessFill"          lib/screens/discover_screen.dart
present "discover: burst cap"                     "_kEndlessBurstCap"             lib/screens/discover_screen.dart
present "test: v61 fit-loop test"                 "fit loop steps one per spread" test/widget_test.dart
present "test: v61 free-zoom test"                "free zoom maps directly"       test/widget_test.dart
present "pubspec version 1.0.0+57"                "^version: 1.0.0+57"           pubspec.yaml
echo ""
if [ "$ok" -eq "$total" ]; then
  echo "==> $ok/$total checks OK - v61 applied."
else
  echo "==> $ok/$total checks OK - SOME MARKERS MISSING. Do not push; re-run or report."
fi

echo ""
echo "============================================================"
echo " DONE. If you saw N/N checks OK, now run (AS-IS, no edits):"
echo "   git add -A && git commit -m \"v61: fit-loop vs free-zoom toggle,"
echo "     single Languages line, endless discover paging (1.0.0+57)\" \\"
echo "     && git push"
echo "============================================================"
echo ""
echo " PHONE TEST CHECKLIST (after installing the Codemagic build):"
echo "  [ ] Settings > turn 'Two-finger pinch to zoom' OFF."
echo "      Put two fingers on the video and SPREAD them:"
echo "        it cycles Fit -> Crop -> Stretch -> 16:9 -> 4:3 -> Original"
echo "        -> back to Fit (LOOP). The video NEVER zooms in."
echo "      Pinch IN walks the loop the other way, Fit -> Original."
echo "      A quick two-finger TAP snaps back to Fit."
echo "  [ ] Turn the toggle ON."
echo "      Pinch two fingers: it zooms 1.0x ... 4.0x IMMEDIATELY (like a"
echo "      map) - no cycling through fits. A quick two-finger TAP resets"
echo "      to 1.0x (Fit)."
echo "  [ ] Open Discover -> tap ANY filter (Hollywood, Tamil, K-Drama,...)."
echo "      Keep scrolling: pages keep loading automatically ('forever')."
echo "  [ ] Open any movie/series detail: the Languages section appears"
echo "      only ONCE ('Languages: English - Hindi' style)."
echo ""
echo " Please paste the LAST ~10 lines of this output, and tell me the"
echo " phone results (any item not checked)."
