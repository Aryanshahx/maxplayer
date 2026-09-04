#!/usr/bin/env bash
# v98: voice control (tap-to-talk), picture quality toggles, gentle sleep
# fade-out; removes Cast to TV + Screenshot from the player UI.
# All Dart, no new dependencies, no native/manifest changes.
#
# Run from the repo root:  bash update_v98.sh
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
    'version: 1.0.0+97',
    'version: 1.0.0+98')

# ------------------------------------------------------- player_settings
rep('lib/state/player_settings.dart',
    '''    this.enhanceVideo = false,
    this.toneMapping = 'auto',
  });''',
    '''    this.enhanceVideo = false,
    this.toneMapping = 'auto',
    this.voiceControl = true,
    this.gentleWindDown = true,
    this.qualityUpscale = false,
    this.smoothMotion = false,
  });''')

rep('lib/state/player_settings.dart',
    '''  /// v32: mpv tone-mapping curve for HDR sources ('auto' | 'clip' |
  /// 'mobius' | 'hable' | 'bt.2390').
  final String toneMapping;''',
    '''  /// v32: mpv tone-mapping curve for HDR sources ('auto' | 'clip' |
  /// 'mobius' | 'hable' | 'bt.2390').
  final String toneMapping;

  /// v98: mic button in the player top bar (tap-to-talk voice commands).
  /// ON by default. The mic is ONLY live while the voice sheet is open -
  /// there is no always-on listening.
  final bool voiceControl;

  /// v98: sleep timer fades the volume out over ~18 s instead of pausing
  /// abruptly. ON by default.
  final bool gentleWindDown;

  /// v98: high-quality mpv scalers for old 480p/720p videos (track sheet >
  /// Picture quality). OFF by default - costs GPU on weak phones.
  final bool qualityUpscale;

  /// v98: mpv motion interpolation for smoother 24/30 fps playback
  /// (track sheet > Picture quality). OFF by default.
  final bool smoothMotion;''')

rep('lib/state/player_settings.dart',
    """  static const String kEnhanceVideo = 'player.enhanceVideo';
  static const String kToneMapping = 'player.toneMapping';""",
    """  static const String kEnhanceVideo = 'player.enhanceVideo';
  static const String kToneMapping = 'player.toneMapping';
  static const String kVoiceControl = 'player.voiceControl';
  static const String kGentleWindDown = 'player.gentleWindDown';
  static const String kQualityUpscale = 'player.qualityUpscale';
  static const String kSmoothMotion = 'player.smoothMotion';""")

rep('lib/state/player_settings.dart',
    '''      enhanceVideo: s[kEnhanceVideo] == 'true',
      toneMapping: kToneMappingModes.contains(s[kToneMapping])
          ? s[kToneMapping]!
          : d.toneMapping,
    );''',
    '''      enhanceVideo: s[kEnhanceVideo] == 'true',
      toneMapping: kToneMappingModes.contains(s[kToneMapping])
          ? s[kToneMapping]!
          : d.toneMapping,
      voiceControl: s[kVoiceControl] != 'false',
      gentleWindDown: s[kGentleWindDown] != 'false',
      qualityUpscale: s[kQualityUpscale] == 'true',
      smoothMotion: s[kSmoothMotion] == 'true',
    );''')

rep('lib/state/player_settings.dart',
    """    NativeBridge.saveSetting(kEnhanceVideo, '$enhanceVideo');
    return NativeBridge.saveSetting(kToneMapping, toneMapping);
  }""",
    """    NativeBridge.saveSetting(kEnhanceVideo, '$enhanceVideo');
    NativeBridge.saveSetting(kToneMapping, toneMapping);
    NativeBridge.saveSetting(kVoiceControl, '$voiceControl');
    NativeBridge.saveSetting(kGentleWindDown, '$gentleWindDown');
    NativeBridge.saveSetting(kQualityUpscale, '$qualityUpscale');
    return NativeBridge.saveSetting(kSmoothMotion, '$smoothMotion');
  }""")

rep('lib/state/player_settings.dart',
    '''    bool? enhanceVideo,
    String? toneMapping,
  }) {''',
    '''    bool? enhanceVideo,
    String? toneMapping,
    bool? voiceControl,
    bool? gentleWindDown,
    bool? qualityUpscale,
    bool? smoothMotion,
  }) {''')

rep('lib/state/player_settings.dart',
    '''      enhanceVideo: enhanceVideo ?? this.enhanceVideo,
      toneMapping: toneMapping ?? this.toneMapping,
    );''',
    '''      enhanceVideo: enhanceVideo ?? this.enhanceVideo,
      toneMapping: toneMapping ?? this.toneMapping,
      voiceControl: voiceControl ?? this.voiceControl,
      gentleWindDown: gentleWindDown ?? this.gentleWindDown,
      qualityUpscale: qualityUpscale ?? this.qualityUpscale,
      smoothMotion: smoothMotion ?? this.smoothMotion,
    );''')

# ---------------------------------------------------- media_player_state
rep('lib/state/media_player_state.dart',
    '''    // Restore equalizer & audio optimization settings.
    dialogueBoost = s[PlayerSettings.kDialogueBoost] == 'true';''',
    '''    // Restore equalizer & audio optimization settings.
    // v98: also restore the wind-down + picture-quality flags.
    gentleWindDown = s[PlayerSettings.kGentleWindDown] != 'false';
    qualityUpscale = s[PlayerSettings.kQualityUpscale] == 'true';
    smoothMotion = s[PlayerSettings.kSmoothMotion] == 'true';
    dialogueBoost = s[PlayerSettings.kDialogueBoost] == 'true';''')

rep('lib/state/media_player_state.dart',
    '''  Future<void> _fireSleepTimer() async {
    cancelSleepTimer();
    _notices.add('Sleep timer paused playback');
    await pause();
  }''',
    '''  Future<void> _fireSleepTimer() async {
    cancelSleepTimer();
    // v98: wind down gently instead of stopping abruptly (when enabled,
    // playing, and something is actually open).
    if (gentleWindDown && isPlaying && currentTrack != null) {
      await _fadeVolumeAndPause();
      _notices.add('Sleep timer paused playback');
      notifyListeners();
      return;
    }
    _notices.add('Sleep timer paused playback');
    await pause();
  }''')

rep('lib/state/media_player_state.dart',
    '''  void _checkSleepAtEnd(Duration pos) {
    if (!_sleepAtEndOfVideo || duration <= Duration.zero) return;
    if (duration - pos <= const Duration(milliseconds: 1500)) {
      cancelSleepTimer();
      _notices.add('Sleep timer: stopped at end of video');
      pause();
    }
  }''',
    '''  void _checkSleepAtEnd(Duration pos) {
    if (!_sleepAtEndOfVideo || duration <= Duration.zero) return;
    if (duration - pos <= const Duration(milliseconds: 1500)) {
      cancelSleepTimer();
      _notices.add('Sleep timer: stopped at end of video');
      pause();
    }
  }

  // ---------------------------------------------------------------------------
  // v98: gentle sleep wind-down + picture-quality toggles.
  //
  // Wind-down: when the sleep timer fires, the volume fades out over ~18 s
  // instead of pausing abruptly (the device MEDIA volume is stepped down,
  // then restored so the next video starts at the user's real level). ON by
  // default; the sleep sheet toggles it. Front-camera eye tracking is NOT
  // part of this build - it needs a CAMERA permission, an on-device face
  // model and real-device testing, so it stays a follow-up, not a stub.
  //
  // Picture quality: two OPT-IN mpv render switches for old 480p/720p
  // files and 24 fps judder. These are stock mpv scalers / interpolator -
  // NOT an ML upscaler (those need native GPU models that would undo the
  // v97 low-end gains). OFF by default; the v97 fast profile stays until
  // the user opts in. Applied live AND re-asserted for every new file,
  // like Enhance.
  // ---------------------------------------------------------------------------

  /// v98: fade-out instead of an abrupt sleep stop. Persisted.
  bool gentleWindDown = true;

  Future<void> setGentleWindDown(bool on) async {
    gentleWindDown = on;
    NativeBridge.saveSetting(PlayerSettings.kGentleWindDown, '$on');
    notifyListeners();
  }

  Future<void> _fadeVolumeAndPause() async {
    final startVol = volume;
    _notices.add('Sleep timer: fading out...');
    notifyListeners();
    try {
      for (var i = 9; i >= 1; i--) {
        await Future<void>.delayed(const Duration(seconds: 2));
        // User paused mid-fade, or left the player: stop touching volume.
        if (!isPlaying || currentTrack == null) break;
        await setVolume(startVol * i / 10);
      }
    } catch (_) {}
    await pause();
    try {
      await setVolume(startVol);
    } catch (_) {}
  }

  /// v98: high-quality upscaling scalers for old low-res videos.
  bool qualityUpscale = false;

  /// v98: mpv motion interpolation (smoother 24/30 fps motion).
  bool smoothMotion = false;

  /// v98: upscale render properties (mpv's own high-quality scalers).
  static const Map<String, String> kQualityUpscaleProps = {
    'scale': 'spline36',
    'cscale': 'spline36',
    'dscale': 'mitchell',
    'dither-depth': 'auto',
    'correct-downscaling': 'yes',
  };

  /// v98: v97 fast-profile values, restored when upscaling is turned off.
  static const Map<String, String> kQualityFastProps = {
    'scale': 'bilinear',
    'cscale': 'bilinear',
    'dscale': 'bilinear',
    'dither-depth': 'no',
    'correct-downscaling': 'no',
  };

  /// v98: smooth-motion properties (mpv frame interpolation).
  static const Map<String, String> kSmoothMotionProps = {
    'interpolation': 'yes',
    'tscale': 'oversample',
  };

  /// v98: interpolation off (matches the v97 fast profile).
  static const Map<String, String> kSmoothMotionOffProps = {
    'interpolation': 'no',
  };

  /// Pushes the current quality toggles into mpv. Safe to call any time:
  /// a non-native platform or a rejected property is ignored.
  Future<void> _applyQualityProps() async {
    final plat = player.platform;
    if (plat is! NativePlayer) return;
    try {
      final q = qualityUpscale ? kQualityUpscaleProps : kQualityFastProps;
      for (final e in q.entries) {
        await plat.setProperty(e.key, e.value);
      }
      final m = smoothMotion ? kSmoothMotionProps : kSmoothMotionOffProps;
      for (final e in m.entries) {
        await plat.setProperty(e.key, e.value);
      }
    } catch (_) {}
  }

  Future<void> setQualityUpscale(bool on) async {
    qualityUpscale = on;
    NativeBridge.saveSetting(PlayerSettings.kQualityUpscale, '$on');
    notifyListeners();
    await _applyQualityProps();
  }

  Future<void> setSmoothMotion(bool on) async {
    smoothMotion = on;
    NativeBridge.saveSetting(PlayerSettings.kSmoothMotion, '$on');
    notifyListeners();
    await _applyQualityProps();
  }''')

rep('lib/state/media_player_state.dart',
    '''      // v38: keep the Enhance pipeline asserted for every new file.
      if (_enhanceApplied && _enhanceShaderPath != null) {
        unawaited(plat.setProperty('glsl-shaders', _enhanceShaderPath!));
        unawaited(plat.setProperty('hwdec', MediaPlayerState.kEnhanceHwdec));
      }''',
    '''      // v38: keep the Enhance pipeline asserted for every new file.
      if (_enhanceApplied && _enhanceShaderPath != null) {
        unawaited(plat.setProperty('glsl-shaders', _enhanceShaderPath!));
        unawaited(plat.setProperty('hwdec', MediaPlayerState.kEnhanceHwdec));
      }
      // v98: keep the picture-quality toggles asserted for every new
      // file (mpv may reset render options when a new file opens).
      unawaited(_applyQualityProps());''')

# --------------------------------------------------------- player_screen
rep('lib/screens/player_screen.dart',
    """import '../widgets/player_controls_overlay.dart';
import '../widgets/player_settings_sheet.dart';""",
    """import '../utils/voice_commands.dart';
import '../widgets/player_controls_overlay.dart';
import '../widgets/player_settings_sheet.dart';""")

rep('lib/screens/player_screen.dart',
    """import '../widgets/playlist_panel.dart';
import '../widgets/video_info_sheet.dart';""",
    """import '../widgets/playlist_panel.dart';
import '../widgets/video_info_sheet.dart';
import '../widgets/voice_search_sheet.dart';""")

rep('lib/screens/player_screen.dart',
    '''    // v32: picture settings - HDR tone-mapping curve + Enhance shader.
    unawaited(widget.player.setToneMapping(s.toneMapping));
    unawaited(widget.player.setEnhanceVideo(s.enhanceVideo));''',
    '''    // v32: picture settings - HDR tone-mapping curve + Enhance shader.
    unawaited(widget.player.setToneMapping(s.toneMapping));
    unawaited(widget.player.setEnhanceVideo(s.enhanceVideo));
    // v98: picture-quality toggles + gentle sleep wind-down.
    unawaited(widget.player.setQualityUpscale(s.qualityUpscale));
    unawaited(widget.player.setSmoothMotion(s.smoothMotion));
    widget.player.setGentleWindDown(s.gentleWindDown);''')

rep('lib/screens/player_screen.dart',
    '''                                        _topMenu(context),
                                        IconButton(
                                          tooltip: 'Player settings',''',
    '''                                        // v98: tap-to-talk voice commands
                                        // (mic is live ONLY while the
                                        // voice sheet is open).
                                        if (_settings.voiceControl)
                                          IconButton(
                                            tooltip: 'Voice control',
                                            icon: Icon(
                                              Icons.mic_outlined,
                                              size: 22,
                                              color: themeState.accent,
                                            ),
                                            onPressed: () {
                                              _onUserInteraction();
                                              _runVoiceCommand();
                                            },
                                          ),
                                        _topMenu(context),
                                        IconButton(
                                          tooltip: 'Player settings',''')

rep('lib/screens/player_screen.dart',
    '''      onCastStopped: (tvPos) async {
        // Hand playback back to the phone at the TV's position.
        if (tvPos > Duration.zero) await widget.player.seek(tvPos);
        await widget.player.resumePlayback();
        unawaited(NotificationService.cancelCasting());
        if (mounted) _showIndicator('Back on this phone', Icons.smartphone);
      },
    );
  }''',
    '''      onCastStopped: (tvPos) async {
        // Hand playback back to the phone at the TV's position.
        if (tvPos > Duration.zero) await widget.player.seek(tvPos);
        await widget.player.resumePlayback();
        unawaited(NotificationService.cancelCasting());
        if (mounted) _showIndicator('Back on this phone', Icons.smartphone);
      },
    );
  }

  // ---------------------------------------------------------------------------
  // v98: tap-to-talk voice commands (play/pause/seek/jump). Speech runs
  // through the existing in-app recognizer (VoiceSearchSheet); the mic is
  // live ONLY while that sheet is open - nothing listens in the
  // background. Text the parser does not understand shows a hint instead
  // of guessing (semantic "when the speaker mentioned X" needs a
  // transcript, and transcript Q&A was removed in v95).
  // ---------------------------------------------------------------------------

  Future<void> _runVoiceCommand() async {
    final text = await VoiceSearchSheet.show(context);
    if (!mounted) return;
    if (text == null || text.trim().isEmpty) return;
    final player = widget.player;
    final cmd = parseVoiceCommand(text);
    if (cmd == null) {
      _showIndicator(
        'Try "pause" or "go back 10 seconds"',
        Icons.mic_none_outlined,
      );
      return;
    }
    if (player.currentTrack == null) {
      _showIndicator('Nothing playing right now', Icons.mic_off_outlined);
      return;
    }
    switch (cmd.action) {
      case VoicePlaybackAction.play:
        await player.resumePlayback();
        _showIndicator('Playing', Icons.play_arrow);
        break;
      case VoicePlaybackAction.pause:
        await player.pause();
        _showIndicator('Paused', Icons.pause);
        break;
      case VoicePlaybackAction.back:
        final s = cmd.seconds ?? _settings.seekSeconds;
        await player.seekBy(-s);
        _showIndicator('Back $s s', Icons.fast_rewind);
        break;
      case VoicePlaybackAction.forward:
        final s = cmd.seconds ?? _settings.seekSeconds;
        await player.seekBy(s);
        _showIndicator('Forward $s s', Icons.fast_forward);
        break;
      case VoicePlaybackAction.jumpTo:
        final target = Duration(seconds: cmd.seconds ?? 0);
        final d = player.duration;
        final clamped = d > Duration.zero && target > d ? d : target;
        await player.seek(clamped);
        _showIndicator(
          'Jumped to ${formatDuration(clamped)}',
          Icons.skip_next,
        );
        break;
    }
  }''')

rep('lib/screens/player_screen.dart',
    """        _topMenuItem('info', Icons.info_outline, 'Video info'),
        _topMenuItem('eq', Icons.graphic_eq, 'Equalizer & Audio FX'),
        if (_settings.screenshotButton)
          _topMenuItem('shot', Icons.camera_alt_outlined, 'Screenshot'),
        if (_settings.castButton)
          _topMenuItem('cast', Icons.cast_outlined, 'Cast to TV'),
        _topMenuItem(""",
    """        _topMenuItem('info', Icons.info_outline, 'Video info'),
        _topMenuItem('eq', Icons.graphic_eq, 'Equalizer & Audio FX'),
        // v98: Screenshot + Cast to TV removed from the player UI at the
        // developer's request (backend kept, nothing deleted on disk).
        _topMenuItem(""")

rep('lib/screens/player_screen.dart',
    '''                  item(
                    Icons.movie_outlined,
                    'Until end of this video',
                    active: label == 'end of video',
                    onTap: () => player.setSleepTimer(atEndOfVideo: true),
                  ),
                  item(Icons.close, 'Off', onTap: player.cancelSleepTimer),''',
    '''                  item(
                    Icons.movie_outlined,
                    'Until end of this video',
                    active: label == 'end of video',
                    onTap: () => player.setSleepTimer(atEndOfVideo: true),
                  ),
                  // v98: gentle wind-down - fade the volume out instead of
                  // stopping abruptly. Camera/eye tracking is NOT in this
                  // build (needs a camera permission + on-device ML + real
                  // device testing); this is the safe part that ships now.
                  StatefulBuilder(
                    builder: (sheetCtx, setSheetState) {
                      return SwitchListTile(
                        secondary: Icon(
                          Icons.nights_stay_outlined,
                          color: player.gentleWindDown
                              ? themeState.accent
                              : Colors.white70,
                        ),
                        title: const Text(
                          'Wind down gently',
                          style: TextStyle(color: Colors.white),
                        ),
                        subtitle: const Text(
                          'Fade the volume out instead of stopping abruptly',
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                        value: player.gentleWindDown,
                        activeThumbColor: themeState.accent,
                        onChanged: (v) {
                          unawaited(player.setGentleWindDown(v));
                          setSheetState(() {});
                          _onUserInteraction();
                        },
                      );
                    },
                  ),
                  item(Icons.close, 'Off', onTap: player.cancelSleepTimer),''')

# -------------------------------------------------- player_settings_sheet
rep('lib/widgets/player_settings_sheet.dart',
    '''              _SwitchTile(
                icon: Icons.cast_outlined,
                label: 'Cast to TV (DLNA)',
                subtitle: 'Show the cast button in the player top bar',
                value: _settings.castButton,
                onChanged: (v) => _update(_settings.copyWith(castButton: v)),
              ),
              _SwitchTile(
                icon: Icons.camera_alt_outlined,
                label: 'Screenshot button',
                subtitle: 'Save the current frame to the gallery',
                value: _settings.screenshotButton,
                onChanged: (v) =>
                    _update(_settings.copyWith(screenshotButton: v)),
              ),
              _SwitchTile(''',
    '''              // v98: Cast to TV + Screenshot removed from the player UI at
              // the developer's request (settings gone with them).
              _SwitchTile(''')

rep('lib/widgets/player_settings_sheet.dart',
    """              const _SectionHeader('Player buttons'),""",
    """              const _SectionHeader('Voice'),
              _SwitchTile(
                icon: Icons.mic_outlined,
                label: 'Voice control',
                subtitle: 'Mic button in the player: say "pause", "go back '
                    '10 seconds" or "jump to 12 minutes". The mic is live '
                    'only while listening.',
                value: _settings.voiceControl,
                onChanged: (v) =>
                    _update(_settings.copyWith(voiceControl: v)),
              ),
              const _SectionHeader('Player buttons'),""")

# --------------------------------------------------- track_selection_sheet
rep('lib/widgets/track_selection_sheet.dart',
    '''          Expanded(
            child: ListView(
              controller: scrollController,
              children:
                  isSubtitle ? _subtitleTiles(context) : _audioTiles(context),
            ),
          ),''',
    '''          Expanded(
            child: ListView(
              controller: scrollController,
              children: [
                ...isSubtitle
                    ? _subtitleTiles(context)
                    : _audioTiles(context),
                // v98: on-device picture quality (mpv render options, no
                // downloads, no accounts). OFF by default: the v97 fast
                // profile stays until the user opts in.
                _QualityFooter(player: player),
              ],
            ),
          ),''')

rep('lib/widgets/track_selection_sheet.dart',
    '''      subtitle: (detail != null && detail!.isNotEmpty)
          ? Text(detail!,
              style: const TextStyle(color: Colors.white38, fontSize: 12))
          : null,
    );
  }
}''',
    '''      subtitle: (detail != null && detail!.isNotEmpty)
          ? Text(detail!,
              style: const TextStyle(color: Colors.white38, fontSize: 12))
          : null,
    );
  }
}

/// v98: on-device picture-quality switches (mpv render options - nothing
/// leaves the phone). Shown under every track list. Upscaling costs GPU
/// and smooth motion costs CPU/GPU, so weak phones may stutter with both
/// on - turn one off if playback lags.
class _QualityFooter extends StatefulWidget {
  final MediaPlayerState player;

  const _QualityFooter({required this.player});

  @override
  State<_QualityFooter> createState() => _QualityFooterState();
}

class _QualityFooterState extends State<_QualityFooter> {
  late bool _upscale = widget.player.qualityUpscale;
  late bool _smooth = widget.player.smoothMotion;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 16, color: Colors.white12),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Text(
            'Picture quality',
            style: TextStyle(
              color: TrackSelectionSheet._accent,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        SwitchListTile(
          dense: true,
          secondary: const Icon(Icons.hd_outlined, color: Colors.white70),
          title: const Text(
            'Upscale old videos',
            style: TextStyle(color: Colors.white, fontSize: 14),
          ),
          subtitle: const Text(
            'Sharper 480p/720p via high-quality scaling. Uses more battery.',
            style: TextStyle(color: Colors.white38, fontSize: 12),
          ),
          value: _upscale,
          activeThumbColor: TrackSelectionSheet._accent,
          onChanged: (v) {
            setState(() => _upscale = v);
            widget.player.setQualityUpscale(v);
          },
        ),
        SwitchListTile(
          dense: true,
          secondary: const Icon(
            Icons.motion_photos_on_outlined,
            color: Colors.white70,
          ),
          title: const Text(
            'Smooth motion',
            style: TextStyle(color: Colors.white, fontSize: 14),
          ),
          subtitle: const Text(
            'Softer 24 fps motion via frame interpolation. Needs a fast phone.',
            style: TextStyle(color: Colors.white38, fontSize: 12),
          ),
          value: _smooth,
          activeThumbColor: TrackSelectionSheet._accent,
          onChanged: (v) {
            setState(() => _smooth = v);
            widget.player.setSmoothMotion(v);
          },
        ),
      ],
    );
  }
}''')

# ------------------------------------------------------------ user_manual
rep('lib/widgets/user_manual_sheet.dart',
    """  _Item(
    Icons.cast_outlined,
    'Cast to TV (top bar)',
    'Tap the cast icon to send the video to any DLNA smart TV or Android '
        'box on the same Wi-Fi. The phone turns into a remote: play/pause, '
        'a live seek slider, and "Stop casting" hands the video back to '
        'the phone right where the TV left off. Closing the player stops '
        'casting. (Chromecast dongles use a different protocol and are '
        'not supported yet.)',
  ),
""",
    '')

rep('lib/widgets/user_manual_sheet.dart',
    """  _Item(
    Icons.camera_alt_outlined,
    'Screenshot (top bar)',
    'Saves the current frame - with any subtitles burned in, exactly as '
        'you see it - as a PNG into Pictures/Max Player, visible in your '
        'gallery at once. Not available for online streams.',
  ),
""",
    '')

rep('lib/widgets/user_manual_sheet.dart',
    """        'multiplier, resume playback, and which extra buttons (cast / '
        'screenshot / lock) show in the player.',""",
    """        'multiplier, resume playback, voice control, and the screen-lock '
        '(kids mode) button.',""")

rep('lib/widgets/user_manual_sheet.dart',
    """    'Player ⋮ menu → Sleep timer: pauses playback after 15/30/45/60 '
        'minutes, or exactly at the end of the current video. While it '
        'runs, the remaining time shows under the video title.',""",
    """    'Player ⋮ menu → Sleep timer: pauses playback after 15/30/45/60 '
        'minutes, or exactly at the end of the current video. While it '
        'runs, the remaining time shows under the video title. With "Wind '
        'down gently" (on by default) the volume fades out first instead '
        'of stopping abruptly.',""")

rep('lib/widgets/user_manual_sheet.dart',
    """  _Item(
    Icons.speed,
    'Playback speed up to 3x',""",
    """  _Item(
    Icons.mic_outlined,
    'Voice control (player mic)',
    'Tap the mic in the player top bar and say "pause", "go back 10 '
        'seconds" or "jump to 12 minutes". The mic is live only while '
        'listening - nothing records in the background. ON by default; '
        'switch it off in player settings → Voice.',
  ),
  _Item(
    Icons.hd_outlined,
    'Picture quality for old videos',
    'Track sheet → Picture quality: "Upscale old videos" sharpens '
        '480p/720p family videos with high-quality scaling, and "Smooth '
        'motion" eases 24 fps judder. Both run fully on-device and are '
        'OFF by default to keep weak phones smooth.',
  ),
  _Item(
    Icons.speed,
    'Playback speed up to 3x',""")

# ------------------------------------------------------- voice_commands
create_new('lib/utils/voice_commands.dart', r'''/// v98: tap-to-talk voice commands for the player.
///
/// The speech itself comes from the existing in-app recognizer
/// (VoiceSearchSheet + the native `startVoiceSearch` channel that search
/// already uses) - this file is only the TEXT -> ACTION parser, kept pure
/// (no Flutter imports) so `flutter test` can pin it without a device.
///
/// Understood (English, case-insensitive):
///   play / resume / start ................. play
///   pause / stop .......................... pause
///   replay / start over / from beginning .. jump to 0:00
///   go back / rewind (N seconds/minutes) .. rewind (default: seek step)
///   skip ahead / forward (N ...) .......... forward jump
///   go to / jump to / seek to N ........... absolute jump
///
/// Anything else (including "go back to when the speaker mentioned the
/// budget" - semantic search needs a transcript, and transcript Q&A was
/// removed in v95) returns null so the UI shows a hint instead of
/// guessing wrong.
enum VoicePlaybackAction { play, pause, back, forward, jumpTo }

class VoiceCommand {
  final VoicePlaybackAction action;

  /// back/forward: relative seconds. jumpTo: absolute seconds. Null when
  /// the user gave no number - the caller falls back to the seek-step
  /// setting (relative) or 0:00 (absolute).
  final int? seconds;

  const VoiceCommand(this.action, [this.seconds]);
}

/// Number words the parser understands next to a time unit.
const Map<String, int> _voiceNumbers = {
  'one': 1,
  'two': 2,
  'three': 3,
  'four': 4,
  'five': 5,
  'six': 6,
  'seven': 7,
  'eight': 8,
  'nine': 9,
  'ten': 10,
  'eleven': 11,
  'twelve': 12,
  'fifteen': 15,
  'twenty': 20,
  'thirty': 30,
  'forty': 40,
  'fifty': 50,
  'sixty': 60,
  'ninety': 90,
};

int _voiceNumberValue(String w) {
  final d = int.tryParse(w);
  if (d != null) return d;
  return _voiceNumbers[w] ?? -1;
}

final RegExp _voiceAmount = RegExp(
  r'(\d+|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|'
  r'fifteen|twenty|thirty|forty|fifty|sixty|ninety)'
  r'\s*(hours?|hrs?|minutes?|mins?|seconds?|secs?|[hms])\b',
);

final RegExp _voiceBareNumber = RegExp(r'\b(\d{1,5})\b');

int _voiceUnitMultiplier(String unit) {
  final u = unit.toLowerCase();
  if (u.startsWith('h')) return 3600;
  if (u.startsWith('m')) return 60;
  return 1;
}

/// Seconds mentioned in [t], or null when there is no number at all.
/// A bare number ("back 10") counts as seconds.
int? _extractVoiceSeconds(String t) {
  final m = _voiceAmount.firstMatch(t);
  if (m != null) {
    final n = _voiceNumberValue(m.group(1)!);
    if (n < 0) return null;
    return n * _voiceUnitMultiplier(m.group(2)!);
  }
  final b = _voiceBareNumber.firstMatch(t);
  if (b != null) return int.tryParse(b.group(1)!);
  return null;
}

bool _hasVoiceWord(String t, String w) =>
    RegExp('\\b' + RegExp.escape(w) + '\\b').hasMatch(t);

/// Parses a recognized voice string into a player action, or null when the
/// text is not a command this player can execute.
VoiceCommand? parseVoiceCommand(String raw) {
  final t = raw.toLowerCase().trim();
  if (t.isEmpty) return null;

  // Absolute jumps first ("go to 12 minutes").
  if (t.contains('go to') ||
      t.contains('jump to') ||
      t.contains('seek to') ||
      t.contains('skip to')) {
    final s = _extractVoiceSeconds(t);
    if (s != null) return VoiceCommand(VoicePlaybackAction.jumpTo, s);
    if (t.contains('start') || t.contains('beginning')) {
      return const VoiceCommand(VoicePlaybackAction.jumpTo, 0);
    }
    return null;
  }
  // Restart from the top.
  if (t.contains('start over') ||
      t.contains('from the beginning') ||
      t.contains('from beginning') ||
      _hasVoiceWord(t, 'replay') ||
      _hasVoiceWord(t, 'restart')) {
    return const VoiceCommand(VoicePlaybackAction.jumpTo, 0);
  }
  // Transport.
  if (_hasVoiceWord(t, 'pause') ||
      _hasVoiceWord(t, 'stop') ||
      t.contains('stop playing') ||
      t.contains('stop the video')) {
    return const VoiceCommand(VoicePlaybackAction.pause);
  }
  if (_hasVoiceWord(t, 'play') ||
      t.contains('resume') ||
      t.contains('continue') ||
      _hasVoiceWord(t, 'start')) {
    return const VoiceCommand(VoicePlaybackAction.play);
  }
  // Relative rewind.
  if (t.contains('go back') ||
      t.contains('come back') ||
      t.contains('rewind') ||
      t.contains('backward') ||
      _hasVoiceWord(t, 'back')) {
    return VoiceCommand(VoicePlaybackAction.back, _extractVoiceSeconds(t));
  }
  // Relative forward.
  if (t.contains('forward') ||
      t.contains('ahead') ||
      _hasVoiceWord(t, 'skip')) {
    return VoiceCommand(VoicePlaybackAction.forward, _extractVoiceSeconds(t));
  }
  return null;
}
''')

# ------------------------------------------------------------- widget_test
rep('test/widget_test.dart',
    '''import 'package:maxplayer/models/video_track.dart';
import 'package:maxplayer/services/tmdb_client.dart';
import 'package:maxplayer/utils/formatters.dart';''',
    '''import 'package:maxplayer/models/video_track.dart';
import 'package:maxplayer/services/tmdb_client.dart';
import 'package:maxplayer/utils/formatters.dart';
import 'package:maxplayer/utils/voice_commands.dart';''')

rep('test/widget_test.dart',
    '''      // The 500ms guaranteed pulse is what keeps the bar from looking frozen.
      expect(s, contains('Timer.periodic(const Duration(milliseconds: 500)'));
    });
  });
}''',
    '''      // The 500ms guaranteed pulse is what keeps the bar from looking frozen.
      expect(s, contains('Timer.periodic(const Duration(milliseconds: 500)'));
    });
  });
  group('v98 voice control, picture quality, wind-down, player cleanup', () {
    test('voice parser maps transport, relative and absolute commands', () {
      expect(parseVoiceCommand('Pause')?.action, VoicePlaybackAction.pause);
      expect(
          parseVoiceCommand('please resume playing')?.action,
          VoicePlaybackAction.play);
      final back = parseVoiceCommand('Go back 30 seconds')!;
      expect(back.action, VoicePlaybackAction.back);
      expect(back.seconds, 30);
      final words = parseVoiceCommand('go back five minutes')!;
      expect(words.action, VoicePlaybackAction.back);
      expect(words.seconds, 300);
      final fwd = parseVoiceCommand('Skip ahead 5 minutes')!;
      expect(fwd.action, VoicePlaybackAction.forward);
      expect(fwd.seconds, 300);
      final jump = parseVoiceCommand('Jump to 12 minutes')!;
      expect(jump.action, VoicePlaybackAction.jumpTo);
      expect(jump.seconds, 720);
      expect(
        parseVoiceCommand('start over')?.action,
        VoicePlaybackAction.jumpTo,
      );
      // Semantic transcript questions are NOT commands (transcript Q&A
      // was removed in v95) - the UI must show a hint, not guess.
      expect(
        parseVoiceCommand('what did the speaker say about the budget'),
        isNull,
      );
      expect(parseVoiceCommand(''), isNull);
    });

    test('Cast to TV and Screenshot are gone from the player UI', () {
      final screen =
          File('lib/screens/player_screen.dart').readAsStringSync();
      expect(screen, contains('Voice control'));
      expect(screen, contains('Wind down gently'));
      expect(screen.contains("'Cast to TV'"), isFalse);
      expect(screen.contains("'Screenshot'"), isFalse);
      final sheet =
          File('lib/widgets/player_settings_sheet.dart').readAsStringSync();
      expect(sheet.contains('Cast to TV (DLNA)'), isFalse);
      expect(sheet.contains('Screenshot button'), isFalse);
      expect(sheet, contains('Voice control'));
    });

    test('picture-quality toggles drive real mpv render properties', () {
      final s = File('lib/state/media_player_state.dart').readAsStringSync();
      expect(s, contains("'scale': 'spline36'"));
      expect(s, contains("'tscale': 'oversample'"));
      expect(s, contains('_applyQualityProps'));
      expect(s, contains('setQualityUpscale'));
      expect(s, contains('setSmoothMotion'));
      // The v97 fast profile must still be the default that OFF restores.
      expect(s, contains("'scale': 'bilinear'"));
      expect(s, contains("'hwdec': 'auto-safe'"));
      final tracks =
          File('lib/widgets/track_selection_sheet.dart').readAsStringSync();
      expect(tracks, contains('Picture quality'));
      expect(tracks, contains('Upscale old videos'));
      expect(tracks, contains('Smooth motion'));
    });

    test('sleep timer winds down gently instead of stopping abruptly', () {
      final s = File('lib/state/media_player_state.dart').readAsStringSync();
      expect(s, contains('gentleWindDown'));
      expect(s, contains('setGentleWindDown'));
      expect(s, contains('_fadeVolumeAndPause'));
      // The abrupt-stop path must still exist for wind-down OFF.
      expect(s, contains("_notices.add('Sleep timer paused playback')"));
    });
  });
}''')

print('ALL v98 PATCHES APPLIED')
PYEOF

echo "--- diff stat ---"
git diff --stat
