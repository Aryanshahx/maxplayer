#!/usr/bin/env bash
# Max Player v76 update script
# Run from the repo root: ~/IdeaProjects/maxplayer
#
# STEP 0 fixes the damage done by a third-party "v75" script that was
# applied and pushed to this repo (commit message: "v75: Persistent
# thumbnails, navigation fix, rounded icon, auto-reload on resume").
# That script deleted the real lib/services/native_bridge.dart (871
# lines -> a 4-method stub) and replaced lib/main.dart with an unrelated,
# hallucinated screen/provider architecture that does not connect to the
# rest of this app. If that commit is not present in your history (you
# already reverted it yourself), step 0 is a safe no-op.
set -euo pipefail

if [ ! -f "pubspec.yaml" ]; then
  echo "ERROR: run this from the maxplayer repo root (pubspec.yaml not found here)."
  exit 1
fi

echo "==> Step 0: checking for the damaging v75 commit"
BAD_COMMIT=$(git log --all --format="%H %s" | grep -E "^[0-9a-f]+ v75: Persistent thumbnails, navigation fix, rounded icon, auto-reload on resume$" | awk '{print $1}' | head -1)
if [ -n "$BAD_COMMIT" ]; then
  if git merge-base --is-ancestor "$BAD_COMMIT" HEAD; then
    # Make sure it isn't already reverted (native_bridge.dart already healthy
    # means some earlier run of this same script already fixed it).
    CURRENT_NB_LINES=$(wc -l < lib/services/native_bridge.dart 2>/dev/null || echo 0)
    if [ "$CURRENT_NB_LINES" -gt 200 ]; then
      echo "   Found $BAD_COMMIT in history, but native_bridge.dart already"
      echo "   looks healthy ($CURRENT_NB_LINES lines) - already reverted, skipping."
    else
      echo "   Found it on your current branch: $BAD_COMMIT"
      echo "   Reverting it (creates a new commit, keeps history intact)..."
      git revert --no-edit "$BAD_COMMIT"
      echo "   Reverted."
    fi
  else
    echo "   Found in history but not on your current branch - nothing to revert here."
  fi
else
  echo "   Not found on this branch - already clean, skipping."
fi

# Sanity check: the real NativeBridge should be large (~800+ lines). If it's
# still tiny, the revert above didn't fully restore it - stop before patching
# on top of a broken tree.
NB_LINES=$(wc -l < lib/services/native_bridge.dart 2>/dev/null || echo 0)
if [ "$NB_LINES" -lt 200 ]; then
  echo "ERROR: lib/services/native_bridge.dart only has $NB_LINES lines - it looks"
  echo "       like the real file is still missing/replaced. Stopping before making"
  echo "       things worse. Check 'git log --oneline -10' and resolve manually."
  exit 1
fi
if [ -f "lib/screens/home_screen.dart" ] || [ -f "lib/providers/video_provider.dart" ]; then
  echo "ERROR: lib/screens/home_screen.dart or lib/providers/video_provider.dart"
  echo "       still exist - these were added by the bad v75 script and don't belong"
  echo "       in this codebase. Remove them (git rm) before re-running this script."
  exit 1
fi
echo "   Tree looks healthy (native_bridge.dart: $NB_LINES lines). Continuing."

echo "==> Patching android/.../MainActivity.kt (nav-bar overflow fix + persistent thumbnails)"
python3 - <<'PYEOF'
import sys
p = "android/app/src/main/kotlin/com/hypertechlabs/maxplayer/MainActivity.kt"
s = open(p, encoding="utf-8").read()

def apply(old, new):
    global s
    if old not in s:
        sys.exit(f"[MainActivity.kt] anchor not found, aborting:\n{old[:150]}")
    s = s.replace(old, new, 1)

# 1) applyImmersiveMode() now owns the edge-to-edge window flags too, and
#    the false-branch no longer sets SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
#    (legacy <API30 path).
apply(
'''    private fun applyImmersiveMode(enabled: Boolean) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            val lp = window.attributes
            lp.layoutInDisplayCutoutMode = if (enabled) {
                WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
            } else {
                WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_DEFAULT
            }
            window.attributes = lp
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.setDecorFitsSystemWindows(!enabled)
            val controller = window.insetsController ?: return
            if (enabled) {
                controller.hide(android.view.WindowInsets.Type.statusBars() or android.view.WindowInsets.Type.navigationBars())
                controller.systemBarsBehavior =
                    android.view.WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            } else {
                controller.show(android.view.WindowInsets.Type.statusBars() or android.view.WindowInsets.Type.navigationBars())
            }
        } else {
            @Suppress("DEPRECATION")
            if (enabled) {
                window.decorView.systemUiVisibility = (
                    android.view.View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                    or android.view.View.SYSTEM_UI_FLAG_FULLSCREEN
                    or android.view.View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                    or android.view.View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                    or android.view.View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                    or android.view.View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                )
            } else {
                window.decorView.systemUiVisibility = (
                    android.view.View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                    or android.view.View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                )
            }
        }
    }''',
'''    private fun applyImmersiveMode(enabled: Boolean) {
        // v76: these window flags used to be set unconditionally in
        // onCreate() for the whole app, before Dart ever called this
        // function - so every non-player screen (home, library, settings)
        // was drawing edge-to-edge with nothing reserving space for the
        // system navigation bar, which is exactly what showed up as "nav
        // bar overflow over app". They now live here, scoped to the same
        // enabled/disabled toggle as the status/nav bar visibility, so the
        // whole edge-to-edge behavior only ever applies to the player.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            val lp = window.attributes
            lp.layoutInDisplayCutoutMode = if (enabled) {
                WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
            } else {
                WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_DEFAULT
            }
            window.attributes = lp
        }
        if (enabled) {
            window.addFlags(
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN
            )
        } else {
            window.clearFlags(
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN
            )
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.setDecorFitsSystemWindows(!enabled)
            val controller = window.insetsController ?: return
            if (enabled) {
                controller.hide(android.view.WindowInsets.Type.statusBars() or android.view.WindowInsets.Type.navigationBars())
                controller.systemBarsBehavior =
                    android.view.WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            } else {
                controller.show(android.view.WindowInsets.Type.statusBars() or android.view.WindowInsets.Type.navigationBars())
            }
        } else {
            @Suppress("DEPRECATION")
            if (enabled) {
                window.decorView.systemUiVisibility = (
                    android.view.View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                    or android.view.View.SYSTEM_UI_FLAG_FULLSCREEN
                    or android.view.View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                    or android.view.View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                    or android.view.View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                    or android.view.View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                )
            } else {
                window.decorView.systemUiVisibility = (
                    android.view.View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                )
            }
        }
    }''')

# 2) onCreate(): stop forcing edge-to-edge globally at cold start.
apply(
'''        CrashCrumbs.mark(this, "activity_create_begin")
        super.onCreate(savedInstanceState)
        // v68/v70: Cutout / punch hole handling - draw under camera cutouts
        // on short edges for true edge-to-edge borderless display (VLC style).
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            window.attributes.layoutInDisplayCutoutMode =
                WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
        }
        window.addFlags(
            WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS or
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN
        )''',
'''        CrashCrumbs.mark(this, "activity_create_begin")
        super.onCreate(savedInstanceState)
        // v68/v70: Cutout / punch hole handling - draw under camera cutouts
        // on short edges for true edge-to-edge borderless display (VLC style).
        // v76: this used to run unconditionally for every screen, which is
        // what caused the system navigation bar to overlap app content
        // outside the player. applyImmersiveMode(false) now sets the
        // correct "bars visible, content NOT edge-to-edge" default at
        // cold start; the player screen flips it on/off itself via the
        // native bridge as before.
        applyImmersiveMode(false)''')

# 3) thumbFileFor(): cacheDir -> filesDir (persistent, OS never auto-wipes it)
apply(
'''    private fun thumbFileFor(path: String): File {
        val thumbsDir = File(cacheDir, "thumbs").apply { mkdirs() }
        return File(thumbsDir, md5(path) + ".jpg")
    }''',
'''    /**
     * v76: moved from cacheDir to filesDir. cacheDir is fair game for the
     * OS to wipe at any time under memory/storage pressure - several OEM
     * skins (Xiaomi/Realme/ColorOS "RAM booster" style optimizers, named
     * explicitly in this app's compatibility target list) do exactly that
     * the moment the app is backgrounded, which is why every grid
     * thumbnail was disappearing after switching to another app and back.
     * filesDir is private, persistent app storage the OS never auto-clears
     * (only "Clear storage" in system settings touches it) - this is the
     * same place VLC-style players keep their generated thumbnails.
     */
    private fun thumbFileFor(path: String): File {
        val thumbsDir = File(filesDir, "thumbs").apply { mkdirs() }
        return File(thumbsDir, md5(path) + ".jpg")
    }''')

# 4) storageReport(): read thumb size from the new persistent location
apply(
'        out["thumbs"] = dirSizeBytes(File(cacheDir, "thumbs"))\n',
'        out["thumbs"] = dirSizeBytes(File(filesDir, "thumbs"))\n')

# 5) clearStorageKind(): kept working (now unused after the cleaner-UI
#    patch below removes its only caller), but fixed for consistency.
apply(
'''            "thumbs" -> {
                val d = File(cacheDir, "thumbs")''',
'''            "thumbs" -> {
                val d = File(filesDir, "thumbs")''')

open(p, "w", encoding="utf-8").write(s)
print("  OK")
PYEOF

echo "==> Patching lib/state/media_player_state.dart (scrub-preview comment tidy)"
python3 - <<'PYEOF'
import sys
p = "lib/state/media_player_state.dart"
s = open(p, encoding="utf-8").read()
old = "  /// _thumbStripDir is non-null every path is already guaranteed to\n"
new = "  /// [_thumbStripDir] is non-null every path is already guaranteed to\n"
if old in s:
    s = s.replace(old, new, 1)
    open(p, "w", encoding="utf-8").write(s)
    print("  OK")
else:
    print("  (already up to date, skipping)")
PYEOF

echo "==> Patching lib/widgets/cleaner_sheet.dart (remove thumbnail/preview delete)"
python3 - <<'PYEOF'
import sys
p = "lib/widgets/cleaner_sheet.dart"
s = open(p, encoding="utf-8").read()

def apply(old, new):
    global s
    if old not in s:
        sys.exit(f"[cleaner_sheet.dart] anchor not found, aborting:\n{old[:150]}")
    s = s.replace(old, new, 1)

apply(
'''  int get _thumbs => (_report['thumbs'] ?? 0) + (_report['strips'] ?? 0);
  int get _temp => _report['temp'] ?? 0;''',
'''  int get _temp => _report['temp'] ?? 0;''')

apply(
'''  int get _cacheTotal => cleanerCacheTotal(
        thumbs: _report['thumbs'] ?? 0,
        strips: _report['strips'] ?? 0,
        temp: _temp,
        deviceCache: _deviceCache,
      );

  int get _grandTotal => _cacheTotal + _models;

  List<CleanerSegment> get _segments => cleanerSegments(
        thumbs: _report['thumbs'] ?? 0,
        strips: _report['strips'] ?? 0,
        temp: _temp,
        models: _models,
        deviceCache: _deviceCache,
      );''',
'''  int get _cacheTotal => cleanerCacheTotal(
        // v76: thumbs/strips excluded - no longer a "clean me" cache kind
        // (see the removed thumbnail row below), so they shouldn't count
        // toward "reclaimable" space the Deep Clean button promises to free.
        thumbs: 0,
        strips: 0,
        temp: _temp,
        deviceCache: _deviceCache,
      );

  int get _grandTotal => _cacheTotal + _models;

  List<CleanerSegment> get _segments => cleanerSegments(
        thumbs: 0,
        strips: 0,
        temp: _temp,
        models: _models,
        deviceCache: _deviceCache,
      );''')

apply(
'''    try {
      freed += await NativeBridge.clearStorage('thumbs');
      freed += await NativeBridge.clearStorage('temp');''',
'''    try {
      freed += await NativeBridge.clearStorage('temp');''')

apply(
'''                  // ---- Per-kind cache rows ------------------------------
                  section('Caches & Leftovers'),
                  cacheRow(
                    kind: 'thumbs',
                    icon: Icons.image_outlined,
                    title: 'App thumbnails & previews',
                    note: 'Rebuild automatically as you browse',
                    bytes: _thumbs,
                    onClear: () =>
                        _clearKind('thumbs', 'App thumbnails & previews'),
                  ),''',
'''                  // ---- Per-kind cache rows ------------------------------
                  section('Caches & Leftovers'),
                  // v76: removed the "App thumbnails & previews" delete
                  // row. Thumbnails now live in persistent storage (not
                  // cache) precisely so they DON'T get wiped - offering a
                  // one-tap delete for them here just undid that and made
                  // thumbnails vanish from the library after every clean.''')

open(p, "w", encoding="utf-8").write(s)
print("  OK")
PYEOF

echo "==> Patching lib/widgets/video_ask_sheet.dart (cache AI answers across sheet reopens)"
python3 - <<'PYEOF'
import sys
p = "lib/widgets/video_ask_sheet.dart"
s = open(p, encoding="utf-8").read()
old = '''class _VideoAskSheetState extends State<VideoAskSheet> {
  final _client = VideoAiClient();
  final _questionCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final List<_Msg> _messages = [];
  bool _asking = false;
  int _askToken = 0;

  bool get _hasTranscript => VideoAiClient.hasUsableTranscript(widget.cues);'''
new = '''class _VideoAskSheetState extends State<VideoAskSheet> {
  final _client = VideoAiClient();
  final _questionCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  late final List<_Msg> _messages;
  bool _asking = false;
  int _askToken = 0;

  /// v76: in-memory cache of every video's Q&A, so closing this sheet
  /// (a dismissible bottom sheet - Flutter tears its whole State down on
  /// close) doesn't throw away what the AI already generated. Cleared
  /// when the app process dies, same lifetime as the rest of the app's
  /// in-memory state.
  static final Map<String, List<_Msg>> _sessionCache = {};

  @override
  void initState() {
    super.initState();
    _messages = _sessionCache.putIfAbsent(widget.title, () => []);
  }

  bool get _hasTranscript => VideoAiClient.hasUsableTranscript(widget.cues);'''
if old not in s:
    sys.exit("[video_ask_sheet.dart] anchor not found, aborting")
s = s.replace(old, new, 1)
open(p, "w", encoding="utf-8").write(s)
print("  OK")
PYEOF

echo ""
echo "===================================================================="
echo " v76 applied. What changed:"
echo "  0. Reverted the damaging third-party v75 commit if present"
echo "  1. Nav bar overflow fixed at the root cause: edge-to-edge window"
echo "     flags now only apply while the player screen is open, not app-wide"
echo "  2. Thumbnails moved cacheDir -> filesDir (persistent, survives"
echo "     switching apps / OS cache trims on Xiaomi/Realme/ColorOS etc.)"
echo "  3. Cleaner no longer offers to delete thumbnails/preview strips"
echo "     (individually or via One-Tap Deep Clean) - they're needed data,"
echo "     not junk, now that they're not sitting in cache"
echo "  4. Ask-AI (in-player) conversation is now cached per video in"
echo "     memory, so closing and reopening the sheet keeps what the AI"
echo "     already generated instead of starting blank"
echo "===================================================================="
echo ""
echo "NOT changed in this script (need your input first):"
echo "  - 'Not loading all videos in home screen': checked the scanner,"
echo "    extension list, and metadata handling - found no bug. Tell me:"
echo "    roughly how many videos are missing, and are they on the SD"
echo "    card, internal storage, or a WhatsApp/Telegram folder?"
echo "  - 'Round corner app logo on open': your launcher icon is already"
echo "    a proper Android adaptive icon (auto-rounded by the OS). If you"
echo "    mean the splash screen shown while the app is cold-starting,"
echo "    there's currently NO logo there at all (blank/white) - send me"
echo "    your logo image and I'll add it with rounded corners next round."
echo "===================================================================="
echo ""
echo "Next steps:"
echo "  flutter analyze        # should print: No issues found!"
echo "  flutter test"
echo "  flutter build appbundle --release"
echo "  git add -A && git commit -m 'v76: revert bad v75, fix nav bar overflow, persist thumbnails, stop cleaner deleting them, cache AI answers' && git push"
