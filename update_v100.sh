#!/usr/bin/env bash
# v100: (1) remove the v99 volume/brightness indicator blink (AnimatedSwitcher
# cross-fade reverted - values swap instantly again, pill pop kept);
# (2) sleep-timer "Auto-detect sleep": front camera pauses the video after
# eyes stay closed 30 s (CAMERA permission, strictly opt-in, off by default);
# (3) "Look-away auto-pause" below Karaoke subtitles (pause when looking away,
# resume on return); (4) "Dialogue boost" row below Karaoke (surfaces the
# existing v72 filter - it had no UI); (5) "Auto volume leveling" row below
# Karaoke (mpv dynaudnorm against sudden loud spikes).
# New deps: camera (+camera_android legacy backend, API 21+) and ML Kit face
# detection (on-device; model downloads once via Play Services). No hand-written
# native code - manifest permission only. Codemagic build is the real check
# for the new plugins; everything degrades silently if the camera/ML fails.
#
# Run from the repo root:  bash update_v100.sh
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
    'version: 1.0.0+99',
    'version: 1.0.0+100')

rep('pubspec.yaml',
    '  permission_handler: ^11.3.1',
    '''  permission_handler: ^11.3.1

  # v100: front-camera drowsiness + look-away detection (both opt-in, off by
  # default). camera_android pins the legacy Camera2 backend (API 21+) instead
  # of the CameraX default; ML Kit face detection is on-device (its model
  # downloads once via Play Services, then works offline).
  camera: ^0.11.0
  camera_android: ^0.10.11+1
  google_mlkit_face_detection: ^0.13.0''')

# ---------------------------------------------------------------- manifest
rep('android/app/src/main/AndroidManifest.xml',
    '''    <!-- v66 A5: voice search in Discover movies section -->
    <uses-permission android:name="android.permission.RECORD_AUDIO" />''',
    '''    <!-- v66 A5: voice search in Discover movies section -->
    <uses-permission android:name="android.permission.RECORD_AUDIO" />

    <!-- v100: opt-in front-camera drowsiness + look-away detection. Requested
         at runtime only when the user flips one of those switches; the camera
         runs only while a video plays. Declare camera use in Play Data Safety. -->
    <uses-permission android:name="android.permission.CAMERA" />''')

# ------------------------------------------------------- player_settings
rep('lib/state/player_settings.dart',
    '''  /// v72: Smart dialogue booster (boosts 1 kHz - 4 kHz vocal clarity band).
  final bool dialogueBoost;''',
    '''  /// v72: Smart dialogue booster (boosts 1 kHz - 4 kHz vocal clarity band).
  final bool dialogueBoost;

  /// v100: sleep timer pauses when the front camera sees closed eyes for
  /// 30 s. Strictly opt-in, OFF by default.
  final bool autoSleepDetect;

  /// v100: pause when the user looks away; resume when they look back.
  /// Strictly opt-in, OFF by default.
  final bool lookAwayPause;

  /// v100: mpv dynamic normalization against sudden loud spikes.
  /// OFF by default.
  final bool autoLeveling;''')

rep('lib/state/player_settings.dart',
    '    this.dialogueBoost = false,',
    '''    this.dialogueBoost = false,
    this.autoSleepDetect = false,
    this.lookAwayPause = false,
    this.autoLeveling = false,''')

rep('lib/state/player_settings.dart',
    "  static const String kDialogueBoost = 'player.dialogueBoost';",
    """  static const String kDialogueBoost = 'player.dialogueBoost';
  static const String kAutoSleepDetect = 'player.autoSleepDetect';
  static const String kLookAwayPause = 'player.lookAwayPause';
  static const String kAutoLeveling = 'player.autoLeveling';""")

rep('lib/state/player_settings.dart',
    "      dialogueBoost: s[kDialogueBoost] == 'true',",
    """      dialogueBoost: s[kDialogueBoost] == 'true',
      autoSleepDetect: s[kAutoSleepDetect] == 'true',
      lookAwayPause: s[kLookAwayPause] == 'true',
      autoLeveling: s[kAutoLeveling] == 'true',""")

rep('lib/state/player_settings.dart',
    "    NativeBridge.saveSetting(kDialogueBoost, '$dialogueBoost');",
    """    NativeBridge.saveSetting(kDialogueBoost, '$dialogueBoost');
    NativeBridge.saveSetting(kAutoSleepDetect, '$autoSleepDetect');
    NativeBridge.saveSetting(kLookAwayPause, '$lookAwayPause');
    NativeBridge.saveSetting(kAutoLeveling, '$autoLeveling');""")

rep('lib/state/player_settings.dart',
    '    bool? dialogueBoost,',
    '''    bool? dialogueBoost,
    bool? autoSleepDetect,
    bool? lookAwayPause,
    bool? autoLeveling,''')

rep('lib/state/player_settings.dart',
    '      dialogueBoost: dialogueBoost ?? this.dialogueBoost,',
    '''      dialogueBoost: dialogueBoost ?? this.dialogueBoost,
      autoSleepDetect: autoSleepDetect ?? this.autoSleepDetect,
      lookAwayPause: lookAwayPause ?? this.lookAwayPause,
      autoLeveling: autoLeveling ?? this.autoLeveling,''')

# ---------------------------------------------------- media_player_state
rep('lib/state/media_player_state.dart',
    "import '../services/native_bridge.dart';",
    """import '../services/drowsy_detector.dart';
import '../services/native_bridge.dart';""")

rep('lib/state/media_player_state.dart',
    '''      player.stream.playing.listen((v) {
        isPlaying = v;
        notifyListeners();''',
    '''      player.stream.playing.listen((v) {
        isPlaying = v;
        notifyListeners();
        // v100: manual resume clears a look-away auto-pause; the camera
        // only runs while it can do something useful.
        if (v) _lookAwayPaused = false;
        unawaited(_syncDrowsy());''')

rep('lib/state/media_player_state.dart',
    '''    dialogueBoost = s[PlayerSettings.kDialogueBoost] == 'true';''',
    '''    autoSleepDetect = s[PlayerSettings.kAutoSleepDetect] == 'true';
    lookAwayPause = s[PlayerSettings.kLookAwayPause] == 'true';
    autoLeveling = s[PlayerSettings.kAutoLeveling] == 'true';
    dialogueBoost = s[PlayerSettings.kDialogueBoost] == 'true';''')

rep('lib/state/media_player_state.dart',
    '    if (eqEnabled || dialogueBoost) _applyAudioFilters();',
    '    if (eqEnabled || dialogueBoost || autoLeveling) _applyAudioFilters();')

rep('lib/state/media_player_state.dart',
    '''  Future<void> setDialogueBoost(bool on) async {
    dialogueBoost = on;
    NativeBridge.saveSetting(PlayerSettings.kDialogueBoost, '$on');
    notifyListeners();
    await _applyAudioFilters();
  }''',
    '''  Future<void> setDialogueBoost(bool on) async {
    dialogueBoost = on;
    NativeBridge.saveSetting(PlayerSettings.kDialogueBoost, '$on');
    notifyListeners();
    await _applyAudioFilters();
  }

  // ---------------------------------------------------------------------------
  // v100: camera watchers (auto sleep-detect + look-away pause) + auto
  // volume leveling. Camera flags are strictly opt-in (default OFF); the
  // shared camera session runs only while a video is present, the app is
  // foregrounded, and playback is active (or look-away paused).
  // ---------------------------------------------------------------------------

  /// v100: pause when the front camera sees closed eyes for 30 s.
  bool autoSleepDetect = false;

  /// v100: pause when the user looks away; resume when they look back.
  bool lookAwayPause = false;

  /// v100: mpv dynamic normalization against sudden loud spikes.
  bool autoLeveling = false;

  final DrowsyDetector _drowsy = DrowsyDetector();
  bool _drowsyForeground = true;
  bool _lookAwayPaused = false;
  bool _drowsyWarned = false;

  Future<void> setAutoSleepDetect(bool on) async {
    autoSleepDetect = on;
    if (on) _drowsyWarned = false;
    NativeBridge.saveSetting(PlayerSettings.kAutoSleepDetect, '$on');
    notifyListeners();
    await _syncDrowsy();
  }

  Future<void> setLookAwayPause(bool on) async {
    lookAwayPause = on;
    if (on) _drowsyWarned = false;
    NativeBridge.saveSetting(PlayerSettings.kLookAwayPause, '$on');
    notifyListeners();
    await _syncDrowsy();
  }

  Future<void> setAutoLeveling(bool on) async {
    autoLeveling = on;
    NativeBridge.saveSetting(PlayerSettings.kAutoLeveling, '$on');
    notifyListeners();
    await _applyAudioFilters();
  }

  /// The app left / returned (the player screen forwards lifecycle events).
  Future<void> setDrowsyForeground(bool fg) async {
    _drowsyForeground = fg;
    await _drowsy.setForeground(fg);
    await _syncDrowsy();
  }

  void _onDrowsyEvent(DrowsyEvent e) {
    switch (e) {
      case DrowsyEvent.sleepPause:
        if (!isPlaying || currentTrack == null) return;
        unawaited(pause());
        _notices.add('Paused - eyes closed for 30s');
        notifyListeners();
      case DrowsyEvent.lookAwayPause:
        if (!isPlaying || currentTrack == null) return;
        _lookAwayPaused = true;
        unawaited(pause());
        _notices.add('Paused - look back to resume');
        notifyListeners();
      case DrowsyEvent.lookBackResume:
        if (!_lookAwayPaused || currentTrack == null) return;
        _lookAwayPaused = false;
        unawaited(resumePlayback());
        _notices.add('Welcome back');
        notifyListeners();
    }
  }

  /// Starts/stops the shared camera session from the current flags.
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
  }''')

rep('lib/state/media_player_state.dart',
    '''  /// v74: Builds the combined audio filter chain (Dialogue booster + Equalizer).
  /// Night Mode DRC was removed in v74 (setting dropped from Settings).''',
    '''  /// v74: Builds the combined audio filter chain (Dialogue booster +
  /// Equalizer + v100 auto leveling). Night Mode DRC was removed in v74
  /// (setting dropped from Settings); v100 leveling is its honest DSP
  /// successor (single-pass dynamics, no lag).''')

rep('lib/state/media_player_state.dart',
    '''  static String buildCombinedAudioFilter({
    bool dialogueBoost = false,
    bool eqEnabled = false,
    List<double> eqGains = const [],
  }) {''',
    '''  static String buildCombinedAudioFilter({
    bool dialogueBoost = false,
    bool eqEnabled = false,
    List<double> eqGains = const [],
    bool autoLeveling = false,
  }) {''')

rep('lib/state/media_player_state.dart',
    '''    if (eqEnabled && eqGains.isNotEmpty) {
      parts.addAll(equalizerFilterParts(eqGains));
    }
    return parts.isEmpty ? '' : 'lavfi=[${parts.join(',')}]';''',
    '''    if (eqEnabled && eqGains.isNotEmpty) {
      parts.addAll(equalizerFilterParts(eqGains));
    }
    if (autoLeveling) {
      // v100: single-pass dynamic normalization against sudden loud
      // spikes. Runs LAST so it levels the boosted/equalized signal.
      parts.add('dynaudnorm=f=150:g=7');
    }
    return parts.isEmpty ? '' : 'lavfi=[${parts.join(',')}]';''')

rep('lib/state/media_player_state.dart',
    '''    final af = buildCombinedAudioFilter(
      dialogueBoost: dialogueBoost,
      eqEnabled: eqEnabled,
      eqGains: eqGains,
    );''',
    '''    final af = buildCombinedAudioFilter(
      dialogueBoost: dialogueBoost,
      eqEnabled: eqEnabled,
      eqGains: eqGains,
      autoLeveling: autoLeveling,
    );''')

rep('lib/state/media_player_state.dart',
    '''  void dispose() {
    _uiTicker?.cancel();''',
    '''  void dispose() {
    unawaited(_drowsy.dispose());
    _uiTicker?.cancel();''')

# --------------------------------------------------------- player_screen
# v100 (1): remove the v99 cross-fade blink - values swap instantly again.
rep('lib/screens/player_screen.dart',
    '''                          // Transient indicator (seek / volume / brightness /
                          // zoom / resume / fit / play-pause) - pill pops
                          // with scale+fade; every content change
                          // cross-fades via AnimatedSwitcher below.''',
    '''                          // Transient indicator (seek / volume / brightness /
                          // zoom / resume / fit / play-pause) - pill pops
                          // with scale+fade; values swap instantly (v100:
                          // the cross-fade blinked during swipes).''')

rep('lib/screens/player_screen.dart',
    '''                                      // v99: content cross-fade - volume /
                                      // brightness / seek values glide out
                                      // and in on every change instead of
                                      // snapping while the pill stays put.
                                      child: AnimatedSwitcher(
                                        duration: const Duration(milliseconds: 160),
                                        reverseDuration: const Duration(milliseconds: 120),
                                        transitionBuilder: (child, animation) {
                                          return FadeTransition(
                                            opacity: animation,
                                            child: ScaleTransition(
                                              scale: Tween<double>(begin: 0.92, end: 1.0).animate(animation),
                                              child: child,
                                            ),
                                          );
                                        },
                                        child: Row(
                                          key: ValueKey(_indicatorKey ?? 'hidden'),
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
                                      ),''',
    '''                                      child: Row(
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
                                      ),''')

rep('lib/screens/player_screen.dart',
    """import 'package:flutter/services.dart';
import 'package:media_kit_video/media_kit_video.dart';""",
    """import 'package:flutter/services.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:permission_handler/permission_handler.dart';""")

rep('lib/screens/player_screen.dart',
    '''  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_isPip) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      if (!widget.player.backgroundAudio) {
        widget.player.pause();
      }''',
    '''  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_isPip) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      // v100: camera never runs in the background.
      unawaited(widget.player.setDrowsyForeground(false));
      if (!widget.player.backgroundAudio) {
        widget.player.pause();
      }''')

rep('lib/screens/player_screen.dart',
    '''    } else if (state == AppLifecycleState.resumed) {
      // Coming back to the app: the resume nudge is no longer needed.
      unawaited(NotificationService.cancelContinueWatching());
    }
  }''',
    '''    } else if (state == AppLifecycleState.resumed) {
      // Coming back to the app: the resume nudge is no longer needed.
      unawaited(NotificationService.cancelContinueWatching());
      // v100: re-arm the camera watchers (if the user enabled them).
      unawaited(widget.player.setDrowsyForeground(true));
    }
  }''')

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
                  item(Icons.close, 'Off', onTap: player.cancelSleepTimer),''')

# ---------------------------------------------- tracks sheet (overlay)
rep('lib/widgets/player_controls_overlay.dart',
    'import \'package:flutter/material.dart\';',
    '''import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';''')

rep('lib/widgets/player_controls_overlay.dart',
    '''              ListTile(
                leading: Icon(
                  karaokeOn
                      ? Icons.closed_caption
                      : Icons.closed_caption_off_outlined,
                  color: karaokeOn ? themeState.accent : Colors.white70,
                ),
                title: Text(
                  karaokeOn ? 'Karaoke subtitles (on)' : 'Karaoke subtitles',
                  style: TextStyle(
                      color:
                          karaokeOn ? themeState.accent : Colors.white),
                ),
                subtitle: const Text(
                  'Words light up - other subtitles hide while on',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  onToggleKaraoke();
                },
              ),
              const SizedBox(height: 8),''',
    '''              ListTile(
                leading: Icon(
                  karaokeOn
                      ? Icons.closed_caption
                      : Icons.closed_caption_off_outlined,
                  color: karaokeOn ? themeState.accent : Colors.white70,
                ),
                title: Text(
                  karaokeOn ? 'Karaoke subtitles (on)' : 'Karaoke subtitles',
                  style: TextStyle(
                      color:
                          karaokeOn ? themeState.accent : Colors.white),
                ),
                subtitle: const Text(
                  'Words light up - other subtitles hide while on',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  onToggleKaraoke();
                },
              ),
              // v100: camera + audio helpers below Karaoke (user request).
              // Switches stay live in the sheet (no pop) so several can be
              // flipped at once; the player state persists each one.
              StatefulBuilder(
                builder: (sbCtx, setSb) {
                  return SwitchListTile(
                    dense: true,
                    secondary: Icon(
                      Icons.visibility_outlined,
                      color: player.lookAwayPause
                          ? themeState.accent
                          : Colors.white70,
                    ),
                    title: const Text(
                      'Look-away auto-pause',
                      style: TextStyle(color: Colors.white, fontSize: 14),
                    ),
                    subtitle: const Text(
                      'Front camera pauses when you look away, resumes when you return. Off by default.',
                      style: TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                    value: player.lookAwayPause,
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
                                    'Camera permission needed for look-away pause'),
                                duration: Duration(milliseconds: 1800),
                              ),
                            );
                          return;
                        }
                      }
                      await player.setLookAwayPause(v);
                      setSb(() {});
                      onInteract();
                    },
                  );
                },
              ),
              StatefulBuilder(
                builder: (sbCtx, setSb) {
                  return SwitchListTile(
                    dense: true,
                    secondary: Icon(
                      Icons.graphic_eq_outlined,
                      color: player.dialogueBoost
                          ? themeState.accent
                          : Colors.white70,
                    ),
                    title: const Text(
                      'Dialogue boost',
                      style: TextStyle(color: Colors.white, fontSize: 14),
                    ),
                    subtitle: const Text(
                      'Lifts quiet speech (1-4 kHz). Same on-device filter as before.',
                      style: TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                    value: player.dialogueBoost,
                    activeThumbColor: themeState.accent,
                    onChanged: (v) async {
                      await player.setDialogueBoost(v);
                      setSb(() {});
                      onInteract();
                    },
                  );
                },
              ),
              StatefulBuilder(
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
              const SizedBox(height: 8),''')

rep('lib/widgets/player_controls_overlay.dart',
    '          5, // handle + subtitles + audio + A-B loop + karaoke + ask AI rows',
    '          8, // handle + subtitles + audio + A-B + karaoke + look-away + dialogue + leveling')

# ------------------------------------------------------------ user_manual
rep('lib/widgets/user_manual_sheet.dart',
    '''  _Item(
    Icons.bedtime_outlined,
    'Sleep timer',
    'Player ⋮ menu → Sleep timer: pauses playback after 15/30/45/60 '
        'minutes, or exactly at the end of the current video. While it '
        'runs, the remaining time shows under the video title.',
  ),''',
    '''  _Item(
    Icons.bedtime_outlined,
    'Sleep timer',
    'Player ⋮ menu → Sleep timer: pauses playback after 15/30/45/60 '
        'minutes, or exactly at the end of the current video. While it '
        'runs, the remaining time shows under the video title.',
  ),
  _Item(
    Icons.visibility_outlined,
    'Auto-detect sleep (camera)',
    'Sleep timer sheet → Auto-detect sleep: the front camera pauses the '
        'video when your eyes stay closed for 30 seconds. Strictly opt-in '
        'and off by default; the camera runs only while a video plays, '
        'nothing is recorded or sent anywhere.',
  ),
  _Item(
    Icons.face_outlined,
    'Look-away auto-pause',
    'Player tune sheet → Look-away auto-pause: looking away for a few '
        'seconds pauses, looking back resumes. Same camera rules as above.',
  ),
  _Item(
    Icons.graphic_eq_outlined,
    'Dialogue boost & volume leveling',
    'Player tune sheet: Dialogue boost lifts quiet speech; Auto volume '
        'leveling smooths sudden loud spikes. Both on-device audio '
        'filters, off by default.',
  ),''')

rep('lib/widgets/user_manual_sheet.dart',
    """        'multiplier, resume playback, and which extra buttons (cast / '
        'screenshot / lock) show in the player.',""",
    """        'multiplier, resume playback, and the screen-lock (kids mode) '
        'button.',""")

# ------------------------------------------------------- drowsy_detector
create_new('lib/services/drowsy_detector.dart', '''/// v100: front-camera drowsiness + look-away detection (both strictly
/// opt-in, off by default).
///
/// Uses the `camera` plugin (front lens, low resolution, no audio, no
/// preview widget - frames only) + ML Kit face detection (on-device; its
/// model downloads once via Play Services, then works offline).
///
/// Two independent watchers share one camera session:
/// * sleep watch: face visible + BOTH eyes closed continuously for 30 s
///   -> [DrowsyEvent.sleepPause]. A missing face FREEZES the timer
///   (looking away is not sleeping).
/// * look-away watch: no face (or extreme head yaw) for 3 s ->
///   [DrowsyEvent.lookAwayPause]; face back afterwards ->
///   [DrowsyEvent.lookBackResume].
///
/// Everything degrades silently: no camera, denied permission (checked by
/// the UI before arming), missing ML model, or a bad frame just means no
/// events fire. [ensureStarted] reports success so the player state can
/// tell the user once when the camera itself will not start.
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

/// Events the detector raises. The player state decides what each means
/// (it knows whether anything is playing).
enum DrowsyEvent {
  /// Eyes closed for the full sleep window.
  sleepPause,

  /// Looked away for the full away window.
  lookAwayPause,

  /// Face back after a look-away pause (resume hint).
  lookBackResume,
}

class DrowsyDetector {
  /// Eye-open probability below this counts as "closed" (ML Kit documents
  /// the value as a confidence, not a measurement - 0.4 is conservative).
  static const double kClosedThreshold = 0.4;

  /// Continuous closed-eye time before a sleep event (the requested 30 s).
  static const Duration kSleepSeconds = Duration(seconds: 30);

  /// Continuous face-absent time before a look-away event.
  static const Duration kAwaySeconds = Duration(seconds: 3);

  /// |head yaw| beyond this counts as "looking away" even with a face.
  static const double kAwayYawDegrees = 45.0;

  /// Frames arrive at ~15-30/s; every Nth frame is classified (CPU stays
  /// trivial next to video decode).
  static const int kFrameStride = 6;

  void Function(DrowsyEvent event)? onEvent;

  CameraController? _controller;
  FaceDetector? _faceDetector;
  bool _wantSleep = false;
  bool _wantLookAway = false;
  bool _foreground = true;
  bool _busy = false;
  int _frameCount = 0;
  bool _starting = false;

  DateTime? _closedSince;
  bool _sleepFired = false;
  DateTime? _awaySince;
  bool _awayFired = false;

  bool get isRunning => _controller?.value.isInitialized ?? false;

  /// (Re)configures which watchers are armed. Starts the camera when at
  /// least one is armed AND the app is foregrounded; stops it otherwise.
  Future<void> configure({required bool sleep, required bool lookAway}) async {
    _wantSleep = sleep;
    _wantLookAway = lookAway;
    if (!_wantSleep && !_wantLookAway) {
      await stop();
      return;
    }
    if (_foreground) await ensureStarted();
  }

  /// The app left / returned. The camera never runs in the background
  /// (battery + the OS camera-indicator rules).
  Future<void> setForeground(bool fg) async {
    _foreground = fg;
    if (!fg) {
      await stop();
    } else if (_wantSleep || _wantLookAway) {
      await ensureStarted();
    }
  }

  /// Starts the shared camera session. True when frames will flow.
  Future<bool> ensureStarted() async {
    if (isRunning) return true;
    if (_starting) return false;
    _starting = true;
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return false;
      final front = cameras.where(
        (c) => c.lensDirection == CameraLensDirection.front,
      );
      final desc = front.isNotEmpty ? front.first : cameras.first;
      final controller = CameraController(
        desc,
        ResolutionPreset.low,
        enableAudio: false,
      );
      await controller.initialize();
      if (!controller.value.isInitialized) {
        await controller.dispose();
        return false;
      }
      _faceDetector ??= FaceDetector(
        options: FaceDetectorOptions(
          enableClassification: true,
          enableTracking: true,
          performanceMode: FaceDetectorMode.fast,
          minFaceSize: 0.15,
        ),
      );
      _controller = controller;
      reset();
      await controller.startImageStream(_onFrame);
      return true;
    } catch (_) {
      await stop();
      return false;
    } finally {
      _starting = false;
    }
  }

  void _onFrame(CameraImage image) {
    if (_busy) return;
    _frameCount++;
    if (_frameCount % kFrameStride != 0) return;
    _busy = true;
    unawaited(_classify(image).whenComplete(() => _busy = false));
  }

  Future<void> _classify(CameraImage image) async {
    final detector = _faceDetector;
    final controller = _controller;
    if (detector == null || controller == null) return;
    try {
      final bytes = _toNv21(image);
      final rotation = InputImageRotationValue.fromRawValue(
            controller.description.sensorOrientation,
          ) ??
          InputImageRotation.rotation0deg;
      final metadata = InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: InputImageFormat.nv21,
        bytesPerRow: image.width,
      );
      final faces = await detector.processImage(
        InputImage.fromBytes(bytes: bytes, metadata: metadata),
      );
      _update(faces.isEmpty ? null : faces.first);
    } catch (_) {
      // A bad frame is dropped - the next one tries again.
    }
  }

  /// YUV_420_888 (3 planes, arbitrary strides) -> packed NV21 (Y + VU).
  /// Converted explicitly instead of requesting NV21 from the plugin, so
  /// this works whatever pixel layout the camera backend hands over.
  static Uint8List _toNv21(CameraImage image) {
    if (image.planes.length < 3) throw StateError('expected 3 planes');
    final w = image.width;
    final h = image.height;
    final out = Uint8List(w * h + (w * h) ~/ 2);
    final y = image.planes[0];
    var o = 0;
    for (var r = 0; r < h; r++) {
      out.setRange(o, o + w, y.bytes, r * y.bytesPerRow);
      o += w;
    }
    // NV21 interleaves V before U, both subsampled 2x2.
    final u = image.planes[1];
    final v = image.planes[2];
    final uRow = u.bytesPerRow;
    final vRow = v.bytesPerRow;
    final uPix = u.bytesPerPixel ?? 1;
    final vPix = v.bytesPerPixel ?? 1;
    for (var r = 0; r < h ~/ 2; r++) {
      var uOff = r * uRow;
      var vOff = r * vRow;
      for (var c = 0; c < w ~/ 2; c++) {
        out[o++] = v.bytes[vOff];
        out[o++] = u.bytes[uOff];
        uOff += uPix;
        vOff += vPix;
      }
    }
    return out;
  }

  void _update(Face? face, [DateTime? nowOverride]) {
    final now = nowOverride ?? DateTime.now();
    final yaw = face?.headEulerAngleY?.abs() ?? 0.0;
    final away = face == null || yaw > kAwayYawDegrees;

    // --- sleep watch: needs a face; absence freezes the timer. ---
    if (_wantSleep && !_sleepFired) {
      final left = face?.leftEyeOpenProbability;
      final right = face?.rightEyeOpenProbability;
      final closed = face != null &&
          left != null &&
          right != null &&
          left < kClosedThreshold &&
          right < kClosedThreshold;
      if (closed) {
        _closedSince ??= now;
        if (now.difference(_closedSince!) >= kSleepSeconds) {
          _sleepFired = true;
          onEvent?.call(DrowsyEvent.sleepPause);
        }
      } else if (face != null) {
        // Eyes verifiably open: the streak (and the fired flag) reset.
        _closedSince = null;
        _sleepFired = false;
      }
    }

    // --- look-away watch. ---
    if (_wantLookAway) {
      if (away) {
        _awaySince ??= now;
        if (!_awayFired && now.difference(_awaySince!) >= kAwaySeconds) {
          _awayFired = true;
          onEvent?.call(DrowsyEvent.lookAwayPause);
        }
      } else {
        _awaySince = null;
        if (_awayFired) {
          _awayFired = false;
          onEvent?.call(DrowsyEvent.lookBackResume);
        }
      }
    }
  }

  /// Clears streaks (fresh arm, or a new video).
  void reset() {
    _closedSince = null;
    _sleepFired = false;
    _awaySince = null;
    _awayFired = false;
  }

  Future<void> stop() async {
    reset();
    final controller = _controller;
    _controller = null;
    try {
      if (controller != null) {
        if (controller.value.isStreamingImages) {
          await controller.stopImageStream();
        }
        await controller.dispose();
      }
    } catch (_) {}
  }

  Future<void> dispose() async {
    onEvent = null;
    await stop();
    try {
      await _faceDetector?.close();
    } catch (_) {}
    _faceDetector = null;
  }
}
''')

# ------------------------------------------------------------- widget_test
rep('test/widget_test.dart',
    '''      expect(ps.contains('if (_settings.screenshotButton)'), isFalse);
      expect(ps.contains('if (_settings.castButton)'), isFalse);
    });
  });
}''',
    '''      expect(ps.contains('if (_settings.screenshotButton)'), isFalse);
      expect(ps.contains('if (_settings.castButton)'), isFalse);
    });
  });
  group('v100 blink removal, camera watchers, audio helpers', () {
    test('volume/brightness values swap instantly again (no blink)', () {
      final ps = File('lib/screens/player_screen.dart').readAsStringSync();
      // The v99 wrapper (and only it) is gone - a pre-existing, unrelated
      // AnimatedSwitcher lives on elsewhere in this file.
      expect(ps.contains("ValueKey(_indicatorKey ?? 'hidden')"), isFalse);
      // The pill pop itself must survive.
      expect(ps, contains('AnimatedScale'));
      expect(ps, contains('AnimatedOpacity'));
      expect(ps, contains('_indicatorKey'));
    });

    test('camera permission + plugins are wired', () {
      final manifest =
          File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      expect(manifest, contains('android.permission.CAMERA'));
      final pub = File('pubspec.yaml').readAsStringSync();
      expect(pub, contains('google_mlkit_face_detection'));
      expect(pub, contains('camera_android'));
      final detector =
          File('lib/services/drowsy_detector.dart').readAsStringSync();
      expect(detector, contains('class DrowsyDetector'));
      expect(detector, contains('leftEyeOpenProbability'));
      expect(detector, contains('FaceDetectorOptions'));
      expect(detector, contains('ResolutionPreset.low'));
      expect(detector, contains('InputImageFormat.nv21'));
    });

    test('player state owns the camera flags + leveling filter', () {
      final s = File('lib/state/media_player_state.dart').readAsStringSync();
      for (final k in [
        'autoSleepDetect',
        'lookAwayPause',
        'autoLeveling',
        'setAutoSleepDetect',
        'setLookAwayPause',
        'setAutoLeveling',
        'setDrowsyForeground',
        '_syncDrowsy',
        'dynaudnorm',
      ]) {
        expect(s, contains(k));
      }
      final settings =
          File('lib/state/player_settings.dart').readAsStringSync();
      for (final k in [
        'kAutoSleepDetect',
        'kLookAwayPause',
        'kAutoLeveling',
      ]) {
        expect(settings, contains(k));
      }
    });

    test('sleep sheet + tracks sheet host the new rows', () {
      final ps = File('lib/screens/player_screen.dart').readAsStringSync();
      expect(ps, contains('Auto-detect sleep'));
      expect(ps, contains('Permission.camera.request'));
      final overlay =
          File('lib/widgets/player_controls_overlay.dart').readAsStringSync();
      for (final k in [
        'Look-away auto-pause',
        'Dialogue boost',
        'Auto volume leveling',
      ]) {
        expect(overlay, contains(k));
      }
    });
  });
}''')

print('ALL v100 PATCHES APPLIED')
PYEOF

echo "--- diff stat ---"
git diff --stat
