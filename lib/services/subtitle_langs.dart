import 'dart:convert';
import 'dart:io';

/// OpenSubtitles API key, injected at build time:
/// `flutter build ... --dart-define=OPENSUBTITLES_API_KEY=<key>`.
/// Free consumer key from opensubtitles.com (profile -> API consumers).
/// When it is empty, the detail sheet's subtitle row simply hides.
const String kOpenSubtitlesApiKey =
    String.fromEnvironment('OPENSUBTITLES_API_KEY');

/// Parses an OpenSubtitles /subtitles search response into the sorted,
/// unique list of language CODES that have REAL downloadable subtitles
/// for the movie. Never throws; Pure for tests.
List<String> parseOpenSubLanguages(String jsonBody) {
  try {
    final decoded = jsonDecode(jsonBody);
    if (decoded is! Map) return const [];
    final data = decoded['data'];
    if (data is! List) return const [];
    final langs = <String>{};
    for (final e in data) {
      if (e is! Map) continue;
      final attrs = e['attributes'];
      if (attrs is! Map) continue;
      final lang = '${attrs['language'] ?? ''}'.trim();
      if (lang.isNotEmpty) langs.add(lang);
    }
    final out = langs.toList()..sort();
    return out;
  } catch (_) {
    return const [];
  }
}

/// v47: REAL subtitle availability per movie (replaces the old promo
/// line). One tiny search call, cached 24h next to the TMDB caches.
class OpenSubtitlesClient {
  static const String _host = 'api.opensubtitles.com';

  /// Directory used for the 24h disk cache (from NativeBridge.cacheDirPath).
  Directory? cacheDir;

  static final HttpClient _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 10)
    ..idleTimeout = const Duration(seconds: 8);

  static Future<String> _get(Uri uri) async {
    final req = await _http.getUrl(uri);
    req.headers.set('Api-Key', kOpenSubtitlesApiKey);
    req.headers.set('User-Agent', 'MaxPlayer 1.0');
    final res = await req.close().timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) {
      throw HttpException('OpenSubtitles status ${res.statusCode}');
    }
    return await res.transform(utf8.decoder).join();
  }

  /// Language codes with real subtitles for TMDB movie [tmdbId].
  /// Empty key / failure / nothing found -> empty list (UI hides).
  Future<List<String>> languagesFor(int tmdbId) async {
    if (kOpenSubtitlesApiKey.isEmpty || tmdbId <= 0) return const [];
    final f = cacheDir == null
        ? null
        : File('${cacheDir!.path}${Platform.pathSeparator}osub_$tmdbId.json');
    try {
      if (f != null && await f.exists()) {
        final age = DateTime.now().difference(await f.lastModified());
        if (age <= const Duration(hours: 24)) {
          return parseOpenSubLanguages(await f.readAsString());
        }
      }
    } catch (_) {}
    try {
      final body = await _get(Uri.https(_host, '/api/v1/subtitles', {
        'tmdb_id': '$tmdbId',
        'per_page': '50',
      }));
      try {
        await f?.writeAsString(body, flush: true);
      } catch (_) {}
      return parseOpenSubLanguages(body);
    } catch (_) {
      return const [];
    }
  }
}
