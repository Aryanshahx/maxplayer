#!/usr/bin/env bash
# Max Player v74 update script
# Run from the repo root: ~/IdeaProjects/maxplayer
set -euo pipefail

if [ ! -f "pubspec.yaml" ]; then
  echo "ERROR: run this from the maxplayer repo root (pubspec.yaml not found here)."
  exit 1
fi

echo "==> Patching lib/state/media_player_state.dart (seek/notification sync fix + night mode removal)"
python3 - <<'PYEOF'
import sys
p = "lib/state/media_player_state.dart"
s = open(p, encoding="utf-8").read()

def apply(old, new, required=True):
    global s
    if old not in s:
        if required:
            sys.exit(f"[media_player_state.dart] anchor not found, aborting:\n{old[:150]}")
        return
    s = s.replace(old, new, 1)

# 1) restore-settings: stop reading the removed nightModeDrc key
apply(
"""    dialogueBoost = s[PlayerSettings.kDialogueBoost] == 'true';
    nightModeDrc = s[PlayerSettings.kNightModeDrc] == 'true';
""",
"""    dialogueBoost = s[PlayerSettings.kDialogueBoost] == 'true';
""")

apply(
"    if (eqEnabled || dialogueBoost || nightModeDrc) _applyAudioFilters();\n",
"    if (eqEnabled || dialogueBoost) _applyAudioFilters();\n")

# 2) seek(): fix stale-position race that desynced the notification/lock-screen playbar
#    AND use a fast keyframe seek instead of mpv's default precise seek
#    (precise seeking decodes every frame from the last keyframe to the
#    target - the real cause of "lagging when seek" while scrubbing).
apply(
"""  Future<void> seek(Duration to) async {
    await player.seek(to);
    _syncNowPlaying();
  }

  /// Relative seek (e.g. \u00b110s), using instant keyframe seeking.
  Future<void> seekBy(int seconds) async {
    if (currentTrack == null) return;
    final plat = player.platform;
    if (plat is NativePlayer) {
      try {
        await plat.command(['seek', '$seconds', 'relative+keyframes']);
        _syncNowPlaying();
        return;
      } catch (_) {}
    }
    var target = position + Duration(seconds: seconds);
    if (target < Duration.zero) target = Duration.zero;
    if (duration > Duration.zero && target > duration) target = duration;
    await player.seek(target);
    _syncNowPlaying();
  }""",
"""  Future<void> seek(Duration to) async {
    // v74: fast keyframe seek instead of mpv's default precise seek. The
    // scrub bar can fire this rapidly while dragging, and precise seeking
    // makes mpv decode every frame from the last keyframe up to the
    // target - on long-GOP/4K files that's real CPU work per seek and was
    // the main cause of "lagging when seek". Trading frame-exact landing
    // for an instant jump to the nearest keyframe matches how VLC's own
    // scrub bar behaves.
    final plat = player.platform;
    if (plat is NativePlayer) {
      try {
        final seconds = to.inMilliseconds / 1000.0;
        await plat.command(['seek', '$seconds', 'absolute+keyframes']);
      } catch (_) {
        await player.seek(to);
      }
    } else {
      await player.seek(to);
    }
    // The real player.stream.position event can arrive a beat late (it's
    // an async stream). If _syncNowPlaying() runs before it fires, it
    // pushes the STALE position back to the notification / lock-screen
    // MediaSession, snapping its seekbar back even though playback really
    // did jump \u2014 "video shifts but the notification playbar doesn't".
    // Set the field immediately so every listener (in-app playbar + the
    // notification sync below) sees the true target position right away.
    position = to;
    notifyListeners();
    _syncNowPlaying();
  }

  /// Relative seek (e.g. \u00b110s), using instant keyframe seeking.
  Future<void> seekBy(int seconds) async {
    if (currentTrack == null) return;
    var target = position + Duration(seconds: seconds);
    if (target < Duration.zero) target = Duration.zero;
    if (duration > Duration.zero && target > duration) target = duration;
    final plat = player.platform;
    if (plat is NativePlayer) {
      try {
        await plat.command(['seek', '$seconds', 'relative+keyframes']);
        position = target; // v74: same fix as seek() above.
        notifyListeners();
        _syncNowPlaying();
        return;
      } catch (_) {}
    }
    await player.seek(target);
    position = target;
    notifyListeners();
    _syncNowPlaying();
  }""")

# 2b) scrub-preview thumbnail: drop the blocking existsSync() disk stat
#     that ran on every Slider rebuild while dragging (real cause of the
#     laggy playbar preview). Native already guarantees every frame exists
#     before handing back the strip directory.
apply(
"""  /// Thumbnail file for the preview bubble at [fraction] (0..1 of the
  /// video), or null while that frame hasn't been generated yet (the
  /// bubble then shows the timestamp only).
  String? scrubThumbPath(double fraction) {
    final dir = _thumbStripDir;
    if (dir == null) return null;
    final i = (fraction.clamp(0.0, 1.0) * (thumbStripCount - 1)).round();
    final f = File('$dir/f_${i.toString().padLeft(3, '0')}.jpg');
    return f.existsSync() ? f.path : null;
  }""",
"""  /// Thumbnail file for the preview bubble at [fraction] (0..1 of the
  /// video), or null while the strip hasn't been generated yet (the
  /// bubble then shows the timestamp only).
  ///
  /// v74: dropped the per-call File.existsSync() disk stat that used to
  /// run here. This was called from the Slider's build() on every drag
  /// update (can fire dozens of times/second while scrubbing fast), and
  /// existsSync() blocks the UI thread on a disk syscall each time - that
  /// was the real cause of the laggy scrub-preview bubble. The native
  /// generator (thumbStripEnsureSync) always writes every frame in the
  /// strip BEFORE handing back the directory, so by the time
  /// _thumbStripDir is non-null every path is already guaranteed to
  /// exist; Image.file's existing errorBuilder still covers the rare
  /// frame that failed to encode natively.
  String? scrubThumbPath(double fraction) {
    final dir = _thumbStripDir;
    if (dir == null) return null;
    final i = (fraction.clamp(0.0, 1.0) * (thumbStripCount - 1)).round();
    return '$dir/f_${i.toString().padLeft(3, '0')}.jpg';
  }""")

# 3) remove nightModeDrc field + setter
apply(
"""  /// v72: Night Mode Dynamic Range Compression state.
  bool nightModeDrc = false;

""", "")

apply(
"""  Future<void> setNightModeDrc(bool on) async {
    nightModeDrc = on;
    NativeBridge.saveSetting(PlayerSettings.kNightModeDrc, '$on');
    notifyListeners();
    await _applyAudioFilters();
  }

""", "")

# 4) drop nightModeDrc from the combined-filter builder
apply(
"""  /// v72: Builds the combined audio filter chain (Dialogue booster + Night mode DRC + Equalizer).
  static String buildCombinedAudioFilter({
    bool dialogueBoost = false,
    bool nightModeDrc = false,
    bool eqEnabled = false,
    List<double> eqGains = const [],
  }) {
    final parts = <String>[];
    if (nightModeDrc) {
      // Dynamic Range Compression: boosts quiet dialogue, tames loud action explosions
      parts.add('acompressor=threshold=-21dB:ratio=4:attack=20:release=250:makeup=5dB');
    }
    if (dialogueBoost) {""",
"""  /// v74: Builds the combined audio filter chain (Dialogue booster + Equalizer).
  /// Night Mode DRC was removed in v74 (setting dropped from Settings).
  static String buildCombinedAudioFilter({
    bool dialogueBoost = false,
    bool eqEnabled = false,
    List<double> eqGains = const [],
  }) {
    final parts = <String>[];
    if (dialogueBoost) {""")

apply(
"""    final af = buildCombinedAudioFilter(
      dialogueBoost: dialogueBoost,
      nightModeDrc: nightModeDrc,
      eqEnabled: eqEnabled,
      eqGains: eqGains,
    );""",
"""    final af = buildCombinedAudioFilter(
      dialogueBoost: dialogueBoost,
      eqEnabled: eqEnabled,
      eqGains: eqGains,
    );""")

open(p, "w", encoding="utf-8").write(s)
print("  OK")
PYEOF

echo "==> Patching lib/state/player_settings.dart (remove nightModeDrc setting)"
python3 - <<'PYEOF'
import sys
p = "lib/state/player_settings.dart"
s = open(p, encoding="utf-8").read()

def apply(old, new):
    global s
    if old not in s:
        sys.exit(f"[player_settings.dart] anchor not found, aborting:\n{old[:150]}")
    s = s.replace(old, new, 1)

apply('  /// v72: Night Mode Dynamic Range Compression (evens out quiet speech & loud explosions).\n  final bool nightModeDrc;\n\n', '')
apply('    this.nightModeDrc = false,\n', '')
apply("  static const String kNightModeDrc = 'player.nightModeDrc';\n", '')
apply('      nightModeDrc: s[kNightModeDrc] == \'true\',\n', '')
apply('    NativeBridge.saveSetting(kNightModeDrc, \'$nightModeDrc\');\n', '')
apply('    bool? nightModeDrc,\n', '')
apply('      nightModeDrc: nightModeDrc ?? this.nightModeDrc,\n', '')

open(p, "w", encoding="utf-8").write(s)
print("  OK")
PYEOF

echo "==> Patching lib/screens/player_screen.dart (stop pushing removed setting)"
python3 - <<'PYEOF'
import sys
p = "lib/screens/player_screen.dart"
s = open(p, encoding="utf-8").read()
old = "    unawaited(widget.player.setNightModeDrc(s.nightModeDrc));\n"
if old not in s:
    sys.exit("[player_screen.dart] anchor not found, aborting")
s = s.replace(old, "", 1)
open(p, "w", encoding="utf-8").write(s)
print("  OK")
PYEOF

echo "==> Patching lib/widgets/player_settings_sheet.dart (remove Night Mode toggle row)"
python3 - <<'PYEOF'
import sys
p = "lib/widgets/player_settings_sheet.dart"
s = open(p, encoding="utf-8").read()
old = """              _SwitchTile(
                icon: Icons.nightlight_round_outlined,
                label: 'Night Mode (Dynamic Range Compression)',
                subtitle:
                    'Lifts quiet whispers and tames loud action explosions for balanced nighttime listening',
                value: _settings.nightModeDrc,
                onChanged: (v) =>
                    _update(_settings.copyWith(nightModeDrc: v)),
              ),
              // v65: the old "Skip intro chip" setting is gone - smart"""
new = '              // v65: the old "Skip intro chip" setting is gone - smart'
if old not in s:
    sys.exit("[player_settings_sheet.dart] anchor not found, aborting")
s = s.replace(old, new, 1)
open(p, "w", encoding="utf-8").write(s)
print("  OK")
PYEOF

echo "==> Patching lib/widgets/video_thumb.dart (raise thumbnail decode concurrency 2 -> 4)"
python3 - <<'PYEOF'
import sys
p = "lib/widgets/video_thumb.dart"
s = open(p, encoding="utf-8").read()
old = """  /// v60 (old-phone pack): at most TWO native frame decodes running -
  /// one task per visible grid tile was spiking low-RAM phones. Queued
  /// tiles just keep the placeholder a moment longer.
  static int _thumbJobsRunning = 0;
  static final List<Completer<void>> _thumbWaiters = [];

  static Future<void> acquireThumbSlot() async {
    if (_thumbJobsRunning < 2) {"""
new = """  /// v60 (old-phone pack): capped native frame decodes running at once -
  /// one task per visible grid tile was spiking low-RAM phones. Queued
  /// tiles just keep the placeholder a moment longer.
  /// v74: raised 2 -> 4. The grab is mostly waiting on the decoder/disk,
  /// not spinning the CPU, so 2 was the main reason thumbnails trickled
  /// in noticeably slower than VLC while scrolling a big library.
  static int _thumbJobsRunning = 0;
  static final List<Completer<void>> _thumbWaiters = [];

  static Future<void> acquireThumbSlot() async {
    if (_thumbJobsRunning < 4) {"""
if old not in s:
    sys.exit("[video_thumb.dart] anchor not found, aborting")
s = s.replace(old, new, 1)
open(p, "w", encoding="utf-8").write(s)
print("  OK")
PYEOF

echo "==> Patching test/widget_test.dart (drop tests for removed nightModeDrc)"
python3 - <<'PYEOF'
import sys
p = "test/widget_test.dart"
s = open(p, encoding="utf-8").read()
old = """    test('MediaPlayerState.buildCombinedAudioFilter builds dialogue boost & DRC compressor', () {
      final drcOnly = MediaPlayerState.buildCombinedAudioFilter(nightModeDrc: true);
      expect(drcOnly, contains('acompressor'));
      expect(drcOnly, contains('threshold=-21dB'));

      final dialogueOnly = MediaPlayerState.buildCombinedAudioFilter(dialogueBoost: true);
      expect(dialogueOnly, contains('equalizer=f=1500'));
      expect(dialogueOnly, contains('equalizer=f=3000'));

      final combined = MediaPlayerState.buildCombinedAudioFilter(
        dialogueBoost: true,
        nightModeDrc: true,
        eqEnabled: true,
        eqGains: [2.0, 0.0, 0.0, 0.0, -1.0],
      );
      expect(combined, contains('acompressor'));
      expect(combined, contains('equalizer=f=1500'));
      expect(combined, contains('equalizer=f=60'));
    });

    test('PlayerSettings defaults and copyWith for dialogueBoost & nightModeDrc', () {
      const s = PlayerSettings();
      expect(s.dialogueBoost, isFalse);
      expect(s.nightModeDrc, isFalse);

      final next = s.copyWith(dialogueBoost: true, nightModeDrc: true);
      expect(next.dialogueBoost, isTrue);
      expect(next.nightModeDrc, isTrue);
    });"""
new = """    test('MediaPlayerState.buildCombinedAudioFilter builds dialogue boost chain', () {
      final dialogueOnly = MediaPlayerState.buildCombinedAudioFilter(dialogueBoost: true);
      expect(dialogueOnly, contains('equalizer=f=1500'));
      expect(dialogueOnly, contains('equalizer=f=3000'));

      final combined = MediaPlayerState.buildCombinedAudioFilter(
        dialogueBoost: true,
        eqEnabled: true,
        eqGains: [2.0, 0.0, 0.0, 0.0, -1.0],
      );
      expect(combined, contains('equalizer=f=1500'));
      expect(combined, contains('equalizer=f=60'));
    });

    test('PlayerSettings defaults and copyWith for dialogueBoost', () {
      const s = PlayerSettings();
      expect(s.dialogueBoost, isFalse);

      final next = s.copyWith(dialogueBoost: true);
      expect(next.dialogueBoost, isTrue);
    });"""
if old not in s:
    print("  WARNING: test anchor not found - skipping (tests may fail to compile, check manually)")
else:
    s = s.replace(old, new, 1)
    open(p, "w", encoding="utf-8").write(s)
    print("  OK")
PYEOF

echo "==> Patching Android styles.xml (x3) - status/nav bar stays visible everywhere except the player screen"
for f in android/app/src/main/res/values/styles.xml \
         android/app/src/main/res/values-night/styles.xml \
         android/app/src/main/res/values-v28/styles.xml; do
  if [ ! -f "$f" ]; then
    echo "  WARNING: $f not found, skipping"
    continue
  fi
  python3 - "$f" <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
marker = '<style name="NormalTheme"'
idx = s.find(marker)
if idx == -1:
    sys.exit(f"[{p}] NormalTheme block not found, aborting")
head, tail = s[:idx], s[idx:]
old_line = '        <item name="android:windowFullscreen">true</item>\n'
if old_line not in tail:
    print(f"  {p}: windowFullscreen already absent from NormalTheme, skipping")
else:
    tail = tail.replace(old_line, '', 1)
    open(p, "w", encoding="utf-8").write(head + tail)
    print(f"  {p}: OK (bars now hidden ONLY while NativeBridge.setImmersive(true) is active in the player)")
PYEOF
done

echo ""
echo "===================================================================="
echo " v74 applied. What changed:"
echo "  1. Night Mode (DRC) setting fully removed from Settings + audio chain"
echo "  2. Fixed notification/lock-screen seekbar not following a scrub"
echo "     (stale-position race in MediaPlayerState.seek/seekBy)"
echo "  3. Status bar + nav bar now stay visible on every screen EXCEPT"
echo "     the video player (was forced hidden app-wide via windowFullscreen"
echo "     in the runtime theme, overriding the player-only setImmersive calls)"
echo "  4. Thumbnail grid: concurrent decode slots raised 2 -> 4 for faster"
echo "     population while scrolling a large library"
echo "  5. Seek lag fixed: dragging the progress bar now does a fast"
echo "     keyframe seek instead of mpv's default precise seek (which"
echo "     decoded every frame from the last keyframe to the target)"
echo "  6. Scrub-preview thumbnail lag fixed: removed a blocking disk"
echo "     existsSync() check that ran on every Slider rebuild while"
echo "     dragging (native already guarantees the frames exist)"
echo "===================================================================="
echo ""
echo "Next steps:"
echo "  flutter analyze        # should print: No issues found!"
echo "  flutter test"
echo "  flutter build appbundle --release"
echo "  git add -A && git commit -m 'v74: remove night mode, fix notification seek sync, scope immersive to player, faster thumbnails' && git push"
