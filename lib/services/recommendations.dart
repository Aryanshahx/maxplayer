import '../models/history_entry.dart';
import 'tmdb_client.dart';

/// v65 A6: on-device "Because you watched" recommendations.
///
/// No account, no cloud: we look at the user's LOCAL watch history, try to
/// match the most recently watched titles against TMDB's catalogue, then
/// pull TMDB's "similar" list for the best match. Everything is cached
/// 24 h by the underlying [TmdbClient], so repeated screen opens are free.
class Recommendations {
  /// Words that never help identify a title (resolution, source tags,
  /// release-year brackets etc).
  static const Set<String> _stopWords = {
    'the', 'a', 'an', 'of', 'and', 'or', 'part', 'vol', 'chapter',
    '1080p', '720p', '480p', '2160p', '4k', 'uhd', 'hd', 'bluray',
    'blu', 'ray', 'x264', 'x265', 'hevc', 'h264', 'aac', 'ac3', 'dts',
    'web', 'dl', 'rip', 'hdrip', 'dvdrip', 'brrip', 'yify', 'yts',
    'multi', 'esub', 'english', 'hindi', 'dubbed', 'dual', 'audio',
    'extended', 'remastered', 'unrated', 'proper', 'repack', 'internal',
  };

  /// Reduces a file/history title to a searchable phrase: drops bracketed
  /// tags, year-like suffixes, release-group noise and stop words.
  /// Pure + unit-tested.
  static String normalizeTitle(String raw) {
    var t = raw;
    // Drop anything in brackets/parens/braces: [1080p], (2014), {x264}.
    t = t.replaceAll(RegExp(r'[\[\(\{].*?[\]\)\}]'), ' ');
    // Drop standalone 4-digit years.
    t = t.replaceAll(RegExp(r'\b(19|20)\d{2}\b'), ' ');
    // Turn separators into spaces.
    t = t.replaceAll(RegExp(r'[._\-–]+'), ' ');
    final words = t
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .where((w) => !_stopWords.contains(w))
        .where((w) => !RegExp(r'^\d{3,4}p?$').hasMatch(w))
        .toList();
    return words.take(5).join(' ').trim();
  }

  /// Picks the best history title to base recommendations on:
  ///  - resumable/in-progress videos first (the user is actively watching),
  ///  - then the most recently played,
  ///  - skipping very short/empty titles.
  static HistoryEntry? pickAnchor(
    List<HistoryEntry> history, {
    int minTitleLen = 3,
  }) {
    if (history.isEmpty) return null;
    HistoryEntry? fallback;
    for (final e in history) {
      final norm = normalizeTitle(e.title);
      if (norm.length < minTitleLen) continue;
      // A video the user is partway through (5%..95%) is the strongest
      // signal - recommend things like it right now.
      if (e.durationSecs > 0) {
        final frac = e.lastPositionSecs / e.durationSecs;
        if (frac >= 0.05 && frac <= 0.95) return e;
      }
      fallback ??= e;
    }
    return fallback;
  }

  /// Searches TMDB for [anchor] and returns similar movies for the top
  /// result. Returns an empty list when there's no match or no similar
  /// titles (or the API key is missing).
  static Future<List<TmdbMovie>> forAnchor(
    TmdbClient client,
    HistoryEntry anchor, {
    bool force = false,
  }) async {
    final query = normalizeTitle(anchor.title);
    if (query.isEmpty) return const [];
    final page = await client.searchMulti(query, force: force);
    final results = page.items;
    if (results.isEmpty) return const [];
    // Prefer a movie/series title that shares a leading word with the
    // anchor; otherwise just use the top result.
    final anchorWords = query.split(' ');
    TmdbMovie? best;
    for (final m in results) {
      final mWords = normalizeTitle(m.title).split(' ');
      if (anchorWords.isNotEmpty &&
          mWords.isNotEmpty &&
          anchorWords.first == mWords.first) {
        best = m;
        break;
      }
    }
    final chosen = best ?? results.first;
    final similar =
        await client.similar(chosen.id, kind: chosen.kind, force: force);
    // Don't recommend the anchor itself.
    return similar.where((m) => m.id != chosen.id).take(12).toList();
  }
}
