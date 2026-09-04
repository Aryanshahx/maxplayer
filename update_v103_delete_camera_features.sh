#!/bin/bash
set -euo pipefail

# v103: completely delete air gestures, look-away auto-pause, and auto-detect sleep
# Works from clean v102 baseline. Does NOT remove flutter/foundation.dart.

echo "Applying v103 feature deletion..."

python3 - <<'PY'
from pathlib import Path

# ---------------------------------------------------------------------------
# 1. pubspec.yaml: remove camera-related dependencies
# ---------------------------------------------------------------------------
p = Path('pubspec.yaml')
text = p.read_text()
lines = text.splitlines()
new_lines = []
for line in lines:
    s = line.strip()
    if s.startswith(('camera:', 'camera_android:', 'google_mlkit_face_detection:', 'hand_landmarker:')):
        continue
    new_lines.append(line)
p.write_text('\n'.join(new_lines) + '\n')
print('Removed camera deps from pubspec.yaml')

# ---------------------------------------------------------------------------
# 2. lib/state/media_player_state.dart: remove imports, early refs, camera block
# ---------------------------------------------------------------------------
mp = Path('lib/state/media_player_state.dart')
text = mp.read_text()

# Remove only camera-related imports, keep foundation
text = text.replace(
"""import 'package:camera/camera.dart';
import 'package:hand_landmarker/hand_landmarker.dart';

import '../services/drowsy_detector.dart';
import '../services/native_bridge.dart';
import '../utils/air_gestures.dart';
import '../utils/formatters.dart';
""",
"""import '../services/native_bridge.dart';
import '../utils/formatters.dart';
""")

# Remove early playing listener camera lines
text = text.replace(
"""        // v100: manual resume clears a look-away auto-pause; the camera
        // only runs while it can do something useful.
        if (v) _lookAwayPaused = false;
        unawaited(_syncDrowsy());
""",
"")

# Remove settings load references
text = text.replace(
"""    autoSleepDetect = s[PlayerSettings.kAutoSleepDetect] == 'true';
    lookAwayPause = s[PlayerSettings.kLookAwayPause] == 'true';
    airGestures = s[PlayerSettings.kAirGestures] == 'true';
""",
"")

# Remove the entire camera/gesture block from the v100 marker to the end of applyAirAction
start = "  // ---------------------------------------------------------------------------\n  // v100: camera watchers"
end = """  /// Runs a recognized air gesture on the player.
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
  }
"""
idx1 = text.find(start)
idx2 = text.find(end)
if idx1 != -1 and idx2 != -1:
    idx2 += len(end)
    text = text[:idx1] + text[idx2:]
    print('Removed camera block from media_player_state.dart')
else:
    print('WARNING: camera block markers not found; manual check needed')

# Remove any remaining lines referencing feature-only identifiers
feature_idents = [
    'autoSleepDetect', 'lookAwayPause', 'airGestures', 'drowsy', 'Drowsy',
    'HandLandmarker', 'AirAction', 'AirGestureEngine', 'onAirAction',
    'setDrowsyForeground', '_syncDrowsy', '_onDrowsyEvent', '_syncHands',
    '_onSharedCameraFrame', '_onHandLandmarks', '_hands', '_handsSub',
    '_airEngine', '_handFrameSkip', '_lookAwayPaused', '_drowsyForeground',
    '_drowsyWarned', 'drowsyStatus', '_drowsy', 'cameraRotation',
]
text = '\n'.join([line for line in text.splitlines() if not any(ident in line for ident in feature_idents)]) + '\n'
mp.write_text(text)
print('Filtered remaining feature references from media_player_state.dart')

# ---------------------------------------------------------------------------
# 3. lib/state/player_settings.dart: remove fields, keys, defaults, load/save/copyWith
# ---------------------------------------------------------------------------
ps = Path('lib/state/player_settings.dart')
text = ps.read_text()
text = text.replace(
"""  /// v100: sleep timer pauses when the front camera sees closed eyes for
  /// 30 s. Strictly opt-in, OFF by default.
  final bool autoSleepDetect;

  /// v100: pause when the user looks away; resume when they look back.
  /// Strictly opt-in, OFF by default.
  final bool lookAwayPause;

  /// v101: MediaPipe air gestures (palm/swipe/OK). Strictly opt-in,
  /// OFF by default.
  final bool airGestures;

""", "")
text = text.replace(
"""    this.dialogueBoost = false,
    this.autoSleepDetect = false,
    this.lookAwayPause = false,
    this.airGestures = false,
""", "    this.dialogueBoost = false,\n")
text = text.replace(
"""  static const String kAutoSleepDetect = 'player.autoSleepDetect';
  static const String kLookAwayPause = 'player.lookAwayPause';
  static const String kAirGestures = 'player.airGestures';
""", "")
text = text.replace(
"""      autoSleepDetect: s[kAutoSleepDetect] == 'true',
      lookAwayPause: s[kLookAwayPause] == 'true',
      airGestures: s[kAirGestures] == 'true',
""", "")
text = text.replace(
"""    NativeBridge.saveSetting(kAutoSleepDetect, '$autoSleepDetect');
    NativeBridge.saveSetting(kLookAwayPause, '$lookAwayPause');
    NativeBridge.saveSetting(kAirGestures, '$airGestures');
""", "")
text = text.replace(
"""    bool? autoSleepDetect,
    bool? lookAwayPause,
    bool? airGestures,
""", "")
text = text.replace(
"""      autoSleepDetect: autoSleepDetect ?? this.autoSleepDetect,
      lookAwayPause: lookAwayPause ?? this.lookAwayPause,
      airGestures: airGestures ?? this.airGestures,
""", "")
ps.write_text(text)
print('Removed camera settings from player_settings.dart')

# ---------------------------------------------------------------------------
# 4. lib/screens/player_screen.dart: remove auto-sleep switch and other refs
# ---------------------------------------------------------------------------
scr = Path('lib/screens/player_screen.dart')
text = scr.read_text()
# Remove the auto-detect sleep StatefulBuilder block (exact from output)
start_block = """                  // v100: auto-detect sleep - the front camera pauses the
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
                        subtitle: Text(
                          player.autoSleepDetect
                              ? 'Status: ${player.drowsyStatus}'
                              : 'Front camera pauses when eyes stay closed 30s',
                          style: const TextStyle(
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
"""
end_line = """                  item(Icons.close, 'Off', onTap: player.cancelSleepTimer),
"""
text = text.replace(start_block + end_line, end_line)

# Remove air_gestures import
text = text.replace("import '../utils/air_gestures.dart';\n", "")
# Remove lines with feature-only identifiers
for ident in ['onAirAction', 'setDrowsyForeground', 'AirAction', 'airGestures',
              'autoSleepDetect', 'lookAwayPause', 'drowsyStatus', 'Drowsy',
              'setAutoSleepDetect', 'setLookAwayPause', 'setAirGestures',
              'Permission.camera']:
    text = '\n'.join([line for line in text.splitlines() if ident not in line]) + '\n'
scr.write_text(text)
print('Removed camera references from player_screen.dart')

# ---------------------------------------------------------------------------
# 5. lib/widgets/player_controls_overlay.dart: remove air gestures and look-away switches
# ---------------------------------------------------------------------------
pco = Path('lib/widgets/player_controls_overlay.dart')
text = pco.read_text()
# Remove air gestures block (exact from earlier)
air_block = """              StatefulBuilder(
                builder: (sbCtx, setSb) {
                  return SwitchListTile(
                    dense: true,
                    secondary: Icon(
                      Icons.gesture_outlined,
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
                        final messenger = ScaffoldMessenger.of(context);
                        final st = await Permission.camera.request();
                        if (!st.isGranted) {
                          messenger
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
"""
text = text.replace(air_block, "")
# Remove look-away block (exact from earlier)
look_block = """              StatefulBuilder(
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
                        final messenger = ScaffoldMessenger.of(context);
                        final st = await Permission.camera.request();
                        if (!st.isGranted) {
                          messenger
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
"""
text = text.replace(look_block, "")
# Remove any remaining camera references
for ident in ['airGestures', 'lookAwayPause', 'setAirGestures', 'setLookAwayPause', 'Permission.camera']:
    text = '\n'.join([line for line in text.splitlines() if ident not in line]) + '\n'
pco.write_text(text)
print('Removed camera switches from player_controls_overlay.dart')

# ---------------------------------------------------------------------------
# 6. lib/widgets/user_manual_sheet.dart: remove three entries
# ---------------------------------------------------------------------------
ums = Path('lib/widgets/user_manual_sheet.dart')
text = ums.read_text()
text = text.replace(
"""  _Item(
    Icons.visibility_outlined,
    'Auto-detect sleep (camera)',
    'Sleep timer sheet → Auto-detect sleep: the front camera pauses the '
        'video when your eyes stay closed for 30 seconds. Strictly opt-in '
        'and off by default; the camera runs only while a video plays, '
        'nothing is recorded or sent anywhere.',
  ),
""", "")
text = text.replace(
"""  _Item(
    Icons.face_outlined,
    'Look-away auto-pause',
    'Player tune sheet → Look-away auto-pause: looking away for a few '
        'seconds pauses, looking back resumes. Same camera rules as above. '
        'If it never triggers, the Status line in the sleep sheet tells '
        'whether the camera is actually watching.',
  ),
""", "")
text = text.replace(
"""  _Item(
    Icons.pan_tool_outlined,
    'Air gestures',
    'Player tune sheet → Air gestures: open palm holds play/pause, index '
        'swipes seek ±10s, two-finger swipes on the right change volume '
        'and on the left brightness, OK sign toggles 2x speed. Needs good '
        'light on your hand; off by default.',
  ),
""", "")
ums.write_text(text)
print('Removed manual entries from user_manual_sheet.dart')

# ---------------------------------------------------------------------------
# 7. Delete feature files
# ---------------------------------------------------------------------------
for f in ['lib/services/drowsy_detector.dart', 'lib/utils/air_gestures.dart']:
    p = Path(f)
    if p.exists():
        p.unlink()
        print(f'Deleted {f}')

# ---------------------------------------------------------------------------
# 8. Remove CAMERA permission from AndroidManifest.xml
# ---------------------------------------------------------------------------
manifest = Path('android/app/src/main/AndroidManifest.xml')
text = manifest.read_text()
text = text.replace('    <uses-permission android:name="android.permission.CAMERA" />\n', '')
manifest.write_text(text)
print('Removed CAMERA permission')

# ---------------------------------------------------------------------------
# 9. Remove Gradle face-detection force block (if present)
# ---------------------------------------------------------------------------
gradle = Path('android/app/build.gradle.kts')
text = gradle.read_text()
text = text.replace("""    configurations.all {
        resolutionStrategy {
            force("com.google.mlkit:face-detection:16.1.6")
        }
    }

""", "")
gradle.write_text(text)
print('Removed Gradle face-detection force block (if existed)')

print('\nv103 deletion complete.')
PY

echo "Done. Run 'flutter analyze' and 'flutter test'."
