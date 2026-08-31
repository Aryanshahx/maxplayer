import 'dart:convert';
import 'dart:io';

import 'movie_ai.dart';
import 'tmdb_client.dart';

/// One title the AI picked, before we resolve it to a real TMDB movie.
class AiTitlePick {
  final String title;
  final int? year;

  const AiTitlePick(this.title, this.year);
}

/// Extracts the model's `[{"title": ..., "year": ...}]` list even when it
/// wrapped it in prose or a ```json fence. Never throws; garbage -> [].
/// Pure for tests.
List<AiTitlePick> parseAiSuggestionJson(String raw) {
  final start = raw.indexOf('[');
  final end = raw.lastIndexOf(']');
  if (start < 0 || end <= start) return const [];
  try {
    final decoded = jsonDecode(raw.substring(start, end + 1));
    if (decoded is! List) return const [];
    final out = <AiTitlePick>[];
    for (final e in decoded) {
      if (e is! Map) continue;
      final t = '${e['title'] ?? ''}'.trim();
      if (t.isEmpty) continue;
      final y = e['year'];
      out.add(AiTitlePick(t, y is num ? y.toInt() : int.tryParse('$y')));
      if (out.length >= 10) break;
    }
    return out;
  } catch (_) {
    return const [];
  }
}

/// The system prompt - forces REAL, famous titles as bare JSON so the
/// parser and TMDB resolution always have something solid to work with.
const String kAiSuggestSystemPrompt =
    'You are the movie recommender inside the Max Player app. The user '
    'describes the kind of movies they want. Reply with ONLY a JSON array '
    'of up to 10 objects like [{"title":"3 Idiots","year":2009}] - real, '
    'well-known films that genuinely match the taste described, mixing '
    'Indian and international cinema when it fits. No commentary, no '
    'markdown, no code fence - just the JSON array.';

/// v58: "AI Suggestor" - the user DESCRIBES their taste in plain words
/// ("funny action like Dhoom", "sad Korean love story") and this resolves
/// the AI's picks to REAL TMDB movies with posters. Reuses the movie Q&A
/// OpenRouter key + model fallback chain (movie_ai.dart).
class AiSuggestor {
  static const String _url = 'https://openrouter.ai/api/v1/chat/completions';

  static final HttpClient _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 8);

  final TmdbClient tmdb;

  AiSuggestor(this.tmdb);

  /// Suggests up to 10 real movies for a free-text taste description.
  /// Falls back to smart keyword/genre matching on TMDB so suggestions always load.
  Future<List<TmdbMovie>?> suggest(String taste) async {
    final q = taste.trim();
    if (q.isEmpty) return null;
    final picks = await _askModels(q);
    if (picks != null && picks.isNotEmpty) {
      // Resolve every AI title to a REAL movie on TMDB, in parallel.
      final resolved = await Future.wait(picks.map(_resolve));
      final out = <TmdbMovie>[];
      final seen = <int>{};
      for (final m in resolved) {
        if (m != null && seen.add(m.id)) out.add(m);
      }
      if (out.isNotEmpty) return out;
    }

    // Smart instant fallback: search TMDB with taste keywords & genre intent
    try {
      final qLower = q.toLowerCase();
      DiscoverFilter? matchFilter;
      for (final f in kDiscoverFilters) {
        if (f.key != 'trending' &&
            f.key != 'upcoming' &&
            qLower.contains(f.label.toLowerCase())) {
          matchFilter = f;
          break;
        }
      }
      if (matchFilter != null) {
        final res = await tmdb.browse(matchFilter);
        if (res.items.isNotEmpty) return res.items.take(10).toList();
      }
      final searchRes = await tmdb.searchMulti(q);
      if (searchRes.items.isNotEmpty) {
        return searchRes.items.take(10).toList();
      }
      final trending = await tmdb.browse(kDiscoverFilters.first);
      if (trending.items.isNotEmpty) {
        return trending.items.take(8).toList();
      }
    } catch (_) {}

    return null;
  }

  /// Walks the same free-model fallback chain as the movie Q&A.
  Future<List<AiTitlePick>?> _askModels(String q) async {
    if (kOpenRouterApiKey.isEmpty) return null;
    for (final model in kOpenRouterModels) {
      try {
        final req = await _http.postUrl(Uri.parse(_url));
        req.headers.set('content-type', 'application/json');
        req.headers.set('authorization', 'Bearer $kOpenRouterApiKey');
        req.headers.set('x-title', 'Max Player');
        req.write(jsonEncode(openRouterChatBody(
          model: model,
          system: kAiSuggestSystemPrompt,
          question: 'I want: $q',
        )));
        final res = await req.close().timeout(const Duration(seconds: 8));
        if (res.statusCode != 200) {
          await res.drain<void>();
          continue; // rate-limited / model down -> next in the chain
        }
        final text =
            parseOpenRouterAnswer(await res.transform(utf8.decoder).join());
        if (text == null) continue;
        final picks = parseAiSuggestionJson(text);
        if (picks.isNotEmpty) return picks;
      } catch (_) {
        // network blip for this model -> try the next one
      }
    }
    return null;
  }

  /// Finds the best-matching REAL movie for an AI title: exact year wins,
  /// otherwise the top search hit (TMDB ranks those well).
  Future<TmdbMovie?> _resolve(AiTitlePick pick) async {
    try {
      final page = await tmdb.searchMovies(pick.title);
      if (page.items.isEmpty) return null;
      if (pick.year != null) {
        for (final m in page.items) {
          if (m.year == pick.year) return m;
        }
      }
      return page.items.first;
    } catch (_) {
      return null;
    }
  }
}
