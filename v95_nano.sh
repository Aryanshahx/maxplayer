#!/usr/bin/env bash
# =============================================================================
#  update_maxplayer_v95.sh   -   Max Player  v94 -> v95
#  Hyper Tech Labs  |  com.hypertechlabs.maxplayer
# =============================================================================
#
#  BASELINE: e4f5322 "v94: repair broken v93 baseline (1.0.0+94)".
#  v94 already fixed the 47 compile errors, so this script contains ONLY the
#  newly requested changes: 24 exact str_replace patches plus ONE new service
#  file, over 8 files in total. It implements nothing else.
#
#  WHAT CHANGED, AND WHY
#  ---------------------
#  1. "In video player remove ask ai about this video from three dots"
#     v94 restored that menu entry (it was v92's fix, reverted by v93). You have
#     now asked for it gone, so B1-B4 remove the import, the `_openVideoAsk()`
#     handler, the `case 'ask':` branch and the menu item, and B5 flips the test
#     assertion back to isFalse. lib/widgets/video_ask_sheet.dart is left on
#     disk, unwired, so the feature can be re-added later without a rewrite.
#
#  2. "season and episode buttons are getting invisible in white theme"
#     Root cause: the season ChoiceChip paints its label WHITE on
#     `selectedColor: themeState.accent` - and the app's DEFAULT accent is white
#     (theme_state.dart:23). White on white. The Discover filter chips already
#     handle this correctly (discover_screen.dart:646); this one chip was missed.
#     Now uses the app's own `themeState.onAccent` contrast helper.
#
#  3. "can't showing each season overall rating" - TWO root causes:
#       (a) parseTmdbSeasons() never passed `rating:` at all, so TmdbSeason.rating
#           was permanently 0.0 and the chip's `s.rating > 0` guard never fired.
#           Now parses vote_average from the /tv/{id} seasons array.
#       (b) the /tv/{id}/season/{n} detail call ALREADY returned that season's
#           rating and synopsis, and _SeasonsBlock fetched it then threw both
#           away. Now rendered in a card above the episode list.
#
#  4. "show contents details above the storyline" + "show all user reviews at
#     the end of the details". New order in the detail sheet:
#       screenshots -> contents/production details -> storyline -> cast ->
#       seasons & episodes -> where to watch -> user reviews (LAST)
#
#  5. "show all user reviews". parseTmdbReviews was hardcoded to count:2 and
#     maxChars:420 and the call site never overrode it - two reviews, each
#     chopped at 420 characters. Now count:20 (everything TMDB's
#     append_to_response returns) and maxChars:4000.
#     NOTE: TMDB paginates reviews 20/page. Truly ALL of them needs a paging
#     fetch of /{movie|tv}/{id}/reviews?page=N - say the word and I will add it.
#
#  6. "file manager is not showing whatsapp media" + "filters are not working
#     properly" - four separate real bugs:
#       (a) NO PERMISSION. The File Manager never called ensureStorageAccess()
#           (only library_screen and private_screen did). On Android 11+
#           Directory.list() then throws, the old catch swallowed it and the
#           list rendered EMPTY with no explanation. Now requested up front,
#           with a "Grant access" button in the empty state.
#       (b) ONE HARDCODED WHATSAPP PATH. WhatsApp moved under Android/media/<pkg>
#           on Android 11+, WhatsApp Business uses com.whatsapp.w4b, and older
#           installs use /sdcard/WhatsApp. Now probes 6 candidates in order.
#       (c) SILENT FAILURE. "folder missing" and "access denied" both rendered as
#           a bare "No files found". Now they say what actually happened.
#       (d) THE FILTER BUG. The type filter was guarded by `&& e is File`, so
#           EVERY folder stayed visible whichever chip you tapped - the list
#           looked identical before and after. Folders are filtered now too.
#           Also .srt/.vtt counted as BOTH Documents and Subtitles; they are now
#           Subtitles only.
#
#  7. "add a small text below Max Player text in home screen". Two-line app-bar
#     title: the gradient brand line plus "Proudly Developed in India" with the
#     flag written as Dart \u{...} escapes so no editor can mangle it.
#
#  8. "ai tool is meaning less" (the File Manager's AI) - B20..B23 + new file
#     lib/services/media_ai.dart. The old dialog counted files and then printed
#     ONE hardcoded sentence, identical for every folder on the device:
#       "AI Recommendation: All media formats here are fully accelerated by
#        libmpv for 100% smooth playback."
#     It was not looking at anything, so it could not say anything. Replaced with:
#       * REAL on-device findings, always shown: orphaned subtitle files (a .srt
#         with no matching video, so it can never auto-load), probable duplicates
#         (byte-identical size + container), files with unrecognized extensions,
#         and the largest file with its percentage of the folder.
#       * REAL AI commentary on top, via the app's EXISTING OpenRouter client in
#         lib/services/movie_ai.dart - same key, same 9-model free-tier fallback
#         chain already used by the movie Q&A and the AI Suggestor. No new
#         dependency, no new secret, no new key handling.
#       * When there is no key or no network it says so plainly and still shows
#         the real findings. It never invents a sentence again.
#       * A privacy line in the dialog: only file names, sizes and counts leave
#         the device - never file contents.
#     _mediaKind() classifies with the SAME rules the filter chips use, so the
#     dialog counts and the Videos/Music/Images/Subtitles counts cannot disagree.
#     Three new unit tests cover the detection logic and pin the old hardcoded
#     string as forbidden.
#
#     ACTION FOR YOU: the OpenRouter key is a compile-time --dart-define with NO
#     default (unlike TMDB_API_KEY, which has a hardcoded fallback). codemagic.yaml
#     already passes --dart-define=OPENROUTER_API_KEY=$OPENROUTER_API_KEY, but if
#     that variable is not set in Codemagic -> your project -> Environment
#     variables, it compiles to an EMPTY string and EVERY AI feature in the app
#     (movie Q&A, AI Suggestor, and now this) silently does nothing. Worth
#     checking - it may also explain the older "poor AI answers" complaint.
#
#  NOT INCLUDED - needs your input (see the chat reply)
#  ----------------------------------------------------
#   * The player crash - cannot be diagnosed without a logcat/tombstone, and
#     guessing is how this repo keeps getting damaged.
#   * Google Sign-In for Drive - plan delivered separately; needs credentials.
#
#  SAFETY
#  ------
#   * refuses to run on a dirty working tree
#   * refuses unless pubspec.yaml says 1.0.0+94 (the expected baseline)
#   * validates ALL 24 anchors match exactly once BEFORE writing any file;
#     on mismatch it aborts and leaves the tree untouched
#   * refuses if native_bridge.dart is under 700 lines (v75 guard)
#   * re-checks brace/paren/bracket balance on every patched .dart file
#   * re-running on an already-patched tree aborts and writes nothing
#
#  USAGE
#  -----
#      ./update_maxplayer_v95.sh                 # uses ~/IdeaProjects/maxplayer
#      ./update_maxplayer_v95.sh /path/to/repo
# =============================================================================
set -euo pipefail

REPO="${1:-$HOME/IdeaProjects/maxplayer}"

echo "=============================================================="
echo " Max Player v95  (v94 -> v95)"
echo "=============================================================="
echo "Repo: $REPO"
[ -d "$REPO/.git" ] || { echo "ERROR: '$REPO' is not a git repository." >&2; exit 1; }
cd "$REPO"
echo
git log --oneline -3
echo

git diff --quiet && git diff --cached --quiet || {
  echo "ERROR: working tree is dirty. Commit or stash first so this patch is" >&2
  echo "       the only thing in the next commit." >&2
  git status --short >&2; exit 1; }

for f in lib/services/tmdb_client.dart lib/widgets/movie_detail_sheet.dart \
         lib/screens/player_screen.dart lib/screens/file_manager_screen.dart \
         lib/screens/library_screen.dart test/widget_test.dart pubspec.yaml ; do
  [ -f "$f" ] || { echo "ERROR: expected file missing: $f" >&2; exit 1; }
done

NB=$(wc -l < lib/services/native_bridge.dart)
[ "$NB" -ge 700 ] || { echo "ERROR: native_bridge.dart is only $NB lines (real bridge is ~877)." >&2
                       echo "       Looks like v75-style damage - aborting." >&2; exit 1; }
echo "native_bridge.dart integrity: $NB lines (OK)"

grep -q "^version: 1.0.0+94" pubspec.yaml || {
  echo "ERROR: pubspec.yaml is not at 1.0.0+94 - this script expects the v94" >&2
  echo "       baseline (e4f5322). Check where you are before patching." >&2; exit 1; }
echo "baseline: v94 (OK)"

echo
echo "--- Applying 24 patches + 1 new file ---"
set +e
python3 - <<'PYEOF'

from dataclasses import dataclass
import os
import sys


@dataclass
class Patch:
    pid: str
    stage: str
    rel: str
    old: str
    new: str
    why: str


PATCHES = [
    Patch(
        pid='B1-askai-import',
        stage='B',
        rel='lib/screens/player_screen.dart',
        old="import '../widgets/video_ask_sheet.dart';\n",
        new='',
        why="REQUEST: 'remove ask ai about this video from three dots'. v93 already\n    took it out of the menu but left the handler orphaned; remove the now\n    unused import too.",
    ),
    Patch(
        pid='B2-askai-handler',
        stage='B',
        rel='lib/screens/player_screen.dart',
        old='  /// v65 A2: opens the "Ask about this video" sheet, scoped to the\n  /// current video\'s own transcript/subtitles (not TMDB metadata).\n  Future<void> _openVideoAsk() async {\n    final track = widget.player.currentTrack;\n    if (track == null) return;\n    final cues = widget.player.transcriptCues;\n    await VideoAskSheet.show(\n      context,\n      title: track.title,\n      cues: cues ?? const [],\n      onSeek: (at) => widget.player.seek(at),\n    );\n  }\n\n',
        new='',
        why='Delete the orphaned `_openVideoAsk()` handler (it was an unused_element\n    warning) so nothing can re-surface Ask AI in the player. The sheet\n    widget itself, lib/widgets/video_ask_sheet.dart, is left on disk in\n    case you want the feature back later - it is simply no longer wired.',
    ),
    Patch(
        pid='B3-askai-case',
        stage='B',
        rel='lib/screens/player_screen.dart',
        old="          case 'ask':\n            _openVideoAsk();\n            break;\n",
        new='',
        why="REQUEST: 'remove ask ai about this video from three dots'. v94 put\n    this handler back into the menu; removing it again.",
    ),
    Patch(
        pid='B4-askai-menuitem',
        stage='B',
        rel='lib/screens/player_screen.dart',
        old="        _topMenuItem('ask', Icons.auto_awesome, 'Ask AI about this video'),\n",
        new='',
        why='Remove the matching menu entry.',
    ),
    Patch(
        pid='B5-test-ask-assert',
        stage='B',
        rel='test/widget_test.dart',
        old='      // v94: Ask AI lives in the player\'s THREE-DOT menu (request #4),\n      // not next to Subtitles/Audio in the tracks sheet.\n      expect(playerScreen.contains("Ask AI about this video"), isTrue);\n',
        new='      // v95: Ask AI is REMOVED from the player entirely (developer\n      // request: "remove ask ai about this video from three dots").\n      // lib/widgets/video_ask_sheet.dart stays on disk, unwired.\n      expect(playerScreen.contains("Ask AI about this video"), isFalse);\n',
        why='v94 flipped this assertion to isTrue when it restored the menu entry.\n    Flipping it back so the suite documents the new intent.',
    ),
    Patch(
        pid='B6-season-chip-contrast',
        stage='B',
        rel='lib/widgets/movie_detail_sheet.dart',
        old='                  labelStyle: TextStyle(\n                    color: isSelected ? Colors.white : Colors.white70,\n                    fontSize: 12,\n                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,\n                  ),\n',
        new="                  labelStyle: TextStyle(\n                    // v95 FIX: the app's DEFAULT accent is white\n                    // (theme_state.dart:23), so `selectedColor: accent`\n                    // + a hardcoded white label = white-on-white, i.e.\n                    // invisible season buttons. Use the app's own\n                    // contrast helper, exactly like the Discover filter\n                    // chips already do (discover_screen.dart:646).\n                    color: isSelected\n                        ? themeState.onAccent\n                        : Colors.white70,\n                    fontSize: 12,\n                    fontWeight:\n                        isSelected ? FontWeight.bold : FontWeight.normal,\n                  ),\n",
        why="REQUEST: 'season and episode buttons are getting invisible in white\n    theme'. Root cause: ChoiceChip paints the label white on an\n    accent-coloured background, and the default accent IS white.",
    ),
    Patch(
        pid='B9-season-rating-parse',
        stage='B',
        rel='lib/services/tmdb_client.dart',
        old="    for (final e in list) {\n      if (e is! Map) continue;\n      final n = e['season_number'] is num ? (e['season_number'] as num).toInt() : 0;\n      final name = '${e['name'] ?? ''}'.trim();\n      final eps = e['episode_count'] is num ? (e['episode_count'] as num).toInt() : 0;\n      final air = '${e['air_date'] ?? ''}';\n      out.add(TmdbSeason(\n        number: n,\n        name: name.isEmpty ? (n == 0 ? 'Specials' : 'Season $n') : name,\n        episodes: eps,\n        year: air.length >= 4 ? int.tryParse(air.substring(0, 4)) : null,\n      ));\n    }\n",
        new="    for (final e in list) {\n      if (e is! Map) continue;\n      final n = e['season_number'] is num ? (e['season_number'] as num).toInt() : 0;\n      final name = '${e['name'] ?? ''}'.trim();\n      final eps = e['episode_count'] is num ? (e['episode_count'] as num).toInt() : 0;\n      final air = '${e['air_date'] ?? ''}';\n      // v95 FIX: `TmdbSeason.rating` was NEVER populated - the field\n      // existed and defaulted to 0.0, so the chip's `s.rating > 0` guard\n      // was always false and the star never rendered. TMDB does return\n      // vote_average per season on /tv/{id}.\n      final vote = e['vote_average'] is num\n          ? (e['vote_average'] as num).toDouble()\n          : 0.0;\n      out.add(TmdbSeason(\n        number: n,\n        name: name.isEmpty ? (n == 0 ? 'Specials' : 'Season $n') : name,\n        episodes: eps,\n        year: air.length >= 4 ? int.tryParse(air.substring(0, 4)) : null,\n        rating: vote,\n      ));\n    }\n",
        why="REQUEST: 'can't showing each season overall rating'. Root cause found:\n    parseTmdbSeasons never passed `rating:`, so it was always 0.0.",
    ),
    Patch(
        pid='B7-season-detail-header',
        stage='B',
        rel='lib/widgets/movie_detail_sheet.dart',
        old='                  onSelected: (_) => _loadSeasonDetail(s.number),\n                );\n              },\n            ),\n          ),\n          const SizedBox(height: 10),\n          if (_loadingSeason)\n',
        new="                );\n              },\n            ),\n          ),\n          const SizedBox(height: 10),\n          // v95: the selected season's OWN rating + synopsis. TMDB's\n          // /tv/{id} payload often omits vote_average per season, but the\n          // /tv/{id}/season/{n} detail call always carries it - and that\n          // call was already being made and thrown away.\n          if (!_loadingSeason && _seasonDetail != null)\n            Container(\n              width: double.infinity,\n              margin: const EdgeInsets.only(bottom: 10),\n              padding: const EdgeInsets.all(11),\n              decoration: BoxDecoration(\n                color: Colors.white.withValues(alpha: 0.05),\n                borderRadius: BorderRadius.circular(11),\n                border: Border.all(color: Colors.white10),\n              ),\n              child: Column(\n                crossAxisAlignment: CrossAxisAlignment.start,\n                children: [\n                  Row(\n                    children: [\n                      Expanded(\n                        child: Text(\n                          _seasonDetail!.name.isNotEmpty\n                              ? _seasonDetail!.name\n                              : 'Season $_selectedSeason',\n                          style: const TextStyle(\n                            color: Colors.white,\n                            fontSize: 13,\n                            fontWeight: FontWeight.w700,\n                          ),\n                        ),\n                      ),\n                      if (_seasonDetail!.rating > 0)\n                        Text(\n                          '⭐ ${_seasonDetail!.rating.toStringAsFixed(1)} / 10',\n                          style: TextStyle(\n                            color: themeState.onAccent == Colors.white\n                                ? themeState.accent\n                                : Colors.white,\n                            fontSize: 12,\n                            fontWeight: FontWeight.bold,\n                          ),\n                        ),\n                    ],\n                  ),\n                  if (_seasonDetail!.overview.isNotEmpty) ...[\n                    const SizedBox(height: 5),\n                    Text(\n                      _seasonDetail!.overview,\n                      maxLines: 3,\n                      overflow: TextOverflow.ellipsis,\n                      style: const TextStyle(\n                        color: Colors.white60,\n                        fontSize: 11.5,\n                        height: 1.4,\n                      ),\n                    ),\n                  ],\n                ],\n              ),\n            ),\n          if (_loadingSeason)\n",
        why="Second half of the season-rating fix: surface the detail call's rating\n    and synopsis, which were fetched but never displayed.",
    ),
    Patch(
        pid='B8-detail-order',
        stage='B',
        rel='lib/widgets/movie_detail_sheet.dart',
        old='                  // Screenshots / Scene Stills\n                  if (full.screenshots.isNotEmpty)\n                    _ScreenshotsRow(paths: full.screenshots),\n\n                  // Rich Storyline & Overview\n                  _DetailedStoryBlock(movie: movie, extras: full.extras),\n\n                  // Top Cast Slider with Profile Images\n                  if (full.extras.castMembers.isNotEmpty)\n                    _TopCastSlider(cast: full.extras.castMembers),\n\n                  // Web Series Seasons & Episodes breakdown\n                  if (isTv && full.seasons.isNotEmpty)\n                    _SeasonsBlock(tvId: movie.id, seasons: full.seasons),\n\n                  // Where to Watch\n                  if (!full.watch.isEmpty)\n                    _WatchBlock(info: full.watch),\n\n                  // User Reviews\n                  if (full.reviews.isNotEmpty)\n                    _ReviewsBlock(reviews: full.reviews),\n\n                  // Production & Technical metadata\n                  _AllDataBlock(extras: full.extras, movieId: movie.id),\n',
        new='                  // Screenshots / Scene Stills\n                  if (full.screenshots.isNotEmpty)\n                    _ScreenshotsRow(paths: full.screenshots),\n\n                  // v95: "show contents details ABOVE the storyline" -\n                  // this production/technical block used to sit dead last.\n                  _AllDataBlock(extras: full.extras, movieId: movie.id),\n\n                  // Rich Storyline & Overview\n                  _DetailedStoryBlock(movie: movie, extras: full.extras),\n\n                  // Top Cast Slider with Profile Images\n                  if (full.extras.castMembers.isNotEmpty)\n                    _TopCastSlider(cast: full.extras.castMembers),\n\n                  // Web Series Seasons & Episodes breakdown\n                  if (isTv && full.seasons.isNotEmpty)\n                    _SeasonsBlock(tvId: movie.id, seasons: full.seasons),\n\n                  // Where to Watch\n                  if (!full.watch.isEmpty)\n                    _WatchBlock(info: full.watch),\n\n                  // v95: "show ALL user reviews at the END of the details"\n                  if (full.reviews.isNotEmpty)\n                    _ReviewsBlock(reviews: full.reviews),\n',
        why="REQUEST: 'show all user reviews at the end of the details and show\n    contents details above the storyline'. New order: screenshots ->\n    contents/production details -> storyline -> cast -> seasons ->\n    where-to-watch -> reviews (last).",
    ),
    Patch(
        pid='B10-reviews-count',
        stage='B',
        rel='lib/services/tmdb_client.dart',
        old='      reviews: parseTmdbReviews(body),\n',
        new='      // v95: "show ALL user reviews" - this was hardcoded to TWO reviews\n      // truncated at 420 characters. TMDB\'s append_to_response returns the\n      // first page (up to 20); take all of it and stop chopping the text.\n      reviews: parseTmdbReviews(body, count: 20, maxChars: 4000),\n',
        why="REQUEST: 'show all user reviews'. Root cause: parseTmdbReviews defaults\n    to count:2, maxChars:420 and the call site never overrode them.",
    ),
    Patch(
        pid='B7a-fm-import',
        stage='B',
        rel='lib/screens/file_manager_screen.dart',
        old="import '../utils/formatters.dart';\nimport '../widgets/playlists_sheet.dart';\n",
        new="import '../utils/formatters.dart';\nimport '../utils/storage_permission.dart';\nimport '../widgets/playlists_sheet.dart';\n",
        why="The File Manager needs the app's one storage-permission helper.",
    ),
    Patch(
        pid='B7b-fm-state',
        stage='B',
        rel='lib/screens/file_manager_screen.dart',
        old="  String _typeFilter = 'all'; // 'all', 'video', 'audio', 'image', 'subs', 'doc'\n  bool _isGridView = false;\n",
        new='  String _typeFilter = \'all\'; // \'all\', \'video\', \'audio\', \'image\', \'subs\', \'doc\'\n  bool _isGridView = false;\n\n  /// v95: the File Manager never asked for storage access. On Android 11+\n  /// Directory.list() then throws, the old catch swallowed it and the list\n  /// rendered EMPTY with no explanation - which is exactly why WhatsApp\n  /// media "was not showing".\n  bool _permissionDenied = false;\n  String? _errorMsg;\n',
        why='State for the permission + error surfacing below.',
    ),
    Patch(
        pid='B7c-fm-whatsapp',
        stage='B',
        rel='lib/screens/file_manager_screen.dart',
        old="  static const List<Map<String, String>> _shortcuts = [\n    {'name': 'Internal', 'path': '/storage/emulated/0', 'icon': 'storage'},\n    {'name': 'Camera', 'path': '/storage/emulated/0/DCIM/Camera', 'icon': 'camera'},\n    {'name': 'Movies', 'path': '/storage/emulated/0/Movies', 'icon': 'movie'},\n    {'name': 'Download', 'path': '/storage/emulated/0/Download', 'icon': 'download'},\n    {\n      'name': 'WhatsApp',\n      'path': '/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Video',\n      'icon': 'chat',\n    },\n  ];\n",
        new="  /// v95 FIX: WhatsApp media was not showing. Two reasons: (1) no storage\n  /// permission was ever requested, and (2) the shortcut hardcoded ONE\n  /// path. WhatsApp moved under Android/media/<pkg> on Android 11+,\n  /// WhatsApp Business uses com.whatsapp.w4b, and older installs still use\n  /// /sdcard/WhatsApp. Probe them in order and use the first that exists.\n  static const List<String> _whatsAppCandidates = [\n    '/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Video',\n    '/storage/emulated/0/Android/media/com.whatsapp.w4b/WhatsApp/Media/WhatsApp Video',\n    '/storage/emulated/0/WhatsApp/Media/WhatsApp Video',\n    '/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Media',\n    '/storage/emulated/0/Android/media/com.whatsapp.w4b/WhatsApp/Media',\n    '/storage/emulated/0/WhatsApp/Media',\n  ];\n\n  static String _resolveWhatsApp() {\n    for (final c in _whatsAppCandidates) {\n      try {\n        if (Directory(c).existsSync()) return c;\n      } catch (_) {}\n    }\n    return _whatsAppCandidates.first;\n  }\n\n  static List<Map<String, String>> get _shortcuts => [\n        {'name': 'Internal', 'path': '/storage/emulated/0', 'icon': 'storage'},\n        {\n          'name': 'Camera',\n          'path': '/storage/emulated/0/DCIM/Camera',\n          'icon': 'camera'\n        },\n        {'name': 'Movies', 'path': '/storage/emulated/0/Movies', 'icon': 'movie'},\n        {\n          'name': 'Download',\n          'path': '/storage/emulated/0/Download',\n          'icon': 'download'\n        },\n        {'name': 'WhatsApp', 'path': _resolveWhatsApp(), 'icon': 'chat'},\n      ];\n",
        why="REQUEST: 'file manager is not showing whatsapp media'.",
    ),
    Patch(
        pid='B7d-fm-bootstrap',
        stage='B',
        rel='lib/screens/file_manager_screen.dart',
        old='  @override\n  void initState() {\n    super.initState();\n    _loadDirectory(_currentPath);\n  }\n',
        new='  @override\n  void initState() {\n    super.initState();\n    _bootstrap();\n  }\n\n  /// v95: ask for "All files access" ONCE up front, then list. Without\n  /// this the shortcut tiles (WhatsApp especially) silently showed nothing\n  /// on Android 11+. Re-used by the in-list "Grant access" button.\n  Future<void> _bootstrap() async {\n    final granted = await ensureStorageAccess();\n    if (!mounted) return;\n    setState(() => _permissionDenied = !granted);\n    if (mounted) _loadDirectory(_currentPath);\n  }\n',
        why='Actually request the permission the manifest already declares.',
    ),
    Patch(
        pid='B7e-fm-load-errors',
        stage='B',
        rel='lib/screens/file_manager_screen.dart',
        old="    final dir = Directory(path);\n    if (!dir.existsSync()) {\n      setState(() {\n        _entries = [];\n        _loading = false;\n      });\n      return;\n    }\n\n    try {\n      final list = await dir.list(followLinks: false).toList();\n      final visible = list.where((e) {\n        final name = p.basename(e.path);\n        return !name.startsWith('.') || name == '.thumbnails';\n      }).toList();\n\n      _sortEntries(visible);\n\n      if (mounted) {\n        setState(() {\n          _entries = visible;\n          _loading = false;\n        });\n      }\n    } catch (_) {\n      if (mounted) {\n        setState(() {\n          _entries = [];\n          _loading = false;\n        });\n      }\n    }\n",
        new='    final dir = Directory(path);\n    if (!dir.existsSync()) {\n      if (mounted) {\n        setState(() {\n          _entries = [];\n          _loading = false;\n          _errorMsg = \'This folder does not exist on this device.\';\n        });\n      }\n      return;\n    }\n\n    try {\n      final list = await dir.list(followLinks: false).toList();\n      final visible = list.where((e) {\n        final name = p.basename(e.path);\n        return !name.startsWith(\'.\') || name == \'.thumbnails\';\n      }).toList();\n\n      _sortEntries(visible);\n\n      if (mounted) {\n        setState(() {\n          _entries = visible;\n          _loading = false;\n          _errorMsg = null;\n        });\n      }\n    } catch (_) {\n      // v95: never fail silently. An unreadable folder used to render as a\n      // bare "No files found", which reads as "my videos are gone".\n      if (mounted) {\n        setState(() {\n          _entries = [];\n          _loading = false;\n          _errorMsg = _permissionDenied\n              ? \'Max Player needs "All files access" to read this folder.\'\n              : \'Android blocked access to this folder.\';\n        });\n      }\n    }\n',
        why='Replace the silent empty list with a real, actionable message.',
    ),
    Patch(
        pid='B7f-fm-doc-subtitle-overlap',
        stage='B',
        rel='lib/screens/file_manager_screen.dart',
        old="    return ext == '.txt' || ext == '.pdf' || ext == '.json' || ext == '.doc' || ext == '.docx' || ext == '.log' || ext == '.xml' || ext == '.csv' || ext == '.md' || ext == '.srt' || ext == '.vtt';\n",
        new="    // v95: .srt/.vtt used to count as BOTH Documents and Subtitles, so the\n    // two filter chips overlapped and the counts disagreed.\n    return ext == '.txt' ||\n        ext == '.pdf' ||\n        ext == '.json' ||\n        ext == '.doc' ||\n        ext == '.docx' ||\n        ext == '.log' ||\n        ext == '.xml' ||\n        ext == '.csv' ||\n        ext == '.md';\n",
        why="REQUEST: 'filters are not working properly' (part 1 of 2).",
    ),
    Patch(
        pid='B7g-fm-filter-dirs',
        stage='B',
        rel='lib/screens/file_manager_screen.dart',
        old="      if (_typeFilter != 'all' && e is File) {\n        if (_typeFilter == 'video') return isVideoFile(e.path);\n        if (_typeFilter == 'audio') return _isAudioFile(e.path);\n        if (_typeFilter == 'image') return _isImageFile(e.path);\n        if (_typeFilter == 'subs') {\n          final ext = p.extension(e.path).toLowerCase();\n          return ext == '.srt' || ext == '.vtt' || ext == '.ass' || ext == '.sub';\n        }\n        if (_typeFilter == 'doc') return _isDocFile(e.path);\n      }\n      return true;\n",
        new='      // v95 FIX: this block was guarded by `&& e is File`, so EVERY folder\n      // stayed visible whichever chip was picked - the list looked exactly\n      // the same after tapping Videos/Music/Images, i.e. "filters are not\n      // working". A type filter now filters everything, folders included.\n      if (_typeFilter != \'all\') {\n        if (e is! File) return false;\n        if (_typeFilter == \'video\') return isVideoFile(e.path);\n        if (_typeFilter == \'audio\') return _isAudioFile(e.path);\n        if (_typeFilter == \'image\') return _isImageFile(e.path);\n        if (_typeFilter == \'subs\') {\n          final ext = p.extension(e.path).toLowerCase();\n          return ext == \'.srt\' || ext == \'.vtt\' || ext == \'.ass\' || ext == \'.sub\';\n        }\n        if (_typeFilter == \'doc\') return _isDocFile(e.path);\n      }\n      return true;\n',
        why="REQUEST: 'filters are not working properly' (part 2 of 2) - the real bug.",
    ),
    Patch(
        pid='B7h-fm-empty-state',
        stage='B',
        rel='lib/screens/file_manager_screen.dart',
        old="                              const Icon(Icons.folder_open, size: 54, color: Colors.white24),\n                              const SizedBox(height: 12),\n                              const Text('No files found', style: TextStyle(color: Colors.white54, fontSize: 15)),\n",
        new='                              Icon(\n                                _errorMsg != null\n                                    ? Icons.lock_outline\n                                    : Icons.folder_open,\n                                size: 54,\n                                color: Colors.white24,\n                              ),\n                              const SizedBox(height: 12),\n                              Padding(\n                                padding:\n                                    const EdgeInsets.symmetric(horizontal: 24),\n                                child: Text(\n                                  _errorMsg ??\n                                      (_typeFilter != \'all\'\n                                          ? \'Nothing of this type in this folder.\\nTap "All Files" to browse into subfolders.\'\n                                          : \'No files found\'),\n                                  textAlign: TextAlign.center,\n                                  style: const TextStyle(\n                                      color: Colors.white54, fontSize: 14),\n                                ),\n                              ),\n                              if (_errorMsg != null && _permissionDenied)\n                                Padding(\n                                  padding: const EdgeInsets.only(top: 10),\n                                  child: TextButton.icon(\n                                    onPressed: _bootstrap,\n                                    icon: const Icon(\n                                        Icons.folder_shared_outlined,\n                                        size: 16),\n                                    label: const Text(\'Grant access\'),\n                                    style: TextButton.styleFrom(\n                                      foregroundColor: themeState.accent,\n                                    ),\n                                  ),\n                                ),\n',
        why='Render the permission/error message and offer a retry button.',
    ),
    Patch(
        pid='B19-home-india',
        stage='B',
        rel='lib/screens/library_screen.dart',
        old="        title: ShaderMask(\n          shaderCallback: (bounds) => const LinearGradient(\n            colors: [Color(0xFFA78BFA), Color(0xFF8B5CF6), Color(0xFF22D3EE)],\n          ).createShader(bounds),\n          child: const Text(\n            'Max Player',\n            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),\n          ),\n        ),\n",
        new="        // v95: two-line app-bar title - brand line plus the new tagline.\n        title: Column(\n          mainAxisAlignment: MainAxisAlignment.center,\n          crossAxisAlignment: CrossAxisAlignment.start,\n          mainAxisSize: MainAxisSize.min,\n          children: [\n            ShaderMask(\n              shaderCallback: (bounds) => const LinearGradient(\n                colors: [\n                  Color(0xFFA78BFA),\n                  Color(0xFF8B5CF6),\n                  Color(0xFF22D3EE)\n                ],\n              ).createShader(bounds),\n              child: const Text(\n                'Max Player',\n                style: TextStyle(\n                  fontWeight: FontWeight.bold,\n                  color: Colors.white,\n                  fontSize: 19,\n                ),\n              ),\n            ),\n            const Text(\n              'Proudly Developed in India \\u{1F1EE}\\u{1F1F3}',\n              style: TextStyle(\n                color: Colors.white54,\n                fontSize: 9.5,\n                letterSpacing: 0.3,\n                height: 1.3,\n              ),\n            ),\n          ],\n        ),\n",
        why='REQUEST: \'add a small text below Max Player text in home screen\n    "Proudly Developed in India"\'. Written with Dart unicode escapes so\n    the flag survives any editor/encoding that mangles emoji.',
    ),
    Patch(
        pid='Z-pubspec-bump',
        stage='B',
        rel='pubspec.yaml',
        old='version: 1.0.0+94\n',
        new='version: 1.0.0+95\n',
        why='Version bump 94 -> 95.',
    ),
    Patch(
        pid='B20-fm-ai-import',
        stage='B',
        rel='lib/screens/file_manager_screen.dart',
        old="import '../models/video_track.dart';\nimport '../state/media_player_state.dart';\n",
        new="import '../models/video_track.dart';\nimport '../services/media_ai.dart';\nimport '../state/media_player_state.dart';\n",
        why='Import the new media_ai service (kept alphabetically sorted, which\n    is how the rest of this import block is ordered).',
    ),
    Patch(
        pid='B21-fm-ai-real',
        stage='B',
        rel='lib/screens/file_manager_screen.dart',
        old="  void _showAiMediaInsights() {\n    final totalDirs = _entries.whereType<Directory>().length;\n    int videoCount = 0;\n    int audioCount = 0;\n    int imageCount = 0;\n    int docCount = 0;\n    int totalBytes = 0;\n\n    for (final e in _entries) {\n      if (e is File) {\n        try {\n          final len = e.lengthSync();\n          totalBytes += len;\n          if (isVideoFile(e.path)) {\n            videoCount++;\n          } else if (_isAudioFile(e.path)) {\n            audioCount++;\n          } else if (_isImageFile(e.path)) {\n            imageCount++;\n          } else if (_isDocFile(e.path)) {\n            docCount++;\n          }\n        } catch (_) {}\n      }\n    }\n\n    final totalSizeStr = formatFileSize(totalBytes);\n\n    showDialog<void>(\n      context: context,\n      builder: (ctx) => AlertDialog(\n        backgroundColor: const Color(0xFF181826),\n        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),\n        title: Row(\n          children: [\n            Icon(Icons.auto_awesome, color: themeState.accent, size: 22),\n            const SizedBox(width: 10),\n            const Text('AI Media Insights', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),\n          ],\n        ),\n        content: Column(\n          mainAxisSize: MainAxisSize.min,\n          crossAxisAlignment: CrossAxisAlignment.start,\n          children: [\n            Text('Directory: ${p.basename(_currentPath)}', style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),\n            const SizedBox(height: 10),\n            _aiStatRow('Total Storage Used', totalSizeStr),\n            _aiStatRow('Videos Found', '$videoCount files'),\n            _aiStatRow('Audio Tracks', '$audioCount files'),\n            _aiStatRow('Images & Photos', '$imageCount files'),\n            _aiStatRow('Documents', '$docCount files'),\n            _aiStatRow('Subfolders', '$totalDirs folders'),\n            const SizedBox(height: 12),\n            Container(\n              padding: const EdgeInsets.all(10),\n              decoration: BoxDecoration(\n                color: themeState.accent.withValues(alpha: 0.12),\n                borderRadius: BorderRadius.circular(10),\n                border: Border.all(color: themeState.accent.withValues(alpha: 0.3)),\n              ),\n              child: Row(\n                children: [\n                  Icon(Icons.lightbulb_outline, color: themeState.accent, size: 18),\n                  const SizedBox(width: 8),\n                  const Expanded(\n                    child: Text(\n                      'AI Recommendation: All media formats here are fully accelerated by libmpv for 100% smooth playback.',\n                      style: TextStyle(color: Colors.white70, fontSize: 11.5, height: 1.35),\n                    ),\n                  ),\n                ],\n              ),\n            ),\n          ],\n        ),\n        actions: [\n          TextButton(\n            onPressed: () => Navigator.of(ctx).pop(),\n            child: Text('Close', style: TextStyle(color: themeState.accent)),\n          ),\n        ],\n      ),\n    );\n  }\n",
        new='  /// v95 FIX: "ai tool is meaning less". The old version counted files and then\n  /// printed ONE hardcoded marketing sentence, identical for every folder on the\n  /// device, so it was not really looking at anything. (The exact wording is\n  /// recorded in services/media_ai.dart, and a test forbids it back in here.)\n  /// Now it computes findings that are genuinely\n  /// derived from this folder (orphaned subtitles, probable duplicates,\n  /// unrecognized extensions, largest file) via services/media_ai.dart, and asks\n  /// the app\'s EXISTING OpenRouter client for commentary on top. With no API key\n  /// or no network it still shows the real findings and says plainly that the AI\n  /// part is unavailable - it never invents a sentence.\n  Future<void> _showAiMediaInsights() async {\n    final files = <MediaFileInfo>[];\n    int dirs = 0;\n    for (final e in _entries) {\n      if (e is Directory) {\n        dirs++;\n        continue;\n      }\n      if (e is! File) continue;\n      try {\n        files.add(MediaFileInfo(\n          p.basename(e.path),\n          e.lengthSync(),\n          _mediaKind(e.path),\n        ));\n      } catch (_) {}\n    }\n    final stats = MediaFolderStats(\n      folderName: p.basename(_currentPath),\n      dirs: dirs,\n      files: files,\n    );\n    final findings = localMediaInsights(stats);\n    // Start the request now so it is already in flight while the dialog builds.\n    // Deliberately NOT awaited here: there must be no `await` before the\n    // context use below (use_build_context_synchronously).\n    final ai = MediaAiClient.ask(stats);\n\n    await showDialog<void>(\n      context: context,\n      builder: (ctx) => AlertDialog(\n        backgroundColor: const Color(0xFF181826),\n        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),\n        title: Row(\n          children: [\n            Icon(Icons.auto_awesome, color: themeState.accent, size: 22),\n            const SizedBox(width: 10),\n            const Text(\'AI Media Insights\', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),\n          ],\n        ),\n        content: ConstrainedBox(\n          constraints: const BoxConstraints(maxHeight: 420),\n          child: SingleChildScrollView(\n            child: Column(\n              mainAxisSize: MainAxisSize.min,\n              crossAxisAlignment: CrossAxisAlignment.start,\n              children: [\n                Text(\'Directory: ${p.basename(_currentPath)}\', style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),\n                const SizedBox(height: 10),\n                _aiStatRow(\'Total Storage Used\', formatFileSize(stats.totalBytes)),\n                _aiStatRow(\'Videos Found\', \'${stats.videos} files\'),\n                _aiStatRow(\'Audio Tracks\', \'${stats.audios} files\'),\n                _aiStatRow(\'Images & Photos\', \'${stats.images} files\'),\n                _aiStatRow(\'Documents\', \'${stats.docs} files\'),\n                _aiStatRow(\'Subtitles\', \'${stats.subtitles} files\'),\n                _aiStatRow(\'Subfolders\', \'$dirs folders\'),\n                const SizedBox(height: 12),\n                // v95: real, computed, folder-specific findings. Always shown.\n                for (final f in findings)\n                  Padding(\n                    padding: const EdgeInsets.only(bottom: 7),\n                    child: Row(\n                      crossAxisAlignment: CrossAxisAlignment.start,\n                      children: [\n                        Icon(Icons.insights_outlined, color: themeState.accent, size: 15),\n                        const SizedBox(width: 8),\n                        Expanded(\n                          child: Text(\n                            f,\n                            style: const TextStyle(color: Colors.white70, fontSize: 11.5, height: 1.35),\n                          ),\n                        ),\n                      ],\n                    ),\n                  ),\n                const SizedBox(height: 4),\n                FutureBuilder<MediaAiAnswer?>(\n                  future: ai,\n                  builder: (context, snap) {\n                    if (snap.connectionState != ConnectionState.done) {\n                      return Row(\n                        children: [\n                          SizedBox(\n                            width: 13,\n                            height: 13,\n                            child: CircularProgressIndicator(strokeWidth: 2, color: themeState.accent),\n                          ),\n                          const SizedBox(width: 10),\n                          const Expanded(\n                            child: Text(\'Asking Max AI about this folder...\',\n                                style: TextStyle(color: Colors.white38, fontSize: 11.5)),\n                          ),\n                        ],\n                      );\n                    }\n                    final ans = snap.data;\n                    return Container(\n                      padding: const EdgeInsets.all(10),\n                      decoration: BoxDecoration(\n                        color: themeState.accent.withValues(alpha: 0.12),\n                        borderRadius: BorderRadius.circular(10),\n                        border: Border.all(color: themeState.accent.withValues(alpha: 0.3)),\n                      ),\n                      child: Row(\n                        crossAxisAlignment: CrossAxisAlignment.start,\n                        children: [\n                          Icon(Icons.lightbulb_outline, color: themeState.accent, size: 18),\n                          const SizedBox(width: 8),\n                          Expanded(\n                            child: Column(\n                              crossAxisAlignment: CrossAxisAlignment.start,\n                              children: [\n                                Text(\n                                  ans == null\n                                      ? \'Max AI commentary unavailable (no API key or no network). The findings above were computed on your device.\'\n                                      : ans.text,\n                                  style: const TextStyle(color: Colors.white70, fontSize: 11.5, height: 1.35),\n                                ),\n                                if (ans != null)\n                                  Padding(\n                                    padding: const EdgeInsets.only(top: 6),\n                                    child: Text(\'Max AI - ${ans.model}\',\n                                        style: const TextStyle(color: Colors.white24, fontSize: 10)),\n                                  ),\n                              ],\n                            ),\n                          ),\n                        ],\n                      ),\n                    );\n                  },\n                ),\n                const SizedBox(height: 8),\n                const Text(\n                  \'AI commentary uses only this folder\\\'s file names, sizes and counts - never file contents.\',\n                  style: TextStyle(color: Colors.white24, fontSize: 9.5, height: 1.3),\n                ),\n              ],\n            ),\n          ),\n        ),\n        actions: [\n          TextButton(\n            onPressed: () => Navigator.of(ctx).pop(),\n            child: Text(\'Close\', style: TextStyle(color: themeState.accent)),\n          ),\n        ],\n      ),\n    );\n  }\n\n  /// v95: classify with the SAME rules the filter chips use, so the counts in\n  /// this dialog and the counts behind Videos/Music/Images/Subtitles agree.\n  MediaKind _mediaKind(String path) {\n    if (isVideoFile(path)) return MediaKind.video;\n    if (_isAudioFile(path)) return MediaKind.audio;\n    if (_isImageFile(path)) return MediaKind.image;\n    final ext = p.extension(path).toLowerCase();\n    if (ext == \'.srt\' || ext == \'.vtt\' || ext == \'.ass\' || ext == \'.sub\') {\n      return MediaKind.subtitle;\n    }\n    if (_isDocFile(path)) return MediaKind.doc;\n    return MediaKind.other;\n  }\n',
        why="Replace the fake insights dialog. Line 470 of the old code was a\n    `const Text('AI Recommendation: All media formats here are fully\n    accelerated by libmpv for 100% smooth playback.')` - the same string\n    for every folder, which is exactly why it read as meaningless.\n    Now: real computed findings (orphaned subtitles, probable duplicates,\n    unrecognized extensions, largest file + its share of the folder)\n    always shown, plus genuine AI commentary through the app's existing\n    OpenRouter client when a key and network are available, and an honest\n    'unavailable' line when they are not. Also adds _mediaKind(), which\n    classifies with the SAME rules the filter chips use so the two counts\n    can never disagree.",
    ),
    Patch(
        pid='B22-test-ai-import',
        stage='B',
        rel='test/widget_test.dart',
        old="import 'package:maxplayer/models/video_track.dart';\nimport 'package:maxplayer/services/tmdb_client.dart';\nimport 'package:maxplayer/utils/formatters.dart';\n",
        new="import 'package:maxplayer/models/video_track.dart';\nimport 'package:maxplayer/services/media_ai.dart';\nimport 'package:maxplayer/services/tmdb_client.dart';\nimport 'package:maxplayer/utils/formatters.dart';\n",
        why='Import media_ai into the suite.',
    ),
    Patch(
        pid='B23-test-ai-group',
        stage='B',
        rel='test/widget_test.dart',
        old="    test('NetworkStorageSheet uses dynamic contrast colors for buttons', () {\n      final net = File('lib/widgets/network_storage_sheet.dart').readAsStringSync();\n      expect(net, contains('computeLuminance'));\n      expect(net, contains('btnTextColor'));\n    });\n  });\n}\n",
        new='    test(\'NetworkStorageSheet uses dynamic contrast colors for buttons\', () {\n      final net = File(\'lib/widgets/network_storage_sheet.dart\').readAsStringSync();\n      expect(net, contains(\'computeLuminance\'));\n      expect(net, contains(\'btnTextColor\'));\n    });\n  });\n\n  group(\'v95 media_ai - real File Manager insights\', () {\n    test(\'finds orphaned subtitles, duplicates and the largest file\', () {\n      final stats = MediaFolderStats(\n        folderName: \'Movies\',\n        dirs: 1,\n        files: const [\n          MediaFileInfo(\'Dune.mkv\', 2147483648, MediaKind.video),\n          MediaFileInfo(\'Dune.mkv\', 2147483648, MediaKind.video),\n          MediaFileInfo(\'Dune.srt\', 40960, MediaKind.subtitle),\n          MediaFileInfo(\'Orphan.srt\', 30720, MediaKind.subtitle),\n          MediaFileInfo(\'notes.xyz\', 1024, MediaKind.other),\n        ],\n      );\n      expect(stats.videos, 2);\n      expect(stats.subtitles, 2);\n      expect(stats.others, 1);\n      // \'Dune.srt\' pairs with \'Dune.mkv\'; \'Orphan.srt\' has nothing to attach to.\n      expect(stats.orphanedSubtitles.map((f) => f.name).toList(), [\'Orphan.srt\']);\n      // Two byte-identical videos over the 1 MB floor = one duplicate group.\n      expect(stats.duplicateCandidates.length, 1);\n      expect(stats.largest!.bytes, 2147483648);\n      expect(stats.topExtensions[\'mkv\'], 2);\n    });\n\n    test(\'insights come from the data, never from one fixed sentence\', () {\n      final empty = MediaFolderStats(folderName: \'A\', dirs: 0, files: const []);\n      final one = MediaFolderStats(\n        folderName: \'B\',\n        dirs: 0,\n        files: const [MediaFileInfo(\'Orphan.srt\', 1024, MediaKind.subtitle)],\n      );\n      final emptyText = localMediaInsights(empty).join(\' \');\n      final oneText = localMediaInsights(one).join(\' \');\n      expect(emptyText, isNot(oneText));\n      expect(oneText, contains(\'Orphan.srt\'));\n      // The v93 hardcoded marketing line must never come back.\n      expect(oneText, isNot(contains(\'fully accelerated by libmpv\')));\n      expect(emptyText, isNot(contains(\'fully accelerated by libmpv\')));\n    });\n\n    test(\'File Manager wires the real service, not a static string\', () {\n      final fm = File(\'lib/screens/file_manager_screen.dart\').readAsStringSync();\n      expect(fm, contains("import \'../services/media_ai.dart\';"));\n      expect(fm, contains(\'MediaAiClient.ask(\'));\n      expect(fm, contains(\'localMediaInsights(\'));\n      expect(fm, isNot(contains(\'fully accelerated by libmpv\')));\n    });\n  });\n}\n',
        why='Three real unit tests for the new service: orphan/duplicate detection,\n    proof the insights vary with the data (and that the old hardcoded\n    sentence can never come back), and a source check that the File\n    Manager is actually wired to it.',
    ),
]

NEWFILES = [
    ('lib/services/media_ai.dart', 'import \'dart:convert\';\nimport \'dart:io\';\n\nimport \'../utils/formatters.dart\';\nimport \'movie_ai.dart\';\n\n/// v95: REAL analysis for the File Manager\'s "AI Media Insights".\n///\n/// WHY THIS FILE EXISTS\n/// --------------------\n/// The old `_showAiMediaInsights()` counted files and then printed the SAME\n/// hardcoded sentence for every folder on the device:\n///   "AI Recommendation: All media formats here are fully accelerated by\n///    libmpv for 100% smooth playback."\n/// That is why it read as meaningless - it was not looking at anything.\n///\n/// This service instead computes findings that are genuinely derived from the\n/// folder (orphaned subtitles, probable duplicates, unrecognized extensions,\n/// the largest file), and only THEN asks the app\'s EXISTING OpenRouter client\n/// in movie_ai.dart for commentary on top - same key, same model fallback\n/// chain, no new dependency and no new secret to manage.\n///\n/// PRIVACY: only file *names*, sizes and counts leave the device, and only for\n/// the handful of items actually worth commenting on. Never file contents,\n/// never paths outside the folder being inspected.\n\nenum MediaKind { video, audio, image, doc, subtitle, other }\n\nclass MediaFileInfo {\n  final String name;\n  final int bytes;\n  final MediaKind kind;\n\n  const MediaFileInfo(this.name, this.bytes, this.kind);\n\n  /// Lowercased extension without the dot; \'\' when there is none.\n  String get ext {\n    final i = name.lastIndexOf(\'.\');\n    return (i <= 0 || i == name.length - 1)\n        ? \'\'\n        : name.substring(i + 1).toLowerCase();\n  }\n\n  /// Name with its extension removed, lowercased - used to pair subtitles up.\n  String get stem {\n    final i = name.lastIndexOf(\'.\');\n    return (i <= 0 ? name : name.substring(0, i)).toLowerCase();\n  }\n}\n\n/// Pure, computed facts about one folder. The caller does the I/O; this class\n/// only reasons about what it was given, so it is unit-testable.\nclass MediaFolderStats {\n  final String folderName;\n  final int dirs;\n  final List<MediaFileInfo> files;\n\n  MediaFolderStats({\n    required this.folderName,\n    required this.dirs,\n    required this.files,\n  });\n\n  int countOf(MediaKind k) => files.where((f) => f.kind == k).length;\n\n  int get videos => countOf(MediaKind.video);\n  int get audios => countOf(MediaKind.audio);\n  int get images => countOf(MediaKind.image);\n  int get docs => countOf(MediaKind.doc);\n  int get subtitles => countOf(MediaKind.subtitle);\n  int get others => countOf(MediaKind.other);\n\n  int get totalBytes => files.fold(0, (a, f) => a + f.bytes);\n\n  MediaFileInfo? get largest {\n    MediaFileInfo? best;\n    for (final f in files) {\n      if (best == null || f.bytes > best.bytes) best = f;\n    }\n    return best;\n  }\n\n  /// Subtitle files that have no video in this folder to attach to, so they\n  /// will never auto-load. Allows the common "movie.en.srt" / "movie (1).srt"\n  /// spellings to still count as a match for "movie.mkv".\n  List<MediaFileInfo> get orphanedSubtitles {\n    final all = files.where((f) => f.kind == MediaKind.subtitle).toList();\n    if (all.isEmpty) return const [];\n    final stems =\n        files.where((f) => f.kind == MediaKind.video).map((f) => f.stem).toList();\n    if (stems.isEmpty) return all;\n    return all.where((f) {\n      for (final v in stems) {\n        if (f.stem == v || f.stem.startsWith(\'$v.\') || f.stem.startsWith(\'$v \')) {\n          return false;\n        }\n      }\n      return true;\n    }).toList();\n  }\n\n  /// Videos that are byte-identical in size AND extension - almost certainly\n  /// the same file downloaded twice. The 1 MB floor skips thumbnails/partial\n  /// downloads, which collide constantly and would be noise.\n  List<String> get duplicateCandidates {\n    final seen = <String, List<MediaFileInfo>>{};\n    for (final f in files) {\n      if (f.kind != MediaKind.video) continue;\n      if (f.bytes < 1024 * 1024) continue;\n      seen.putIfAbsent(\'${f.bytes}|${f.ext}\', () => []).add(f);\n    }\n    final out = <String>[];\n    for (final group in seen.values) {\n      if (group.length < 2) continue;\n      out.add(\'${group.length} x ${group.first.name}\');\n    }\n    out.sort();\n    return out;\n  }\n\n  /// The four most common extensions, most frequent first.\n  Map<String, int> get topExtensions {\n    final m = <String, int>{};\n    for (final f in files) {\n      if (f.ext.isEmpty) continue;\n      m[f.ext] = (m[f.ext] ?? 0) + 1;\n    }\n    final sorted = m.entries.toList()\n      ..sort((a, b) => b.value.compareTo(a.value));\n    return Map<String, int>.fromEntries(sorted.take(4));\n  }\n}\n\n/// Findings derived purely from the data above - ALWAYS shown, even with no\n/// network and no API key. This is the part that can never be a lie.\nList<String> localMediaInsights(MediaFolderStats s) {\n  final out = <String>[];\n\n  if (s.files.isEmpty && s.dirs == 0) {\n    out.add(\'This folder is empty - nothing to analyze.\');\n    return out;\n  }\n  if (s.files.isEmpty) {\n    out.add(\'Only subfolders here (${s.dirs}), no media files at this level.\');\n    return out;\n  }\n\n  final orphans = s.orphanedSubtitles;\n  if (orphans.isNotEmpty) {\n    final names = orphans.take(3).map((f) => f.name).join(\', \');\n    out.add(\n      \'${orphans.length} subtitle file${orphans.length == 1 ? \'\' : \'s\'} match no \'\n      \'video in this folder: $names. Rename ${orphans.length == 1 ? \'it\' : \'them\'} \'\n      \'to the video\\\'s exact name to make ${orphans.length == 1 ? \'it\' : \'them\'} load automatically.\',\n    );\n  }\n\n  final dupes = s.duplicateCandidates;\n  if (dupes.isNotEmpty) {\n    out.add(\n      \'Possible duplicates (same size and container): ${dupes.take(3).join(\'; \')}.\',\n    );\n  }\n\n  if (s.others > 0) {\n    final ex = s.files\n        .where((f) => f.kind == MediaKind.other)\n        .take(3)\n        .map((f) => f.name)\n        .join(\', \');\n    out.add(\n      \'${s.others} file${s.others == 1 ? \'\' : \'s\'} with an unrecognized extension \'\n      \'($ex) - these may not play.\',\n    );\n  }\n\n  final big = s.largest;\n  if (big != null && big.bytes >= 1024 * 1024 * 1024) {\n    final share = s.totalBytes == 0 ? 0 : (big.bytes * 100) ~/ s.totalBytes;\n    out.add(\n      \'Largest: ${big.name} at ${formatFileSize(big.bytes)} - $share% of this \'\n      \'folder\\\'s ${formatFileSize(s.totalBytes)}.\',\n    );\n  }\n\n  if (out.isEmpty) {\n    final exts = s.topExtensions.entries.map((e) => \'.${e.key}\').join(\', \');\n    out.add(\n      \'Nothing needs attention: ${s.videos} video${s.videos == 1 ? \'\' : \'s\'}, \'\n      \'${s.files.length} files, ${formatFileSize(s.totalBytes)}\'\n      \'${exts.isEmpty ? \'\' : \', formats $exts\'} - all handled natively by libmpv.\',\n    );\n  }\n  return out;\n}\n\nclass MediaAiAnswer {\n  final String text;\n  final String model;\n\n  const MediaAiAnswer(this.text, this.model);\n}\n\nconst String kMediaAiSystemPrompt =\n    \'You are the media librarian inside the Max Player Android app. You are \'\n    \'given REAL statistics that were computed on the user\\\'s device about one \'\n    \'folder of their storage. Reply with 2 to 4 short, specific, practical \'\n    \'observations in plain prose - no markdown, no headings, no bullet \'\n    \'characters, no emoji. Refer ONLY to files, counts and sizes that actually \'\n    \'appear in the statistics; never invent titles or files, never suggest \'\n    \'buying anything, never say that you are an AI. If nothing needs the \'\n    \'user\\\'s attention, say that plainly in one sentence. Keep the whole reply \'\n    \'under 90 words.\';\n\nclass MediaAiClient {\n  static const String _url = \'https://openrouter.ai/api/v1/chat/completions\';\n\n  static final HttpClient _http = HttpClient()\n    ..connectionTimeout = const Duration(seconds: 10)\n    ..idleTimeout = const Duration(seconds: 8);\n\n  /// Compact, privacy-bounded payload: counts, sizes, formats and at most a\n  /// few file names. Never contents, never the full path.\n  static String statsPrompt(MediaFolderStats s) {\n    final buf = StringBuffer()\n      ..writeln(\'Folder: ${s.folderName}\')\n      ..writeln(\'Subfolders: ${s.dirs}\')\n      ..writeln(\n        \'Files: ${s.files.length} (videos ${s.videos}, audio ${s.audios}, \'\n        \'images ${s.images}, documents ${s.docs}, subtitles ${s.subtitles}, \'\n        \'unrecognized ${s.others})\',\n      )\n      ..writeln(\'Total size: ${formatFileSize(s.totalBytes)}\');\n\n    final exts = s.topExtensions;\n    if (exts.isNotEmpty) {\n      buf.writeln(\n        \'Formats: ${exts.entries.map((e) => \'.${e.key} x${e.value}\').join(\', \')}\',\n      );\n    }\n    final big = s.largest;\n    if (big != null) {\n      buf.writeln(\'Largest file: ${big.name} (${formatFileSize(big.bytes)})\');\n    }\n    final orphans = s.orphanedSubtitles;\n    if (orphans.isNotEmpty) {\n      buf.writeln(\n        \'Subtitles matching no video in this folder: \'\n        \'${orphans.take(4).map((f) => f.name).join(\', \')}\',\n      );\n    }\n    final dupes = s.duplicateCandidates;\n    if (dupes.isNotEmpty) {\n      buf.writeln(\'Same-size same-format video groups: ${dupes.take(3).join(\'; \')}\');\n    }\n    buf.write(\n      \'On-device findings already shown to the user: \'\n      \'${localMediaInsights(s).join(\' | \')}\',\n    );\n    return buf.toString();\n  }\n\n  /// Returns null when there is no API key, no network, or every model in the\n  /// fallback chain failed. The caller then shows the on-device findings\n  /// instead and says so - it never substitutes a made-up sentence.\n  static Future<MediaAiAnswer?> ask(MediaFolderStats s) async {\n    if (kOpenRouterApiKey.isEmpty) return null;\n    if (s.files.isEmpty && s.dirs == 0) return null;\n\n    final question = statsPrompt(s);\n    for (final model in kOpenRouterModels) {\n      try {\n        final req = await _http.postUrl(Uri.parse(_url));\n        req.headers.set(\'content-type\', \'application/json\');\n        req.headers.set(\'authorization\', \'Bearer $kOpenRouterApiKey\');\n        req.headers.set(\'x-title\', \'Max Player\');\n        req.write(jsonEncode(openRouterChatBody(\n          model: model,\n          system: kMediaAiSystemPrompt,\n          question: question,\n          maxTokens: 260,\n        )));\n        final res = await req.close().timeout(const Duration(seconds: 10));\n        if (res.statusCode != 200) {\n          await res.drain<void>();\n          continue;\n        }\n        final body = await res.transform(utf8.decoder).join();\n        final text = parseOpenRouterAnswer(body);\n        if (text != null && text.trim().isNotEmpty) {\n          return MediaAiAnswer(text.trim(), model);\n        }\n      } catch (_) {\n        // try the next model in the chain\n      }\n    }\n    return null;\n  }\n}\n'),
]

def main():
    sources = {}
    for p in PATCHES:
        if p.rel not in sources:
            if not os.path.isfile(p.rel):
                sys.exit(f"ERROR: missing file {p.rel}")
            with open(p.rel, encoding="utf-8") as f:
                sources[p.rel] = f.read()

    failures = [(p, sources[p.rel].count(p.old)) for p in PATCHES
                if sources[p.rel].count(p.old) != 1]
    if failures:
        print("\nABORTED - no files were modified.")
        for p, n in failures:
            print(f"  [{p.pid}] anchor matched {n}x (need exactly 1) in {p.rel}")
            print("    why: " + p.why.splitlines()[0].strip())
        print("\nThe tree has probably moved on since v94. Re-clone and re-check")
        print("the anchors against the CURRENT file content before retrying.")
        sys.exit(1)

    for p in PATCHES:
        sources[p.rel] = sources[p.rel].replace(p.old, p.new, 1)
    for rel, text in sources.items():
        with open(rel, "w", encoding="utf-8") as f:
            f.write(text)

    for rel, content in NEWFILES:
        d = os.path.dirname(rel)
        if d:
            os.makedirs(d, exist_ok=True)
        existed = os.path.isfile(rel)
        with open(rel, "w", encoding="utf-8") as f:
            f.write(content)
        print(f"    {'overwrote' if existed else 'created  '} {rel}  ({len(content)} bytes)")

    print()
    for p in PATCHES:
        print(f"    applied {p.pid:30s} {p.rel}  ({len(p.new)-len(p.old):+d} bytes)")
    print()
    print(f"  {len(PATCHES)} patches applied to {len(sources)} files.")

if __name__ == "__main__":
    main()
PYEOF
PATCH_RC=$?
set -e
[ "$PATCH_RC" -eq 0 ] || { echo "ERROR: patch stage failed; tree NOT modified." >&2; exit 1; }

echo
echo "--- Verifying brace / paren / bracket balance ---"
set +e
python3 - lib/screens/file_manager_screen.dart lib/screens/library_screen.dart lib/screens/player_screen.dart lib/services/media_ai.dart lib/services/tmdb_client.dart lib/widgets/movie_detail_sheet.dart test/widget_test.dart <<'PYEOF'
import sys

def balance(path):
    s = open(path, encoding='utf-8').read()
    d = {'{': 0, '(': 0, '[': 0}
    close = {'}': '{', ')': '(', ']': '['}
    i, q = 0, None
    while i < len(s):
        c = s[i]
        if q:
            if c == '\\':
                i += 2; continue
            if c == q: q = None
        elif c in ('"', "'"):
            q = c
        elif s.startswith('//', i):
            i = s.find('\n', i)
            if i < 0: break
            continue
        elif s.startswith('/*', i):
            j = s.find('*/', i + 2)
            i = len(s) if j < 0 else j + 2
            continue
        elif c in d: d[c] += 1
        elif c in close: d[close[c]] -= 1
        i += 1
    return d

bad = False
for f in sys.argv[1:]:
    d = balance(f)
    ok = all(v == 0 for v in d.values())
    bad = bad or not ok
    print(('  OK   ' if ok else '  FAIL ') + f'{f}  braces={d["{"]} parens={d["("]} brackets={d["["]}')
sys.exit(1 if bad else 0)
PYEOF
BAL=$?
set -e
if [ "$BAL" -ne 0 ]; then
  echo "ERROR: balance check failed. Undo everything with:" >&2
  echo "  git checkout -- ." >&2
  exit 1
fi

echo
echo "--- Diff summary ---"
git --no-pager diff --stat

echo
echo "=============================================================="
echo " PATCHED. Verify on this machine:"
echo "=============================================================="
cat <<'TIPS'

  flutter analyze      # must report: No issues found!
  flutter test         # must pass

  Then commit:

    git add -A
    git commit -F- <<'MSG'
v95: player Ask AI removed; season chip contrast + per-season ratings;
contents details above storyline; all reviews last & un-truncated;
File Manager permissions, WhatsApp paths, real filters; India tagline (1.0.0+95)
MSG
    git push origin main

  Full builds still go through Codemagic (Build APK / Build AAB).
TIPS
