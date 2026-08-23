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

  /// v52: which fit mode the player starts in (and a two-finger tap snaps
  /// back to). 0 = Fit screen (the default); indexes match [kFitModeNames].
  final int defaultFitIndex;

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
    this.defaultFitIndex = 0,
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
  static const String kDefaultFitIndex = 'player.defaultFitIndex';

  /// v52: fit modes offered in Settings. MUST stay in the same order as
  /// PlayerScreen's private _fits/_fitNames lists (tested).
  static const List<String> kFitModeNames = [
    'Fit',
    'Crop',
    'Stretch',
    '16:9',
    '4:3',
    'Original',
  ];
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
      defaultFitIndex: (int.tryParse(s[kDefaultFitIndex] ?? '') ??
              d.defaultFitIndex)
          .clamp(0, kFitModeNames.length - 1),
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
    NativeBridge.saveSetting(kDefaultFitIndex, '$defaultFitIndex');
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
    int? defaultFitIndex,
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
      defaultFitIndex: defaultFitIndex ?? this.defaultFitIndex,
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
