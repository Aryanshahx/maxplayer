#!/usr/bin/env bash
# v99: swap Cloud Storage <-> File Manager quick tiles; smooth cross-fade
# for every gesture-indicator change; remove Cast to TV + Screenshot from
# Player SETTINGS only (they stay in the player three-dots menu).
# All Dart, no new dependencies, no native/manifest changes.
# (Numbered v99 / build +99: v98 exists in history but was reverted, and
# +98 may already have been uploaded to a Play track, so both move forward.)
#
# Run from the repo root:  bash update_v99.sh
set -euo pipefail
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

# ---------------------------------------------------------------- pubspec
rep('pubspec.yaml',
    'version: 1.0.0+97',
    'version: 1.0.0+99')

# ------------------------------------------- library quick-tile swap ---
rep('lib/screens/library_screen.dart',
    '''/// Page 1: Private Space, Playlists, Folders, File Manager
/// Page 2: Network Storage, Cloud Storage, Open Stream, Cleaner''',
    '''/// Page 1: Private Space, Playlists, Folders, Cloud Storage
/// Page 2: Network Storage, File Manager, Open Stream, Cleaner''')

rep('lib/screens/library_screen.dart',
    '// Page 1 (2x2 Grid): Private Space, Playlists, Folders, File Manager',
    '// Page 1 (2x2 Grid): Private Space, Playlists, Folders, Cloud Storage')

# NOTE: the two tiles are swapped via a placeholder - replacing one with
# the other's text first would match twice on the second step.
rep('lib/screens/library_screen.dart',
    '''                        Expanded(
                          child: _Tile(
                            Icons.folder_shared_outlined,
                            'File Manager',
                            accent,
                            widget.onFileManager,
                          ),
                        ),''',
    '                        @@V99SWAP@@')

rep('lib/screens/library_screen.dart',
    '''                        Expanded(
                          child: _Tile(
                            Icons.cloud_queue_outlined,
                            'Cloud Storage',
                            accent,
                            widget.onCloudStorage,
                          ),
                        ),''',
    '''                        Expanded(
                          child: _Tile(
                            Icons.folder_shared_outlined,
                            'File Manager',
                            accent,
                            widget.onFileManager,
                          ),
                        ),''')

rep('lib/screens/library_screen.dart',
    '                        @@V99SWAP@@',
    '''                        Expanded(
                          child: _Tile(
                            Icons.cloud_queue_outlined,
                            'Cloud Storage',
                            accent,
                            widget.onCloudStorage,
                          ),
                        ),''')

rep('lib/screens/library_screen.dart',
    '// Page 2 (2x2 Grid): Network Storage, Cloud Storage, Open Stream, Cleaner',
    '// Page 2 (2x2 Grid): Network Storage, File Manager, Open Stream, Cleaner')

# --------------------------------------- indicator cross-fade (player) ---
rep('lib/screens/player_screen.dart',
    '''                          // Transient indicator (seek / volume / brightness /
                          // zoom / resume / fit / play-pause) - pops in and
                          // out with a small scale+fade.
                          // Transient indicator (seek / volume / brightness /
                          // zoom / resume / fit / play-pause) - smooth scale + fade + glassmorphic pill.''',
    '''                          // Transient indicator (seek / volume / brightness /
                          // zoom / resume / fit / play-pause) - pill pops
                          // with scale+fade; every content change
                          // cross-fades via AnimatedSwitcher below.''')

rep('lib/screens/player_screen.dart',
    '''                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (_indicatorIcon != null) ...[
                                            Icon(_indicatorIcon, color: themeState.accent, size: 20),
                                            const SizedBox(width: 8),
                                          ],
                                          Text(
                                            _indicatorText ?? '',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 14.5,
                                              fontWeight: FontWeight.bold,
                                              letterSpacing: 0.2,
                                            ),
                                          ),
                                        ],
                                      ),''',
    '''                                      // v99: content cross-fade - volume /
                                      // brightness / seek values glide out
                                      // and in on every change instead of
                                      // snapping while the pill stays put.
                                      child: AnimatedSwitcher(
                                        duration: const Duration(milliseconds: 160),
                                        reverseDuration: const Duration(milliseconds: 120),
                                        transitionBuilder: (child, animation) {
                                          return FadeTransition(
                                            opacity: animation,
                                            child: ScaleTransition(
                                              scale: Tween<double>(begin: 0.92, end: 1.0).animate(animation),
                                              child: child,
                                            ),
                                          );
                                        },
                                        child: Row(
                                          key: ValueKey(_indicatorKey ?? 'hidden'),
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            if (_indicatorIcon != null) ...[
                                              Icon(_indicatorIcon, color: themeState.accent, size: 20),
                                              const SizedBox(width: 8),
                                            ],
                                            Text(
                                              _indicatorText ?? '',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 14.5,
                                                fontWeight: FontWeight.bold,
                                                letterSpacing: 0.2,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),''')

# --------------------------------- Cast/Screenshot: settings only -------
rep('lib/screens/player_screen.dart',
    """        if (_settings.screenshotButton)
          _topMenuItem('shot', Icons.camera_alt_outlined, 'Screenshot'),
        if (_settings.castButton)
          _topMenuItem('cast', Icons.cast_outlined, 'Cast to TV'),""",
    """        // v99: always shown - the Player-settings toggles are gone, so
        // there is nothing left to gate these behind.
        _topMenuItem('shot', Icons.camera_alt_outlined, 'Screenshot'),
        _topMenuItem('cast', Icons.cast_outlined, 'Cast to TV'),""")

rep('lib/widgets/player_settings_sheet.dart',
    '''              _SwitchTile(
                icon: Icons.cast_outlined,
                label: 'Cast to TV (DLNA)',
                subtitle: 'Show the cast button in the player top bar',
                value: _settings.castButton,
                onChanged: (v) => _update(_settings.copyWith(castButton: v)),
              ),
              _SwitchTile(
                icon: Icons.camera_alt_outlined,
                label: 'Screenshot button',
                subtitle: 'Save the current frame to the gallery',
                value: _settings.screenshotButton,
                onChanged: (v) =>
                    _update(_settings.copyWith(screenshotButton: v)),
              ),
              _SwitchTile(''',
    '''              // v99: Cast to TV + Screenshot toggles removed here at the
              // developer's request. Both stay in the player three-dots
              // menu (ungated) - only the settings switches are gone.
              _SwitchTile(''')

# ------------------------------------------------------------- widget_test
rep('test/widget_test.dart',
    '''      // The 500ms guaranteed pulse is what keeps the bar from looking frozen.
      expect(s, contains('Timer.periodic(const Duration(milliseconds: 500)'));
    });
  });
}''',
    '''      // The 500ms guaranteed pulse is what keeps the bar from looking frozen.
      expect(s, contains('Timer.periodic(const Duration(milliseconds: 500)'));
    });
  });
  group('v99 tile swap, indicator cross-fade, settings-only Cast/Screenshot removal', () {
    test('Cloud Storage and File Manager swapped pages', () {
      final lib = File('lib/screens/library_screen.dart').readAsStringSync();
      // Page 1 now ends with Cloud Storage; File Manager moved to page 2.
      // Both labels occur exactly once, so index order == page order.
      expect(
          lib.indexOf("'Cloud Storage'") < lib.indexOf("'File Manager'"),
          isTrue);
      expect(
          lib,
          contains(
              'Page 1: Private Space, Playlists, Folders, Cloud Storage'));
      expect(
          lib,
          contains(
              'Page 2: Network Storage, File Manager, Open Stream, Cleaner'));
    });

    test('indicator content cross-fades on every change', () {
      final ps = File('lib/screens/player_screen.dart').readAsStringSync();
      expect(ps, contains('AnimatedSwitcher'));
      expect(ps, contains("ValueKey(_indicatorKey ?? 'hidden')"));
      expect(ps, contains('reverseDuration'));
      // The pill show/hide animation must survive.
      expect(ps, contains('AnimatedScale'));
      expect(ps, contains('AnimatedOpacity'));
    });

    test('Cast/Screenshot leave Player settings but stay in the player menu',
        () {
      final sheet =
          File('lib/widgets/player_settings_sheet.dart').readAsStringSync();
      expect(sheet.contains('Cast to TV (DLNA)'), isFalse);
      expect(sheet.contains('Screenshot button'), isFalse);
      final ps = File('lib/screens/player_screen.dart').readAsStringSync();
      // Ungated: no setting left to hide behind.
      expect(
          ps,
          contains(
              "_topMenuItem('shot', Icons.camera_alt_outlined, 'Screenshot')"));
      expect(
          ps,
          contains("_topMenuItem('cast', Icons.cast_outlined, 'Cast to TV')"));
      expect(ps.contains('if (_settings.screenshotButton)'), isFalse);
      expect(ps.contains('if (_settings.castButton)'), isFalse);
    });
  });
}''')

print('ALL v99 PATCHES APPLIED')
PYEOF

echo "--- diff stat ---"
git diff --stat
