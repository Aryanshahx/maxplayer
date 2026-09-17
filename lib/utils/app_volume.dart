import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Device-independent in-app volume (v1.0.10): a single global level owned by
/// the player, mixed INSIDE mpv (the engine's own `volume` property), never
/// touching the Android media stream. 0..100% is the normal span, 101..200%
/// is a software over-amplification boost exactly like VLC's boost region.
///
/// The level and the muted flag survive app restarts. While a player screen
/// is open the hardware volume keys and the right-side swipe both drive this
/// value instead of the device stream (the keys are intercepted natively).
class AppVolume extends ChangeNotifier {
  AppVolume._();

  static final AppVolume instance = AppVolume._();

  static const _kLevel = 'appVolume.level';
  static const _kMuted = 'appVolume.muted';

  /// Current level, 0..[kAppVolumeMax] percent. Above [kBoostStart] is boost.
  double level = 100;

  /// Muted flag. Kept separate from [level] so unmuting restores the exact
  /// previous level (0% and "muted" are different states, like VLC).
  bool muted = false;

  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final p = await SharedPreferences.getInstance();
    level = clampAppVolume(p.getDouble(_kLevel) ?? 100);
    muted = p.getBool(_kMuted) ?? false;
    notifyListeners();
  }

  /// Sets the level (clamped to 0..200). Raising above zero while muted
  /// clears the muted flag — moving the volume always means "make sound".
  Future<void> setLevel(double v) async {
    final next = clampAppVolume(v);
    if (next == level) return;
    level = next;
    if (level > 0 && muted) muted = false;
    notifyListeners();
    // Persisted pref: device-independent volume is remembered across launches.
    unawaited(_save());
  }

  /// Toggles (or explicitly sets) the muted flag.
  Future<void> setMuted(bool m) async {
    if (m == muted) return;
    muted = m;
    notifyListeners();
    unawaited(_save());
  }

  /// One hardware-key notch: +/-[kKeyStepPct] percentage points.
  Future<void> step(int direction) => setLevel(stepAppVolume(level, direction));

  /// The effective gain mpv should be given right now.
  double get mpvGain => muted ? 0 : level;

  Future<void> _save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setDouble(_kLevel, level);
      await p.setBool(_kMuted, muted);
    } catch (_) {
      // Persistence is best-effort; volume still works in-session.
    }
  }
}

/// Upper bound of the in-app volume scale (VLC-style boost to 200%).
const double kAppVolumeMax = 200.0;

/// Above this level the engine is amplifying (may clip on loud sources).
const double kBoostStart = 100.0;

/// One hardware-key press moves this many percentage points.
const double kKeyStepPct = 5.0;

/// A full 300px vertical swipe covers these many percentage points (same
/// sweep feel as the brightness gesture on the left half of the screen).
const double kSwipeSpanPct = 100.0;
const double kSwipeSpanPx = 300.0;

/// Clamps an arbitrary level into 0..[kAppVolumeMax].
double clampAppVolume(double v) => v.clamp(0.0, kAppVolumeMax).toDouble();

/// One hardware-key notch on the display scale, clamped into range.
double stepAppVolume(double current, int direction) =>
    clampAppVolume(current + direction * kKeyStepPct);

/// Level after a vertical drag of [dyPx] pixels (negative dy = finger moved
/// up = louder), starting from [startLevel]. Positive when should unmute.
double swipeAppVolume(double startLevel, double dyPx) =>
    clampAppVolume(startLevel - dyPx / kSwipeSpanPx * kSwipeSpanPct);

/// Icon bucket for a level (drive HUD/bottom-bar icons consistently).
String appVolumeIconName(double level, bool muted) {
  if (muted || level <= 0) return 'off';
  if (level < 50) return 'down';
  return 'up';
}
