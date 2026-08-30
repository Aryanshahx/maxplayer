#!/usr/bin/env bash
# Max Player v80 update script
# Run from the repo root: ~/IdeaProjects/maxplayer
set -euo pipefail

if [ ! -f "pubspec.yaml" ]; then
  echo "ERROR: run this from the maxplayer repo root (pubspec.yaml not found here)."
  exit 1
fi

echo "==> Patching lib/state/media_player_state.dart (request notification permission at the right moment)"
python3 - <<'PYEOF'
import sys
p = "lib/state/media_player_state.dart"
s = open(p, encoding="utf-8").read()
old = """  /// v67 B1/B2/v70: syncs Now Playing notification, media session, thumbnail & duration.
  void _syncNowPlaying() {
    final track = currentTrack;
    if (track == null) {
      unawaited(NativeBridge.cancelNowPlaying());
      unawaited(NativeBridge.setWakeLock(false));
      return;
    }
    if (backgroundAudio) {
      unawaited(NativeBridge.showNowPlaying("""
new = """  /// v80: replaces the old About-screen "test notification" button as the
  /// trigger for the notification permission prompt. Requesting it at
  /// cold app start (before the user has done anything) is bad UX and
  /// easy to reflexively deny; asking the first time it's actually
  /// needed - the first video plays with background audio on, which is
  /// what drives the lock-screen/notification media controls - gives the
  /// user context for why the app wants it. Only ever asked once per
  /// install (Android itself also won't re-show the OS dialog after a
  /// user denial, but this avoids even the repeat method-channel call).
  static const String _kNotifPermAskedKey = 'app.notificationPermAsked';
  static bool _notifPermCheckDone = false;

  Future<void> _maybeRequestNotificationPermission() async {
    if (_notifPermCheckDone) return;
    _notifPermCheckDone = true;
    final settings = await NativeBridge.loadSettings();
    if (settings[_kNotifPermAskedKey] == 'true') return;
    await NativeBridge.saveSetting(_kNotifPermAskedKey, 'true');
    await NativeBridge.requestNotifications();
  }

  /// v67 B1/B2/v70: syncs Now Playing notification, media session, thumbnail & duration.
  void _syncNowPlaying() {
    final track = currentTrack;
    if (track == null) {
      unawaited(NativeBridge.cancelNowPlaying());
      unawaited(NativeBridge.setWakeLock(false));
      return;
    }
    if (backgroundAudio) {
      unawaited(_maybeRequestNotificationPermission());
      unawaited(NativeBridge.showNowPlaying("""
if old not in s:
    sys.exit("[media_player_state.dart] anchor not found, aborting")
s = s.replace(old, new, 1)
open(p, "w", encoding="utf-8").write(s)
print("  OK")
PYEOF

echo "==> Patching lib/widgets/about_sheet.dart (remove test notification button)"
python3 - <<'PYEOF'
import sys
p = "lib/widgets/about_sheet.dart"
s = open(p, encoding="utf-8").read()

def apply(old, new):
    global s
    if old not in s:
        sys.exit(f"[about_sheet.dart] anchor not found, aborting:\n{old[:150]}")
    s = s.replace(old, new, 1)

apply(
'''  /// v62 Phase 1: asks for the notification permission once (Android 13+)
  /// and posts a simple test notification. Tapping it should bring the app
  /// back and show a "Notification: test:hello" snackbar - proving the whole
  /// permission -> channel -> tap pipeline works for later phases.
  Future<void> _sendTestNotification(BuildContext context) async {
    final granted = await NativeBridge.requestNotifications();
    if (!context.mounted) return;
    if (!granted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Notifications are blocked - enable them in '
              'Android settings > App notifications'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    await NativeBridge.showNotification(
      channel: NotificationChannels.general,
      title: 'Max Player notifications are on',
      body: 'Tap this to return to the app. AI subtitle alerts and new-'
          'episode updates will appear here soon.',
      payload: 'test:hello',
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Test notification sent - check your status bar'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

''', '')

apply(
'''          'building a player that truly puts you first.',
          style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.45),
        ),

        const SizedBox(height: 22),
        const Divider(color: Colors.white12),
        const SizedBox(height: 6),
        // v62 Phase 1: lets the user verify the notification foundation
        // (permission prompt + channel + tap delivery) on their phone. Later
        // phases replace this with the real AI-subs / continue-watching
        // notifications.
        Center(
          child: TextButton.icon(
            onPressed: () => _sendTestNotification(context),
            icon: const Icon(Icons.notifications_active_outlined, size: 16),
            label: const Text('Send a test notification'),
            style: TextButton.styleFrom(
              foregroundColor: accent,
              textStyle: const TextStyle(fontSize: 12.5),
            ),
          ),
        ),
        Center(
          child: TextButton.icon(
            onPressed: () => showPrivacyPolicyDialog(context),''',
'''          'building a player that truly puts you first.',
          style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.45),
        ),
        Center(
          child: TextButton.icon(
            onPressed: () => showPrivacyPolicyDialog(context),''')

open(p, "w", encoding="utf-8").write(s)
print("  OK")
PYEOF

echo ""
echo "===================================================================="
echo " v80 applied. What changed:"
echo "  1. Notification permission is now requested automatically the"
echo "     first time a video plays with background audio on (the actual"
echo "     feature that needs it) - asked once ever, with real context,"
echo "     instead of sitting behind a hidden About-screen test button"
echo "  2. Removed the 'Send a test notification' debug button from About"
echo "===================================================================="
echo ""
echo "Next steps:"
echo "  flutter analyze        # should print: No issues found!"
echo "  flutter test"
echo "  flutter build appbundle --release"
echo "  git add -A && git commit -m 'v80: request notification permission at first background play, remove test button from About' && git push"
