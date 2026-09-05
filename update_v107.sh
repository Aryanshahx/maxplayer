#!/bin/bash
# v107: (1) forced Play Store updates (immediate in-app update on launch);
# (2) Drive sign-in stays sticky - a dead silent grant no longer wipes the
# saved email, it just retries next open (still never prompts on its own);
# (3) GitHub-Pages branding docs (home / privacy / terms) for the OAuth
# consent screen + Play listing.
# AFTER RUNNING: repo Settings -> Pages -> Deploy from branch -> main + /docs,
# then paste these into the OAuth consent screen + Play Console:
#   home:    https://aryanshahx.github.io/maxplayer/
#   privacy: https://aryanshahx.github.io/maxplayer/privacy.html
#   terms:   https://aryanshahx.github.io/maxplayer/terms.html
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

# ------------------------------------------------- version + dep
rep('pubspec.yaml', 'version: 1.0.0+106', 'version: 1.0.0+107')
rep('pubspec.yaml',
    """  # v106: native Google Sign-In for Drive (no google-services.json - the
  # SHA-1-registered OAuth client resolves via Play Services at runtime).
  google_sign_in: ^7.2.0
""",
    """  # v106: native Google Sign-In for Drive (no google-services.json - the
  # SHA-1-registered OAuth client resolves via Play Services at runtime).
  google_sign_in: ^7.2.0

  # v107: forced Play Store updates (immediate in-app update flow).
  in_app_update: ^5.0.0
""")

# ------------------------------------------------- forced update on launch
rep('lib/screens/library_screen.dart',
    "import 'package:flutter/material.dart';\n",
    """import 'package:flutter/material.dart';
import 'package:in_app_update/in_app_update.dart';
""")
rep('lib/screens/library_screen.dart',
    """      // If the previous session died with an error, offer the recorded
      // crash report (copyable) so it can be sent for analysis.
      CrashLog.takeLastIncludingNative().then((report) {
        if (report != null && mounted) _showCrashReport(report);
      });""",
    """      // If the previous session died with an error, offer the recorded
      // crash report (copyable) so it can be sent for analysis.
      CrashLog.takeLastIncludingNative().then((report) {
        if (report != null && mounted) _showCrashReport(report);
      });
      _checkPlayUpdate();""")
rep('lib/screens/library_screen.dart',
    """  void _showCrashReport(String report) {""",
    """  /// v107: forced Play update - when the Play build is newer, the
  /// full-screen immediate flow blocks until the user updates. Silent
  /// everywhere else (sideloaded/debug builds are not Play-managed, and
  /// iOS has no such API - both throw and land in the catch).
  Future<void> _checkPlayUpdate() async {
    try {
      final info = await InAppUpdate.checkForUpdate();
      if (!mounted) return;
      if (info.updateAvailability == UpdateAvailability.updateAvailable &&
          info.immediateUpdateAllowed) {
        await InAppUpdate.performImmediateUpdate();
      }
    } catch (_) {}
  }

  void _showCrashReport(String report) {""")

# ------------------------------------------------- sticky sign-in
rep('lib/widgets/cloud_storage_sheet.dart',
    """    if (email == null || email.isEmpty) return;
    try {
      final account = await GDriveAuth.signInSilently();
      if (!mounted || account == null) {
        // Grant gone (revoked) - stop trying on future opens too.
        NativeBridge.saveSetting(_kDriveUserKey, '');
        return;
      }""",
    """    if (email == null || email.isEmpty) return;
    try {
      // v107: stay signed in once signed in - a dead grant just retries
      // silently next open (never prompts); only Disconnect clears it.
      final account = await GDriveAuth.signInSilently();
      if (!mounted || account == null) return;""")
PYEOF

# ------------------------------------------------- branding docs for Pages
python3 <<'PYEOF'
import os
os.makedirs('docs', exist_ok=True)

index = '''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Max Player - local video library &amp; player for Android</title>
<style>
  body{font-family:system-ui,-apple-system,Segoe UI,Roboto,sans-serif;margin:0;
    background:#0a0a0f;color:#eee;line-height:1.6}
  main{max-width:720px;margin:0 auto;padding:40px 20px}
  h1{font-size:2em;margin-bottom:.2em}
  .tag{color:#a78bfa;font-weight:bold}
  a{color:#22d3ee}
  footer{margin-top:48px;font-size:.85em;color:#888}
</style>
</head>
<body>
<main>
  <h1>Max Player</h1>
  <p class="tag">A local video library &amp; player for Android.</p>
  <p>Max Player plays the videos already on your device - mp4, webm, mkv, avi
  and more - with subtitles, audio-track switching, A-B loop, sleep timer,
  playback speed up to 3x, karaoke word highlight, dialogue boost, picture
  enhancement, private folder, network (SMB) playback and optional Google
  Drive streaming. Local-first: your files never leave your phone unless you
  explicitly stream them from your own Drive.</p>
  <p><a href="privacy.html">Privacy Policy</a> &middot;
     <a href="terms.html">Terms of Service</a> &middot;
     <a href="https://github.com/Aryanshahx/maxplayer">Source &amp; support</a></p>
  <footer>&copy; 2026 HyperTech Labs. Max Player is provided as-is.</footer>
</main>
</body>
</html>
'''

privacy = '''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Max Player - Privacy Policy</title>
<style>
  body{font-family:system-ui,-apple-system,Segoe UI,Roboto,sans-serif;margin:0;
    background:#0a0a0f;color:#eee;line-height:1.6}
  main{max-width:720px;margin:0 auto;padding:40px 20px}
  a{color:#22d3ee}
  footer{margin-top:48px;font-size:.85em;color:#888}
</style>
</head>
<body>
<main>
  <h1>Privacy Policy</h1>
  <p>Effective: 5 September 2026. Max Player ("the app", by HyperTech Labs) is
  a local-first video player. This policy explains what the app accesses.</p>
  <h2>What stays on your device</h2>
  <p>Your videos, watch history, bookmarks, playlists and settings live only
  on your phone. The app has no accounts, no analytics, no ads and no
  tracking. Nothing is uploaded to our servers - we operate none.</p>
  <h2>Google Drive (optional)</h2>
  <p>If you tap "Sign in with Google" in Cloud Storage, the app uses Google
  OAuth to list your Drive video files and stream the ones you tap. It
  requests the read-only Drive scope; the access token stays on your device
  and is never shared. Revoke anytime via the in-app Disconnect button or
  your Google Account permissions page.</p>
  <h2>Device permissions</h2>
  <ul>
    <li><b>Videos / Photos / Music &amp; audio:</b> finding and playing your
    media files.</li>
    <li><b>All files access (optional):</b> full-folder scanning on Android
    11+.</li>
    <li><b>Microphone:</b> voice search only, while you use it.</li>
    <li><b>Notifications:</b> playback controls and resume reminders.</li>
  </ul>
  <h2>Third parties</h2>
  <p>Movie posters and details come from TMDB when you open Discover; Google
  Play handles app updates. Their own policies apply to those services.</p>
  <h2>Contact</h2>
  <p>Questions: open an issue at
  <a href="https://github.com/Aryanshahx/maxplayer">github.com/Aryanshahx/maxplayer</a>.</p>
  <p><a href="index.html">Home</a> &middot; <a href="terms.html">Terms</a></p>
  <footer>&copy; 2026 HyperTech Labs.</footer>
</main>
</body>
</html>
'''

terms = '''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Max Player - Terms of Service</title>
<style>
  body{font-family:system-ui,-apple-system,Segoe UI,Roboto,sans-serif;margin:0;
    background:#0a0a0f;color:#eee;line-height:1.6}
  main{max-width:720px;margin:0 auto;padding:40px 20px}
  a{color:#22d3ee}
  footer{margin-top:48px;font-size:.85em;color:#888}
</style>
</head>
<body>
<main>
  <h1>Terms of Service</h1>
  <p>Effective: 5 September 2026. By installing Max Player (by HyperTech
  Labs) you agree to these terms.</p>
  <h2>The app</h2>
  <p>Max Player is a local media player for files you own or are entitled to
  play, plus playback of your own Google Drive and network shares. It is
  provided "as is", without warranties of any kind.</p>
  <h2>Acceptable use</h2>
  <p>Do not use the app to infringe copyright or any law. You are responsible
  for the content you play. Google Drive features are subject to Google's
  Terms and API policies.</p>
  <h2>Updates</h2>
  <p>Play Store builds may require installing newer versions to keep working
  (in-app update flow). Sideloaded builds are not covered by update or
  support promises.</p>
  <h2>Liability</h2>
  <p>To the maximum extent permitted by law, HyperTech Labs is not liable for
  any loss arising from use of the app.</p>
  <h2>Contact</h2>
  <p><a href="https://github.com/Aryanshahx/maxplayer">github.com/Aryanshahx/maxplayer</a>.</p>
  <p><a href="index.html">Home</a> &middot; <a href="privacy.html">Privacy</a></p>
  <footer>&copy; 2026 HyperTech Labs.</footer>
</main>
</body>
</html>
'''

for name, content in [('docs/index.html', index),
                       ('docs/privacy.html', privacy),
                       ('docs/terms.html', terms)]:
    if 'HyperTech Labs' not in content:
        raise SystemExit(f'PATCH FAILED: {name} content broken')
    open(name, 'w').write(content)
    print(f'wrote (1x): {name}')
PYEOF

python3 <<'PYEOF'
path = 'test/widget_test.dart'
src = open(path).read()
tail = '    });\n  });\n}\n'
assert src.endswith(tail), 'test file tail changed'
new_test = '''    test('v107 forced updates, sticky sign-in, branding docs', () {
      final pub = File('pubspec.yaml').readAsStringSync();
      expect(pub, contains('in_app_update'));
      final lib = File('lib/screens/library_screen.dart').readAsStringSync();
      for (final k in [
        'InAppUpdate.checkForUpdate',
        'performImmediateUpdate',
        'UpdateAvailability.updateAvailable',
      ]) {
        expect(lib, contains(k));
      }
      final sheet =
          File('lib/widgets/cloud_storage_sheet.dart').readAsStringSync();
      // Silent auth still gated on a past sign-in, but a dead grant no
      // longer wipes the email - the session stays sticky.
      expect(sheet, contains('email == null || email.isEmpty'));
      expect(sheet.contains('stop trying on future opens'), isFalse);
      for (final f in [
        'docs/index.html',
        'docs/privacy.html',
        'docs/terms.html',
      ]) {
        expect(File(f).existsSync(), isTrue);
      }
      final privacy = File('docs/privacy.html').readAsStringSync();
      expect(privacy, contains('Drive'));
      final terms = File('docs/terms.html').readAsStringSync();
      expect(terms, contains('as is'));
    });

'''
open(path, 'w').write(src[:-len(tail)] + new_test + tail)
print('patched (1x): test/widget_test.dart')
PYEOF

echo "ALL v107 PATCHES APPLIED"
echo "--- diff stat ---"
git diff --stat
