import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Playback/player-control preferences shown by the player settings screen.
/// Kept separate from display/app settings so the player gear controls only
/// playback behaviour.
class PlayerSettings extends ChangeNotifier {
  PlayerSettings._();

  static final PlayerSettings instance = PlayerSettings._();

  static const seekSteps = <int>[5, 10, 15, 30];
  /// Long-press speed-boost multipliers (set in player settings).
  static const speedRates = <double>[1.5, 2.0, 2.5, 3.0];
  /// Constant playback-speed choices, 0.5× .. 4.0×.
  static const playbackRates = <double>[
    0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0, 3.5, 4.0,
  ];
  static const autoHideSeconds = <int>[3, 4, 5, 6];
  static const performanceModes = <String>['auto', 'on', 'off'];

  static const _kDoubleTapSides = 'player.doubleTapSides';
  static const _kDoubleTapMiddle = 'player.doubleTapMiddle';
  static const _kSeekStep = 'player.seekStep';
  static const _kSwipeVolume = 'player.swipeVolume';
  static const _kSwipeBrightness = 'player.swipeBrightness';
  static const _kHorizontalSeek = 'player.horizontalSeek';
  static const _kPinchZoom = 'player.pinchZoom.v3';
  static const _kDefaultFit = 'player.defaultFit';
  static const _kLongPressSpeed = 'player.longPressSpeed';
  static const _kLongPressRate = 'player.longPressRate';
  static const _kAutoHide = 'player.autoHide';
  static const _kAutoHideDelay = 'player.autoHideDelay';
  static const _kResume = 'player.resume';
  static const _kScreenLock = 'player.screenLock';
  static const _kVolumeBoost = 'player.volumeBoost';
  static const _kBackgroundAudio = 'player.backgroundAudio';
  static const _kPerformanceMode = 'player.performanceMode';

  bool doubleTapSides = true;
  bool doubleTapMiddle = true;
  int seekStep = 10;
  bool swipeVolume = true;
  bool swipeBrightness = true;
  bool horizontalSeek = true;
  bool pinchZoom = false;

  /// Which of the six fit modes (Fit/Crop/Stretch/16:9/4:3/Original) the
  /// player starts in, and what a two-finger tap snaps back to. 0 = Fit.
  int defaultFit = 0;

  bool longPressSpeed = true;
  double longPressRate = 2.0;
  bool autoHide = true;
  int autoHideDelay = 4;
  bool resume = true;
  bool screenLock = true;
  bool volumeBoost = true;
  bool backgroundAudio = true;

  /// VLC-style low-end profile: 'auto' (default) | 'on' | 'off'.
  String performanceMode = 'auto';

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    doubleTapSides = p.getBool(_kDoubleTapSides) ?? true;
    doubleTapMiddle = p.getBool(_kDoubleTapMiddle) ?? true;
    final storedSeek = p.getInt(_kSeekStep);
    seekStep = seekSteps.contains(storedSeek) ? storedSeek! : 10;
    swipeVolume = p.getBool(_kSwipeVolume) ?? true;
    swipeBrightness = p.getBool(_kSwipeBrightness) ?? true;
    horizontalSeek = p.getBool(_kHorizontalSeek) ?? true;
    pinchZoom = p.getBool(_kPinchZoom) ?? false;
    final storedFit = p.getInt(_kDefaultFit);
    defaultFit = storedFit != null ? storedFit.clamp(0, 5) : 0;
    longPressSpeed = p.getBool(_kLongPressSpeed) ?? true;
    final storedRate = p.getDouble(_kLongPressRate);
    longPressRate = speedRates.contains(storedRate) ? storedRate! : 2.0;
    autoHide = p.getBool(_kAutoHide) ?? true;
    final storedHide = p.getInt(_kAutoHideDelay);
    autoHideDelay = autoHideSeconds.contains(storedHide) ? storedHide! : 4;
    resume = p.getBool(_kResume) ?? true;
    screenLock = p.getBool(_kScreenLock) ?? true;
    volumeBoost = p.getBool(_kVolumeBoost) ?? true;
    backgroundAudio = p.getBool(_kBackgroundAudio) ?? true;
    final storedPerf = p.getString(_kPerformanceMode);
    performanceMode =
        performanceModes.contains(storedPerf) ? storedPerf! : 'auto';
    notifyListeners();
  }

  Future<void> setDoubleTapSides(bool v) async {
    doubleTapSides = v;
    await _saveBool(_kDoubleTapSides, v);
  }

  Future<void> setDoubleTapMiddle(bool v) async {
    doubleTapMiddle = v;
    await _saveBool(_kDoubleTapMiddle, v);
  }

  Future<void> setSeekStep(int v) async {
    seekStep = v;
    notifyListeners();
    await _save((p) => p.setInt(_kSeekStep, v));
  }

  Future<void> setSwipeVolume(bool v) async {
    swipeVolume = v;
    await _saveBool(_kSwipeVolume, v);
  }

  Future<void> setSwipeBrightness(bool v) async {
    swipeBrightness = v;
    await _saveBool(_kSwipeBrightness, v);
  }

  Future<void> setHorizontalSeek(bool v) async {
    horizontalSeek = v;
    await _saveBool(_kHorizontalSeek, v);
  }

  Future<void> setPinchZoom(bool v) async {
    pinchZoom = v;
    await _saveBool(_kPinchZoom, v);
  }

  Future<void> setDefaultFit(int v) async {
    defaultFit = v.clamp(0, 5);
    notifyListeners();
    await _save((p) => p.setInt(_kDefaultFit, defaultFit));
  }

  Future<void> setLongPressSpeed(bool v) async {
    longPressSpeed = v;
    await _saveBool(_kLongPressSpeed, v);
  }

  Future<void> setLongPressRate(double v) async {
    longPressRate = v;
    notifyListeners();
    await _save((p) => p.setDouble(_kLongPressRate, v));
  }

  Future<void> setAutoHide(bool v) async {
    autoHide = v;
    await _saveBool(_kAutoHide, v);
  }

  Future<void> setAutoHideDelay(int v) async {
    autoHideDelay = v;
    notifyListeners();
    await _save((p) => p.setInt(_kAutoHideDelay, v));
  }

  Future<void> setResume(bool v) async {
    resume = v;
    await _saveBool(_kResume, v);
  }

  Future<void> setScreenLock(bool v) async {
    screenLock = v;
    await _saveBool(_kScreenLock, v);
  }

  Future<void> setVolumeBoost(bool v) async {
    volumeBoost = v;
    await _saveBool(_kVolumeBoost, v);
  }

  Future<void> setBackgroundAudio(bool v) async {
    backgroundAudio = v;
    await _saveBool(_kBackgroundAudio, v);
  }

  Future<void> setPerformanceMode(String v) async {
    performanceMode = performanceModes.contains(v) ? v : 'auto';
    notifyListeners();
    await _save((p) => p.setString(_kPerformanceMode, performanceMode));
  }

  Future<void> _saveBool(String key, bool value) async {
    notifyListeners();
    await _save((p) => p.setBool(key, value));
  }

  Future<void> _save(
      Future<bool> Function(SharedPreferences prefs) write) async {
    await write(await SharedPreferences.getInstance());
  }
}

/// Snaps a speed value to the nearest 0.25× step inside the 0.5×–4.0×
/// range (the speed sheet's slider grid). Pure + unit-tested.
double nearestPlaybackRate(double rate) {
  const min = 0.5;
  const max = 4.0;
  final clamped = rate.clamp(min, max);
  final steps = ((clamped - min) / 0.25).round();
  return (min + steps * 0.25).clamp(min, max);
}

