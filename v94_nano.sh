#!/usr/bin/env bash
# =============================================================================
#  v94_nano.sh - COMPACT twin of update_maxplayer_v94.sh (Max Player v93 -> v94)
#  Same 18 fixes as the full script, 1/3 the size - pasteable into nano.
#  Produces a BYTE-IDENTICAL tree to the full script (verified).
#
#  USAGE:  nano v94_nano.sh   -> paste -> Ctrl+O Enter Ctrl+X
#          chmod +x v94_nano.sh && ./v94_nano.sh
#          (or:  bash v94_nano.sh ~/IdeaProjects/maxplayer )
# =============================================================================
set -euo pipefail
R="${1:-$HOME/IdeaProjects/maxplayer}"
cd "$R" || { echo "ERROR: no such repo: $R"; exit 1; }
echo "== Max Player v94 nano patcher =="
echo "repo: $R   HEAD: $(git rev-parse --short HEAD)"

# ---- pre-flight -------------------------------------------------------------
[ "$(git rev-parse --show-toplevel)" = "$(pwd)" ] || { echo "ERROR: not a repo root"; exit 1; }
git diff --quiet && git diff --cached --quiet || { echo "ERROR: dirty tree - commit/stash first"; git status -s; exit 1; }
[ "$(wc -l < lib/services/native_bridge.dart)" -ge 700 ] || { echo "ERROR: native_bridge.dart <700 lines (v75-style damage?) - aborting"; exit 1; }
git cat-file -e 5117d44^{commit} 2>/dev/null || { echo "ERROR: v92 commit 5117d44 missing from this clone (shallow?) - run: git fetch --unshallow"; exit 1; }
[ "$(git rev-parse --short HEAD)" = "e6dc458" ] || echo "WARN: HEAD is not e6dc458 (v93) - anchors may not match"

# ---- python does every text patch: validate ALL anchors, then write ---------
python3 - <<'PY'
import re, sys

P = {}
def rd(p):
    if p not in P:
        P[p] = open(p, encoding='utf-8').read()
    return P[p]
def fail(m):
    print('\nABORTED - ' + m)
    print('No file was written by this step; the tree is still clean.')
    sys.exit(1)
def sub(p, old, new, tag):
    s = rd(p); n = s.count(old)
    if n != 1: fail(f'[{tag}] anchor matched {n}x (need exactly 1) in {p}')
    P[p] = s.replace(old, new, 1)
def subre(p, pat, new, tag):
    s = rd(p); m = re.findall(pat, s)
    if len(m) != 1: fail(f'[{tag}] regex matched {len(m)}x (need 1) in {p}')
    P[p] = re.sub(pat, new, s, count=1)
def cut(p, a, b, tag):
    s = rd(p)
    if s.count(a) != 1 or s.count(b) < 1: fail(f'[{tag}] markers not unique in {p}')
    i, j = s.find(a), s.find(b, s.find(a))
    if i < 0 or j < i: fail(f'[{tag}] marker order wrong in {p}')
    P[p] = s[:i] + s[j:]

T = 'lib/services/tmdb_client.dart'
# (1) stray extra '}' closed parseTmdbExtras' try block early -> 24 of the 47 errors
sub(T, "      }\n    }\n    }\n    final genres", "      }\n    }\n    final genres", 'stray-brace')
sub(T, "    final cast = <String>[];\n        final castMembers",
        "    final cast = <String>[];\n    final castMembers", 'tmdb-indent')

# (2) helpers are duplicated into formatters.dart -> ambiguous_import (12 errors)
sub('lib/widgets/movie_detail_sheet.dart', "import '../utils/formatters.dart';\n", "", 'mds-import')

S = 'lib/screens/player_screen.dart'
# (3) 145 lines of dead code, superseded by v93's compact _topMenu
cut(S, "  void _showMoreActionsSheet() {", "  Widget _lockChip({", 'dead-sheet')
# (4) restore v92's Ask AI in the three-dot menu (v93 deleted it)
sub(S, "          case 'eq':\n            EqualizerSheet.show(context, widget.player);\n            break;\n",
       "          case 'eq':\n            EqualizerSheet.show(context, widget.player);\n            break;\n"
       "          case 'ask':\n            _openVideoAsk();\n            break;\n", 'ask-case')
sub(S, "        _topMenuItem('eq', Icons.graphic_eq, 'Equalizer & Audio FX'),\n",
       "        _topMenuItem('eq', Icons.graphic_eq, 'Equalizer & Audio FX'),\n"
       "        _topMenuItem('ask', Icons.auto_awesome, 'Ask AI about this video'),\n", 'ask-item')
# (5) repair the 70-space-mangled '),' left where 'onAskAi: _openVideoAsk,' was dropped
subre(S, r"onToggleKaraoke: _toggleKaraoke,\n[ ]+\),",
         "onToggleKaraoke: _toggleKaraoke,\n                                  ),", 'ctor-indent')

W = 'test/widget_test.dart'
# (6) 45 imports -> the 5 the suite actually uses (40 unused_import warnings)
s = rd(W); i = s.find('void main() {')
if i < 0: fail('[imports] void main() not found in ' + W)
P[W] = ("import 'dart:io';\n\n"
        "import 'package:flutter_test/flutter_test.dart';\n\n"
        "// v94: v93 imported 45 app libraries but this suite only ever touches five\n"
        "// of them - the other 40 were unused_import warnings that drowned out real\n"
        "// problems. (They were invisible in v93 only because the file's resolution\n"
        "// errors suppressed the hint.)\n"
        "import 'package:maxplayer/models/video_track.dart';\n"
        "import 'package:maxplayer/services/tmdb_client.dart';\n"
        "import 'package:maxplayer/utils/formatters.dart';\n\n") + s[i:]
# (7) timeAgo takes int ms, not DateTime; 5 minutes is '5m ago', not 'Just now'
sub(W, "      final now = DateTime.now();\n"
       "      expect(timeAgo(now.subtract(const Duration(minutes: 5))), 'Just now');\n"
       "      expect(timeAgo(now.subtract(const Duration(hours: 2))), '2h ago');\n"
       "      expect(timeAgo(now.subtract(const Duration(days: 3))), '3d ago');\n",
       "      final nowMs = DateTime.now().millisecondsSinceEpoch;\n"
       "      expect(\n"
       "          timeAgo(nowMs - const Duration(minutes: 5).inMilliseconds), '5m ago');\n"
       "      expect(\n"
       "          timeAgo(nowMs - const Duration(hours: 2).inMilliseconds), '2h ago');\n"
       "      expect(\n"
       "          timeAgo(nowMs - const Duration(days: 3).inMilliseconds), '3d ago');\n", 'timeago')
# (8) resolutionBadge(w,h) has never existed; the real API is VideoTrack.qualityLabel
sub(W, "      expect(resolutionBadge(1920, 1080), '1080p');\n"
       "      expect(resolutionBadge(1280, 720), '720p');\n"
       "      expect(resolutionBadge(3840, 2160), '4K');\n",
       "      String? badge(int w, int h) => VideoTrack(\n"
       "            id: 'x',\n"
       "            title: 'x',\n"
       "            path: '/sdcard/Movies/x.mp4',\n"
       "            width: w,\n"
       "            height: h,\n"
       "          ).qualityLabel;\n"
       "      expect(badge(1920, 1080), '1080p');\n"
       "      expect(badge(1280, 720), '720p');\n"
       "      expect(badge(3840, 2160), '4K');\n", 'badge')
# (9) formatFileSize renders GB with 2 decimals -> '1.00 GB' (lib/ NOT changed)
sub(W, "'1.0 GB'", "'1.00 GB'", 'gb')
# (10) Ask AI DOES live in player_screen's three-dot menu now (request #4)
sub(W, '      expect(playerScreen.contains("Ask AI about this video"), isFalse);\n',
       '      // v94: Ask AI lives in the player\'s THREE-DOT menu (request #4),\n'
       '      // not next to Subtitles/Audio in the tracks sheet.\n'
       '      expect(playerScreen.contains("Ask AI about this video"), isTrue);\n', 'ask-assert')
# (11) drop the duplicate test that made v93 copy the helpers into formatters.dart
sub(W, "\n    test('Formatters define tmdbRatingText, formatRuntime and formatVoteCount', () {\n"
       "      expect(tmdbRatingText(8.365), '8.4');\n"
       "      expect(formatRuntime(136), '2h 16m');\n"
       "      expect(formatRuntime(45), '45m');\n"
       "      expect(formatVoteCount(24513), '24,513');\n"
       "    });\n", "", 'dup-test')

sub('pubspec.yaml', 'version: 1.0.0+93', 'version: 1.0.0+94', 'bump')

for p, txt in P.items():
    open(p, 'w', encoding='utf-8').write(txt)
print(f'  python: {len(P)} files patched, all anchors unique')
PY

# ---- two files revert byte-for-byte to v92; let git do it exactly -----------
git checkout 5117d44 -- lib/utils/formatters.dart lib/widgets/player_controls_overlay.dart
echo "  git   : formatters.dart + player_controls_overlay.dart restored to v92 blobs"

# ---- verify: brace / paren / bracket balance on every patched .dart file -----
echo
DART_FILES=$({ git diff --name-only; git diff --cached --name-only; } | sort -u | grep '\.dart$' || true)
set +e
if [ -n "$DART_FILES" ]; then
python3 - $DART_FILES <<'PY'
import sys

def balance(path):
    s = open(path, encoding='utf-8').read()
    d = {'{': 0, '(': 0, '[': 0}
    close = {'}': '{', ')': '(', ']': '['}
    i, q = 0, None
    while i < len(s):
        c = s[i]
        if q:
            if c == '\\':
                i += 2; continue
            if c == q:
                q = None
        elif c in ('"', "'"):
            q = c
        elif s.startswith('//', i):
            i = s.find('\n', i)
            if i < 0: break
            continue
        elif s.startswith('/*', i):
            j = s.find('*/', i + 2)
            i = len(s) if j < 0 else j + 2
            continue
        elif c in d:
            d[c] += 1
        elif c in close:
            d[close[c]] -= 1
        i += 1
    return d

bad = False
for f in sys.argv[1:]:
    d = balance(f)
    ok = all(v == 0 for v in d.values())
    bad = bad or not ok
    print(('  OK   ' if ok else '  FAIL ') + f'{f}  braces={d["{"]} parens={d["("]} brackets={d["["]}')
sys.exit(1 if bad else 0)
PY
RC=$?
else
  echo "  (no .dart files changed?!)"; RC=1
fi
set -e
if [ "$RC" -ne 0 ]; then
  echo "ERROR: balance check failed. Undo everything with:" >&2
  echo "  git reset -q && git checkout -- ." >&2
  exit 1
fi

echo
git --no-pager diff --cached --stat
git --no-pager diff --stat
echo
echo "DONE. Now verify:"
echo "  flutter analyze   # -> No issues found!"
echo "  flutter test      # -> All tests passed!  (13/13)"
echo
echo "Then commit v94 ALONE:"
echo "  git add -A"
echo "  git commit -m 'v94: repair broken v93 baseline (1.0.0+94)'"
echo "  git push origin main"
