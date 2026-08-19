import 'dart:convert';
import 'dart:io';

/// TMDB API key, injected at build time:
/// `flutter build ... --dart-define=TMDB_API_KEY=<key>`.
/// The value lives in Codemagic environment variables, never in the repo.
/// When it is empty (local/dev builds) ALL client calls return empty
/// results and the Discover screen shows its setup note - nothing crashes.
const String kTmdbApiKey = String.fromEnvironment('TMDB_API_KEY');

/// One movie row from TMDB (trending / discover / detail).
class TmdbMovie {
  final int id;
  final String title;
  final int? year;

  /// TMDB user score 0..10 (NOT IMDb - copying IMDb breaks their terms;
  /// TMDB is the licensed, Play-safe source. UI credit: "via TMDB").
  final double rating;
  final String? posterPath;
  final String? backdropPath;
  final String overview;

  /// Filled only by the detail call (the official YouTube trailer KEY).
  final String? trailerKey;

  const TmdbMovie({
    required this.id,
    required this.title,
    required this.rating,
    this.year,
    this.posterPath,
    this.backdropPath,
    this.overview = '',
    this.trailerKey,
  });

  TmdbMovie copyWith({String? trailerKey}) => TmdbMovie(
        id: id,
        title: title,
        rating: rating,
        year: year,
        posterPath: posterPath,
        backdropPath: backdropPath,
        overview: overview,
        trailerKey: trailerKey ?? this.trailerKey,
      );
}

/// "7.834" -> "7.8" (badge text). Pure for tests.
String tmdbRatingText(double rating) => rating.toStringAsFixed(1);

/// Full poster URL for a TMDB `poster_path` (w342 grid / w500 detail).
String tmdbPosterUrl(String? path, {bool big = false}) => (path == null || path.isEmpty)
    ? ''
    : 'https://image.tmdb.org/t/p/${big ? 'w500' : 'w342'}$path';

double? _numToDouble(Object? v) =>
    v is num ? v.toDouble() : double.tryParse('$v');

TmdbMovie? _movieFromMap(Object? e) {
  if (e is! Map) return null;
  final title = '${e['title'] ?? e['name'] ?? ''}'.trim();
  if (title.isEmpty) return null;
  final date = '${e['release_date'] ?? ''}';
  final year = date.length >= 4 ? int.tryParse(date.substring(0, 4)) : null;
  final poster = '${e['poster_path'] ?? ''}';
  final backdrop = '${e['backdrop_path'] ?? ''}';
  return TmdbMovie(
    id: e['id'] is num ? (e['id'] as num).toInt() : 0,
    title: title,
    year: year,
    rating: _numToDouble(e['vote_average']) ?? 0,
    posterPath: poster.isEmpty ? null : poster,
    backdropPath: backdrop.isEmpty ? null : backdrop,
    overview: '${e['overview'] ?? ''}',
  );
}

/// Parses a trending/discover LIST response. Never throws: any garbage
/// row is skipped, garbage body -> empty list. Pure for tests.
List<TmdbMovie> parseTmdbList(String jsonBody) {
  try {
    final decoded = jsonDecode(jsonBody);
    if (decoded is! Map) return const [];
    final results = decoded['results'];
    if (results is! List) return const [];
    final out = <TmdbMovie>[];
    for (final e in results) {
      final m = _movieFromMap(e);
      if (m != null) out.add(m);
    }
    return out;
  } catch (_) {
    return const [];
  }
}

/// Parses a DETAIL response (with append_to_response=videos).
TmdbMovie? parseTmdbDetail(String jsonBody) {
  try {
    final decoded = jsonDecode(jsonBody);
    if (decoded is! Map) return null;
    final base = _movieFromMap(decoded);
    if (base == null) return null;
    return base.copyWith(trailerKey: pickTrailerKey(decoded['videos']));
  } catch (_) {
    return null;
  }
}

/// Picks the best trailer's YouTube key from a `videos` object:
/// official YouTube Trailer > any YouTube Trailer > any YouTube video.
/// Pure for tests. Returns null when there is no YouTube video at all.
String? pickTrailerKey(Object? videos) {
  if (videos is! Map) return null;
  final results = videos['results'];
  if (results is! List) return null;
  final yt = [
    for (final v in results)
      if (v is Map && v['site'] == 'YouTube') v,
  ];
  if (yt.isEmpty) return null;
  for (final v in yt) {
    if (v['type'] == 'Trailer' && v['official'] == true) {
      final k = '${v['key'] ?? ''}';
      if (k.isNotEmpty) return k;
    }
  }
  for (final v in yt) {
    if (v['type'] == 'Trailer') {
      final k = '${v['key'] ?? ''}';
      if (k.isNotEmpty) return k;
    }
  }
  final k = '${yt.first['key'] ?? ''}';
  return k.isEmpty ? null : k;
}

/// v43: tiny TMDB client for the Discover screen. Plain dart:io HTTP -
/// zero new dependencies. Every response (list, detail, posters handled
/// by TmdbImage) is cached on disk for 24h, so once loaded the section
/// works offline and refreshes ITSELF in the background on the next open
/// after the cache expires - the "automatically updated library".
class TmdbClient {
  static const String _host = 'api.themoviedb.org';

  /// Directory used for the 24h disk cache (from NativeBridge.cacheDirPath).
  Directory? cacheDir;

  Future<String> _get(Uri uri) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 5);
    try {
      final req = await client.getUrl(uri);
      final res = await req.close().timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) {
        throw HttpException('TMDB status ${res.statusCode}');
      }
      return await res.transform(utf8.decoder).join();
    } finally {
      client.close(force: true);
    }
  }

  File? _cacheFile(String name) {
    final dir = cacheDir;
    if (dir == null) return null;
    return File('${dir.path}${Platform.pathSeparator}$name');
  }

  /// Fresh cache (<= ttl) -> network (write cache) -> stale cache -> null.
  Future<String?> _fetch(String cacheName, Uri uri,
      {Duration ttl = const Duration(hours: 24)}) async {
    final f = _cacheFile(cacheName);
    try {
      if (f != null && await f.exists()) {
        final age = DateTime.now().difference(await f.lastModified());
        if (age <= ttl) return await f.readAsString();
      }
    } catch (_) {}
    try {
      final body = await _get(uri);
      try {
        await f?.writeAsString(body, flush: true);
      } catch (_) {
        // Caching is best-effort - never fail the request because of it.
      }
      return body;
    } catch (_) {
      try {
        if (f != null && await f.exists()) return await f.readAsString();
      } catch (_) {}
      return null;
    }
  }

  /// The weekly trending movies. [language] '' = all, 'hi' = Bollywood
  /// etc., 'en' = Hollywood etc. (via TMDB discover popularity).
  Future<List<TmdbMovie>> trending({String language = '', bool force = false}) async {
    if (kTmdbApiKey.isEmpty) return const [];
    final Uri uri;
    final String cacheName;
    if (language.isEmpty) {
      cacheName = 'tmdb_trending_all.json';
      uri = Uri.https(_host, '/3/trending/movie/week',
          {'api_key': kTmdbApiKey, 'language': 'en-US'});
    } else {
      cacheName = 'tmdb_trending_$language.json';
      uri = Uri.https(_host, '/3/discover/movie', {
        'api_key': kTmdbApiKey,
        'language': 'en-US',
        'with_original_language': language,
        'sort_by': 'popularity.desc',
        'include_adult': 'false',
        'vote_count.gte': '25',
      });
    }
    final body = await _fetch(cacheName, uri,
        ttl: force ? Duration.zero : const Duration(hours: 24));
    return body == null ? const [] : parseTmdbList(body);
  }

  /// Detail incl. the official trailer key (cached alongside).
  Future<TmdbMovie?> details(int id, {bool force = false}) async {
    if (kTmdbApiKey.isEmpty) return null;
    final uri = Uri.https(_host, '/3/movie/$id', {
      'api_key': kTmdbApiKey,
      'language': 'en-US',
      'append_to_response': 'videos',
    });
    final body = await _fetch('tmdb_movie_$id.json', uri,
        ttl: force ? Duration.zero : const Duration(hours: 24));
    return body == null ? null : parseTmdbDetail(body);
  }
}
