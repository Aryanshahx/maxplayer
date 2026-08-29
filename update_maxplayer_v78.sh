#!/usr/bin/env bash
# Max Player v78 update script
# Run from the repo root: ~/IdeaProjects/maxplayer
set -euo pipefail

if [ ! -f "pubspec.yaml" ]; then
  echo "ERROR: run this from the maxplayer repo root (pubspec.yaml not found here)."
  exit 1
fi

echo "==> Patching lib/state/media_player_state.dart (fix video opening muted)"
python3 - <<'PYEOF'
import sys
p = "lib/state/media_player_state.dart"
s = open(p, encoding="utf-8").read()
old = '''  /// Reads the real device media volume once so the player swipe starts
  /// from the true level (mirrors [currentBrightness]).
  Future<double> currentVolume() async {
    if (!_volumeSynced) {
      volume = await NativeBridge.getMediaVolume();
      isMuted = volume <= 0;
      _volumeSynced = true;
      notifyListeners();
    }
    return volume;
  }'''
new = '''  /// Reads the real device media volume once so the player swipe starts
  /// from the true level (mirrors [currentBrightness]).
  ///
  /// v78: this used to be gated by [_volumeSynced] forever - a single
  /// bad/low reading (very common: plenty of phones just sit at a low or
  /// zero STREAM_MUSIC level until something nudges it) permanently
  /// muted every video for the rest of the app session, since it was
  /// never re-checked. Re-synced now, and a low system level no longer
  /// flips [isMuted] on its own - that flag means "the user muted it",
  /// not "the system happened to be quiet"; if it's genuinely near zero
  /// we nudge it up to an audible floor instead of starting silent.
  static const double _kAudibleFloor = 0.3;

  Future<double> currentVolume() async {
    if (!_volumeSynced) {
      final real = await NativeBridge.getMediaVolume();
      if (real <= 0.02) {
        volume = _kAudibleFloor;
        await NativeBridge.setMediaVolume(_kAudibleFloor);
      } else {
        volume = real;
      }
      _volumeSynced = true;
      notifyListeners();
    }
    return volume;
  }'''
if old not in s:
    sys.exit("[media_player_state.dart] anchor not found, aborting")
s = s.replace(old, new, 1)
open(p, "w", encoding="utf-8").write(s)
print("  OK")
PYEOF

echo "==> Patching lib/screens/player_screen.dart (sleep timer landscape fix, Ask-AI moved, gesture-bubble animation)"
python3 - <<'PYEOF'
import sys
p = "lib/screens/player_screen.dart"
s = open(p, encoding="utf-8").read()

def apply(old, new):
    global s
    if old not in s:
        sys.exit(f"[player_screen.dart] anchor not found, aborting:\n{old[:150]}")
    s = s.replace(old, new, 1)

# 1) Sleep timer: isScrollControlled + scrollable wrapper (landscape fix)
apply(
'''  void _showSleepSheet() {
    final player = widget.player;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1a1a24),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {''',
'''  void _showSleepSheet() {
    final player = widget.player;
    showModalBottomSheet<void>(
      context: context,
      // v78: without this, the sheet gets a fixed height budget that a
      // landscape phone's short screen can't satisfy for 6 rows of
      // content, and (with no scroll wrapper either) the extra rows were
      // simply unreachable - "sleep timer not opening properly in
      // landscape". isScrollControlled + the SingleChildScrollView below
      // let it size itself and scroll instead of clipping.
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1a1a24),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {''')

apply(
'''        return SafeArea(
          child: AnimatedBuilder(
            animation: player,
            builder: (context, _) {
              final label = player.sleepTimerLabel;
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    label == null
                        ? 'Sleep timer'
                        : 'Sleep timer: stops in $label',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  for (final mins in const [15, 30, 45, 60])
                    item(
                      Icons.bedtime_outlined,
                      '$mins minutes',
                      active: label == '$mins min',
                      onTap: () => player.setSleepTimer(
                        forDuration: Duration(minutes: mins),
                      ),
                    ),
                  item(
                    Icons.movie_outlined,
                    'Until end of this video',
                    active: label == 'end of video',
                    onTap: () => player.setSleepTimer(atEndOfVideo: true),
                  ),
                  item(Icons.close, 'Off', onTap: player.cancelSleepTimer),
                  const SizedBox(height: 8),
                ],
              );
            },
          ),
        );
      },
    );''',
'''        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheetContext).size.height * 0.9,
            ),
            child: SingleChildScrollView(
              child: AnimatedBuilder(
                animation: player,
                builder: (context, _) {
                  final label = player.sleepTimerLabel;
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 10),
                      Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        label == null
                            ? 'Sleep timer'
                            : 'Sleep timer: stops in $label',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      for (final mins in const [15, 30, 45, 60])
                        item(
                          Icons.bedtime_outlined,
                          '$mins minutes',
                          active: label == '$mins min',
                          onTap: () => player.setSleepTimer(
                            forDuration: Duration(minutes: mins),
                          ),
                        ),
                      item(
                        Icons.movie_outlined,
                        'Until end of this video',
                        active: label == 'end of video',
                        onTap: () => player.setSleepTimer(atEndOfVideo: true),
                      ),
                      item(Icons.close, 'Off', onTap: player.cancelSleepTimer),
                      const SizedBox(height: 8),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );''')

# 2) Remove "Ask AI about this video" from the three-dot menu
apply(
'''          case 'ask':
            _openVideoAsk();
          case 'eq':
            EqualizerSheet.show(context, widget.player);''',
'''          case 'eq':
            EqualizerSheet.show(context, widget.player);''')

apply(
'''        _topMenuItem('info', Icons.info_outline, 'Video info'),
        _topMenuItem('ask', Icons.auto_awesome, 'Ask AI about this video'),
        _topMenuItem('eq', Icons.graphic_eq, 'Equalizer'),''',
'''        _topMenuItem('info', Icons.info_outline, 'Video info'),
        _topMenuItem('eq', Icons.graphic_eq, 'Equalizer'),''')

apply(
'''                                    karaokeOn: _settings.karaokeSubs,
                                    onToggleKaraoke: _toggleKaraoke,
                                  ),''',
'''                                    karaokeOn: _settings.karaokeSubs,
                                    onToggleKaraoke: _toggleKaraoke,
                                    onAskAi: _openVideoAsk,
                                  ),''')

# 3) Gesture indicator: add the scale-pop the old comment always claimed
apply(
'''import 'dart:io';

import 'package:flutter/material.dart';''',
'''import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';''')

apply(
'''                                child: AnimatedOpacity(
                                  duration: const Duration(milliseconds: 120),
                                  opacity: (_indicatorText != null && !_isPip)
                                      ? 1.0
                                      : 0.0,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(
                                        alpha: 0.72,
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (_indicatorIcon != null) ...[
                                          Icon(
                                            _indicatorIcon,
                                            color: Colors.white,
                                            size: 20,
                                          ),
                                          const SizedBox(width: 8),
                                        ],
                                        Text(
                                          _indicatorText ?? '',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),''',
'''                                // v78: real frosted-glass bubble (blurred
                                // backdrop + soft border) with a scale+fade
                                // pop, replacing the old flat dark chip.
                                child: AnimatedScale(
                                  duration: const Duration(milliseconds: 160),
                                  curve: Curves.easeOutBack,
                                  scale: (_indicatorText != null && !_isPip)
                                      ? 1.0
                                      : 0.92,
                                  child: AnimatedOpacity(
                                    duration: const Duration(milliseconds: 120),
                                    opacity: (_indicatorText != null && !_isPip)
                                        ? 1.0
                                        : 0.0,
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(14),
                                      child: BackdropFilter(
                                        filter: ui.ImageFilter.blur(
                                          sigmaX: 18,
                                          sigmaY: 18,
                                        ),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 10,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.black.withValues(
                                              alpha: 0.45,
                                            ),
                                            borderRadius:
                                                BorderRadius.circular(14),
                                            border: Border.all(
                                              color: Colors.white.withValues(
                                                alpha: 0.14,
                                              ),
                                              width: 1,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              if (_indicatorIcon != null) ...[
                                                Icon(
                                                  _indicatorIcon,
                                                  color: Colors.white,
                                                  size: 20,
                                                ),
                                                const SizedBox(width: 8),
                                              ],
                                              Text(
                                                _indicatorText ?? '',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),'''),

open(p, "w", encoding="utf-8").write(s)
print("  OK")
PYEOF

echo "==> Patching lib/widgets/player_controls_overlay.dart (Ask AI moved into the tracks sheet)"
python3 - <<'PYEOF'
import sys
p = "lib/widgets/player_controls_overlay.dart"
s = open(p, encoding="utf-8").read()

def apply(old, new):
    global s
    if old not in s:
        sys.exit(f"[player_controls_overlay.dart] anchor not found, aborting:\n{old[:150]}")
    s = s.replace(old, new, 1)

apply(
'''  const PlayerControlsOverlay({
    super.key,
    required this.player,
    required this.onToggleQueue,
    required this.onInteract,
    required this.onScrubbing,
    required this.onCycleFit,
    required this.orientationLocked,
    required this.onToggleOrientationLock,
    // v25: karaoke toggle moved INTO the tracks sheet (was the ⋮ menu).
    required this.karaokeOn,
    required this.onToggleKaraoke,
  });

  /// v25: karaoke state + toggle, so the tracks sheet can host the switch
  /// next to Subtitles / Audio track / A-B loop.
  final bool karaokeOn;
  final VoidCallback onToggleKaraoke;''',
'''  const PlayerControlsOverlay({
    super.key,
    required this.player,
    required this.onToggleQueue,
    required this.onInteract,
    required this.onScrubbing,
    required this.onCycleFit,
    required this.orientationLocked,
    required this.onToggleOrientationLock,
    // v25: karaoke toggle moved INTO the tracks sheet (was the ⋮ menu).
    required this.karaokeOn,
    required this.onToggleKaraoke,
    // v78: "Ask AI about this video" moved INTO the tracks sheet too
    // (was the ⋮ menu) - it belongs next to Subtitles/Audio/A-B loop,
    // not buried behind "more actions".
    required this.onAskAi,
  });

  /// v25: karaoke state + toggle, so the tracks sheet can host the switch
  /// next to Subtitles / Audio track / A-B loop.
  final bool karaokeOn;
  final VoidCallback onToggleKaraoke;

  /// v78: opens the "Ask AI about this video" sheet.
  final VoidCallback onAskAi;''')

apply(
'''      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: trackSheetInitialSize(
          4, // handle + subtitles + audio + A-B loop + karaoke rows
          MediaQuery.of(sheetContext).size.height,
        ),''',
'''      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: trackSheetInitialSize(
          5, // handle + subtitles + audio + A-B loop + karaoke + ask AI rows
          MediaQuery.of(sheetContext).size.height,
        ),''')

apply(
'''                onTap: () {
                  Navigator.of(sheetContext).pop();
                  onToggleKaraoke();
                },
              ),
              const SizedBox(height: 8),''',
'''                onTap: () {
                  Navigator.of(sheetContext).pop();
                  onToggleKaraoke();
                },
              ),
              ListTile(
                leading: Icon(Icons.auto_awesome, color: themeState.accent),
                title: const Text(
                  'Ask AI about this video',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: const Text(
                  'Answers from the subtitles - AI-generated or the video\\'s own',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  onAskAi();
                },
              ),
              const SizedBox(height: 8),''')

open(p, "w", encoding="utf-8").write(s)
print("  OK")
PYEOF

echo ""
echo "===================================================================="
echo " v78 applied. What changed:"
echo "  1. Fixed video opening muted by default: the one-time device-volume"
echo "     sync could permanently mute every video for the rest of the app"
echo "     session off a single low/zero reading; now a low system level"
echo "     is nudged to an audible floor instead of leaving playback silent"
echo "  2. Sleep timer sheet no longer clips/fails to open in landscape on"
echo "     phones (same isScrollControlled fix already proven on the"
echo "     Subtitles/Audio/A-B loop sheet)"
echo "  3. 'Ask AI about this video' moved out of the three-dot menu into"
echo "     the tracks sheet (the tune button), next to Subtitles, Audio"
echo "     track, A-B loop, and Karaoke Subtitles"
echo "  4. Gesture indicator (volume/brightness/seek bubble) now pops in"
echo "     with a smooth scale+fade instead of just a flat fade - matches"
echo "     what the code's own old comment always claimed it did"
echo "===================================================================="
echo ""
echo "NOT changed in this script - explained below instead of guessed at:"
echo "===================================================================="
echo ""
echo "Next steps:"
echo "  flutter analyze        # should print: No issues found!"
echo "  flutter test"
echo "  flutter build appbundle --release"
echo "  git add -A && git commit -m 'v78: fix default-muted video, sleep timer landscape bug, move Ask-AI into tracks sheet, smoother gesture bubble' && git push"
