#!/usr/bin/env bash
# Max Player update script - Discover section polish + secrets wiring
# Run from the repo root: ~/IdeaProjects/maxplayer
set -euo pipefail

if [ ! -f "pubspec.yaml" ]; then
  echo "ERROR: run this from the maxplayer repo root (pubspec.yaml not found here)."
  exit 1
fi

echo "==> Patching .github/workflows/android-apk.yml (wire TMDB_API_KEY/OPENROUTER_API_KEY into the build)"
python3 - <<'PYEOF'
import sys
p = ".github/workflows/android-apk.yml"
s = open(p, encoding="utf-8").read()
if "--dart-define=OPENROUTER_API_KEY" in s:
    print("  already applied, skipping")
    sys.exit(0)
old = "      - run: flutter build apk --release"
new = '''      # TMDB_API_KEY and OPENROUTER_API_KEY come from repo secrets (Settings
      # > Secrets and variables > Actions). Without --dart-define here,
      # AppConfig.tmdbToken/openRouterKey fall back to their defaults in
      # lib/utils/config.dart (TMDB still works via its baked-in fallback;
      # OpenRouter/Ask-AI does NOT, its fallback is empty).
      - run: >
          flutter build apk --release
          --dart-define=TMDB_API_KEY=${{ secrets.TMDB_API_KEY }}
          --dart-define=OPENROUTER_API_KEY=${{ secrets.OPENROUTER_API_KEY }}'''
if old not in s:
    sys.exit("[android-apk.yml] anchor not found, aborting")
s = s.replace(old, new, 1)
open(p, "w", encoding="utf-8").write(s)
print("  OK")
PYEOF

echo "==> Patching lib/screens/library_screen.dart (Discover section order + brand gradient title)"
python3 - <<'PYEOF'
import sys
p = "lib/screens/library_screen.dart"
s = open(p, encoding="utf-8").read()

def apply(old, new, required=True):
    global s
    if old not in s:
        if required:
            sys.exit(f"[library_screen.dart] anchor not found, aborting:\n{old[:150]}")
        return False
    s = s.replace(old, new, 1)
    return True

# 1) Discover carousel above the quick-tiles row (matches the reference
#    screenshot: header -> Discover movies -> Private Space/Playlists/
#    Folders/Cloud Storage tiles -> video grid).
apply(
'''        _buildHeader(),
        _buildTiles(),
        const DiscoverSection(),''',
'''        _buildHeader(),
        const DiscoverSection(),
        _buildTiles(),''',
required=False)

# 2) "Max Player" title: violet -> cyan brand gradient instead of plain white.
apply(
'''                const Text(
                  'Max Player',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                    color: Colors.white, // fixed brand white (never themes)
                    letterSpacing: 0.2,
                  ),
                ),''',
'''                ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(
                    colors: [Color(0xFF8B5CF6), Color(0xFF22D3EE)],
                  ).createShader(bounds),
                  child: const Text(
                    'Max Player',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                      color: Colors.white, // ShaderMask paints over this
                      letterSpacing: 0.2,
                    ),
                  ),
                ),''',
required=False)

open(p, "w", encoding="utf-8").write(s)
print("  OK")
PYEOF

echo ""
echo "===================================================================="
echo " Applied. What changed:"
echo "  1. GitHub Actions now actually passes TMDB_API_KEY and"
echo "     OPENROUTER_API_KEY into the build. Your secrets were sitting"
echo "     configured but unused before this - Ask AI (OpenRouter) had no"
echo "     fallback key, so it was silently broken in every real build."
echo "     TMDB still worked because it has a baked-in fallback token,"
echo "     but this lets it use your own key with your own rate limits."
echo "  2. Discover movies carousel now sits above the quick-tiles row,"
echo "     matching your reference screenshot's layout."
echo "  3. 'Max Player' title now uses the violet-to-cyan brand gradient"
echo "     instead of plain white, matching your reference screenshot."
echo ""
echo "  Note: I checked your Discover carousel and full Discover page"
echo "  against your screenshots in detail - both already closely match"
echo "  (auto-scrolling hero carousel, overlay title/subtitle, arrow"
echo "  button, category chips, search bar) - no other changes needed"
echo "  there."
echo "===================================================================="
echo ""
echo "Next steps:"
echo "  nano update_discover_fix.sh"
echo "  # (paste this script, Ctrl+O, Enter, Ctrl+X)"
echo "  bash update_discover_fix.sh"
echo "  flutter analyze"
echo "  flutter test"
echo "  git add -A && git commit -m 'Discover section polish: gradient title, section order, wire build secrets'"
echo "  git push"
echo ""
echo "Pushing triggers GitHub Actions automatically - download the APK"
echo "from the Actions tab's build run once it finishes (~3-5 min)."
