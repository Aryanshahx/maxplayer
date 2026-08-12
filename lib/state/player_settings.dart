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
    );
  }

  Future<void> save() {
    NativeBridge.saveSetting(kDoubleTapSeek, '$doubleTapSeek');
    NativeBridge.saveSetting(kSeekSeconds, '$seekSeconds');
    NativeBridge.saveSetting(kDoubleTapPlayPause, '$doubleTapPlayPause');
    NativeBridge.saveSetting(kVolumeSwipe, '$volumeSwipe');
    NativeBridge.saveSetting(kBrightnessSwipe, '$brightnessSwipe');
    NativeBridge.saveSetting(kPinchZoom, '$pinchZoom');
    NativeBridge.saveSetting(kLongPressSpeed, '$longPressSpeed');
    NativeBridge.saveSetting(
        kLongPressMultiplier, longPressMultiplier.toStringAsFixed(1));
    NativeBridge.saveSetting(kAutoHideSeconds, '$autoHideSeconds');
    NativeBridge.saveSetting(kResumePlayback, '$resumePlayback');
    NativeBridge.saveSetting(kHorizontalSeek, '$horizontalSeek');
    NativeBridge.saveSetting(kCastButton, '$castButton');
    NativeBridge.saveSetting(kScreenshotButton, '$screenshotButton');
    return NativeBridge.saveSetting(kLockButton, '$lockButton');
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
    );
  }
}
