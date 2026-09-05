#!/bin/bash
# v106-fix2: (1) sleep timer sheet scrolls in landscape (same bug class as the
# v35 tracks sheet: capped unscrollable Column); (2) silent Google re-auth
# runs ONLY when this device signed in before - first open never prompts.
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

# ------------------------------------------------- 1. sleep sheet scrolls
rep('lib/screens/player_screen.dart',
    """  void _showSleepSheet() {
    final player = widget.player;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1a1a24),""",
    """  void _showSleepSheet() {
    final player = widget.player;
    showModalBottomSheet<void>(
      context: context,
      // v106-fix2: full-height scrollable sheet (landscape never clips).
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1a1a24),""")
rep('lib/screens/player_screen.dart',
    """              final label = player.sleepTimerLabel;
              return Column(
                mainAxisSize: MainAxisSize.min,""",
    """              final label = player.sleepTimerLabel;
              // v106-fix2: scrollable so a short (landscape) screen never
              // clips the rows - same bug class as the v35 tracks sheet.
              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,""")
rep('lib/screens/player_screen.dart',
    """                  item(Icons.close, 'Off', onTap: player.cancelSleepTimer),
                  const SizedBox(height: 8),
                ],
              );
            },
          ),
        );
      },
    );
  }

  void _cycleFit() {""",
    """                  item(Icons.close, 'Off', onTap: player.cancelSleepTimer),
                  const SizedBox(height: 8),
                ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  void _cycleFit() {""")

# ------------------------------------------------- 2. silent sign-in gated
rep('lib/widgets/cloud_storage_sheet.dart',
    """    // Instant UI from the last cached list, then a silent Google session.
    final s = await NativeBridge.loadSettings();
    final cachedJson = s[_kDriveVideosCacheKey];""",
    """    // Instant UI from the last cached list, then a silent Google session.
    final s = await NativeBridge.loadSettings();
    final email = s[_kDriveUserKey];
    final cachedJson = s[_kDriveVideosCacheKey];""")
rep('lib/widgets/cloud_storage_sheet.dart',
    """    try {
      final account = await GDriveAuth.signInSilently();
      if (!mounted || account == null) return;""",
    """    // v106-fix2: never prompt on open - silent re-auth runs only when
    // this device signed in before (email saved); otherwise wait for the
    // Sign-In button.
    if (email == null || email.isEmpty) return;
    try {
      final account = await GDriveAuth.signInSilently();
      if (!mounted || account == null) {
        // Grant gone (revoked) - stop trying on future opens too.
        NativeBridge.saveSetting(_kDriveUserKey, '');
        return;
      }""")
PYEOF

python3 <<'PYEOF'
path = 'test/widget_test.dart'
src = open(path).read()
tail = '    });\n  });\n}\n'
assert src.endswith(tail), 'test file tail changed'
new_test = '''    test('v106-fix2 sleep scrolls, silent sign-in gated', () {
      final ps = File('lib/screens/player_screen.dart').readAsStringSync();
      final sleepStart = ps.indexOf('void _showSleepSheet()');
      final sleepEnd =
          ps.indexOf('Widget build(BuildContext context)', sleepStart);
      final sleepSheet = ps.substring(sleepStart, sleepEnd);
      expect(sleepSheet, contains('isScrollControlled: true'));
      expect(sleepSheet, contains('SingleChildScrollView'));
      final sheet =
          File('lib/widgets/cloud_storage_sheet.dart').readAsStringSync();
      expect(sheet, contains('email == null || email.isEmpty'));
      expect(sheet, contains('wait for the button'));
    });

'''
open(path, 'w').write(src[:-len(tail)] + new_test + tail)
print('patched (1x): test/widget_test.dart')
PYEOF

echo "ALL v106 FIX2 PATCHES APPLIED"
