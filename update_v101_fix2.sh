#!/usr/bin/env bash
# v101-fix2: clean `flutter analyze` infos + repair the 1 failing test.
#
# State of the Pi before this script: v101 + v101-fix applied,
# `flutter pub get` green, `flutter analyze` shows 4 infos, `flutter test`
# is 28/29 with one failure.
#
# 1) dangling_library_doc_comments x2 (drowsy_detector.dart, air_gestures.dart):
#    leading `///` file-overview docs with no `library` directive (new lint in
#    recent Dart). Fix: insert `library;` directly after the leading doc block.
# 2) use_build_context_synchronously x2 (player_controls_overlay toggles):
#    `ScaffoldMessenger.of(context)` after `await Permission.camera.request()`.
#    Fix: capture the messenger BEFORE the await (behavior-identical).
# 3) Failing test 'indicator content cross-fades on every change': STALE since
#    v100, not broken by v101 - v100's "indicator blink removal" deleted the
#    `ValueKey(_indicatorKey ?? 'hidden')` + `reverseDuration` pill it asserts.
#    Fix: assert the CURRENT indicator (speed-badge AnimatedSwitcher with
#    fade+scale) + assert the old blink wrapper stays gone (consistent with
#    the neighboring blink-removal test).
#
# Run ONCE on the v101+fix tree:
#   cd ~/IdeaProjects/maxplayer && git pull && bash update_v101_fix2.sh \
#     && flutter analyze && flutter test
set -eu
cd "$(dirname "$0")"

python3 <<'PYEOF'
import re, sys

def add_library(path):
    with open(path, 'r', encoding='utf-8') as f:
        src = f.read()
    if 'library;' in src:
        print(f'PATCH FAILED: {path}: library directive already present')
        sys.exit(1)
    m = re.match(r'((?:///.*\n)+)', src)
    if not m:
        print(f'PATCH FAILED: {path}: no leading /// doc block found')
        sys.exit(1)
    src = m.group(1) + 'library;\n' + src[m.end():]
    with open(path, 'w', encoding='utf-8') as f:
        f.write(src)
    print(f'patched (1x): {path}')

# --- 1) library directives (fixes the 2 dangling_library_doc_comments) ---
add_library('lib/services/drowsy_detector.dart')
add_library('lib/utils/air_gestures.dart')
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

# --- 2a) air-gestures toggle: messenger before the await ---
rep('lib/widgets/player_controls_overlay.dart',
    """                        final st = await Permission.camera.request();
                        if (!st.isGranted) {
                          ScaffoldMessenger.of(context)
                            ..clearSnackBars()
                            ..showSnackBar(
                              const SnackBar(
                                content: Text(
                                    'Camera permission needed for air gestures'),""",
    """                        final messenger = ScaffoldMessenger.of(context);
                        final st = await Permission.camera.request();
                        if (!st.isGranted) {
                          messenger
                            ..clearSnackBars()
                            ..showSnackBar(
                              const SnackBar(
                                content: Text(
                                    'Camera permission needed for air gestures'),""")

# --- 2b) look-away toggle: messenger before the await ---
rep('lib/widgets/player_controls_overlay.dart',
    """                        final st = await Permission.camera.request();
                        if (!st.isGranted) {
                          ScaffoldMessenger.of(context)
                            ..clearSnackBars()
                            ..showSnackBar(
                              const SnackBar(
                                content: Text(
                                    'Camera permission needed for look-away pause'),""",
    """                        final messenger = ScaffoldMessenger.of(context);
                        final st = await Permission.camera.request();
                        if (!st.isGranted) {
                          messenger
                            ..clearSnackBars()
                            ..showSnackBar(
                              const SnackBar(
                                content: Text(
                                    'Camera permission needed for look-away pause'),""")

# --- 3) stale v99 indicator test -> current (post blink-removal) reality ---
rep('test/widget_test.dart',
    """    test('indicator content cross-fades on every change', () {
      final ps = File('lib/screens/player_screen.dart').readAsStringSync();
      expect(ps, contains('AnimatedSwitcher'));
      expect(ps, contains("ValueKey(_indicatorKey ?? 'hidden')"));
      expect(ps, contains('reverseDuration'));
      // The pill show/hide animation must survive.
      expect(ps, contains('AnimatedScale'));
      expect(ps, contains('AnimatedOpacity'));
    });""",
    """    test('indicator content cross-fades on every change', () {
      final ps = File('lib/screens/player_screen.dart').readAsStringSync();
      expect(ps, contains('AnimatedSwitcher'));
      // v100 removed the old blink pill (ValueKey(_indicatorKey..) wrapper +
      // reverseDuration); the switcher that remains is the speed badge with
      // a fade+scale transition on every change.
      expect(ps.contains("ValueKey(_indicatorKey ?? 'hidden')"), isFalse);
      expect(ps.contains('reverseDuration'), isFalse);
      expect(ps, contains("ValueKey('speedBadge')"));
      expect(ps, contains('FadeTransition'));
      expect(ps, contains('ScaleTransition'));
      // The pill show/hide animation must survive.
      expect(ps, contains('AnimatedScale'));
      expect(ps, contains('AnimatedOpacity'));
    });""")
PYEOF

echo "ALL v101-fix2 PATCHES APPLIED"
echo "--- diff stat ---"
git diff --stat
