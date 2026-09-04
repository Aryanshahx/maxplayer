#!/usr/bin/env bash
# v104: remove the whole camera feature set + move picture rows.
#
# Developer request: Air gestures, Look-away auto-pause and Auto-detect
# sleep never worked reliably - delete all three completely (code, plugins,
# permission, settings keys, manual, tests). Move Enhance video + HDR
# tone-mapping OUT of Settings INTO the player tune sheet, directly below
# Karaoke subtitles (their persisted keys stay the source of truth).
#
# What goes:
#   lib/services/drowsy_detector.dart + lib/utils/air_gestures.dart (deleted),
#   camera/hand_landmarker/ML Kit plugins (pubspec), CAMERA permission
#   (manifest), kAutoSleepDetect/kLookAwayPause/kAirGestures keys, every
#   camera row/method/status in state/screen/overlay/manual/tests.
# What moves:
#   'Picture' section (Enhance + tone-mapping) from player_settings_sheet
#   to player_controls_overlay tune sheet below Karaoke. The tune sheet
#   writes the player AND the same persisted keys, so Settings (which
#   reloads on open) and _reloadSettings never disagree.
# Untouched: sleep TIMER, dialogue boost, karaoke, permission_handler
# package (still used by library/storage code), the user's own Gradle ML
# Kit force (harmless no-op once the dep is gone).
#
# Run ONCE on the v103 tree:
#   cd ~/IdeaProjects/maxplayer && git pull && bash update_v104.sh \
#     && flutter pub get && flutter analyze && flutter test
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
    """Delete [start_marker, end_marker): start line goes, end line stays."""
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

# --- version: v104 is a new release ---
rep('pubspec.yaml', 'version: 1.0.0+103', 'version: 1.0.0+104')

# --- pubspec: drop the camera plugins (permission_handler stays - the
# library/storage code still uses it) ---
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

""",
    "")

# --- manifest: drop the camera permission ---
rep('android/app/src/main/AndroidManifest.xml',
    """    <!-- v100: opt-in front-camera drowsiness + look-away detection. Requested
         at runtime only when the user flips one of those switches; the camera
         runs only while a video plays. Declare camera use in Play Data Safety. -->
    <uses-permission android:name="android.permission.CAMERA" />

""",
    "")
PYEOF

# --- delete the two camera services (history keeps them if ever needed) ---
for f in lib/services/drowsy_detector.dart lib/utils/air_gestures.dart; do
  if [ ! -f "$f" ]; then
    echo "PATCH FAILED: $f missing, refusing to continue"
    exit 1
  fi
  rm "$f"
  echo "deleted: $f"
done

python3 <<'PYEOF'
import sys
sys.path.insert(0, '.')
# reuse rep/cut by exec'ing their defs from part 1 (kept identical here)
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
# v104: camera keys die with the features (dialogue boost + picture keys
# stay - those features stay).
rep('lib/state/player_settings.dart',
    """  /// v100: sleep timer pauses when the front camera sees closed eyes for
  /// 30 s. Strictly opt-in, OFF by default.
  final bool autoSleepDetect;

  /// v100: pause when the user looks away; resume when they look back.
  /// Strictly opt-in, OFF by default.
  final bool lookAwayPause;

  /// v101: MediaPipe air gestures (palm/swipe/OK). Strictly opt-in,
  /// OFF by default.
  final bool airGestures;


""",
    "")
rep('lib/state/player_settings.dart',
    """    this.dialogueBoost = false,
    this.autoSleepDetect = false,
    this.lookAwayPause = false,
    this.airGestures = false,
""",
    """    this.dialogueBoost = false,
""")
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
# v104: camera imports die with the features.
rep('lib/state/media_player_state.dart',
    "import 'package:camera/camera.dart';\n", "")
rep('lib/state/media_player_state.dart',
    "import 'package:hand_landmarker/hand_landmarker.dart';\n", "")
rep('lib/state/media_player_state.dart',
    "import '../services/drowsy_detector.dart';\n", "")
rep('lib/state/media_player_state.dart',
    "import '../utils/air_gestures.dart';\n", "")

# v104: _init no longer restores camera flags.
rep('lib/state/media_player_state.dart',
    """    autoSleepDetect = s[PlayerSettings.kAutoSleepDetect] == 'true';
    lookAwayPause = s[PlayerSettings.kLookAwayPause] == 'true';
    airGestures = s[PlayerSettings.kAirGestures] == 'true';
""",
    "")

# v104: playing listener drops the look-away bookkeeping.
rep('lib/state/media_player_state.dart',
    """        // v100: manual resume clears a look-away auto-pause; the camera
        // only runs while it can do something useful.
        if (v) _lookAwayPaused = false;
        unawaited(_syncDrowsy());
""",
    "")

# v104: the whole camera section (flags, detector, hands, status, tick,
# events, actions) goes - from its header dashes to the v74 audio chain.
cut('lib/state/media_player_state.dart',
    '  // v100: camera watchers (auto sleep-detect',
    '\n  /// v74: Builds the combined audio filter chain',
    back_up_to='  // ---')

# v104: readable picture state for the tune-sheet rows + validated mode.
rep('lib/state/media_player_state.dart',
    """  Future<void> setToneMapping(String mode) async {
    final plat = player.platform;
    if (plat is! NativePlayer) return;
    try {
      await plat.setProperty('tone-mapping', mode);
    } catch (_) {}
  }""",
    """  /// v104: readable picture state for the tune-sheet rows (moved from
  /// Settings at the user's request). The persisted keys stay the source
  /// of truth; these mirror what the player last applied.
  String toneMappingMode = 'auto';

  /// v104: readable Enhance state for the tune-sheet row.
  bool get enhanceVideoOn => _enhanceApplied;

  Future<void> setToneMapping(String mode) async {
    toneMappingMode =
        const ['auto', 'mobius', 'hable', 'bt.2390'].contains(mode)
        ? mode
        : 'auto';
    final plat = player.platform;
    if (plat is! NativePlayer) return;
    try {
      await plat.setProperty('tone-mapping', toneMappingMode);
    } catch (_) {}
  }""")

# v104: dispose drops the camera teardown.
rep('lib/state/media_player_state.dart',
    """    _drowsyTick?.cancel();
    unawaited(_handsSub?.cancel());
    _hands?.dispose();
    _drowsy.onFrame = null;
    unawaited(_drowsy.dispose());
""",
    "")
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

# ------------------------------------------------- player screen
# v104: dead imports (air engine + camera permission ask).
rep('lib/screens/player_screen.dart',
    "import '../utils/air_gestures.dart';\n", "")
rep('lib/screens/player_screen.dart',
    "import 'package:permission_handler/permission_handler.dart';\n", "")

# v104: lifecycle stops arming a camera that no longer exists.
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

# v104: gesture-feedback hookup goes.
rep('lib/screens/player_screen.dart',
    """    // v101: air-gesture feedback toasts.
    widget.player.onAirAction = _onAirAction;
""",
    "")
rep('lib/screens/player_screen.dart',
    "    widget.player.onAirAction = null;\n", "")
PYEOF

# v104: the whole _onAirAction method goes (generic indicator stays).
python3 <<'PYEOF3'
import sys
path = 'lib/screens/player_screen.dart'
src = open(path).read()
start_marker = '  // v101: air-gesture feedback - the state runs the action'
tail_marker = ("      case AirAction.speed1x:\n"
               "        _showIndicator('1x speed', Icons.speed);\n"
               "        break;\n"
               "    }\n"
               "  }\n")
assert src.count(start_marker) == 1, 'onAirAction start count'
assert src.count(tail_marker) == 1, 'onAirAction tail count'
start = src.index(start_marker)
# also swallow the separator comment directly above (else two remain)
start = src.rindex('  // ---', 0, start)
end = src.index(tail_marker) + len(tail_marker)
open(path, 'w').write(src[:start] + src[end:])
print('cut (1x): lib/screens/player_screen.dart _onAirAction')
PYEOF3

# ------------------------------------------------- tune sheet
# v104: camera rows become picture rows below Karaoke (dialogue stays).
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

rep('lib/widgets/player_controls_overlay.dart',
    """import 'package:permission_handler/permission_handler.dart';

import '../state/media_player_state.dart';""",
    """import '../services/native_bridge.dart';
import '../state/media_player_state.dart';
import '../state/player_settings.dart';""")
PYEOF

python3 <<'PYEOF2'
import sys
path = 'lib/widgets/player_controls_overlay.dart'
src = open(path).read()
start_marker = '              // v100/v101: helpers below Karaoke (user request).'
dlg_marker = "                      'Dialogue boost',"
assert src.count(start_marker) == 1, 'helper comment count'
assert src.count(dlg_marker) == 1, 'dialogue marker count'
start = src.index(start_marker)
dlg_use = src.index(dlg_marker)
dlg_builder = src.rindex('              StatefulBuilder(', 0, dlg_use)
assert dlg_builder > start, 'dialogue must follow the helpers comment'
new_rows = '''              // v104: picture helpers below Karaoke (moved from Settings
              // at the user's request). Switches stay live in the sheet (no
              // pop) so several can be flipped at once; each one writes the
              // player AND its persisted Settings key.
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
                        await NativeBridge.saveSetting(
                            PlayerSettings.kToneMapping,
                            player.toneMappingMode);
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

# ------------------------------------------------- settings sheet
# v104: Picture section moves to the player tune sheet (model keys stay -
# they persist the moved rows).
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

cut('lib/widgets/player_settings_sheet.dart',
    "              const _SectionHeader('Picture'),",
    "              const _SectionHeader('Player buttons'),")

# v104: sleep sheet loses the camera row (plain timers stay).
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

def cut_test(path, name):
    """Delete one whole `test('name', ...)` block (4-space close)."""
    with open(path, 'r', encoding='utf-8') as f:
        src = f.read()
    m = re.search(r"    test\('" + re.escape(name) + r"', \(\) \{.*?\n    \}\);",
                  src, re.DOTALL)
    if not m:
        print(f'PATCH FAILED: {path}: test not found: {name}')
        sys.exit(1)
    # re.escape(name) cannot match twice - but be strict anyway
    rest = src[m.end():]
    if ("    test('" + name + "', () {") in rest:
        print(f'PATCH FAILED: {path}: test name twice: {name}')
        sys.exit(1)
    with open(path, 'w', encoding='utf-8') as f:
        f.write(src[:m.start()] + rest)
    print(f'cut test (1x): {path} :: {name}')

# ------------------------------------------------- manual
# v104: camera items die with the features (sleep timer + dialogue stay).
# Each cut backs up to its _Item( opener; the next item's opener stays.
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

def cut_test(path, name, new_block=None):
    """Replace (or with new_block=None, delete) one `test('name', ...)`."""
    with open(path, 'r', encoding='utf-8') as f:
        src = f.read()
    m = re.search(r"    test\('" + re.escape(name) + r"', \(\) \{.*?\n    \}\);",
                  src, re.DOTALL)
    if not m:
        print(f'PATCH FAILED: {path}: test not found: {name}')
        sys.exit(1)
    if ("    test('" + name + "', () {") in src[m.end():]:
        print(f'PATCH FAILED: {path}: test name twice: {name}')
        sys.exit(1)
    replacement = new_block if new_block is not None else ''
    with open(path, 'w', encoding='utf-8') as f:
        f.write(src[:m.start()] + replacement + src[m.end():])
    print(f'cut test (1x): {path} :: {name}')

# ------------------------------------------------- tests
# v104: the engine import dies with its file.
rep('test/widget_test.dart',
    "import 'package:maxplayer/utils/air_gestures.dart';\n", "")

# v104: group label stops advertising removed features.
rep('test/widget_test.dart',
    "  group('v100 blink removal, camera watchers, audio helpers', () {",
    "  group('v100 blink removal, v104 camera removal, audio helpers', () {")

# v104: dart:math only fed the deleted engine test (Point) - drop it.
rep('test/widget_test.dart',
    "import 'dart:io';\nimport 'dart:math';\n",
    "import 'dart:io';\n")

# v104: engine test becomes the full-removal pin (leveling asserts fold in).
cut_test('test/widget_test.dart',
    'v102 robust engine: any-pose motion, flicker grace, mirror',
    '''    test('v104 camera features are fully removed', () {
      // Source files deleted (git history keeps them if ever needed).
      expect(File('lib/services/drowsy_detector.dart').existsSync(), isFalse);
      expect(File('lib/utils/air_gestures.dart').existsSync(), isFalse);
      // No plugin left behind.
      final pub = File('pubspec.yaml').readAsStringSync();
      for (final k in [
        'hand_landmarker',
        'google_mlkit_face_detection',
        'camera_android',
      ]) {
        expect(pub.contains(k), isFalse);
      }
      // No permission left behind.
      final manifest =
          File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      expect(manifest.contains('android.permission.CAMERA'), isFalse);
      // No wiring left behind in the player state.
      final s = File('lib/state/media_player_state.dart').readAsStringSync();
      for (final k in [
        'DrowsyDetector',
        'HandLandmarkerPlugin',
        'AirAction',
        'drowsyStatus',
        'mirrorSelfieX',
        'applyAirAction',
        'onAirAction',
        'autoSleepDetect',
        'lookAwayPause',
        'airGestures',
      ]) {
        expect(s.contains(k), isFalse);
      }
      // No rows left behind in the tune sheet.
      final overlay =
          File('lib/widgets/player_controls_overlay.dart').readAsStringSync();
      for (final k in [
        'Air gestures',
        'Look-away auto-pause',
        'Permission.camera',
      ]) {
        expect(overlay.contains(k), isFalse);
      }
      // No rows/hooks left behind in the player screen.
      final ps = File('lib/screens/player_screen.dart').readAsStringSync();
      for (final k in [
        'Auto-detect sleep',
        'setDrowsyForeground',
        '_onAirAction',
        'Permission.camera',
      ]) {
        expect(ps.contains(k), isFalse);
      }
      // No keys left behind in settings.
      final settings =
          File('lib/state/player_settings.dart').readAsStringSync();
      for (final k in [
        'kAutoSleepDetect',
        'kLookAwayPause',
        'kAirGestures',
      ]) {
        expect(settings.contains(k), isFalse);
      }
      // Leveling stays deleted (v101).
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
    });
''')

# v104: plugins test becomes the picture-row order pin.
cut_test('test/widget_test.dart',
    'camera permission + plugins are wired',
    '''    test('v104 picture rows live below Karaoke', () {
      final overlay =
          File('lib/widgets/player_controls_overlay.dart').readAsStringSync();
      final karaoke = overlay.indexOf('Karaoke subtitles');
      final enhance = overlay.indexOf("'Enhance video'");
      final tone = overlay.indexOf("'HDR tone-mapping'");
      final dialogue = overlay.indexOf("'Dialogue boost'");
      expect(karaoke, greaterThanOrEqualTo(0));
      expect(enhance, greaterThan(karaoke));
      expect(tone, greaterThan(enhance));
      expect(dialogue, greaterThan(tone));
      // Moved OUT of Settings (the model keys stay - they persist the rows).
      final sheet =
          File('lib/widgets/player_settings_sheet.dart').readAsStringSync();
      expect(sheet.contains('Enhance video (real-time)'), isFalse);
      expect(sheet.contains('HDR tone-mapping'), isFalse);
      expect(sheet.contains("_SectionHeader('Picture')"), isFalse);
      // The tune sheet writes player + keys directly.
      final s = File('lib/state/media_player_state.dart').readAsStringSync();
      expect(s, contains('enhanceVideoOn'));
      expect(s, contains('toneMappingMode'));
      expect(
          overlay, contains('PlayerSettings.kEnhanceVideo'));
      expect(
          overlay, contains('PlayerSettings.kToneMapping'));
    });
''')

# v104: stale flag/wiring tests go (their valid bits folded into the
# removal pin above).
cut_test('test/widget_test.dart',
    'player state owns the camera flags (v101 keeps flags, leveling deleted)')
cut_test('test/widget_test.dart',
    'v101 MediaPipe wiring + leveling deletion')

# v104: sleep test keeps timers, drops the camera row.
cut_test('test/widget_test.dart',
    'sleep sheet + tracks sheet host the new rows',
    '''    test('sleep sheet keeps timers, camera rows gone', () {
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
''')
PYEOF

echo "ALL v104 PATCHES APPLIED"
echo "--- diff stat ---"
git diff --stat
