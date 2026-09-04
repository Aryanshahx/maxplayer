#!/bin/bash
# v105: fully remove air gestures, look-away auto-pause, auto sleep-detect.
# Built for the REAL Pi tree (732ff8e, version 1.0.0+101, v101-era code).
# The committed update_v104.sh expects a v102+v103 tree that was never
# applied on the Pi - do NOT run it; run this instead.
# Also moves Enhance video + HDR tone-mapping from Settings' Picture section
# into the player tune sheet directly below Karaoke subtitles.
set -eu
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

def cut(path, start_marker, end_marker, back_up_to=None):
    with open(path, 'r', encoding='utf-8') as f:
        src = f.read()
    if src.count(start_marker) != 1:
        print(f'PATCH FAILED: {path}: start marker found '
              f'{src.count(start_marker)}x, want 1x: {start_marker[:80]}')
        sys.exit(1)
    if src.count(end_marker) != 1:
        print(f'PATCH FAILED: {path}: end marker found '
              f'{src.count(end_marker)}x, want 1x: {end_marker[:80]}')
        sys.exit(1)
    start = src.index(start_marker)
    if back_up_to is not None:
        try:
            start = src.rindex(back_up_to, 0, start)
        except ValueError:
            print(f'PATCH FAILED: {path}: back_up_to not found: {back_up_to}')
            sys.exit(1)
    end = src.index(end_marker)
    if end <= start:
        print(f'PATCH FAILED: {path}: end marker precedes start marker')
        sys.exit(1)
    with open(path, 'w', encoding='utf-8') as f:
        f.write(src[:start] + src[end:])
    print(f'cut (1x): {path}')

# ------------------------------------------------- version + pubspec
rep('pubspec.yaml', 'version: 1.0.0+101', 'version: 1.0.0+105')
rep('pubspec.yaml',
    """  # v100: front-camera drowsiness + look-away detection (both opt-in, off by
  # default). camera_android pins the legacy Camera2 backend instead of the
  # CameraX default; ML Kit face detection is on-device (its model
  # downloads once via Play Services, then works offline).
  # v101-fix: camera 0.12 (additions only, no Dart API breaks) because
  # hand_landmarker 3 requires camera ^0.12.0+1.
  camera: ^0.12.0+1
  camera_android: ^0.10.11+1
  google_mlkit_face_detection: ^0.13.0

  # v101: MediaPipe air gestures (model bundled with the plugin, inference on
  # a background thread). Needs Flutter >= 3.44 - `flutter upgrade` on old
  # installs; Codemagic's latest stable already satisfies this.
  hand_landmarker: ^3.0.1

  path: ^1.9.0""",
    """  path: ^1.9.0""")

# ------------------------------------------------- manifest
rep('android/app/src/main/AndroidManifest.xml',
    """    <!-- v100: opt-in front-camera drowsiness + look-away detection. Requested
         at runtime only when the user flips one of those switches; the camera
         runs only while a video plays. Declare camera use in Play Data Safety. -->
    <uses-permission android:name="android.permission.CAMERA" />
""",
    "")
PYEOF

for f in lib/services/drowsy_detector.dart lib/utils/air_gestures.dart; do
  if [ ! -f "$f" ]; then
    echo "PATCH FAILED: expected file missing: $f"
    exit 1
  fi
  rm "$f"
  echo "deleted: $f"
done

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

def cut(path, start_marker, end_marker, back_up_to=None):
    with open(path, 'r', encoding='utf-8') as f:
        src = f.read()
    if src.count(start_marker) != 1:
        print(f'PATCH FAILED: {path}: start marker found '
              f'{src.count(start_marker)}x, want 1x: {start_marker[:80]}')
        sys.exit(1)
    if src.count(end_marker) != 1:
        print(f'PATCH FAILED: {path}: end marker found '
              f'{src.count(end_marker)}x, want 1x: {end_marker[:80]}')
        sys.exit(1)
    start = src.index(start_marker)
    if back_up_to is not None:
        try:
            start = src.rindex(back_up_to, 0, start)
        except ValueError:
            print(f'PATCH FAILED: {path}: back_up_to not found: {back_up_to}')
            sys.exit(1)
    end = src.index(end_marker)
    if end <= start:
        print(f'PATCH FAILED: {path}: end marker precedes start marker')
        sys.exit(1)
    with open(path, 'w', encoding='utf-8') as f:
        f.write(src[:start] + src[end:])
    print(f'cut (1x): {path}')

# ------------------------------------------------- settings model
# v105: camera fields/keys/load/save/copyWith go; dialogue, karaoke,
# enhance + tone-mapping keys stay (they persist the relocated rows).
cut('lib/state/player_settings.dart',
    "  /// v100: sleep timer pauses when the front camera sees closed eyes for",
    "  /// v67 B2: keep playing audio when the screen is turned off or app minimised.")
rep('lib/state/player_settings.dart',
    """    this.autoSleepDetect = false,
    this.lookAwayPause = false,
    this.airGestures = false,
""",
    "")
rep('lib/state/player_settings.dart',
    """  static const String kAutoSleepDetect = 'player.autoSleepDetect';
  static const String kLookAwayPause = 'player.lookAwayPause';
  static const String kAirGestures = 'player.airGestures';
""",
    "")
rep('lib/state/player_settings.dart',
    """      autoSleepDetect: s[kAutoSleepDetect] == 'true',
      lookAwayPause: s[kLookAwayPause] == 'true',
      airGestures: s[kAirGestures] == 'true',
""",
    "")
rep('lib/state/player_settings.dart',
    """    NativeBridge.saveSetting(kAutoSleepDetect, '$autoSleepDetect');
    NativeBridge.saveSetting(kLookAwayPause, '$lookAwayPause');
    NativeBridge.saveSetting(kAirGestures, '$airGestures');
""",
    "")
rep('lib/state/player_settings.dart',
    """    bool? autoSleepDetect,
    bool? lookAwayPause,
    bool? airGestures,
""",
    "")
rep('lib/state/player_settings.dart',
    """      autoSleepDetect: autoSleepDetect ?? this.autoSleepDetect,
      lookAwayPause: lookAwayPause ?? this.lookAwayPause,
      airGestures: airGestures ?? this.airGestures,
""",
    "")

# ------------------------------------------------- player state
# v105: camera imports go (foundation stays).
rep('lib/state/media_player_state.dart',
    """import '../models/history_entry.dart';
import '../models/video_track.dart';
import 'package:camera/camera.dart';
import 'package:hand_landmarker/hand_landmarker.dart';

import '../services/drowsy_detector.dart';
import '../services/native_bridge.dart';
import '../utils/air_gestures.dart';
import '../utils/formatters.dart';""",
    """import '../models/history_entry.dart';
import '../models/video_track.dart';

import '../services/native_bridge.dart';
import '../utils/formatters.dart';""")
# v105: playing-listener camera hookup goes.
rep('lib/state/media_player_state.dart',
    """        // v100: manual resume clears a look-away auto-pause; the camera
        // only runs while it can do something useful.
        if (v) _lookAwayPaused = false;
        unawaited(_syncDrowsy());
""",
    "")
# v105: settings-load camera lines go.
rep('lib/state/media_player_state.dart',
    """    autoSleepDetect = s[PlayerSettings.kAutoSleepDetect] == 'true';
    lookAwayPause = s[PlayerSettings.kLookAwayPause] == 'true';
    airGestures = s[PlayerSettings.kAirGestures] == 'true';
""",
    "")
# v105: the whole camera section goes (flags, setters, drowsy/hand wiring,
# applyAirAction). Starts at its header dashes, ends before the v74 audio
# filter section. Dialogue state sits above and stays.
cut('lib/state/media_player_state.dart',
    """  // ---------------------------------------------------------------------------
  // v100: camera watchers (auto sleep-detect + look-away pause) + v101""",
    "  /// v74: Builds the combined audio filter chain")
# v105: dispose camera teardown goes.
rep('lib/state/media_player_state.dart',
    """    unawaited(_handsSub?.cancel());
    _hands?.dispose();
    _drowsy.onFrame = null;
    unawaited(_drowsy.dispose());
""",
    "")
# v105: readable Enhance state for the tune-sheet row.
rep('lib/state/media_player_state.dart',
    "  bool _enhanceApplied = false;\n",
    """  bool _enhanceApplied = false;

  /// v105: readable Enhance state for the tune-sheet row.
  bool get enhanceVideoOn => _enhanceApplied;
""")
# v105: readable + persisted tone-mapping mode for the tune-sheet row.
# The Settings Picture section is gone, so the state owns persistence now
# (player_screen still re-applies the saved value at startup).
rep('lib/state/media_player_state.dart',
    """  Future<void> setToneMapping(String mode) async {
    final plat = player.platform;
    if (plat is! NativePlayer) return;
    try {
      await plat.setProperty('tone-mapping', mode);
    } catch (_) {}
  }""",
    """  /// v105: readable HDR tone-mapping mode for the tune-sheet row.
  String toneMappingMode = 'auto';

  Future<void> setToneMapping(String mode) async {
    toneMappingMode =
        const ['auto', 'mobius', 'hable', 'bt.2390'].contains(mode)
            ? mode
            : 'auto';
    NativeBridge.saveSetting(PlayerSettings.kToneMapping, toneMappingMode);
    final plat = player.platform;
    if (plat is! NativePlayer) return;
    try {
      await plat.setProperty('tone-mapping', toneMappingMode);
    } catch (_) {}
  }""")
PYEOF

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

# ------------------------------------------------- player screen
# v105: camera imports go (Permission was only used for camera requests).
rep('lib/screens/player_screen.dart',
    "import 'package:permission_handler/permission_handler.dart';\n", "")
rep('lib/screens/player_screen.dart',
    "import '../utils/air_gestures.dart';\n", "")
# v105: gesture-feedback hookup goes.
rep('lib/screens/player_screen.dart',
    """    // v101: air-gesture feedback toasts.
    widget.player.onAirAction = _onAirAction;
""",
    "")
rep('lib/screens/player_screen.dart',
    "    widget.player.onAirAction = null;\n", "")
# v105: lifecycle camera re-arm goes.
rep('lib/screens/player_screen.dart',
    """      // v100: camera never runs in the background.
      unawaited(widget.player.setDrowsyForeground(false));
""",
    "")
rep('lib/screens/player_screen.dart',
    """      // v100: re-arm the camera watchers (if the user enabled them).
      unawaited(widget.player.setDrowsyForeground(true));
""",
    "")
# v105: the whole _onAirAction method goes (header + body; the divider
# above build() stays). Generic _showIndicator stays for the other callers.
rep('lib/screens/player_screen.dart',
    """  // ---------------------------------------------------------------------------
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
  }
""",
    "")

# ------------------------------------------------- tune sheet imports
# v105: permission import goes (camera prompts are gone); the moved picture
# rows need NativeBridge + PlayerSettings.
rep('lib/widgets/player_controls_overlay.dart',
    """import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../state/media_player_state.dart';""",
    """import 'package:flutter/material.dart';

import '../services/native_bridge.dart';
import '../state/media_player_state.dart';
import '../state/player_settings.dart';""")
# v105: same 8 rows, but air + look-away become enhance + tone.
rep('lib/widgets/player_controls_overlay.dart',
    "          8, // handle + subtitles + audio + A-B + karaoke + air + look-away + dialogue",
    "          8, // handle + subtitles + audio + A-B + karaoke + enhance + tone + dialogue")
PYEOF

python3 <<'PYEOF2'
import sys
path = 'lib/widgets/player_controls_overlay.dart'
src = open(path).read()
start_marker = '              // v100/v101: helpers below Karaoke (user request).'
assert src.count(start_marker) == 1, 'helpers comment count'
start = src.index(start_marker)
# dialogue block is the next keeper: back up from its title to its opener.
dlg_anchor = "'Dialogue boost'"
assert src.count(dlg_anchor) == 1, 'dialogue title count'
dlg_builder = src.rindex('              StatefulBuilder(', 0, src.index(dlg_anchor))
assert dlg_builder > start, 'dialogue must follow the camera rows'
new_rows = '''              // v105: picture rows live here now (were Settings > Picture).
              // Switches stay live in the sheet (no pop) so several can be
              // flipped at once; the player state persists each one.
              StatefulBuilder(
                builder: (sbCtx, setSb) {
                  return SwitchListTile(
                    dense: true,
                    secondary: Icon(
                      Icons.auto_fix_high_outlined,
                      color: player.enhanceVideoOn
                          ? themeState.accent
                          : Colors.white70,
                    ),
                    title: const Text(
                      'Enhance video',
                      style: TextStyle(color: Colors.white, fontSize: 14),
                    ),
                    subtitle: const Text(
                      'GPU sharpen + contrast + colour boost',
                      style: TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                    value: player.enhanceVideoOn,
                    activeThumbColor: themeState.accent,
                    onChanged: (v) async {
                      await player.setEnhanceVideo(v);
                      await NativeBridge.saveSetting(
                          PlayerSettings.kEnhanceVideo, '$v');
                      setSb(() {});
                      onInteract();
                    },
                  );
                },
              ),
              StatefulBuilder(
                builder: (sbCtx, setSb) {
                  return ListTile(
                    dense: true,
                    leading: Icon(
                      Icons.hdr_on_outlined,
                      color: Colors.white70,
                    ),
                    title: const Text(
                      'HDR tone-mapping',
                      style: TextStyle(color: Colors.white, fontSize: 14),
                    ),
                    subtitle: const Text(
                      'How HDR10/Dolby sources fit your screen',
                      style: TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                    trailing: DropdownButton<String>(
                      value: player.toneMappingMode,
                      dropdownColor: const Color(0xFF1a1a24),
                      underline: const SizedBox(),
                      items: const {
                        'auto': 'Auto',
                        'mobius': 'Mobius',
                        'hable': 'Hable',
                        'bt.2390': 'BT.2390',
                      }
                          .entries
                          .map((e) => DropdownMenuItem(
                                value: e.key,
                                child: Text(e.value,
                                    style: TextStyle(
                                        color: Colors.white, fontSize: 13)),
                              ))
                          .toList(),
                      onChanged: (v) async {
                        await player.setToneMapping(v ?? 'auto');
                        setSb(() {});
                        onInteract();
                      },
                    ),
                  );
                },
              ),
'''
open(path, 'w').write(src[:start] + new_rows + src[dlg_builder:])
print('patched (1x): lib/widgets/player_controls_overlay.dart')
PYEOF2

python3 <<'PYEOF'
import sys

def cut(path, start_marker, end_marker, back_up_to=None):
    with open(path, 'r', encoding='utf-8') as f:
        src = f.read()
    if src.count(start_marker) != 1:
        print(f'PATCH FAILED: {path}: start marker found '
              f'{src.count(start_marker)}x, want 1x: {start_marker[:80]}')
        sys.exit(1)
    if src.count(end_marker) != 1:
        print(f'PATCH FAILED: {path}: end marker found '
              f'{src.count(end_marker)}x, want 1x: {end_marker[:80]}')
        sys.exit(1)
    start = src.index(start_marker)
    if back_up_to is not None:
        try:
            start = src.rindex(back_up_to, 0, start)
        except ValueError:
            print(f'PATCH FAILED: {path}: back_up_to not found: {back_up_to}')
            sys.exit(1)
    end = src.index(end_marker)
    if end <= start:
        print(f'PATCH FAILED: {path}: end marker precedes start marker')
        sys.exit(1)
    with open(path, 'w', encoding='utf-8') as f:
        f.write(src[:start] + src[end:])
    print(f'cut (1x): {path}')

# ------------------------------------------------- settings sheet
# v105: Picture section moves to the player tune sheet (model keys stay -
# they persist the moved rows).
cut('lib/widgets/player_settings_sheet.dart',
    "              const _SectionHeader('Picture'),",
    "              const _SectionHeader('Player buttons'),")

# ------------------------------------------------- sleep sheet
# v105: sleep sheet loses the camera row (plain timers stay).
cut('lib/screens/player_screen.dart',
    '                  // v100: auto-detect sleep - the front camera pauses the',
    "                  item(Icons.close, 'Off', onTap: player.cancelSleepTimer),")
PYEOF

python3 <<'PYEOF'
import re, sys

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

def cut(path, start_marker, end_marker, back_up_to=None):
    with open(path, 'r', encoding='utf-8') as f:
        src = f.read()
    if src.count(start_marker) != 1:
        print(f'PATCH FAILED: {path}: start marker found '
              f'{src.count(start_marker)}x, want 1x: {start_marker[:80]}')
        sys.exit(1)
    if src.count(end_marker) != 1:
        print(f'PATCH FAILED: {path}: end marker found '
              f'{src.count(end_marker)}x, want 1x: {end_marker[:80]}')
        sys.exit(1)
    start = src.index(start_marker)
    if back_up_to is not None:
        try:
            start = src.rindex(back_up_to, 0, start)
        except ValueError:
            print(f'PATCH FAILED: {path}: back_up_to not found: {back_up_to}')
            sys.exit(1)
    end = src.index(end_marker)
    if end <= start:
        print(f'PATCH FAILED: {path}: end marker precedes start marker')
        sys.exit(1)
    with open(path, 'w', encoding='utf-8') as f:
        f.write(src[:start] + src[end:])
    print(f'cut (1x): {path}')

# ------------------------------------------------- manual
# v105: camera items die with the features (sleep timer + dialogue stay).
# Each cut backs up to its _Item( opener; the next item's opener stays.
cut('lib/widgets/user_manual_sheet.dart',
    "    'Auto-detect sleep (camera)',",
    "  _Item(\n    Icons.face_outlined,",
    back_up_to='  _Item(')
cut('lib/widgets/user_manual_sheet.dart',
    "    'Look-away auto-pause',",
    "  _Item(\n    Icons.pan_tool_outlined,",
    back_up_to='  _Item(')
cut('lib/widgets/user_manual_sheet.dart',
    "    'Air gestures',",
    "  _Item(\n    Icons.graphic_eq_outlined,",
    back_up_to='  _Item(')

# ------------------------------------------------- tests
# v105: unused imports go (Point + AirGestureEngine both die with the
# deleted engine test).
rep('test/widget_test.dart',
    "import 'dart:io';\nimport 'dart:math';\n",
    "import 'dart:io';\n")
rep('test/widget_test.dart',
    "import 'package:maxplayer/utils/air_gestures.dart';\n",
    "")
# v105: group no longer watches any camera.
rep('test/widget_test.dart',
    "  group('v100 blink removal, camera watchers, audio helpers', () {",
    "  group('v100 blink removal, audio helpers', () {")
# v105: camera tests die with the features (deterministic cuts between
# neighbouring test openers).
cut('test/widget_test.dart',
    "    test('camera permission + plugins are wired', () {",
    "    test('player state owns the camera flags")
cut('test/widget_test.dart',
    "    test('player state owns the camera flags (v101 keeps flags, leveling deleted)', () {",
    "    test('v101 engine maps the gesture table', () {")
cut('test/widget_test.dart',
    "    test('v101 engine maps the gesture table', () {",
    "    test('v101 MediaPipe wiring + leveling deletion', () {")
# v105: MediaPipe asserts die, leveling-deletion + dialogue pins stay.
rep('test/widget_test.dart',
    """    test('v101 MediaPipe wiring + leveling deletion', () {
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
      // Leveling deleted everywhere (settings keys die with it).""",
    """    test('v105 camera features are fully removed', () {
      // Source files deleted (git history keeps them if ever needed).
      expect(File('lib/services/drowsy_detector.dart').existsSync(), isFalse);
      expect(File('lib/utils/air_gestures.dart').existsSync(), isFalse);
      // No plugin left behind (storage permission stays - File Manager
      // scans folders through it, nothing to do with the camera).
      final pub = File('pubspec.yaml').readAsStringSync();
      for (final k in [
        'hand_landmarker',
        'google_mlkit_face_detection',
        'camera_android',
        'camera:',
      ]) {
        expect(pub.contains(k), isFalse);
      }
      expect(pub, contains('permission_handler'));
      final manifest =
          File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      expect(manifest.contains('android.permission.CAMERA'), isFalse);
      // No dangling references in the six touched files.
      final s = File('lib/state/media_player_state.dart').readAsStringSync();
      for (final k in [
        'DrowsyDetector',
        'drowsy_detector',
        'DrowsyEvent',
        'AirAction',
        'air_gestures',
        'drowsyStatus',
        'applyAirAction',
        'onAirAction',
        'autoSleepDetect',
        'lookAwayPause',
        'airGestures',
        'setDrowsyForeground',
        '_onAirAction',
        '_syncDrowsy',
        '_handsSub',
        'HandLandmarkerPlugin',
        'landmarkStream',
        'processFrame',
        'setAirGestures',
        'Permission.camera',
        'permission_handler',
        'Camera will pause',
      ]) {
        expect(s.contains(k), isFalse);
      }
      for (final f in [
        'lib/state/player_settings.dart',
        'lib/widgets/player_controls_overlay.dart',
        'lib/widgets/user_manual_sheet.dart',
        'lib/screens/player_screen.dart',
        'lib/widgets/player_settings_sheet.dart',
      ]) {
        final src = File(f).readAsStringSync();
        for (final k in [
          'autoSleepDetect',
          'lookAwayPause',
          'airGestures',
          'kAutoSleepDetect',
          'kLookAwayPause',
          'kAirGestures',
          'Air gestures',
          'Look-away auto-pause',
          'Auto-detect sleep',
          'Permission.camera',
        ]) {
          expect(src.contains(k), isFalse);
        }
      }
      // The relocated picture rows persist through the kept settings keys.
      final settings =
          File('lib/state/player_settings.dart').readAsStringSync();
      for (final k in [
        'kEnhanceVideo',
        'kToneMapping',
        'player.enhanceVideo',
        'player.toneMapping',
        'kDialogueBoost',
        'kKaraokeSubs',
      ]) {
        expect(settings, contains(k));
      }
      // Screenshot icons are not camera features - they must survive.
      final ps = File('lib/screens/player_screen.dart').readAsStringSync();
      expect(ps, contains('Icons.camera_alt'));
      // Leveling deleted everywhere (settings keys die with it).""")
# v105: sleep sheet keeps plain timers; picture rows pin their new home.
rep('test/widget_test.dart',
    """    test('sleep sheet + tracks sheet host the new rows', () {
      final ps = File('lib/screens/player_screen.dart').readAsStringSync();
      expect(ps, contains('Auto-detect sleep'));
      expect(ps, contains('Permission.camera.request'));
      final overlay =
          File('lib/widgets/player_controls_overlay.dart').readAsStringSync();
      for (final k in [
        'Look-away auto-pause',
        'Dialogue boost',
      ]) {
        expect(overlay, contains(k));
      }
    });""",
    """    test('sleep sheet keeps plain timers, camera rows gone', () {
      final ps = File('lib/screens/player_screen.dart').readAsStringSync();
      expect(ps.contains('Auto-detect sleep'), isFalse);
      expect(ps.contains('Permission.camera.request'), isFalse);
      // The plain sleep timer rows stay.
      expect(ps, contains('Until end of this video'));
      final overlay =
          File('lib/widgets/player_controls_overlay.dart').readAsStringSync();
      expect(overlay.contains('Look-away auto-pause'), isFalse);
      expect(overlay, contains('Dialogue boost'));
    });

    test('v105 picture rows live below Karaoke', () {
      final overlay =
          File('lib/widgets/player_controls_overlay.dart').readAsStringSync();
      final karaoke = overlay.indexOf('Karaoke subtitles');
      final enhance = overlay.indexOf('Enhance video');
      final tone = overlay.indexOf('HDR tone-mapping');
      final dialogue = overlay.indexOf('Dialogue boost');
      expect(karaoke, greaterThanOrEqualTo(0));
      // Karaoke, then Enhance, then tone-mapping, then dialogue.
      expect(enhance, greaterThan(karaoke));
      expect(tone, greaterThan(enhance));
      expect(dialogue, greaterThan(tone));
      // Rows are wired to the player state + persisted settings keys.
      for (final k in [
        'player.enhanceVideoOn',
        'setEnhanceVideo',
        'PlayerSettings.kEnhanceVideo',
        'player.toneMappingMode',
        'setToneMapping',
        'PlayerSettings.kToneMapping',
      ]) {
        expect(overlay, contains(k));
      }
      // Gone from Player settings (moved, not duplicated).
      final sheet =
          File('lib/widgets/player_settings_sheet.dart').readAsStringSync();
      expect(sheet.contains("_SectionHeader('Picture')"), isFalse);
      expect(sheet.contains('Enhance video'), isFalse);
      expect(sheet.contains('HDR tone-mapping'), isFalse);
    });""")
PYEOF

echo "ALL v105 PATCHES APPLIED"
echo "--- diff stat ---"
git diff --stat
