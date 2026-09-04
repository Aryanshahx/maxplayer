#!/usr/bin/env bash
# v101: (1) MediaPipe air gestures below Karaoke (palm=play/pause, index
# swipes=seek, two-finger swipes=volume right/brightness left, OK=2x) via the
# hand_landmarker plugin (model bundled, background thread). Pure-Dart
# gesture engine, unit-tested. (2) Face-watch repair: live camera status
# ("Watching…" / "Standby" / "Camera unavailable") in the sleep toggle so a
# dead camera is visible instead of silent. (3) Auto volume leveling deleted
# completely. (4) Dialogue subtitle trimmed.
# Needs Flutter >=3.44 for hand_landmarker (Codemagic latest is fine;
# `flutter upgrade` on old installs). No hand-written native code.
#
# Run from the repo root:  bash update_v101.sh
set -euo pipefail
cd "$(dirname "$0")"

python3 <<'PYEOF'
import sys

def rep(path, old, new, count=1):
    with open(path, 'r', encoding='utf-8') as f:
        src = f.read()
    n = src.count(old)
    if n != count:
        print(f'PATCH FAILED: {path}: expected {count}x, found {n}x')
        print('--- wanted old text (first 400 chars) ---')
        print(old[:400])
        sys.exit(1)
    with open(path, 'w', encoding='utf-8') as f:
        f.write(src.replace(old, new))
    print(f'patched ({n}x): {path}')

def create_new(path, content):
    try:
        with open(path, 'r', encoding='utf-8'):
            print(f'PATCH FAILED: {path} already exists, refusing to overwrite')
            sys.exit(1)
    except FileNotFoundError:
        pass
    with open(path, 'w', encoding='utf-8') as f:
        f.write(content)
    print(f'created: {path}')

# ---------------------------------------------------------------- pubspec
rep('pubspec.yaml',
    'version: 1.0.0+100',
    'version: 1.0.0+101')

rep('pubspec.yaml',
    '  google_mlkit_face_detection: ^0.13.0',
    '''  google_mlkit_face_detection: ^0.13.0

  # v101: MediaPipe air gestures (model bundled with the plugin, inference on
  # a background thread). Needs Flutter >= 3.44 - `flutter upgrade` on old
  # installs; Codemagic's latest stable already satisfies this.
  hand_landmarker: ^3.0.1''')

# ------------------------------------------------------- player_settings
# v101-A: delete autoLeveling completely (7 spots).
rep('lib/state/player_settings.dart',
    '''  /// v100: mpv dynamic normalization against sudden loud spikes.
  /// OFF by default.
  final bool autoLeveling;
''',
    '')
rep('lib/state/player_settings.dart',
    '    this.autoLeveling = false,\n',
    '')
rep('lib/state/player_settings.dart',
    "  static const String kAutoLeveling = 'player.autoLeveling';\n",
    '')
rep('lib/state/player_settings.dart',
    "      autoLeveling: s[kAutoLeveling] == 'true',\n",
    '')
rep('lib/state/player_settings.dart',
    "    NativeBridge.saveSetting(kAutoLeveling, '$autoLeveling');\n",
    '')
rep('lib/state/player_settings.dart',
    '    bool? autoLeveling,\n',
    '')
rep('lib/state/player_settings.dart',
    '      autoLeveling: autoLeveling ?? this.autoLeveling,\n',
    '')

# v101-B: add airGestures flag (opt-in, OFF by default).
rep('lib/state/player_settings.dart',
    '''  /// v100: pause when the user looks away; resume when they look back.
  /// Strictly opt-in, OFF by default.
  final bool lookAwayPause;''',
    '''  /// v100: pause when the user looks away; resume when they look back.
  /// Strictly opt-in, OFF by default.
  final bool lookAwayPause;

  /// v101: MediaPipe air gestures (palm/swipe/OK). Strictly opt-in,
  /// OFF by default.
  final bool airGestures;''')
rep('lib/state/player_settings.dart',
    '    this.lookAwayPause = false,',
    '''    this.lookAwayPause = false,
    this.airGestures = false,''')
rep('lib/state/player_settings.dart',
    "  static const String kLookAwayPause = 'player.lookAwayPause';",
    """  static const String kLookAwayPause = 'player.lookAwayPause';
  static const String kAirGestures = 'player.airGestures';""")
rep('lib/state/player_settings.dart',
    "      lookAwayPause: s[kLookAwayPause] == 'true',",
    """      lookAwayPause: s[kLookAwayPause] == 'true',
      airGestures: s[kAirGestures] == 'true',""")
rep('lib/state/player_settings.dart',
    "    NativeBridge.saveSetting(kLookAwayPause, '$lookAwayPause');",
    """    NativeBridge.saveSetting(kLookAwayPause, '$lookAwayPause');
    NativeBridge.saveSetting(kAirGestures, '$airGestures');""")
rep('lib/state/player_settings.dart',
    '    bool? lookAwayPause,',
    '''    bool? lookAwayPause,
    bool? airGestures,''')
rep('lib/state/player_settings.dart',
    '      lookAwayPause: lookAwayPause ?? this.lookAwayPause,',
    '''      lookAwayPause: lookAwayPause ?? this.lookAwayPause,
      airGestures: airGestures ?? this.airGestures,''')

# ---------------------------------------------------- media_player_state
rep('lib/state/media_player_state.dart',
    "import '../services/drowsy_detector.dart';",
    """import 'package:camera/camera.dart';
import 'package:hand_landmarker/hand_landmarker.dart';

import '../services/drowsy_detector.dart';""")

rep('lib/state/media_player_state.dart',
    "import '../utils/formatters.dart';",
    """import '../utils/air_gestures.dart';
import '../utils/formatters.dart';""")

# v101-A: delete autoLeveling completely (7 spots).
rep('lib/state/media_player_state.dart',
    '''  /// v100: mpv dynamic normalization against sudden loud spikes.
  bool autoLeveling = false;

''',
    '')
rep('lib/state/media_player_state.dart',
    '''  Future<void> setAutoLeveling(bool on) async {
    autoLeveling = on;
    NativeBridge.saveSetting(PlayerSettings.kAutoLeveling, '$on');
    notifyListeners();
    await _applyAudioFilters();
  }

''',
    '')
rep('lib/state/media_player_state.dart',
    '    autoLeveling = s[PlayerSettings.kAutoLeveling] == \'true\';\n',
    '')
rep('lib/state/media_player_state.dart',
    '    if (eqEnabled || dialogueBoost || autoLeveling) _applyAudioFilters();',
    '    if (eqEnabled || dialogueBoost) _applyAudioFilters();')
rep('lib/state/media_player_state.dart',
    '''  /// v74: Builds the combined audio filter chain (Dialogue booster +
  /// Equalizer + v100 auto leveling). Night Mode DRC was removed in v74
  /// (setting dropped from Settings); v100 leveling is its honest DSP
  /// successor (single-pass dynamics, no lag).''',
    '''  /// v74: Builds the combined audio filter chain (Dialogue booster + Equalizer).
  /// Night Mode DRC was removed in v74 (setting dropped from Settings).''')
rep('lib/state/media_player_state.dart',
    '''    List<double> eqGains = const [],
    bool autoLeveling = false,
  }) {''',
    '''    List<double> eqGains = const [],
  }) {''')
rep('lib/state/media_player_state.dart',
    '''    if (autoLeveling) {
      // v100: single-pass dynamic normalization against sudden loud
      // spikes. Runs LAST so it levels the boosted/equalized signal.
      parts.add('dynaudnorm=f=150:g=7');
    }
''',
    '')
rep('lib/state/media_player_state.dart',
    '      autoLeveling: autoLeveling,\n',
    '')

# v101-B: live camera status + air-gesture engine + shared-frame wiring.
rep('lib/state/media_player_state.dart',
    '''  final DrowsyDetector _drowsy = DrowsyDetector();
  bool _drowsyForeground = true;
  bool _lookAwayPaused = false;
  bool _drowsyWarned = false;''',
    '''  final DrowsyDetector _drowsy = DrowsyDetector();
  bool _drowsyForeground = true;
  bool _lookAwayPaused = false;
  bool _drowsyWarned = false;

  /// v101: one-line camera status for the sleep toggle ('off' / 'Standby' /
  /// 'Watching…' / 'Camera unavailable'). v100 was silent on failure, which
  /// is why a dead camera looked like "not working" with no clue.
  String drowsyStatus = 'off';

  /// v101: MediaPipe air gestures (opt-in, OFF by default). Frames come
  /// from the SAME shared camera session as face watching - never a
  /// second controller (two owners cannot open one camera).
  bool airGestures = false;
  HandLandmarkerPlugin? _hands;
  StreamSubscription<List<Hand>>? _handsSub;
  final AirGestureEngine _airEngine = AirGestureEngine();
  int _handFrameSkip = 0;

  /// The player screen sets this to toast what each gesture did.
  void Function(AirAction action)? onAirAction;''')

rep('lib/state/media_player_state.dart',
    '''  Future<void> setLookAwayPause(bool on) async {
    lookAwayPause = on;
    if (on) _drowsyWarned = false;
    NativeBridge.saveSetting(PlayerSettings.kLookAwayPause, '$on');
    notifyListeners();
    await _syncDrowsy();
  }''',
    '''  Future<void> setLookAwayPause(bool on) async {
    lookAwayPause = on;
    if (on) _drowsyWarned = false;
    NativeBridge.saveSetting(PlayerSettings.kLookAwayPause, '$on');
    notifyListeners();
    await _syncDrowsy();
  }

  Future<void> setAirGestures(bool on) async {
    airGestures = on;
    NativeBridge.saveSetting(PlayerSettings.kAirGestures, '$on');
    notifyListeners();
    await _syncDrowsy();
  }''')

rep('lib/state/media_player_state.dart',
    '''  /// Starts/stops the shared camera session from the current flags.
  Future<void> _syncDrowsy() async {
    _drowsy.onEvent = _onDrowsyEvent;
    final want = _drowsyForeground &&
        (autoSleepDetect || lookAwayPause) &&
        currentTrack != null &&
        (isPlaying || _lookAwayPaused);
    await _drowsy.configure(
      sleep: autoSleepDetect && want,
      lookAway: lookAwayPause && want,
    );
    // Camera broken/missing: say so once per arming, then stay quiet.
    if (want && !_drowsyWarned && !_drowsy.isRunning) {
      _drowsyWarned = true;
      _notices.add('Camera unavailable - auto-detect paused');
      notifyListeners();
    }
  }''',
    '''  /// Starts/stops the shared camera session from the current flags.
  /// Air gestures ride the same session but do NOT need playback to be
  /// active (a palm must be able to resume a paused video).
  Future<void> _syncDrowsy() async {
    _drowsy.onEvent = _onDrowsyEvent;
    _drowsy.onFrame = _onSharedCameraFrame;
    final faceArmed = autoSleepDetect || lookAwayPause;
    final faceWant = _drowsyForeground &&
        faceArmed &&
        currentTrack != null &&
        (isPlaying || _lookAwayPaused);
    final handsWant =
        _drowsyForeground && airGestures && currentTrack != null;
    await _drowsy.configure(
      sleep: autoSleepDetect && faceWant,
      lookAway: lookAwayPause && faceWant,
      hands: handsWant,
    );
    await _syncHands(handsWant);
    // v101: live status so a dead camera is VISIBLE (v100's silence is
    // why "not working" gave no clue). The sleep sheet listens to this.
    if (!faceArmed) {
      drowsyStatus = 'off';
    } else if (!faceWant) {
      drowsyStatus = 'Standby';
    } else if (_drowsy.isRunning) {
      drowsyStatus = 'Watching…';
    } else {
      drowsyStatus = 'Camera unavailable';
    }
    // Camera broken/missing: say so once per arming, then stay quiet.
    if (faceWant && !_drowsyWarned && !_drowsy.isRunning) {
      _drowsyWarned = true;
      _notices.add('Camera unavailable - auto-detect paused');
    }
    notifyListeners();
  }

  /// Creates/tears down the MediaPipe plugin with the camera session.
  Future<void> _syncHands(bool want) async {
    if (!want) {
      await _handsSub?.cancel();
      _handsSub = null;
      _hands?.dispose();
      _hands = null;
      return;
    }
    if (_hands != null) return;
    try {
      final plugin = HandLandmarkerPlugin.create(
        numHands: 1,
        minHandDetectionConfidence: 0.6,
      );
      _hands = plugin;
      _handsSub = plugin.landmarkStream.listen(_onHandLandmarks);
    } catch (_) {
      _hands = null;
    }
  }

  /// Shared camera frames also feed MediaPipe (every 3rd - inference is
  /// ~12-17 ms, so this stays far ahead of gesture speeds).
  void _onSharedCameraFrame(CameraImage image) {
    if (!airGestures) return;
    final plugin = _hands;
    if (plugin == null) return;
    _handFrameSkip++;
    if (_handFrameSkip % 3 != 0) return;
    try {
      plugin.processFrame(image, _drowsy.cameraRotation);
    } catch (_) {}
  }

  void _onHandLandmarks(List<Hand> hands) {
    if (!airGestures || currentTrack == null) return;
    final action = _airEngine.push(
      hands.isEmpty
          ? null
          : hands.first.landmarks.map((l) => Point(l.x, l.y)).toList(),
      DateTime.now(),
    );
    if (action == null) return;
    unawaited(applyAirAction(action));
    onAirAction?.call(action);
  }

  /// Runs a recognized air gesture on the player.
  Future<void> applyAirAction(AirAction action) async {
    if (currentTrack == null) return;
    switch (action) {
      case AirAction.playPause:
        await togglePlay();
      case AirAction.seekForward:
        await seekBy(10);
      case AirAction.seekBackward:
        await seekBy(-10);
      case AirAction.volumeUp:
        await setVolume(volume + 0.07);
      case AirAction.volumeDown:
        await setVolume(volume - 0.07);
      case AirAction.brightnessUp:
        await setBrightness((await currentBrightness()) + 0.08);
      case AirAction.brightnessDown:
        await setBrightness((await currentBrightness()) - 0.08);
      case AirAction.speed2x:
        await setPlaybackRate(2.0);
      case AirAction.speed1x:
        await setPlaybackRate(1.0);
    }
  }''')

rep('lib/state/media_player_state.dart',
    '''    autoSleepDetect = s[PlayerSettings.kAutoSleepDetect] == 'true';
    lookAwayPause = s[PlayerSettings.kLookAwayPause] == 'true';''',
    '''    autoSleepDetect = s[PlayerSettings.kAutoSleepDetect] == 'true';
    lookAwayPause = s[PlayerSettings.kLookAwayPause] == 'true';
    airGestures = s[PlayerSettings.kAirGestures] == 'true';''')

rep('lib/state/media_player_state.dart',
    '''  void dispose() {
    unawaited(_drowsy.dispose());''',
    '''  void dispose() {
    unawaited(_handsSub?.cancel());
    _hands?.dispose();
    _drowsy.onFrame = null;
    unawaited(_drowsy.dispose());''')

# ---------------------------------------------------- drowsy_detector
# v101: share the camera session with air gestures (one camera, one owner).
rep('lib/services/drowsy_detector.dart',
    '  void Function(DrowsyEvent event)? onEvent;',
    '''  void Function(DrowsyEvent event)? onEvent;

  /// Every streamed frame is also offered here (air gestures share the
  /// session; a throwing subscriber never breaks face watching).
  void Function(CameraImage image)? onFrame;

  bool _wantHands = false;

  /// Rotation of the owned camera for frame consumers (MediaPipe).
  int get cameraRotation =>
      _controller?.description.sensorOrientation ?? 0;''')

rep('lib/services/drowsy_detector.dart',
    '''  Future<void> configure({required bool sleep, required bool lookAway}) async {
    _wantSleep = sleep;
    _wantLookAway = lookAway;
    if (!_wantSleep && !_wantLookAway) {
      await stop();
      return;
    }
    if (_foreground) await ensureStarted();
  }''',
    '''  Future<void> configure({
    required bool sleep,
    required bool lookAway,
    bool hands = false,
  }) async {
    _wantSleep = sleep;
    _wantLookAway = lookAway;
    _wantHands = hands;
    if (!_wantSleep && !_wantLookAway && !_wantHands) {
      await stop();
      return;
    }
    if (_foreground) await ensureStarted();
  }''')

rep('lib/services/drowsy_detector.dart',
    '    } else if (_wantSleep || _wantLookAway) {',
    '    } else if (_wantSleep || _wantLookAway || _wantHands) {')

rep('lib/services/drowsy_detector.dart',
    '''  void _onFrame(CameraImage image) {
    if (_busy) return;''',
    '''  void _onFrame(CameraImage image) {
    if (onFrame != null) {
      try {
        onFrame!(image);
      } catch (_) {}
    }
    if (_busy) return;''')

# ------------------------------------------------------- air_gestures
create_new('lib/utils/air_gestures.dart', '''/// v101: air-gesture recognition from MediaPipe hand landmarks.
///
/// The landmarks themselves come from the `hand_landmarker` plugin
/// (MediaPipe Hand Landmarker, bundled model, background thread) - this
/// file is only the LANDMARKS -> ACTION engine, kept pure (no Flutter
/// imports, just `dart:math`) so `flutter test` can pin the whole gesture
/// table without a camera or a device.
///
/// Implemented table (normalized 0..1 coords, y grows downwards):
///   Play/Pause ......... open palm, all 5 fingertips above their
///                        knuckles (PIP joints), held steady 300 ms.
///   Seek +10s ........... index tip (8) sweeps left-to-right across 5
///   Seek -10s ........... consecutive frames past a distance threshold.
///   Volume up/down ...... index+middle extended, on the RIGHT half:
///   Brightness up/down . same two fingers on the LEFT half. Vertical
///                        travel past a threshold fires; the baseline
///                        re-arms so a long swipe keeps stepping.
///   2x speed ............ OK sign: thumb tip (4) near index tip (8).
///   1x speed ............ the OK opens again (or the hand leaves).
///
/// Anti-misfire notes: the OK requires index+middle extended (a bare fist
/// never counts); every action has a cooldown; motion baselines go stale
/// after 1.5 s so slow drifts never fire.
import 'dart:math';

/// Player-level gesture actions (the state maps these onto transport calls).
enum AirAction {
  playPause,
  seekForward,
  seekBackward,
  volumeUp,
  volumeDown,
  brightnessUp,
  brightnessDown,
  speed2x,
  speed1x,
}

class _Sample {
  final double v;
  final DateTime at;
  const _Sample(this.v, this.at);
}

class AirGestureEngine {
  // MediaPipe hand landmark indices.
  static const int kThumbTip = 4;
  static const int kThumbMcp = 2;
  static const int kIndexTip = 8;
  static const int kIndexPip = 6;
  static const int kMiddleTip = 12;
  static const int kMiddlePip = 10;
  static const int kRingTip = 16;
  static const int kRingPip = 14;
  static const int kPinkyTip = 20;
  static const int kPinkyPip = 18;
  static const int kPinkyMcp = 17;

  /// Tip must clear its knuckle by this margin to count as extended.
  static const double kExtendMargin = 0.015;

  /// Palm must hold still this long to toggle play/pause.
  static const int kPalmDwellMs = 300;

  /// Palm re-fire cooldown.
  static const int kPalmCooldownMs = 2000;

  /// Swipe samples per decision + max span + travel threshold.
  static const int kSwipeFrames = 5;
  static const double kSwipeDx = 0.10;
  static const int kSwipeWindowMs = 600;

  /// Seek re-fire cooldown.
  static const int kSeekCooldownMs = 1200;

  /// Vertical travel per volume/brightness step + re-fire cooldown.
  static const double kVertDy = 0.06;
  static const int kVertCooldownMs = 450;

  /// Motion baselines older than this re-anchor without firing.
  static const int kVertStaleMs = 1500;

  /// Thumb-index distance that counts as an OK sign + flip debounce.
  static const double kOkDist = 0.045;
  static const int kOkDebounceMs = 800;

  DateTime? _palmSince;
  DateTime _lastPalmFire = DateTime.fromMillisecondsSinceEpoch(0);
  final List<_Sample> _swipeX = [];
  DateTime _lastSeekFire = DateTime.fromMillisecondsSinceEpoch(0);
  bool? _vertLeft;
  double _vertBaseY = 0;
  DateTime _vertLast = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastVertFire = DateTime.fromMillisecondsSinceEpoch(0);
  bool _okActive = false;
  DateTime _lastOkFlip = DateTime.fromMillisecondsSinceEpoch(0);

  static double _dist(Point<double> a, Point<double> b) {
    final dx = a.x - b.x;
    final dy = a.y - b.y;
    return sqrt(dx * dx + dy * dy);
  }

  static bool _ext(List<Point<double>> p, int tip, int pip) =>
      p[tip].y < p[pip].y - kExtendMargin;

  /// Feeds one frame (21 normalized landmarks, or null when no hand is
  /// visible) and returns the fired action, if any.
  AirAction? push(List<Point<double>>? raw, DateTime now) {
    if (raw == null || raw.length < 21) {
      // Hand lost: clear motion streaks; an open-then-gone OK releases 2x.
      _swipeX.clear();
      _vertLeft = null;
      _palmSince = null;
      if (_okActive) {
        _okActive = false;
        _lastOkFlip = now;
        return AirAction.speed1x;
      }
      return null;
    }
    final p = raw;
    final index = _ext(p, kIndexTip, kIndexPip);
    final middle = _ext(p, kMiddleTip, kMiddlePip);
    final ring = _ext(p, kRingTip, kRingPip);
    final pinky = _ext(p, kPinkyTip, kPinkyPip);
    final thumb =
        _dist(p[kThumbTip], p[kPinkyMcp]) > _dist(p[kThumbMcp], p[kPinkyMcp]);

    // OK sign first (thumb tip near index tip, both fingers up).
    final okNow =
        _dist(p[kThumbTip], p[kIndexTip]) < kOkDist && index && middle;
    if (okNow != _okActive &&
        now.difference(_lastOkFlip).inMilliseconds >= kOkDebounceMs) {
      _okActive = okNow;
      _lastOkFlip = now;
      _swipeX.clear();
      _vertLeft = null;
      _palmSince = null;
      return okNow ? AirAction.speed2x : AirAction.speed1x;
    }
    if (_okActive) return null;

    // Open palm: all five extended, held steady 300 ms.
    if (index && middle && ring && pinky && thumb) {
      _palmSince ??= now;
      if (now.difference(_palmSince!).inMilliseconds >= kPalmDwellMs &&
          now.difference(_lastPalmFire).inMilliseconds >= kPalmCooldownMs) {
        _lastPalmFire = now;
        _palmSince = null;
        _swipeX.clear();
        _vertLeft = null;
        return AirAction.playPause;
      }
      return null;
    }
    _palmSince = null;

    // Single index finger: horizontal sweep over 5 consecutive frames.
    if (index && !middle && !ring && !pinky) {
      _swipeX.add(_Sample(p[kIndexTip].x, now));
      while (_swipeX.length > kSwipeFrames) {
        _swipeX.removeAt(0);
      }
      while (_swipeX.length > 1 &&
          now.difference(_swipeX.first.at).inMilliseconds > kSwipeWindowMs) {
        _swipeX.removeAt(0);
      }
      if (_swipeX.length >= kSwipeFrames &&
          now.difference(_lastSeekFire).inMilliseconds >= kSeekCooldownMs) {
        final total = _swipeX.last.v - _swipeX.first.v;
        var ordered = total.abs() > 0;
        for (var i = 1; i < _swipeX.length && ordered; i++) {
          final d = _swipeX[i].v - _swipeX[i - 1].v;
          if (total > 0 ? d < -0.004 : d > 0.004) ordered = false;
        }
        if (ordered && total > kSwipeDx) {
          _lastSeekFire = now;
          _swipeX.clear();
          return AirAction.seekForward;
        }
        if (ordered && total < -kSwipeDx) {
          _lastSeekFire = now;
          _swipeX.clear();
          return AirAction.seekBackward;
        }
      }
      return null;
    }
    _swipeX.clear();

    // Two fingers: vertical travel; the half of the frame picks volume
    // (right) vs brightness (left). Baseline re-arms after each step so
    // one long swipe keeps stepping.
    if (index && middle && !ring && !pinky) {
      final midX = (p[kIndexTip].x + p[kMiddleTip].x) / 2;
      final midY = (p[kIndexTip].y + p[kMiddleTip].y) / 2;
      final left = midX < 0.5;
      if (_vertLeft != left) {
        _vertLeft = left;
        _vertBaseY = midY;
        _vertLast = now;
        return null;
      }
      if (now.difference(_vertLast).inMilliseconds > kVertStaleMs) {
        _vertBaseY = midY;
        _vertLast = now;
        return null;
      }
      _vertLast = now;
      final dy = midY - _vertBaseY;
      if ((dy <= -kVertDy || dy >= kVertDy) &&
          now.difference(_lastVertFire).inMilliseconds >= kVertCooldownMs) {
        _lastVertFire = now;
        _vertBaseY = midY;
        if (left) {
          return dy < 0 ? AirAction.brightnessUp : AirAction.brightnessDown;
        }
        return dy < 0 ? AirAction.volumeUp : AirAction.volumeDown;
      }
      return null;
    }
    _vertLeft = null;
    return null;
  }
}
''')

# --------------------------------------------------------- player_screen
rep('lib/screens/player_screen.dart',
    "import '../utils/formatters.dart';",
    """import '../utils/air_gestures.dart';
import '../utils/formatters.dart';""")

rep('lib/screens/player_screen.dart',
    '''      _showIndicator(m, Icons.history);
    });''',
    '''      _showIndicator(m, Icons.history);
    });
    // v101: air-gesture feedback toasts.
    widget.player.onAirAction = _onAirAction;''')

rep('lib/screens/player_screen.dart',
    '    _noticeSub?.cancel();',
    '''    _noticeSub?.cancel();
    widget.player.onAirAction = null;''')

rep('lib/screens/player_screen.dart',
    '''        unawaited(NotificationService.cancelCasting());
        if (mounted) _showIndicator('Back on this phone', Icons.smartphone);
      },
    );
  }''',
    '''        unawaited(NotificationService.cancelCasting());
        if (mounted) _showIndicator('Back on this phone', Icons.smartphone);
      },
    );
  }

  // ---------------------------------------------------------------------------
  // v101: air-gesture feedback - the state runs the action, the screen
  // shows what happened.
  // ---------------------------------------------------------------------------

  void _onAirAction(AirAction action) {
    if (!mounted) return;
    _onUserInteraction();
    switch (action) {
      case AirAction.playPause:
        _showIndicator('Play / Pause', Icons.pan_tool);
        break;
      case AirAction.seekForward:
        _showIndicator('Forward 10s', Icons.fast_forward);
        break;
      case AirAction.seekBackward:
        _showIndicator('Back 10s', Icons.fast_rewind);
        break;
      case AirAction.volumeUp:
        _showIndicator('Volume up', Icons.volume_up);
        break;
      case AirAction.volumeDown:
        _showIndicator('Volume down', Icons.volume_down);
        break;
      case AirAction.brightnessUp:
        _showIndicator('Brightness up', Icons.brightness_6);
        break;
      case AirAction.brightnessDown:
        _showIndicator('Brightness down', Icons.brightness_6);
        break;
      case AirAction.speed2x:
        _showIndicator('2x speed', Icons.speed);
        break;
      case AirAction.speed1x:
        _showIndicator('1x speed', Icons.speed);
        break;
    }
  }''')

# v101: sleep toggle shows the live camera status (the sheet listens).
rep('lib/screens/player_screen.dart',
    '''                        subtitle: const Text(
                          'Front camera pauses when eyes stay closed 30s',
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),''',
    '''                        subtitle: Text(
                          player.autoSleepDetect
                              ? 'Status: ${player.drowsyStatus}'
                              : 'Front camera pauses when eyes stay closed 30s',
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),''')

# ---------------------------------------------- tracks sheet (overlay)
rep('lib/widgets/player_controls_overlay.dart',
    '''              // v100: camera + audio helpers below Karaoke (user request).
              // Switches stay live in the sheet (no pop) so several can be
              // flipped at once; the player state persists each one.
              StatefulBuilder(''',
    '''              // v100/v101: helpers below Karaoke (user request).
              // Switches stay live in the sheet (no pop) so several can be
              // flipped at once; the player state persists each one.
              StatefulBuilder(
                builder: (sbCtx, setSb) {
                  return SwitchListTile(
                    dense: true,
                    secondary: Icon(
                      Icons.pan_tool_outlined,
                      color: player.airGestures
                          ? themeState.accent
                          : Colors.white70,
                    ),
                    title: const Text(
                      'Air gestures',
                      style: TextStyle(color: Colors.white, fontSize: 14),
                    ),
                    subtitle: const Text(
                      'Palm=play/pause, swipes=seek/volume/brightness, OK=2x. Off by default.',
                      style: TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                    value: player.airGestures,
                    activeThumbColor: themeState.accent,
                    onChanged: (v) async {
                      if (v) {
                        final st = await Permission.camera.request();
                        if (!st.isGranted) {
                          ScaffoldMessenger.of(context)
                            ..clearSnackBars()
                            ..showSnackBar(
                              const SnackBar(
                                content: Text(
                                    'Camera permission needed for air gestures'),
                                duration: Duration(milliseconds: 1800),
                              ),
                            );
                          return;
                        }
                      }
                      await player.setAirGestures(v);
                      setSb(() {});
                      onInteract();
                    },
                  );
                },
              ),
              StatefulBuilder(''')

# v101-A: delete the auto-leveling row completely.
rep('lib/widgets/player_controls_overlay.dart',
    '''              StatefulBuilder(
                builder: (sbCtx, setSb) {
                  return SwitchListTile(
                    dense: true,
                    secondary: Icon(
                      Icons.volume_up_outlined,
                      color: player.autoLeveling
                          ? themeState.accent
                          : Colors.white70,
                    ),
                    title: const Text(
                      'Auto volume leveling',
                      style: TextStyle(color: Colors.white, fontSize: 14),
                    ),
                    subtitle: const Text(
                      'Smooths sudden loud spikes on-device. Off by default.',
                      style: TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                    value: player.autoLeveling,
                    activeThumbColor: themeState.accent,
                    onChanged: (v) async {
                      await player.setAutoLeveling(v);
                      setSb(() {});
                      onInteract();
                    },
                  );
                },
              ),
''',
    '')

# v101: trim the dialogue subtitle as requested.
rep('lib/widgets/player_controls_overlay.dart',
    """                      'Lifts quiet speech (1-4 kHz). Same on-device filter as before.',""",
    """                      'Lifts quiet speech (1-4 kHz). Off by default.',""")

rep('lib/widgets/player_controls_overlay.dart',
    '          8, // handle + subtitles + audio + A-B + karaoke + look-away + dialogue + leveling',
    '          8, // handle + subtitles + audio + A-B + karaoke + air + look-away + dialogue')

# ------------------------------------------------------------ user_manual
rep('lib/widgets/user_manual_sheet.dart',
    '''  _Item(
    Icons.face_outlined,
    'Look-away auto-pause',
    'Player tune sheet → Look-away auto-pause: looking away for a few '
        'seconds pauses, looking back resumes. Same camera rules as above.',
  ),''',
    '''  _Item(
    Icons.face_outlined,
    'Look-away auto-pause',
    'Player tune sheet → Look-away auto-pause: looking away for a few '
        'seconds pauses, looking back resumes. Same camera rules as above. '
        'If it never triggers, the Status line in the sleep sheet tells '
        'whether the camera is actually watching.',
  ),
  _Item(
    Icons.pan_tool_outlined,
    'Air gestures',
    'Player tune sheet → Air gestures: open palm holds play/pause, index '
        'swipes seek ±10s, two-finger swipes on the right change volume '
        'and on the left brightness, OK sign toggles 2x speed. Needs good '
        'light on your hand; off by default.',
  ),''')

rep('lib/widgets/user_manual_sheet.dart',
    '''  _Item(
    Icons.graphic_eq_outlined,
    'Dialogue boost & volume leveling',
    'Player tune sheet: Dialogue boost lifts quiet speech; Auto volume '
        'leveling smooths sudden loud spikes. Both on-device audio '
        'filters, off by default.',
  ),''',
    '''  _Item(
    Icons.graphic_eq_outlined,
    'Dialogue boost',
    'Player tune sheet: Dialogue boost lifts quiet speech. On-device '
        'audio filter, off by default.',
  ),''')

# ------------------------------------------------------------- widget_test
# v101-A: drop the deleted leveling pins from the v100 group.
rep('test/widget_test.dart',
    '''      for (final k in [
        'autoSleepDetect',
        'lookAwayPause',
        'autoLeveling',
        'setAutoSleepDetect',
        'setLookAwayPause',
        'setAutoLeveling',
        'setDrowsyForeground',
        '_syncDrowsy',
        'dynaudnorm',
      ]) {''',
    '''      for (final k in [
        'autoSleepDetect',
        'lookAwayPause',
        'setAutoSleepDetect',
        'setLookAwayPause',
        'setDrowsyForeground',
        '_syncDrowsy',
        'drowsyStatus',
      ]) {''')

rep('test/widget_test.dart',
    '''      for (final k in [
        'Look-away auto-pause',
        'Dialogue boost',
        'Auto volume leveling',
      ]) {''',
    '''      for (final k in [
        'Look-away auto-pause',
        'Dialogue boost',
      ]) {''')

rep('test/widget_test.dart',
    '''import 'package:maxplayer/services/tmdb_client.dart';
import 'package:maxplayer/utils/formatters.dart';''',
    '''import 'package:maxplayer/services/tmdb_client.dart';
import 'package:maxplayer/utils/air_gestures.dart';
import 'package:maxplayer/utils/formatters.dart';''')

rep('test/widget_test.dart',
    '''import 'dart:io';

import 'package:flutter_test/flutter_test.dart';''',
    '''import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';''')

rep('test/widget_test.dart',
    '''    test('sleep sheet + tracks sheet host the new rows', () {''',
    '''    test('v101 engine maps the gesture table', () {
      List<Point<double>> handOf(Map<int, Point<double>> over) {
        final pts = List<Point<double>>.filled(21, const Point(0.5, 0.5));
        over.forEach((k, v) => pts[k] = v);
        return pts;
      }

      // Open palm held 300 ms toggles play/pause.
      final palmEngine = AirGestureEngine();
      final palm = handOf({
        8: const Point(0.3, 0.3),
        6: const Point(0.3, 0.5),
        12: const Point(0.4, 0.3),
        10: const Point(0.4, 0.5),
        16: const Point(0.6, 0.3),
        14: const Point(0.6, 0.5),
        20: const Point(0.7, 0.3),
        18: const Point(0.7, 0.5),
        4: const Point(0.1, 0.3),
        2: const Point(0.2, 0.5),
        17: const Point(0.8, 0.6),
      });
      final t0 = DateTime(2026, 1, 1);
      expect(palmEngine.push(palm, t0), isNull);
      expect(
          palmEngine.push(palm, t0.add(const Duration(milliseconds: 100))),
          isNull);
      expect(
          palmEngine.push(palm, t0.add(const Duration(milliseconds: 350))),
          AirAction.playPause);

      // Index sweep right across 5 frames seeks forward.
      final swipeEngine = AirGestureEngine();
      List<Point<double>> swipeAt(double x) => handOf({
            8: Point(x, 0.3),
            6: const Point(0.3, 0.5),
            12: const Point(0.4, 0.7),
            10: const Point(0.4, 0.5),
          });
      AirAction? fired;
      for (var i = 0; i < 5; i++) {
        fired = swipeEngine.push(
            swipeAt(0.20 + i * 0.055),
            t0.add(Duration(milliseconds: 500 + i * 100)));
      }
      expect(fired, AirAction.seekForward);

      // Two fingers on the right half moving up raises volume.
      final vertEngine = AirGestureEngine();
      List<Point<double>> vertAt(double y) => handOf({
            8: Point(0.70, y),
            6: const Point(0.70, 0.9),
            12: Point(0.75, y),
            10: const Point(0.75, 0.9),
            16: const Point(0.6, 0.9),
            14: const Point(0.6, 0.5),
            20: const Point(0.65, 0.9),
            18: const Point(0.65, 0.5),
          });
      expect(vertEngine.push(vertAt(0.60), t0), isNull);
      expect(vertEngine.push(
          vertAt(0.52), t0.add(const Duration(milliseconds: 100))),
          AirAction.volumeUp);

      // OK closes to 2x, opens back to 1x.
      final okEngine = AirGestureEngine();
      final okClosed = handOf({
        8: const Point(0.50, 0.30),
        6: const Point(0.50, 0.50),
        12: const Point(0.60, 0.30),
        10: const Point(0.60, 0.50),
        4: const Point(0.51, 0.32),
      });
      final okOpen = handOf({
        8: const Point(0.50, 0.30),
        6: const Point(0.50, 0.50),
        12: const Point(0.60, 0.30),
        10: const Point(0.60, 0.50),
        4: const Point(0.20, 0.50),
      });
      expect(okEngine.push(okClosed, t0), AirAction.speed2x);
      expect(
          okEngine.push(okOpen, t0.add(const Duration(milliseconds: 900))),
          AirAction.speed1x);

      // A bare fist is nothing.
      final fistEngine = AirGestureEngine();
      final fist = handOf({
        8: const Point(0.5, 0.7),
        6: const Point(0.5, 0.5),
        12: const Point(0.55, 0.7),
        10: const Point(0.55, 0.5),
        16: const Point(0.6, 0.7),
        14: const Point(0.6, 0.5),
        20: const Point(0.65, 0.7),
        18: const Point(0.65, 0.5),
      });
      expect(fistEngine.push(fist, t0), isNull);
      expect(fistEngine.push(null, t0), isNull);
    });

    test('v101 MediaPipe wiring + leveling deletion', () {
      final pub = File('pubspec.yaml').readAsStringSync();
      expect(pub, contains('hand_landmarker'));
      final s = File('lib/state/media_player_state.dart').readAsStringSync();
      for (final k in [
        'HandLandmarkerPlugin',
        'landmarkStream',
        'processFrame',
        'applyAirAction',
        'onAirAction',
        'setAirGestures',
        'kAirGestures',
      ]) {
        expect(s, contains(k));
      }
      final overlay =
          File('lib/widgets/player_controls_overlay.dart').readAsStringSync();
      expect(overlay, contains('Air gestures'));
      final ps = File('lib/screens/player_screen.dart').readAsStringSync();
      expect(ps, contains('_onAirAction'));
      // Leveling deleted everywhere (settings keys die with it).
      for (final f in [
        'lib/state/media_player_state.dart',
        'lib/state/player_settings.dart',
        'lib/widgets/player_controls_overlay.dart',
        'lib/widgets/user_manual_sheet.dart',
      ]) {
        final src = File(f).readAsStringSync();
        expect(src.contains('autoLeveling'), isFalse);
        expect(src.contains('dynaudnorm'), isFalse);
        expect(src.contains('Auto volume leveling'), isFalse);
      }
      // Dialogue subtitle trimmed as requested.
      expect(
          overlay,
          contains(
              "'Lifts quiet speech (1-4 kHz). Off by default.'"));
      expect(overlay.contains('Same on-device filter as before'), isFalse);
    });

    test('sleep sheet + tracks sheet host the new rows', () {''')

print('ALL v101 PATCHES APPLIED')
PYEOF

python3 - "test/widget_test.dart" <<'PYEOF'
import sys
p = sys.argv[1]
src = open(p).read()

# v101f: the old v100 camera test demanded the kAutoLeveling key back.
# Leveling is deleted, so the test must stop expecting it (+ every other
# camera-flag assertion stays untouched).
src = src.replace("owns the camera flags + leveling filter",
                  "owns the camera flags (v101 keeps flags, leveling deleted)", 1)
src = src.replace("""        'kLookAwayPause',
        'kAutoLeveling',
      ]) {""",
                  """        'kLookAwayPause',
      ]) {""", 1)
open(p, 'w').write(src)
print('patched (1x): test/widget_test.dart')
PYEOF

python3 - "lib/state/media_player_state.dart" <<'PYEOF'
import sys
p = sys.argv[1]
src = open(p).read()

# v101g: scrub the last "leveling" WORDS from comments (the feature itself is
# already deleted - these are just stale comment/doc words).
src = src.replace("re-apply the current gain /\n      // leveling filter for the new file.",
                  "re-apply the current gain /\n      // filter chain for the new file.", 1)
src = src.replace("await _applyAudioFilters(); // equalizer + leveling survive file changes",
                  "await _applyAudioFilters(); // equalizer settings survive file changes", 1)
src = src.replace("auto sleep-detect + look-away pause) + auto\n  // volume leveling. Camera flags",
                  "auto sleep-detect + look-away pause) + v101\n  // air-gesture wiring. Camera flags", 1)
open(p, 'w').write(src)
print('patched (1x): lib/state/media_player_state.dart')
PYEOF

echo "--- diff stat ---"
git diff --stat
