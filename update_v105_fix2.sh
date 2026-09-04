#!/bin/bash
# v105 fix2: the picture-rows test wrongly expects 'PlayerSettings.kToneMapping'
# in the overlay. Tone persistence lives in the state setter (single writer) -
# the overlay only calls setToneMapping. Correct the test, not the app.
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

rep('test/widget_test.dart',
    """      // Rows are wired to the player state + persisted settings keys.
      for (final k in [
        'player.enhanceVideoOn',
        'setEnhanceVideo',
        'PlayerSettings.kEnhanceVideo',
        'player.toneMappingMode',
        'setToneMapping',
        'PlayerSettings.kToneMapping',
      ]) {
        expect(overlay, contains(k));
      }""",
    """      // Rows are wired to the player state + persisted settings keys.
      // (Tone persistence lives in the state setter - single writer - so
      // the overlay only calls setToneMapping.)
      for (final k in [
        'player.enhanceVideoOn',
        'setEnhanceVideo',
        'PlayerSettings.kEnhanceVideo',
        'player.toneMappingMode',
        'setToneMapping',
      ]) {
        expect(overlay, contains(k));
      }
      final state =
          File('lib/state/media_player_state.dart').readAsStringSync();
      expect(state, contains('PlayerSettings.kToneMapping'));""")
PYEOF

echo "ALL v105 FIX2 PATCHES APPLIED"
