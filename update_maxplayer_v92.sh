#!/usr/bin/env bash
# Max Player v92 update script
# Run from the repo root: ~/IdeaProjects/maxplayer
#
# IMPORTANT: run this only AFTER reconciling your local Pi folder with
# GitHub (see git status / git checkout -- . guidance) - this script
# patches against the known-good v91 committed code, not whatever local
# state caused your flutter analyze errors.
set -euo pipefail

if [ ! -f "pubspec.yaml" ]; then
  echo "ERROR: run this from the maxplayer repo root (pubspec.yaml not found here)."
  exit 1
fi

echo "==> Patching lib/screens/player_screen.dart (re-wire orphaned Ask AI feature into the 3-dot menu)"
python3 - <<'PYEOF'
import sys
p = "lib/screens/player_screen.dart"
s = open(p, encoding="utf-8").read()

def apply(old, new):
    global s
    if old not in s:
        sys.exit(f"[player_screen.dart] anchor not found, aborting:\n{old[:150]}")
    s = s.replace(old, new, 1)

apply(
"""          case 'eq':
            EqualizerSheet.show(context, widget.player);
            break;
          case 'shot':""",
"""          case 'eq':
            EqualizerSheet.show(context, widget.player);
            break;
          case 'ask':
            _openVideoAsk();
            break;
          case 'shot':""")

apply(
"""        _topMenuItem('info', Icons.info_outline, 'Video info'),
        _topMenuItem('eq', Icons.graphic_eq, 'Equalizer & Audio FX'),
        if (_settings.screenshotButton)""",
"""        _topMenuItem('info', Icons.info_outline, 'Video info'),
        _topMenuItem('eq', Icons.graphic_eq, 'Equalizer & Audio FX'),
        _topMenuItem('ask', Icons.auto_awesome, 'Ask AI about this video'),
        if (_settings.screenshotButton)""")

open(p, "w", encoding="utf-8").write(s)
print("  OK")
PYEOF

echo ""
echo "===================================================================="
echo " v92 applied. What was fixed:"
echo "  'Ask AI about this video' existed as working code (_openVideoAsk)"
echo "  but nothing in the UI called it anymore - it was removed from the"
echo "  tracks sheet at some point and never given a new home, making the"
echo "  whole feature invisible/unreachable. Added it back to the 3-dot"
echo "  menu (which you also asked to have redesigned to be lighter -"
echo "  that redesign already happened in v91, this just restores the"
echo "  missing feature to it)."
echo "===================================================================="
echo ""
echo "Next steps:"
echo "  flutter analyze        # should print: No issues found!"
echo "  flutter test"
echo "  git add -A && git commit -m 'v92: re-wire orphaned Ask AI feature into player 3-dot menu' && git push"
