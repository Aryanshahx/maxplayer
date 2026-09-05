#!/bin/bash
# v106-fix: (1) sign-in errors now include the server description so the real
# cause is visible; (2) Discover + Library mic buttons ask for the microphone
# before launching voice search; (3) Android 13+ also asks Photos / Videos /
# Music access so App info stops showing "Not allowed".
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

# ------------------------------------------------- 1. sign-in details
rep('lib/widgets/cloud_storage_sheet.dart',
    """            : 'Sign in failed (${e.code}). If this persists, the app '
                'SHA-1 may not match the Cloud Console OAuth client.';""",
    """            : 'Sign in failed (${e.code}): ${e.description ?? 'no details'}. '
                'If this persists, the app SHA-1 may not match the Cloud '
                'Console OAuth client.';""")

# ------------------------------------------------- 2a. Discover mic asks first
rep('lib/screens/discover_screen.dart',
    "import 'package:flutter/material.dart';\n",
    """import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
""")
rep('lib/screens/discover_screen.dart',
    """  /// Voice search - launches native Google speech recognition dialogue and
  /// populates the search bar.
  Future<void> _startVoiceSearch() async {
    final query = await NativeBridge.launchSystemVoiceSearch();
    if (!mounted || query == null || query.isEmpty) return;
    _searchCtrl.text = query;
    _onSearchChanged(query);
  }""",
    """  /// Voice search - the app asks for the microphone first (so it also
  /// shows in App info), then launches native Google speech recognition
  /// dialogue and populates the search bar.
  Future<void> _startVoiceSearch() async {
    final mic = await Permission.microphone.request();
    if (!mounted) return;
    if (!mic.isGranted) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          const SnackBar(
            content: Text('Microphone needed for voice search'),
            duration: Duration(milliseconds: 1800),
          ),
        );
      return;
    }
    final query = await NativeBridge.launchSystemVoiceSearch();
    if (!mounted || query == null || query.isEmpty) return;
    _searchCtrl.text = query;
    _onSearchChanged(query);
  }""")

# ------------------------------------------------- 2b. Library search mic asks first
rep('lib/widgets/video_search_delegate.dart',
    "import 'package:flutter/material.dart';\n",
    """import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
""")
rep('lib/widgets/video_search_delegate.dart',
    """            onPressed: () async {
              final res = await NativeBridge.launchSystemVoiceSearch();
              if (res != null && res.trim().isNotEmpty) {
                query = res.trim();
                // ignore: use_build_context_synchronously
                showResults(context);
              }
            },""",
    """            onPressed: () async {
              final mic = await Permission.microphone.request();
              if (!mic.isGranted) {
                // ignore: use_build_context_synchronously
                ScaffoldMessenger.of(context)
                  ..clearSnackBars()
                  ..showSnackBar(
                    const SnackBar(
                      content: Text('Microphone needed for voice search'),
                      duration: Duration(milliseconds: 1800),
                    ),
                  );
                return;
              }
              final res = await NativeBridge.launchSystemVoiceSearch();
              if (res != null && res.trim().isNotEmpty) {
                query = res.trim();
                // ignore: use_build_context_synchronously
                showResults(context);
              }
            },""")

# ------------------------------------------------- 3. media permissions on 13+
rep('lib/utils/storage_permission.dart',
    """  if (!status.isGranted && (await NativeBridge.sdkInt()) < 30) {
    status = await Permission.storage.request();
  }
  return status.isGranted;
}""",
    """  if (!status.isGranted && (await NativeBridge.sdkInt()) < 30) {
    status = await Permission.storage.request();
  }
  if ((await NativeBridge.sdkInt()) >= 33) {
    // v106-fix: Android 13+ lists Photos / Videos / Music separately in App
    // info and gates MediaStore reads on them - ask even when All-files is
    // granted, so nothing shows "Not allowed".
    final videos = await Permission.videos.request();
    await Permission.photos.request();
    await Permission.audio.request();
    // All-files denied but videos granted: MediaStore still serves videos.
    if (!status.isGranted && videos.isGranted) return true;
  }
  return status.isGranted;
}""")
PYEOF

python3 <<'PYEOF'
path = 'test/widget_test.dart'
src = open(path).read()
tail = '    });\n  });\n}\n'
assert src.endswith(tail), 'test file tail changed'
new_test = '''    test('v106 fix: mic prompt, media permissions, sign-in details', () {
      final discover =
          File('lib/screens/discover_screen.dart').readAsStringSync();
      expect(discover, contains('Permission.microphone.request'));
      expect(discover, contains('Microphone needed for voice search'));
      final delegate =
          File('lib/widgets/video_search_delegate.dart').readAsStringSync();
      expect(delegate, contains('Permission.microphone.request'));
      final storage =
          File('lib/utils/storage_permission.dart').readAsStringSync();
      for (final k in [
        'Permission.videos.request',
        'Permission.photos.request',
        'Permission.audio.request',
      ]) {
        expect(storage, contains(k));
      }
      final sheet =
          File('lib/widgets/cloud_storage_sheet.dart').readAsStringSync();
      expect(sheet, contains('e.description'));
    });

'''
open(path, 'w').write(src[:-len(tail)] + new_test + tail)
print('patched (1x): test/widget_test.dart')
PYEOF

echo "ALL v106 FIX PATCHES APPLIED"

