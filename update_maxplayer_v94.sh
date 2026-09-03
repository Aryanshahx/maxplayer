#!/usr/bin/env bash
# =============================================================================
#  update_maxplayer_v94.sh   -   Max Player  v93 -> v94  BASELINE REPAIR
#  Hyper Tech Labs  |  com.hypertechlabs.maxplayer
# =============================================================================
#
#  WHY THIS RELEASE EXISTS
#  -----------------------
#  v93 was committed with the message "Clean compile fix" but it is NOT clean.
#  A fresh clone of main @ e6dc458 produces:
#
#      49 issues found.  (47 errors, 2 warnings)   -- flutter analyze, 3.44.9
#
#  v93 also silently REVERTED v92's "Ask AI in the player 3-dot menu" fix and
#  left two half-applied str_replace patches behind (missing lines + mangled
#  indentation). This is the same mixed-AI-session damage seen in v75 / v88.
#
#  This script does ONE thing: repair the baseline so `flutter analyze` is
#  green. It implements no new features.
#
#  VERIFIED RESULT (Flutter 3.44.9, matching codemagic.yaml's pin)
#  ---------------------------------------------------------------
#  Tested four times, each on a THROWAWAY `git clone` of the real repo at
#  e6dc458, running this script unmodified:
#
#      before : 49 issues found.  (47 errors, 2 warnings)
#      after  : No issues found!  (0 errors, 0 warnings)   exit 0
#      tests  : 00:00 +13: All tests passed!               exit 0
#
#  Extra proof the patches are a true revert and not invented content: after
#  patching, lib/utils/formatters.dart and lib/widgets/player_controls_overlay.dart
#  hash BYTE-FOR-BYTE back to their v92 blobs (8dd6a7ff / a60b33ab).
#
#  Fail-safes, both exercised:
#    * refuses to run on a dirty working tree
#    * validates ALL 18 anchors match exactly once BEFORE writing any file;
#      on mismatch it aborts and leaves the tree untouched (re-running it on an
#      already-patched tree therefore cannot corrupt anything)
#    * refuses to run if native_bridge.dart is under 700 lines (v75 guard)
#    * re-checks brace/paren/bracket balance on every patched file afterwards
#
#  THE 6 ROOT CAUSES (47 errors collapse into these)
#  -------------------------------------------------
#  1. lib/services/tmdb_client.dart:620 - ONE stray extra `}` closed the `try`
#     block of parseTmdbExtras() early. Everything after it fell out of scope,
#     producing 24 cascading errors (undefined `decoded`, `director`, `cast`,
#     `castMembers`; `'catch' can't be used as an identifier`;
#     `expected_executable`). v92 has no such brace - v93 added it.
#     Fixing this ONE character removes 24 of the 47 errors.
#
#  2. lib/utils/formatters.dart:126-148 - tmdbRatingText / formatRuntime /
#     formatVoteCount were DUPLICATED out of tmdb_client.dart. Any file
#     importing both (movie_detail_sheet.dart, widget_test.dart) hit
#     `ambiguous_import`. 12 errors.
#
#  3. lib/widgets/player_controls_overlay.dart - v93 added an "Ask AI" ListTile
#     calling `onAskAi()`, plus a doc comment for the field, but the actual
#     `final VoidCallback onAskAi;` declaration and its `required this.onAskAi,`
#     constructor entry were DROPPED by the patch. 1 error + visible scars
#     (a 6-space `});` and a dangling doc comment).
#
#  4. lib/screens/player_screen.dart - v93 deleted v92's `case 'ask'` +
#     `_topMenuItem('ask', ...)`, orphaning `_openVideoAsk()` (warning), and
#     left a 70-space-mangled `),` where `onAskAi: _openVideoAsk,` was dropped.
#
#  5. lib/screens/player_screen.dart:1749-1893 - `_showMoreActionsSheet()` and
#     its `_actionTile()` helper are dead code (unused_element warning),
#     superseded by v93's own compact `_topMenu` PopupMenuButton.
#
#  6. test/widget_test.dart - v93 shipped an AI-written spec that does not match
#     the real API: `timeAgo(DateTime)` (it takes int ms), a call to
#     `resolutionBadge(w,h)` which has NEVER existed in lib/ (the real API is
#     VideoTrack.qualityLabel), a duplicate Formatters test, an expectation of
#     '1.0 GB' where formatFileSize deliberately renders '1.00 GB', and an
#     assertion that Ask AI is absent from player_screen.dart - contradicting
#     both v92 and the developer's own outstanding request #4. 10 errors.
#     None of these tests could run at all in v93, because the file did not
#     compile - so the whole suite was silently dead.
#
#  7. Follow-on from fix #2: once the duplicate helpers are gone, the
#     `import '../utils/formatters.dart'` in movie_detail_sheet.dart and 40 of
#     the 45 imports in widget_test.dart become unused. These 41 warnings were
#     invisible in v93 (resolution errors suppress the hint) and would have
#     drowned out real problems, so they are cleaned here too.
#
#  DECISION TAKEN (flag this if you disagree)
#  ------------------------------------------
#  Request #4 says Ask AI should NOT sit next to Subtitles/Audio and SHOULD live
#  in the three-dot menu. v93's in-flight code did the opposite. The developer's
#  written request wins: the tile is removed from the tracks sheet and the entry
#  is restored in `_topMenu` - i.e. v92's behaviour, which v93 regressed.
#
#  SCOPE: nothing else is touched. No features from the outstanding list are
#  implemented here beyond the Ask-AI placement needed to resolve errors 3/4.
#
#  USAGE
#  -----
#      ./update_maxplayer_v94.sh                 # uses ~/IdeaProjects/maxplayer
#      ./update_maxplayer_v94.sh /path/to/repo   # explicit path
#
#  Every patch is an exact str_replace that ASSERTS it matched exactly once.
#  If any anchor does not match, the script stops BEFORE writing anything
#  (all files are patched in memory first, then written) - so it can never
#  leave the tree half-edited. Re-running it on an already-patched tree fails
#  loudly instead of corrupting files.
# =============================================================================
set -euo pipefail

REPO="${1:-$HOME/IdeaProjects/maxplayer}"

echo "=============================================================="
echo " Max Player v94 - baseline repair"
echo "=============================================================="
echo "Repo: $REPO"

if [ ! -d "$REPO/.git" ]; then
  echo "ERROR: '$REPO' is not a git repository." >&2
  echo "       Pass the path as the first argument, e.g.:" >&2
  echo "       ./update_maxplayer_v94.sh ~/IdeaProjects/maxplayer" >&2
  exit 1
fi

cd "$REPO"

echo
echo "--- Pre-flight: where are we? ---"
git log --oneline -3
echo

if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "ERROR: working tree is dirty. Commit or stash first so this" >&2
  echo "       patch is the only thing in the next commit." >&2
  git status --short >&2
  exit 1
fi

for f in lib/services/tmdb_client.dart \
         lib/utils/formatters.dart \
         lib/widgets/player_controls_overlay.dart \
         lib/widgets/movie_detail_sheet.dart \
         lib/screens/player_screen.dart \
         test/widget_test.dart \
         pubspec.yaml ; do
  [ -f "$f" ] || { echo "ERROR: expected file missing: $f" >&2; exit 1; }
done

# Guard against the v75-style catastrophe: the real bridge is ~870+ lines.
NB_LINES=$(wc -l < lib/services/native_bridge.dart)
if [ "$NB_LINES" -lt 700 ]; then
  echo "ERROR: lib/services/native_bridge.dart is only $NB_LINES lines." >&2
  echo "       The real bridge is ~877. This looks like the v75-style" >&2
  echo "       fake-architecture replacement. Aborting - do not patch." >&2
  exit 1
fi
echo "native_bridge.dart integrity: $NB_LINES lines (OK)"

echo
echo "--- Applying patches ---"
set +e
python3 - <<'PYEOF'

from dataclasses import dataclass
import os
import sys


@dataclass
class Patch:
    pid: str
    rel: str
    old: str
    new: str
    why: str


PATCHES = [
    Patch(
        pid='tmdb-extras-indent',
        rel='lib/services/tmdb_client.dart',
        old='    final cast = <String>[];\n        final castMembers = <TmdbCastMember>[];\n',
        new='    final cast = <String>[];\n    final castMembers = <TmdbCastMember>[];\n',
        why='parseTmdbExtras: undo the 8-space mis-indent v93 left on `castMembers`.',
    ),
    Patch(
        pid='tmdb-stray-brace',
        rel='lib/services/tmdb_client.dart',
        old='      }\n    }\n    }\n    final genres = <String>[];\n',
        new='      }\n    }\n    final genres = <String>[];\n',
        why='ROOT CAUSE of 24 errors: v93 inserted one extra `}` that closed the `try`\n    block early, so `decoded`/`director`/`cast`/`castMembers` fell out of scope\n    and the `} catch (_)` became a syntax error. v92 had no such brace.',
    ),
    Patch(
        pid='formatters-dupes',
        rel='lib/utils/formatters.dart',
        old='/// "7.834" -> "7.8" (badge text). Pure for tests.\nString tmdbRatingText(double rating) => rating.toStringAsFixed(1);\n\n/// 136 -> "2h 16m", 45 -> "45m", 120 -> "2h", 0 -> \'\'. Pure for tests.\nString formatRuntime(int minutes) {\n  if (minutes <= 0) return \'\';\n  final h = minutes ~/ 60;\n  final m = minutes % 60;\n  if (h == 0) return \'${m}m\';\n  if (m == 0) return \'${h}h\';\n  return \'${h}h ${m}m\';\n}\n\n/// 24513 -> "24,513" (hand-rolled so no intl locale setup is needed). Pure.\nString formatVoteCount(int votes) {\n  final s = \'$votes\';\n  final out = StringBuffer();\n  for (var i = 0; i < s.length; i++) {\n    if (i > 0 && (s.length - i) % 3 == 0) out.write(\',\');\n    out.write(s[i]);\n  }\n  return out.toString();\n}\n',
        new='',
        why='Delete tmdbRatingText/formatRuntime/formatVoteCount DUPLICATED into\n    formatters.dart by v93. They already live in tmdb_client.dart (their\n    canonical home). Two copies + a file importing both = ambiguous_import\n    errors in movie_detail_sheet.dart and widget_test.dart.',
    ),
    Patch(
        pid='overlay-ctor',
        rel='lib/widgets/player_controls_overlay.dart',
        old='    // v78: "Ask AI about this video" moved INTO the tracks sheet too\n    // (was the ⋮ menu) - it belongs next to Subtitles/Audio/A-B loop,\n    // not buried behind "more actions".\n      });\n',
        new='  });\n',
        why="Remove the orphaned v78 comment block and the mis-indented `});` left\n    behind when v93's patch dropped the `required this.onAskAi,` line.",
    ),
    Patch(
        pid='overlay-dangling-doc',
        rel='lib/widgets/player_controls_overlay.dart',
        old='  /// v78: opens the "Ask AI about this video" sheet.\n  \n',
        new='',
        why='Remove the dangling `/// v78: opens the ...` doc comment whose field\n    declaration (`final VoidCallback onAskAi;`) was never written - the\n    direct cause of the `onAskAi` undefined_method error at line 343.',
    ),
    Patch(
        pid='overlay-askai-tile',
        rel='lib/widgets/player_controls_overlay.dart',
        old="              ListTile(\n                leading: Icon(Icons.auto_awesome, color: themeState.accent),\n                title: const Text(\n                  'Ask AI about this video',\n                  style: TextStyle(color: Colors.white),\n                ),\n                subtitle: const Text(\n                  'Answers from the subtitles - AI-generated or the video\\'s own',\n                  style: TextStyle(color: Colors.white54, fontSize: 12),\n                ),\n                onTap: () {\n                  Navigator.of(sheetContext).pop();\n                  onAskAi();\n                },\n              ),\n",
        new='',
        why="Remove 'Ask AI about this video' from the tracks/tune sheet (it sat right\n    next to Subtitles / Audio track / A-B loop / Karaoke). Outstanding\n    request #4 says it belongs in the three-dot menu instead - restored there\n    by the player_screen patch below (this is what v92 did and v93 undid).",
    ),
    Patch(
        pid='player-ctor-indent',
        rel='lib/screens/player_screen.dart',
        old='                                    onToggleKaraoke: _toggleKaraoke,\n                                                                      ),\n',
        new='                                    onToggleKaraoke: _toggleKaraoke,\n                                  ),\n',
        why="Repair the 70-space-mangled `),` closing the PlayerControlsOverlay call -\n    the scar left where v93's patch dropped `onAskAi: _openVideoAsk,`.",
    ),
    Patch(
        pid='player-ask-case',
        rel='lib/screens/player_screen.dart',
        old="          case 'eq':\n            EqualizerSheet.show(context, widget.player);\n            break;\n",
        new="          case 'eq':\n            EqualizerSheet.show(context, widget.player);\n            break;\n          case 'ask':\n            _openVideoAsk();\n            break;\n",
        why="Restore v92's `case 'ask'` handler in the three-dot menu (v93 deleted it,\n    which is why `_openVideoAsk` became an unused_element warning).",
    ),
    Patch(
        pid='player-ask-item',
        rel='lib/screens/player_screen.dart',
        old="        _topMenuItem('eq', Icons.graphic_eq, 'Equalizer & Audio FX'),\n",
        new="        _topMenuItem('eq', Icons.graphic_eq, 'Equalizer & Audio FX'),\n        _topMenuItem('ask', Icons.auto_awesome, 'Ask AI about this video'),\n",
        why="Restore the 'Ask AI about this video' entry in the player's three-dot menu.",
    ),
    Patch(
        pid='player-dead-sheet',
        rel='lib/screens/player_screen.dart',
        old="  void _showMoreActionsSheet() {\n    _onUserInteraction();\n    final accent = themeState.accent;\n\n    showModalBottomSheet<void>(\n      context: context,\n      backgroundColor: const Color(0xFF14141c),\n      shape: const RoundedRectangleBorder(\n        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),\n      ),\n      builder: (sheetContext) => SafeArea(\n        child: SingleChildScrollView(\n          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),\n          child: Column(\n            mainAxisSize: MainAxisSize.min,\n            children: [\n              Container(\n                width: 36,\n                height: 4,\n                decoration: BoxDecoration(\n                  color: Colors.white24,\n                  borderRadius: BorderRadius.circular(2),\n                ),\n              ),\n              const SizedBox(height: 14),\n              Row(\n                children: [\n                  Icon(Icons.more_horiz, color: accent, size: 22),\n                  const SizedBox(width: 8),\n                  const Text(\n                    'More Actions',\n                    style: TextStyle(\n                      color: Colors.white,\n                      fontSize: 17,\n                      fontWeight: FontWeight.bold,\n                    ),\n                  ),\n                ],\n              ),\n              const SizedBox(height: 12),\n              _actionTile(\n                icon: Icons.info_outline,\n                title: 'Video Information',\n                subtitle: 'Codec, resolution, bitrate, audio channels',\n                accent: accent,\n                onTap: () {\n                  Navigator.of(sheetContext).pop();\n                  VideoInfoSheet.show(context, widget.player);\n                },\n              ),\n              _actionTile(\n                icon: Icons.graphic_eq,\n                title: 'Equalizer & Audio FX',\n                subtitle: '5-band equalizer, bass boost, vocal clarity',\n                accent: accent,\n                onTap: () {\n                  Navigator.of(sheetContext).pop();\n                  EqualizerSheet.show(context, widget.player);\n                },\n              ),\n              if (_settings.screenshotButton)\n                _actionTile(\n                  icon: Icons.camera_alt_outlined,\n                  title: 'Take Screenshot',\n                  subtitle: 'Save current video frame to gallery',\n                  accent: accent,\n                  onTap: () {\n                    Navigator.of(sheetContext).pop();\n                    _takeScreenshot();\n                  },\n                ),\n              if (_settings.castButton)\n                _actionTile(\n                  icon: Icons.cast_outlined,\n                  title: 'Cast to Smart TV / DLNA',\n                  subtitle: 'Stream video directly over Wi-Fi',\n                  accent: accent,\n                  onTap: () {\n                    Navigator.of(sheetContext).pop();\n                    _openCast();\n                  },\n                ),\n              _actionTile(\n                icon: Icons.picture_in_picture_alt_outlined,\n                title: 'Picture-in-Picture (PiP)',\n                subtitle: 'Play in floating window while multitasking',\n                accent: accent,\n                onTap: () {\n                  Navigator.of(sheetContext).pop();\n                  NativeBridge.enterPip(playing: widget.player.isPlaying);\n                },\n              ),\n              _actionTile(\n                icon: Icons.bedtime_outlined,\n                title: widget.player.sleepTimerActive\n                    ? 'Sleep Timer (${widget.player.sleepTimerLabel})'\n                    : 'Sleep Timer',\n                subtitle: 'Auto-pause playback after timer ends',\n                accent: accent,\n                onTap: () {\n                  Navigator.of(sheetContext).pop();\n                  _showSleepSheet();\n                },\n              ),\n            ],\n          ),\n        ),\n      ),\n    );\n  }\n\n  Widget _actionTile({\n    required IconData icon,\n    required String title,\n    required String subtitle,\n    required Color accent,\n    required VoidCallback onTap,\n  }) {\n    return Container(\n      margin: const EdgeInsets.only(bottom: 8),\n      decoration: BoxDecoration(\n        color: Colors.white.withValues(alpha: 0.04),\n        borderRadius: BorderRadius.circular(12),\n      ),\n      child: ListTile(\n        dense: true,\n        leading: CircleAvatar(\n          radius: 18,\n          backgroundColor: accent.withValues(alpha: 0.18),\n          child: Icon(icon, color: accent, size: 18),\n        ),\n        title: Text(\n          title,\n          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13.5),\n        ),\n        subtitle: Text(\n          subtitle,\n          style: const TextStyle(color: Colors.white38, fontSize: 11),\n        ),\n        trailing: const Icon(Icons.chevron_right, color: Colors.white24, size: 18),\n        onTap: onTap,\n      ),\n    );\n  }\n\n",
        new='',
        why="Delete `_showMoreActionsSheet()` + its `_actionTile()` helper (145 lines of\n    dead code, unused_element warning). v93's own comment on `_topMenu`\n    says the compact PopupMenuButton IS the new v93 design, so the old heavy\n    bottom sheet is the superseded one. Satisfies request #5 (lighter menu).",
    ),
    Patch(
        pid='test-timeago',
        rel='test/widget_test.dart',
        old="    test('timeAgo buckets', () {\n      final now = DateTime.now();\n      expect(timeAgo(now.subtract(const Duration(minutes: 5))), 'Just now');\n      expect(timeAgo(now.subtract(const Duration(hours: 2))), '2h ago');\n      expect(timeAgo(now.subtract(const Duration(days: 3))), '3d ago');\n    });\n",
        new="    test('timeAgo buckets', () {\n      final nowMs = DateTime.now().millisecondsSinceEpoch;\n      expect(\n          timeAgo(nowMs - const Duration(minutes: 5).inMilliseconds), '5m ago');\n      expect(\n          timeAgo(nowMs - const Duration(hours: 2).inMilliseconds), '2h ago');\n      expect(\n          timeAgo(nowMs - const Duration(days: 3).inMilliseconds), '3d ago');\n    });\n",
        why="`timeAgo` takes an int of ms-since-epoch, not a DateTime (3 errors). The\n    old expectation of 'Just now' for a 5-minute-old stamp was also wrong -\n    timeAgo only returns 'Just now' under 60 seconds.",
    ),
    Patch(
        pid='test-resolution-badge',
        rel='test/widget_test.dart',
        old="    test('maps the SHORTER side to a resolution badge', () {\n      expect(resolutionBadge(1920, 1080), '1080p');\n      expect(resolutionBadge(1280, 720), '720p');\n      expect(resolutionBadge(3840, 2160), '4K');\n    });\n",
        new="    test('maps the SHORTER side to a resolution badge', () {\n      String? badge(int w, int h) => VideoTrack(\n            id: 'x',\n            title: 'x',\n            path: '/sdcard/Movies/x.mp4',\n            width: w,\n            height: h,\n          ).qualityLabel;\n      expect(badge(1920, 1080), '1080p');\n      expect(badge(1280, 720), '720p');\n      expect(badge(3840, 2160), '4K');\n    });\n",
        why='`resolutionBadge(w, h)` has never existed in lib/ (git log -S confirms).\n    The real API is the `qualityLabel` getter on VideoTrack - test that.',
    ),
    Patch(
        pid='test-askai-assert',
        rel='test/widget_test.dart',
        old='      expect(playerScreen.contains("Ask AI about this video"), isFalse);\n',
        new='      // v94: Ask AI lives in the player\'s THREE-DOT menu (request #4),\n      // not next to Subtitles/Audio in the tracks sheet.\n      expect(playerScreen.contains("Ask AI about this video"), isTrue);\n',
        why="v93's spec test asserted Ask AI was absent from player_screen.dart, which\n    contradicted both v92 and outstanding request #4. Flipped to isTrue.",
    ),
    Patch(
        pid='test-formatters-dupe',
        rel='test/widget_test.dart',
        old="    test('Formatters define tmdbRatingText, formatRuntime and formatVoteCount', () {\n      expect(tmdbRatingText(8.365), '8.4');\n      expect(formatRuntime(136), '2h 16m');\n      expect(formatRuntime(45), '45m');\n      expect(formatVoteCount(24513), '24,513');\n    });\n\n",
        new='',
        why="Delete the redundant 'Formatters define tmdbRatingText...' test. It is an\n    exact duplicate of the 'TmdbClient defines...' test immediately above and\n    is what pushed v93 to duplicate the helpers into formatters.dart.",
    ),
    Patch(
        pid='detail-sheet-unused-import',
        rel='lib/widgets/movie_detail_sheet.dart',
        old="import '../utils/formatters.dart';\n",
        new='',
        why="Drop `import '../utils/formatters.dart'`. Once the duplicated TMDB\n    helpers are gone from formatters.dart this sheet uses nothing from it\n    (tmdbRatingText/formatRuntime/formatVoteCount now resolve to the\n    canonical copies in tmdb_client.dart, already imported on line 8).",
    ),
    Patch(
        pid='test-import-spring-clean',
        rel='test/widget_test.dart',
        old="import 'dart:io';\n\nimport 'package:flutter/material.dart';\nimport 'package:flutter/services.dart';\nimport 'package:flutter_test/flutter_test.dart';\n\nimport 'package:maxplayer/app_info.dart';\nimport 'package:maxplayer/cast/cast_support.dart';\nimport 'package:maxplayer/screens/player_screen.dart';\nimport 'package:maxplayer/models/history_entry.dart';\nimport 'package:maxplayer/models/playlist.dart';\nimport 'package:maxplayer/models/saved_server.dart';\nimport 'package:maxplayer/models/video_track.dart';\nimport 'package:maxplayer/services/native_bridge.dart';\nimport 'package:maxplayer/services/notification_service.dart';\nimport 'package:maxplayer/services/recommendations.dart';\nimport 'package:maxplayer/services/resume_sync_service.dart';\nimport 'package:maxplayer/services/tmdb_client.dart';\nimport 'package:maxplayer/widgets/tmdb_image.dart';\nimport 'package:maxplayer/services/movie_ai.dart';\nimport 'package:maxplayer/services/ai_suggest.dart';\nimport 'package:maxplayer/services/subtitle_langs.dart';\nimport 'package:maxplayer/widgets/video_search_delegate.dart';\nimport 'package:maxplayer/widgets/video_thumb.dart';\nimport 'package:maxplayer/state/media_player_state.dart';\nimport 'package:maxplayer/state/video_zoom.dart';\nimport 'package:maxplayer/state/player_settings.dart';\nimport 'package:maxplayer/state/playlist_store.dart';\nimport 'package:maxplayer/utils/movie_match.dart';\nimport 'package:maxplayer/state/private_vault.dart';\nimport 'package:maxplayer/state/theme_state.dart';\nimport 'package:maxplayer/state/video_library_state.dart';\nimport 'package:maxplayer/utils/ai_subtitles.dart';\nimport 'package:maxplayer/utils/cleaner_stats.dart';\nimport 'package:maxplayer/utils/crash_log.dart';\nimport 'package:maxplayer/utils/formatters.dart';\nimport 'package:maxplayer/utils/privacy_policy.dart';\nimport 'package:maxplayer/utils/sha256.dart';\nimport 'package:maxplayer/utils/srt.dart';\nimport 'package:maxplayer/widgets/karaoke_subtitle.dart';\nimport 'package:maxplayer/widgets/about_sheet.dart';\nimport 'package:maxplayer/widgets/track_selection_sheet.dart';\nimport 'package:maxplayer/widgets/gesture_illustrations.dart';\nimport 'package:maxplayer/widgets/user_manual_sheet.dart';\nimport 'package:maxplayer/widgets/voice_search_sheet.dart';\nimport 'package:maxplayer/services/gdrive_service.dart';\nimport 'package:maxplayer/widgets/network_storage_sheet.dart';\n",
        new="import 'dart:io';\n\nimport 'package:flutter_test/flutter_test.dart';\n\n// v94: v93 imported 45 app libraries but this suite only ever touches five\n// of them - the other 40 were unused_import warnings that drowned out real\n// problems. (They were invisible in v93 only because the file's resolution\n// errors suppressed the hint.)\nimport 'package:maxplayer/models/video_track.dart';\nimport 'package:maxplayer/services/tmdb_client.dart';\nimport 'package:maxplayer/utils/formatters.dart';\n",
        why='Reduce the test file to the imports it actually uses: dart:io (File),\n    flutter_test, VideoTrack, tmdb_client and formatters. Removes 40\n    unused_import warnings.',
    ),
    Patch(
        pid='test-gb-expectation',
        rel='test/widget_test.dart',
        old="      expect(formatFileSize(1024 * 1024 * 1024), '1.0 GB');\n",
        new="      expect(formatFileSize(1024 * 1024 * 1024), '1.00 GB');\n",
        why="formatFileSize renders GB with toStringAsFixed(2) -> '1.00 GB' (KB/MB use\n    one decimal, GB uses two - deliberate, it is the shipping behaviour).\n    v93's test guessed '1.0 GB'. This failure was invisible in v93 because\n    the file did not compile, so no test in it could run at all. The test is\n    corrected; lib/ behaviour is NOT changed.",
    ),
    Patch(
        pid='pubspec-bump',
        rel='pubspec.yaml',
        old='version: 1.0.0+93\n',
        new='version: 1.0.0+94\n',
        why='Version bump 93 -> 94.',
    ),
]


def main():
    # Stage 1: read everything, verify every anchor matches EXACTLY once.
    # Nothing is written until every single patch has been validated, so a
    # mismatch anywhere aborts cleanly with the tree untouched.
    sources = {}
    for p in PATCHES:
        if p.rel not in sources:
            if not os.path.isfile(p.rel):
                sys.exit(f"ERROR: missing file {p.rel}")
            with open(p.rel, encoding="utf-8") as f:
                sources[p.rel] = f.read()

    failures = []
    for p in PATCHES:
        n = sources[p.rel].count(p.old)
        if n != 1:
            failures.append((p, n))
    if failures:
        print()
        print("ABORTED - no files were modified.")
        for p, n in failures:
            print(f"  [{p.pid}] anchor matched {n}x (need exactly 1) in {p.rel}")
            print("  reason: " + p.why.splitlines()[0])
            print("  --- anchor (first 300 chars) ---")
            print("  " + p.old[:300].replace("\n", "\n  "))
            print("  --------------------------------")
        print()
        print("The tree has probably moved on since v93. Re-clone and re-check")
        print("the anchors against the CURRENT file content before retrying.")
        sys.exit(1)

    # Stage 2: apply in memory.
    for p in PATCHES:
        sources[p.rel] = sources[p.rel].replace(p.old, p.new, 1)

    # Stage 3: write.
    for rel, text in sources.items():
        with open(rel, "w", encoding="utf-8") as f:
            f.write(text)

    print()
    for p in PATCHES:
        delta = len(p.new) - len(p.old)
        print(f"  applied  {p.pid:24s} {p.rel}  ({delta:+d} bytes)")
        for i, line in enumerate(p.why.splitlines()):
            print(("           # " if i == 0 else "           # ") + line.strip())
    print()
    print(f"{len(PATCHES)} patches applied to {len(sources)} files.")

if __name__ == "__main__":
    main()
PYEOF

PATCH_RC=$?
set -e
if [ "$PATCH_RC" -ne 0 ]; then
  echo "ERROR: patching failed (see above). The tree was NOT modified." >&2
  exit 1
fi

echo
echo "--- Verifying: brace / paren / bracket balance on every patched .dart file ---"
set +e
python3 - lib/screens/player_screen.dart lib/services/tmdb_client.dart lib/utils/formatters.dart lib/widgets/movie_detail_sheet.dart lib/widgets/player_controls_overlay.dart test/widget_test.dart <<'PYEOF'
import sys

def balance(path):
    src = open(path, encoding="utf-8").read()
    depth_c = depth_p = depth_b = 0
    i, n = 0, len(src)
    in_s = in_d = in_line = in_block = False
    while i < n:
        c = src[i]
        nxt = src[i+1] if i + 1 < n else ""
        if in_line:
            if c == "\n":
                in_line = False
        elif in_block:
            if c == "*" and nxt == "/":
                in_block = False; i += 1
        elif in_s:
            if c == "\\": i += 1
            elif c == "'": in_s = False
        elif in_d:
            if c == "\\": i += 1
            elif c == '"': in_d = False
        elif c == "/" and nxt == "/":
            in_line = True; i += 1
        elif c == "/" and nxt == "*":
            in_block = True; i += 1
        elif c == "'":
            in_s = True
        elif c == '"':
            in_d = True
        elif c == "{": depth_c += 1
        elif c == "}": depth_c -= 1
        elif c == "(": depth_p += 1
        elif c == ")": depth_p -= 1
        elif c == "[": depth_b += 1
        elif c == "]": depth_b -= 1
        i += 1
    return depth_c, depth_p, depth_b

bad = False
for f in sys.argv[1:]:
    c, p, b = balance(f)
    ok = (c == 0 and p == 0 and b == 0)
    bad = bad or (not ok)
    print(("  OK   " if ok else "  FAIL ") + f"{f}  braces={c} parens={p} brackets={b}")
sys.exit(1 if bad else 0)
PYEOF

if [ $? -ne 0 ]; then
  echo "ERROR: brace/paren balance check failed. Restoring..." >&2
  git checkout -- .
  exit 1
fi

echo
echo "--- Diff summary ---"
git --no-pager diff --stat

echo
echo "=============================================================="
echo " PATCHED. Now verify on this machine:"
echo "=============================================================="
cat <<'TIPS'

  flutter analyze        # must report: No issues found!
  flutter test           # must pass

  Then commit ONLY this change:

    git add -A
    git commit -m "v94: repair broken v93 baseline (1.0.0+94)" -m "47 analyze errors -> 0. Removed the stray brace that closed parseTmdbExtras' try block early; deleted the TMDB formatters duplicated out of tmdb_client.dart; removed the orphaned Ask-AI tile whose onAskAi field v93 never declared; restored Ask AI to the player 3-dot menu (v92 behaviour that v93 reverted); deleted dead _showMoreActionsSheet; fixed the test suite to match the real API."
    git push origin main

  Full builds still go through Codemagic (Build APK / Build AAB) - the Pi
  cannot run `flutter build`.
TIPS
