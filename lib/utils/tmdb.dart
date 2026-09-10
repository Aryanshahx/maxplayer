import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'config.dart';
import 'crash_log.dart';

/// TMDB v3-over-v4 client (Bearer JWT, read-only). All parsing is PURE
/// (unit-tested); the network methods never throw (return null/[]).
class TmdbMovie {
  const TmdbMovie({
    required this.id,
    required this.title,
    required this.year,
    required this.rating,
    required this.posterUrl,
    this.overview = '',
  });

  final int id;
  final String title;
  final String year;
  final double rating;
  final String posterUrl;
  final String overview;
}

class TmdbCastEntry {
  const TmdbCastEntry({
    required this.name,
    required this.character,
    this.photoUrl = '',
  });

  final String name;
  final String character;
  final String photoUrl; // w185 profile or ''
}

class TmdbReviewEntry {
  const TmdbReviewEntry({
    required this.author,
    required this.ratingText,
    required this.content,
  });

  final String author;
  final String ratingText; // "" if no rating
  final String content;
}

class TmdbGenreChip {
  const TmdbGenreChip(this.name);
  final String name;
}

class TmdbMovieDetail {
  const TmdbMovieDetail({
    required this.id,
    required this.title,
    required this.originalTitle,
    required this.year,
    required this.rating,
    required this.votes,
    required this.releaseDate,
    required this.runtimeMinutes,
    required this.overview,
    required this.tagline,
    required this.posterUrl,
    required this.backdropUrl,
    required this.budget,
    required this.revenue,
    required this.studios,
    required this.countries,
    required this.languages,
    required this.genres,
  });

  final int id;
  final String title;
  final String originalTitle;
  final String year;
  final double rating;
  final int votes;
  final String releaseDate;
  final int runtimeMinutes;
  final String overview;
  final String tagline;
  final String posterUrl;
  final String backdropUrl;
  final int budget;
  final int revenue;
  final String studios; // "Marvel · Pascal"
  final String countries; // "United States"
  final String languages; // "English, Hindi"
  final List<TmdbGenreChip> genres;

  /// "2h 25m" style runtime.
  String get runtimeLabel {
    if (runtimeMinutes <= 0) return '';
    final h = runtimeMinutes ~/ 60;
    final m = runtimeMinutes % 60;
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }
}

// ---------------- pure parsers ----------------

String _poster(Object? path, {String size = 'w342'}) =>
    path is String && path.isNotEmpty
        ? 'https://image.tmdb.org/t/p/$size$path'
        : '';

/// Trending/search/upcoming/discover lists all share the {results: [...]}
/// shape — one parser serves every category.
List<TmdbMovie> parseTrending(String body) {
  try {
    final decoded = jsonDecode(body);
    final results =
        decoded is Map ? decoded['results'] : null;
    if (results is! List) return [];
    return [
      for (final m in results.whereType<Map>())
        TmdbMovie(
          id: (m['id'] as num?)?.toInt() ?? 0,
          title: (m['title'] ?? m['name'] ?? 'Untitled') as String,
          year: ((m['release_date'] ?? m['first_air_date'] ?? '') as String)
                  .length >=
              4
              ? ((m['release_date'] ?? m['first_air_date']) as String)
                  .substring(0, 4)
              : '',
          rating: ((m['vote_average'] as num?) ?? 0).toDouble(),
          overview: (m['overview'] ?? '') as String,
          posterUrl: _poster(m['poster_path']),
        ),
    ];
  } catch (_) {
    return [];
  }
}

/// total_results from a listing response — "48,212 titles".
int parseTotalResults(String body) {
  try {
    final decoded = jsonDecode(body);
    return decoded is Map && decoded['total_results'] is num
        ? (decoded['total_results'] as num).toInt()
        : 0;
  } catch (_) {
    return 0;
  }
}

List<String> parseGenreNames(String body) {
  try {
    final decoded = jsonDecode(body);
    final g = decoded is Map ? decoded['genres'] : null;
    if (g is! List) return [];
    return [
      for (final e in g.whereType<Map>()) '${e['name']}',
    ];
  } catch (_) {
    return [];
  }
}

TmdbMovieDetail? parseMovieDetail(String body) {
  try {
    final m = jsonDecode(body);
    if (m is! Map) return null;
    final rd = (m['release_date'] ?? '') as String;
    return TmdbMovieDetail(
      id: (m['id'] as num?)?.toInt() ?? 0,
      title: (m['title'] ?? 'Untitled') as String,
      originalTitle: (m['original_title'] ?? '') as String,
      year: rd.length >= 4 ? rd.substring(0, 4) : '',
      rating: ((m['vote_average'] as num?) ?? 0).toDouble(),
      votes: (m['vote_count'] as num?)?.toInt() ?? 0,
      releaseDate: rd,
      runtimeMinutes: (m['runtime'] as num?)?.toInt() ?? 0,
      overview: (m['overview'] ?? '') as String,
      tagline: (m['tagline'] ?? '') as String,
      posterUrl: _poster(m['poster_path']),
      backdropUrl: _poster(m['backdrop_path'], size: 'w780'),
      budget: (m['budget'] as num?)?.toInt() ?? 0,
      revenue: (m['revenue'] as num?)?.toInt() ?? 0,
      studios: ((m['production_companies'] as List?) ?? [])
          .whereType<Map>()
          .map((e) => '${e['name']}')
          .join(' · '),
      countries: ((m['production_countries'] as List?) ?? [])
          .whereType<Map>()
          .map((e) => '${e['name']}')
          .join(', '),
      languages: ((m['spoken_languages'] as List?) ?? [])
          .whereType<Map>()
          .map((e) => '${e['english_name']}')
          .join(', '),
      genres: [
        for (final g in ((m['genres'] as List?) ?? []).whereType<Map>())
          TmdbGenreChip('${g['name']}'),
      ],
    );
  } catch (_) {
    return null;
  }
}

/// credits: director (crew) + top cast with photo URLs.
({String director, List<TmdbCastEntry> cast}) parseCredits(String body) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is! Map) return (director: '', cast: []);
    String director = '';
    final crew = decoded['crew'];
    if (crew is List) {
      for (final e in crew.whereType<Map>()) {
        if (e['job'] == 'Director') {
          director = '${e['name']}';
          break;
        }
      }
    }
    final cast = decoded['cast'];
    final list = <TmdbCastEntry>[];
    if (cast is List) {
      for (final e in cast.whereType<Map>().take(10)) {
        list.add(TmdbCastEntry(
          name: '${e['name']}',
          character: '${e['character'] ?? ''}',
          photoUrl: _poster(e['profile_path'], size: 'w185'),
        ));
      }
    }
    return (director: director, cast: list);
  } catch (_) {
    return (director: '', cast: []);
  }
}

/// videos: best YouTube trailer/teaser key (null if none).
String? parseTrailerKey(String body) {
  try {
    final decoded = jsonDecode(body);
    final results =
        decoded is Map ? decoded['results'] : null;
    if (results is! List) return null;
    String? teaser;
    for (final v in results.whereType<Map>()) {
      if (v['site'] != 'YouTube' || v['key'] == null) continue;
      if (v['type'] == 'Trailer') return '${v['key']}';
      teaser ??= '${v['key']}';
    }
    return teaser;
  } catch (_) {
    return null;
  }
}

List<TmdbReviewEntry> parseReviews(String body) {
  try {
    final decoded = jsonDecode(body);
    final results =
        decoded is Map ? decoded['results'] : null;
    if (results is! List) return [];
    return [
      for (final r in results.whereType<Map>().take(5))
        TmdbReviewEntry(
          author: '${r['author']}',
          ratingText: r['author_details'] is Map &&
                  (r['author_details'] as Map)['rating'] != null
              ? '${(r['author_details'] as Map)['rating']} / 10'
              : '',
          content: '${r['content'] ?? ''}',
        ),
    ];
  } catch (_) {
    return [];
  }
}

/// images.backdrops -> up to 3 w780 URLs.
List<String> parseBackdrops(String body) {
  try {
    final decoded = jsonDecode(body);
    final bd = decoded is Map ? decoded['backdrops'] : null;
    if (bd is! List) return [];
    return [
      for (final e in bd.whereType<Map>().take(3))
        _poster(e['file_path'], size: 'w780'),
    ];
  } catch (_) {
    return [];
  }
}

// ---------------- network (never throws) ----------------

const tmdbBase = 'https://api.themoviedb.org/3';

Future<String?> _getBody(String path) async {
  if (AppConfig.tmdbToken.isEmpty) return null;
  try {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
    final req = await client
        .getUrl(Uri.parse('$tmdbBase$path'))
        .timeout(const Duration(seconds: 12));
    req.headers.set('Authorization', 'Bearer ${AppConfig.tmdbToken}');
    req.headers.set('content-type', 'application/json;charset=utf-8');
    final res = await req.close().timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) {
      CrashLog.crumb('tmdb.http_${res.statusCode}', {'path': path});
      return null;
    }
    return await res
        .transform(utf8.decoder)
        .join()
        .timeout(const Duration(seconds: 12));
  } catch (e) {
    CrashLog.error('tmdb.fetch_failed', e, {'path': path});
    return null;
  }
}

/// Categories mapped to TMDB endpoints (Discover screen chips).
const tmdbCategories = <String, String>{
  'Trending': '/trending/movie/week',
  'Upcoming': '/movie/upcoming?region=IN',
  'Animation': '/discover/movie?with_genres=16&sort_by=popularity.desc',
  'Hollywood':
      '/discover/movie?with_original_language=en&sort_by=popularity.desc',
  'Bollywood':
      '/discover/movie?with_original_language=hi&sort_by=popularity.desc',
};

/// One page of a category listing; [body] is passed back raw so callers
/// can read total_results.
Future<({List<TmdbMovie> movies, int total, bool hasMore})>
    fetchCategoryPage(String categoryPath, int page) async {
  final sep = categoryPath.contains('?') ? '&' : '?';
  final body = await _getBody('$categoryPath${sep}page=$page');
  if (body == null) {
    return (movies: <TmdbMovie>[], total: 0, hasMore: false);
  }
  final movies = parseTrending(body);
  final total = parseTotalResults(body);
  return (
    movies: movies,
    total: total,
    hasMore: page < 500 && movies.isNotEmpty,
  );
}

Future<({List<TmdbMovie> movies, int total})> searchMovies(
    String query, int page) async {
  final body = await _getBody(
      '/search/movie?query=${Uri.encodeQueryComponent(query)}&include_adult=false&page=$page');
  if (body == null) return (movies: <TmdbMovie>[], total: 0);
  return (movies: parseTrending(body), total: parseTotalResults(body));
}

Future<TmdbMovieDetail?> fetchMovieDetail(int id) async {
  final body = await _getBody('/movie/$id');
  if (body == null) return null;
  return parseMovieDetail(body);
}

Future<({String director, List<TmdbCastEntry> cast})> fetchCredits(
    int id) async {
  final body = await _getBody('/movie/$id/credits');
  if (body == null) return (director: '', cast: <TmdbCastEntry>[]);
  return parseCredits(body);
}

Future<String?> fetchTrailerKey(int id) async {
  final body = await _getBody('/movie/$id/videos');
  if (body == null) return null;
  return parseTrailerKey(body);
}

Future<List<TmdbReviewEntry>> fetchReviews(int id) async {
  final body = await _getBody('/movie/$id/reviews');
  if (body == null) return [];
  return parseReviews(body);
}

Future<List<String>> fetchBackdrops(int id) async {
  final body = await _getBody('/movie/$id/images');
  if (body == null) return [];
  return parseBackdrops(body);
}

/// Legacy single-shot used by the home banner (kept API-compatible).
Future<List<TmdbMovie>> fetchTrending() async {
  final page = await fetchCategoryPage(tmdbCategories['Trending']!, 1);
  return page.movies;
}
