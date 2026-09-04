import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:permission_handler/permission_handler.dart';

import '../cast/cast_state.dart';
import '../services/native_bridge.dart';
import '../services/notification_service.dart';
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
    // v68: VLC-style immersive mode with notch cutout support.
    unawaited(NativeBridge.setImmersive(true));
    _noticeSub = widget.player.notices.listen((m) {
      // v65: the player state posts "Skipped credits" after the auto-skip;
      // surface the Undo chip instead of the generic indicator.
      if (m == 'Skipped credits') {
        setState(() {
          _showCreditsUndo = true;
          _creditsUndoShownAt = DateTime.now();
        });
        return;
      }
      _showIndicator(m, Icons.history);
    });
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
    unawaited(NativeBridge.setImmersive(false));
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
      // v100: camera never runs in the background.
      unawaited(widget.player.setDrowsyForeground(false));
      if (!widget.player.backgroundAudio) {
        widget.player.pause();
      }
      // v63 Phase 2: when the user leaves the player mid-video, offer a
      // "Continue watching" notification (only if the video is actually
      // resumable; the service enforces the 5%..95% + cool-down rules).
      unawaited(
        NotificationService.notifyContinueWatching(widget.player.history),
      );
    } else if (state == AppLifecycleState.resumed) {
      // Coming back to the app: the resume nudge is no longer needed.
      unawaited(NotificationService.cancelContinueWatching());
      // v100: re-arm the camera watchers (if the user enabled them).
      unawaited(widget.player.setDrowsyForeground(true));
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
    widget.player.setBackgroundAudio(s.backgroundAudio);
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

  /// v65: briefly true after we auto-skipped the credits so the "Undo" chip
  /// can be shown. Reset by track changes / time.
  bool _showCreditsUndo = false;
  static const Duration _creditsUndoWindow = Duration(seconds: 8);
  DateTime? _creditsUndoShownAt;

  /// Builds either the "Skip intro" chip or the "Skipped credits · Undo"
  /// chip (whichever applies right now). v65 made intro-skipping automatic
  /// and added credits detection; there is no settings toggle anymore.
  Widget _buildSmartSkipChip() {
    // 1) Undo a recent credits auto-skip.
    if (_showCreditsUndo) {
      final shownAt = _creditsUndoShownAt;
      if (shownAt != null &&
          DateTime.now().difference(shownAt) <= _creditsUndoWindow) {
        return _chip(
          icon: Icons.undo,
          label: 'Skipped credits',
          action: 'Undo',
          onTap: () {
            widget.player.undoSkipCredits();
            setState(() => _showCreditsUndo = false);
          },
          onClose: () => setState(() => _showCreditsUndo = false),
        );
      }
      _showCreditsUndo = false;
    }

    // 2) Skip intro (while before the dialogue starts).
    final at = widget.player.skipIntroAt;
    if (at != null) {
      final pos = widget.player.position;
      final untimely = pos >= at - const Duration(seconds: 1) ||
          pos > const Duration(minutes: 10);
      if (_skipChipDismissedFor != at && !untimely) {
        // Listen for the player's "Skipped credits" notice so we can flip
        // into the Undo chip once credits auto-skip (done once, cheap).
        return _chip(
          icon: Icons.fast_forward,
          label: 'Skip intro',
          action: formatDuration(at),
          onTap: () {
            widget.player.seek(at);
            setState(() => _skipChipDismissedFor = at);
            _onUserInteraction();
          },
          onClose: () => setState(() => _skipChipDismissedFor = at),
        );
      }
    }
    return const SizedBox.shrink();
  }

  Widget _chip({
    required IconData icon,
    required String label,
    required String action,
    required VoidCallback onTap,
    required VoidCallback onClose,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          decoration: BoxDecoration(
            color: const Color(0xF2152026),
            borderRadius: BorderRadius.circular(20),
            border:
                Border.all(color: themeState.accent.withValues(alpha: 0.65)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: themeState.accent),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                action,
                style: TextStyle(
                  color: themeState.accent,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: onClose,
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.close, size: 14, color: Colors.white54),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

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
                  // v100: auto-detect sleep - the front camera pauses the
                  // video after the user's eyes stay closed for 30 s.
                  // Strictly opt-in (OFF by default); the camera runs only
                  // while a video plays, nothing is recorded or uploaded.
                  StatefulBuilder(
                    builder: (sheetCtx, setSheetState) {
                      return SwitchListTile(
                        secondary: Icon(
                          Icons.visibility_outlined,
                          color: player.autoSleepDetect
                              ? themeState.accent
                              : Colors.white70,
                        ),
                        title: const Text(
                          'Auto-detect sleep',
                          style: TextStyle(color: Colors.white),
                        ),
                        subtitle: const Text(
                          'Front camera pauses when eyes stay closed 30s',
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                        value: player.autoSleepDetect,
                        activeThumbColor: themeState.accent,
                        onChanged: (v) async {
                          if (v) {
                            final st = await Permission.camera.request();
                            if (!st.isGranted) {
                              _showIndicator(
                                'Camera permission needed for sleep detect',
                                Icons.videocam_off_outlined,
                              );
                              return;
                            }
                          }
                          await player.setAutoSleepDetect(v);
                          setSheetState(() {});
                          _onUserInteraction();
                        },
                      );
                    },
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
        // v63 Phase 2: ongoing "Casting to <TV>" notification; tapping it
        // brings the app (and its remote controls) back to the front.
        final tvName = _castState.current?.name ?? '';
        unawaited(NotificationService.notifyCasting(tvName));
      },
      onCastStopped: (tvPos) async {
        // Hand playback back to the phone at the TV's position.
        if (tvPos > Duration.zero) await widget.player.seek(tvPos);
        await widget.player.resumePlayback();
        unawaited(NotificationService.cancelCasting());
        if (mounted) _showIndicator('Back on this phone', Icons.smartphone);
      },
    );
  }

  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final player = widget.player;
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

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
        // v19/v70: no Scaffold AppBar anymore - the title + actions live in an
        // auto-hiding top overlay INSIDE the video stack. In landscape/fullscreen,
        // left and right insets are released so video bleeds 100% under punch hole.
        body: SafeArea(
          top: !_isFullscreen,
          left: !isLandscape,
          right: !isLandscape,
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
                          // zoom / resume / fit / play-pause) - pill pops
                          // with scale+fade; values swap instantly (v100:
                          // the cross-fade blinked during swipes).
                          Positioned(
                            top: 64,
                            left: 0,
                            right: 0,
                            child: IgnorePointer(
                              child: Center(
                                child: AnimatedScale(
                                  scale: (_indicatorText != null && !_isPip) ? 1.0 : 0.85,
                                  duration: const Duration(milliseconds: 200),
                                  curve: Curves.easeOutBack,
                                  child: AnimatedOpacity(
                                    duration: const Duration(milliseconds: 200),
                                    curve: Curves.easeOutCubic,
                                    opacity: (_indicatorText != null && !_isPip) ? 1.0 : 0.0,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF161622).withValues(alpha: 0.88),
                                        borderRadius: BorderRadius.circular(24),
                                        border: Border.all(
                                          color: themeState.accent.withValues(alpha: 0.35),
                                          width: 1.2,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(alpha: 0.45),
                                            blurRadius: 16,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (_indicatorIcon != null) ...[
                                            Icon(_indicatorIcon, color: themeState.accent, size: 20),
                                            const SizedBox(width: 8),
                                          ],
                                          Text(
                                            _indicatorText ?? '',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 14.5,
                                              fontWeight: FontWeight.bold,
                                              letterSpacing: 0.2,
                                            ),
                                          ),
                                        ],
                                      ),
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
                          // v21/v65 Smart skip: a "Skip intro" chip while
                          // the AI/sidecar captions say the dialogue hasn't
                          // started yet (now automatic - no settings toggle),
                          // plus an "Undo" chip right after auto-skipping
                          // the end credits.
                          if (!_isPip)
                            Positioned(
                              right: 14,
                              bottom: 132,
                              child: AnimatedBuilder(
                                animation: widget.player,
                                builder: (context, _) => _buildSmartSkipChip(),
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

  /// Player more-actions menu (v93): sleek, compact native popup menu.
  Widget _topMenu(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'More actions',
      icon: Icon(Icons.more_vert, size: 22, color: themeState.accent),
      color: const Color(0xFF1a1a24),
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      onSelected: (v) {
        _onUserInteraction();
        switch (v) {
          case 'info':
            VideoInfoSheet.show(context, widget.player);
            break;
          case 'eq':
            EqualizerSheet.show(context, widget.player);
            break;
          case 'shot':
            _takeScreenshot();
            break;
          case 'cast':
            _openCast();
            break;
          case 'pip':
            NativeBridge.enterPip(playing: widget.player.isPlaying);
            break;
          case 'sleep':
            _showSleepSheet();
            break;
        }
      },
      itemBuilder: (context) => [
        _topMenuItem('info', Icons.info_outline, 'Video info'),
        _topMenuItem('eq', Icons.graphic_eq, 'Equalizer & Audio FX'),
        // v99: always shown - the Player-settings toggles are gone, so
        // there is nothing left to gate these behind.
        _topMenuItem('shot', Icons.camera_alt_outlined, 'Screenshot'),
        _topMenuItem('cast', Icons.cast_outlined, 'Cast to TV'),
        _topMenuItem(
          'pip',
          Icons.picture_in_picture_alt_outlined,
          'Picture-in-Picture',
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
      height: 44,
      child: Row(
        children: [
          Icon(icon, size: 19, color: themeState.accent),
          const SizedBox(width: 12),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13.5,
              fontWeight: FontWeight.w500,
            ),
          ),
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
