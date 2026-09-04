/// v101: air-gesture recognition from MediaPipe hand landmarks.
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
library;
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
