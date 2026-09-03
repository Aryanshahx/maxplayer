#!/usr/bin/env bash
# =============================================================================
#  v96_nano.sh  -  Max Player v95 -> v96  (compact paste-into-nano version)
#  Byte-identical result to update_maxplayer_v96.sh; only the docs are trimmed.
#
#  BASELINE: 1e48b43 (1.0.0+95). Refuses to run on anything else.
#
#  FIXES
#   C1  season buttons not clicking - v95 deleted the ChoiceChip's onSelected,
#       which silently DISABLES it. Restored. (analyze cannot catch this: the
#       parameter is optional, so dropping it is valid, compiling Dart.)
#   C2/C3 season synopsis (was maxLines:3) and episode synopsis (maxLines:2)
#       are no longer clamped - full text shown.
#   C4  Where to Watch moved to directly below the storyline.
#   C5  Resume button: white text on the accent colour, and the default accent
#       IS white -> invisible in the white theme. Now themeState.onAccent.
#   C6  targetSdk 36 => Android 15+ enforces edge-to-edge, so the system nav
#       bar overlapped the home screen. MiniPlayer is a custom
#       bottomNavigationBar and never consumed the bottom inset; wrapped in
#       SafeArea(top: false).
#   C7-C13 File Manager AI removed entirely, incl. lib/services/media_ai.dart.
#       movie_ai.dart / ai_suggest.dart untouched.
#   C14 version -> 1.0.0+96
#
#  SAFETY
#   * refuses on a dirty tree, or if pubspec is not 1.0.0+95
#   * each patch carries a sha256 of the EXACT block it replaces; the script
#     recomputes it and aborts (writing nothing) on any mismatch
#   * re-checks brace/paren/bracket balance on every patched .dart file
#   * refuses if native_bridge.dart is under 700 lines (the v75 guard)
#   * --ship additionally requires analyze AND test to pass before committing
#
#  USAGE
#      ./v96_nano.sh                          # patch only
#      ./v96_nano.sh ~/IdeaProjects/maxplayer --ship   # patch+verify+commit+push
# =============================================================================
set -euo pipefail

REPO="${1:-$HOME/IdeaProjects/maxplayer}"
SHIP=0
for a in "$@"; do [ "$a" = "--ship" ] && SHIP=1; done

echo "=============================================="
echo " Max Player v96 nano  (v95 -> v96)"
echo "=============================================="
echo "Repo: $REPO"
[ -d "$REPO/.git" ] || { echo "ERROR: '$REPO' is not a git repository." >&2; exit 1; }
cd "$REPO"
git log --oneline -1
echo

git diff --quiet && git diff --cached --quiet || {
  echo "ERROR: working tree is dirty. Commit or stash first." >&2
  git status --short >&2; exit 1; }

for f in lib/widgets/movie_detail_sheet.dart lib/screens/library_screen.dart \
         lib/screens/file_manager_screen.dart lib/services/media_ai.dart \
         test/widget_test.dart pubspec.yaml ; do
  [ -f "$f" ] || { echo "ERROR: expected file missing: $f" >&2; exit 1; }
done

NB=$(wc -l < lib/services/native_bridge.dart)
[ "$NB" -ge 700 ] || { echo "ERROR: native_bridge.dart is only $NB lines (real bridge ~877)." >&2; exit 1; }
grep -q "^version: 1.0.0+95" pubspec.yaml || {
  echo "ERROR: pubspec.yaml is not at 1.0.0+95 - expected baseline 1e48b43." >&2; exit 1; }
echo "baseline v95 OK | native_bridge $NB lines OK"
echo
echo "--- verifying 14 block hashes, then applying ---"

set +e
python3 - <<'PYEOF'
import hashlib
import os
import sys

DELETE_FILES = ['lib/services/media_ai.dart']

PATCHES = [
    ('C1-season-chip-onSelected', 'lib/widgets/movie_detail_sheet.dart', 630, 633, '37739b4fc040199e',
     "                  side: BorderSide(\n                    color: isSelected ? themeState.accent : Colors.white12,\n                  ),\n                  // v96 REGRESSION FIX: v95's season-header patch accidentally\n                  // dropped this line. A ChoiceChip whose onSelected is null is\n                  // DISABLED, which is exactly why the season buttons stopped\n                  // responding to taps. `flutter analyze` cannot catch it: the\n                  // parameter is optional, so the chip just goes silently inert.\n                  onSelected: (_) => _loadSeasonDetail(s.number),\n                );\n"),
    ('C2-season-overview-full', 'lib/widgets/movie_detail_sheet.dart', 684, 687, '8f06e9d60beb7200',
     "                    Text(\n                      // v96: 'dont cut its detail show full' - this season\n                      // synopsis was clamped to 3 lines with an ellipsis.\n                      _seasonDetail!.overview,\n"),
    ('C3-episode-overview-full', 'lib/widgets/movie_detail_sheet.dart', 778, 782, 'b5276a1e92da69cc',
     '                                child: Text(\n                                  // v96: episode synopses were clamped to 2\n                                  // lines with an ellipsis; show them in full.\n                                  ep.overview,\n                                  style: const TextStyle(color: Colors.white54, fontSize: 11.5, height: 1.3),\n'),
    ('C4-watch-below-storyline', 'lib/widgets/movie_detail_sheet.dart', 288, 309, '749cda57b231031b',
     "                  // Contents / production details (v95: above the storyline)\n                  _AllDataBlock(extras: full.extras, movieId: movie.id),\n\n                  // Rich Storyline & Overview\n                  _DetailedStoryBlock(movie: movie, extras: full.extras),\n\n                  // v96: 'show where to watch below storyline' - moved up from\n                  // its old slot down after the seasons block.\n                  if (!full.watch.isEmpty) _WatchBlock(info: full.watch),\n\n                  // Top Cast Slider with Profile Images\n                  if (full.extras.castMembers.isNotEmpty)\n                    _TopCastSlider(cast: full.extras.castMembers),\n\n                  // Web Series Seasons & Episodes breakdown\n                  if (isTv && full.seasons.isNotEmpty)\n                    _SeasonsBlock(tvId: movie.id, seasons: full.seasons),\n\n                  // v95: 'show ALL user reviews at the END of the details'\n                  if (full.reviews.isNotEmpty)\n                    _ReviewsBlock(reviews: full.reviews),\n"),
    ('C5-resume-button-contrast', 'lib/screens/library_screen.dart', 650, 655, '64e6d83cad02dc8c',
     "                        style: TextButton.styleFrom(\n                          backgroundColor: themeState.accent,\n                          // v96 FIX: 'resume button is getting invisible in\n                          // white theme'. Same bug class as the season chips:\n                          // accent background + a hardcoded WHITE foreground,\n                          // and the app's DEFAULT accent is white\n                          // (theme_state.dart:23) => white on white.\n                          foregroundColor: themeState.onAccent,\n                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),\n                          visualDensity: VisualDensity.compact,\n                        ),\n"),
    ('C6-miniplayer-safearea', 'lib/screens/library_screen.dart', 586, 587, 'a7d9591c03e6d81a',
     "      // Mini player sits at the bottom while something is loaded.\n      // v96 FIX: 'navigation bar of device is overflow over home screen'.\n      // android/app/build.gradle.kts sets targetSdk = 36, and Android 15+\n      // ENFORCES edge-to-edge, so the system navigation bar now draws ON TOP\n      // of the bottom of the app. Scaffold does not inset a custom\n      // bottomNavigationBar (Material's NavigationBar does it internally;\n      // MiniPlayer is hand-rolled and did not), so the mini player - and the\n      // home list behind it - sat underneath the gesture bar / 3-button nav.\n      // SafeArea(top: false) adds exactly the bottom inset and nothing else.\n      bottomNavigationBar: SafeArea(\n        top: false,\n        child: MiniPlayer(player: widget.player),\n      ),\n"),
    ('C7-fm-ai-import', 'lib/screens/file_manager_screen.dart', 6, 6, '01996e246972aa43',
     ''),
    ('C8-fm-ai-methods', 'lib/screens/file_manager_screen.dart', 469, 654, '5d9f4274e3894d5a',
     ''),
    ('C9-fm-ai-button', 'lib/screens/file_manager_screen.dart', 861, 865, 'cf0f97756bcc2917',
     ''),
    ('C10-fm-header-comment', 'lib/screens/file_manager_screen.dart', 16, 17, '79d667b34502e40c',
     "/// v93: Advanced Media File Manager & Storage Explorer with full media viewers\n/// (Images, Audio/Music, Documents).\n/// v96: the AI media-insights feature was REMOVED at the developer's request\n/// ('remove ai from file manager'), together with its service file. The\n/// identifiers are deliberately not spelled out here: a test asserts that\n/// this file contains no residue of them at all.\n"),
    ('C11-test-ai-import', 'test/widget_test.dart', 10, 10, 'ccc7ed4cf085ae2f',
     ''),
    ('C12-test-fm-assert', 'test/widget_test.dart', 97, 106, '635a861a21762c78',
     "    test('FileManagerScreen opens images, audio and documents', () {\n      final fileMgr = File('lib/screens/file_manager_screen.dart').readAsStringSync();\n      expect(fileMgr, contains('_openImageViewer'));\n      expect(fileMgr, contains('_openAudioPlayer'));\n      expect(fileMgr, contains('_openDocumentViewer'));\n      // v96: the developer asked for the File Manager's AI to be removed\n      // entirely, so pin its absence instead of its presence.\n      expect(fileMgr.contains('_showAiMediaInsights'), isFalse);\n      expect(fileMgr, contains('widget.player.seekBy'));\n      expect(fileMgr, contains('widget.player.togglePlay'));\n      expect(fileMgr.contains('seekRelative'), isFalse);\n    });\n"),
    ('C13-test-v96-group', 'test/widget_test.dart', 129, 177, '3a0eaa9f3031e61d',
     "\n  group('v96 removals and regression guards', () {\n    test('File Manager AI and its service are gone', () {\n      expect(File('lib/services/media_ai.dart').existsSync(), isFalse);\n      final fm = File('lib/screens/file_manager_screen.dart').readAsStringSync();\n      expect(fm.contains('media_ai.dart'), isFalse);\n      expect(fm.contains('_showAiMediaInsights'), isFalse);\n      expect(fm.contains('AI Media Insights'), isFalse);\n      expect(fm.contains('_aiStatRow'), isFalse);\n      expect(fm.contains('_mediaKind'), isFalse);\n    });\n\n    test('season chips are tappable again (v95 dropped onSelected)', () {\n      // A ChoiceChip with a null onSelected is DISABLED. v95 lost that line,\n      // which is why season buttons stopped responding to taps. This guard\n      // exists because `flutter analyze` structurally cannot catch it.\n      final detail = File('lib/widgets/movie_detail_sheet.dart').readAsStringSync();\n      expect(detail, contains('onSelected: (_) => _loadSeasonDetail(s.number)'));\n    });\n\n    test('no white-on-white buttons survive on an accent background', () {\n      // Both the season chips (v95) and the Resume button (v96) painted\n      // hardcoded white on themeState.accent, and the default accent IS white.\n      final lib = File('lib/screens/library_screen.dart').readAsStringSync();\n      expect(lib, contains('foregroundColor: themeState.onAccent'));\n    });\n\n    test('episode and season synopses are no longer clamped', () {\n      final detail = File('lib/widgets/movie_detail_sheet.dart').readAsStringSync();\n      expect(detail.contains('_seasonDetail!.overview,\\n                      maxLines'), isFalse);\n      expect(detail.contains('ep.overview,\\n                                  maxLines'), isFalse);\n    });\n  });\n"),
    ('C14-pubspec-bump', 'pubspec.yaml', 4, 4, '50cdba14d895015d',
     'version: 1.0.0+96\n'),
]

def main():
    src = {}
    for pid, rel, s, e, h, new in PATCHES:
        if rel not in src:
            if not os.path.isfile(rel):
                sys.exit("ERROR: missing file " + rel)
            src[rel] = open(rel, encoding="utf-8").read()

    bad = []
    for pid, rel, s, e, h, new in PATCHES:
        ls = src[rel].splitlines(keepends=True)
        if e > len(ls):
            bad.append((pid, rel, "file has only %d lines" % len(ls)))
            continue
        blk = "".join(ls[s - 1:e])
        got = hashlib.sha256(blk.encode("utf-8")).hexdigest()[:16]
        if got != h:
            bad.append((pid, rel, "block %d-%d hashes %s, expected %s" % (s, e, got, h)))
    if bad:
        print("\nABORTED - no files were modified.")
        for pid, rel, why in bad:
            print("  [%s] %s: %s" % (pid, rel, why))
        print("\nYour tree does not match the v95 baseline (1e48b43) these")
        print("patches were cut from. Run:  git log --oneline -3")
        print("HEAD must be 1e48b43 and the tree must be clean.")
        sys.exit(1)

    # Splice per file from the BOTTOM up: every patch shifts the line count, so
    # applying in table order would make later ranges point at the wrong lines.
    # (Hash verification above already ran against the untouched originals.)
    for pid, rel, s, e, h, new in sorted(PATCHES, key=lambda p: (p[1], -p[2])):
        ls = src[rel].splitlines(keepends=True)
        src[rel] = "".join(ls[:s - 1]) + new + "".join(ls[e:])
        print("    applied %-28s %s:%d-%d" % (pid, rel, s, e))

    for rel, text in src.items():
        open(rel, "w", encoding="utf-8").write(text)

    for rel in DELETE_FILES:
        if os.path.isfile(rel):
            os.remove(rel)
            print("    deleted %s" % rel)

    print("\n  %d patches -> %d files; %d deleted." % (len(PATCHES), len(src), len(DELETE_FILES)))


if __name__ == "__main__":
    main()
PYEOF
RC=$?
set -e
[ "$RC" -eq 0 ] || { echo "ERROR: patch stage failed; tree NOT modified." >&2; exit 1; }

echo
echo "--- balance check ---"
set +e
python3 - lib/screens/file_manager_screen.dart lib/screens/library_screen.dart lib/widgets/movie_detail_sheet.dart test/widget_test.dart <<'PYEOF'
import sys
def bal(path):
    s = open(path, encoding='utf-8').read()
    d = {'{': 0, '(': 0, '[': 0}
    cl = {'}': '{', ')': '(', ']': '['}
    i, q = 0, None
    while i < len(s):
        c = s[i]
        if q:
            if c == '\\':
                i += 2; continue
            if c == q: q = None
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
        elif c in d: d[c] += 1
        elif c in cl: d[cl[c]] -= 1
        i += 1
    return d
bad = False
for f in sys.argv[1:]:
    d = bal(f)
    ok = all(v == 0 for v in d.values())
    bad |= not ok
    print(('  OK   ' if ok else '  FAIL ') + '%s  {}=%d ()=%d []=%d' % (f, d['{'], d['('], d['[']))
sys.exit(1 if bad else 0)
PYEOF
BAL=$?
set -e
[ "$BAL" -eq 0 ] || { echo "ERROR: balance check failed. Undo: git checkout -- . && git clean -fd lib/services" >&2; exit 1; }

echo
git --no-pager diff --stat

if [ "$SHIP" -ne 1 ]; then
  echo
  echo "PATCHED (not committed). Now run:"
  echo "  flutter analyze      # -> No issues found!"
  echo "  flutter test         # -> All tests passed! (17)"
  echo "  git add -A && git commit && git push origin main"
  echo "Or re-run with --ship to do all of that automatically."
  exit 0
fi

echo
echo "--- --ship: verifying ---"
command -v flutter >/dev/null 2>&1 || {
  echo "ERROR: --ship needs flutter on PATH. Patch IS applied; commit manually." >&2; exit 1; }
git config user.email >/dev/null 2>&1 && git config user.name >/dev/null 2>&1 || {
  echo "ERROR: git has no identity here. Set user.email/user.name, then re-run --ship." >&2
  echo "       Patch IS applied and verified; nothing is lost." >&2; exit 1; }
git remote get-url origin >/dev/null 2>&1 || { echo "ERROR: no origin remote." >&2; exit 1; }

set +e
flutter analyze; A=$?
flutter test;    T=$?
set -e
if [ "$A" -ne 0 ] || [ "$T" -ne 0 ]; then
  echo "ERROR: analyze($A)/test($T) did not both pass - NOT committing, NOT pushing." >&2
  echo "       Undo: git checkout -- . && git clean -fd lib/services" >&2
  exit 1
fi

echo
echo "--- --ship: commit + push ---"
git add -A
git commit -F- <<'MSG'
v96: restore season chip onSelected (v95 regression); remove File Manager AI;
edge-to-edge mini player; Resume contrast; full synopses; watch below storyline

C1  movie_detail_sheet: v95 accidentally deleted the season ChoiceChip's
    onSelected handler, silently DISABLED every season button. A null
    onSelected is valid Dart, so analyze could not catch it. Restored + guarded.
C2/C3 season and episode synopses no longer clamped to 3/2 lines.
C4  Where to Watch moved to directly below the storyline.
C5  library_screen: Resume button painted white on the accent colour; the
    default accent IS white, so it vanished in the white theme. Now onAccent.
C6  library_screen: targetSdk 36 => Android 15+ enforces edge-to-edge, so the
    system nav bar overlapped the home screen. MiniPlayer never consumed the
    bottom inset; wrapped in SafeArea(top: false).
C7-C13 File Manager AI removed entirely, incl. lib/services/media_ai.dart.
MSG
git push origin main
echo
echo "v96 SHIPPED. Build the APK/AAB on Codemagic."
