#!/bin/bash
# v105 fix: repair the two analyze errors + two infos from update_v105.sh.
# Run AFTER update_v105.sh, in the same tree.
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

# ------------------------------------------------- test errors
# v105 deleted the `overlay` local but the dialogue asserts at the tail of
# the removal test still use it. Give them their own local.
rep('test/widget_test.dart',
    """      // Dialogue subtitle trimmed as requested.
      expect(
          overlay,
          contains(
              "'Lifts quiet speech (1-4 kHz). Off by default.'"));
      expect(overlay.contains('Same on-device filter as before'), isFalse);""",
    """      // Dialogue subtitle trimmed as requested.
      final overlaySrc =
          File('lib/widgets/player_controls_overlay.dart').readAsStringSync();
      expect(
          overlaySrc,
          contains(
              "'Lifts quiet speech (1-4 kHz). Off by default.'"));
      expect(overlaySrc.contains('Same on-device filter as before'), isFalse);""")

# ------------------------------------------------- analyze infos
# v105: both constructors take only const args - mark them const.
rep('lib/widgets/player_controls_overlay.dart',
    "                    leading: Icon(",
    "                    leading: const Icon(")
rep('lib/widgets/player_controls_overlay.dart',
    "                                    style: TextStyle(",
    "                                    style: const TextStyle(")
PYEOF

echo "ALL v105 FIX PATCHES APPLIED"
