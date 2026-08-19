/// v43 Discover: the TMDB client.
///
/// Why TMDB and not IMDb: IMDb has no free/public API and scraping it breaks
/// their terms (and dies on every layout change). TMDB gives posters,
/// backdrops, ratings, cast, genres AND the YouTube trailer keys from one
/// free key. Attribution requirement is honoured in the About sheet:
/// "This product uses the TMDB API but is not endorsed or certified by TMDB."
///
/// No new package: plain `dart:io` HttpClient + `dart:convert`, matching the
/// zero-dependency style of cast/cast_file_server.dart.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/movie.dart';

/// Injected at build time (Codemagic: --dart-define=TMDB_KEY=...). Never
/// committed. Empty => the Discover tab shows a "not configured" card
/// instead of failing requests.
const String kTmdbApiKey = String.fromEnvironment('TMDB_KEY');

/// Anything that went wrong talking to TMDB, in words a user can read.
class TmdbException implements Exception {
  final String message;
  final int? statusCode;

  const TmdbException(this.message, {this.statusCode});

  /// True for "your phone is offline" style failures - the UI then falls
  /// back to the cached rails instead of showing a red error.
  bool get isOffline => statusCode == null;

  @override
  String toString() => message;
}

/// One page of a TMDB list response.
class MoviePage {
  final List<Movie> movies;
  final int page;
  final int totalPages;
  final int totalResults;

  const MoviePage({
    this.movies = const [],
    this.page = 1,
    this.totalPages = 1,
    this.totalResults = 0,
  });

  factory MoviePage.fromJson(Map<String, Object?> j) {
    final results = asMapList(j['results']);
    return MoviePage(
      movies: [
        for (final m in results)
          if (asInt(m['id']) > 0) Movie.fromJson(m),
      ],
      page: asInt(j['page']) == 0 ? 1 : asInt(j['page']),
      totalPages: asInt(j['total_pages']) == 0 ? 1 : asInt(j['total_pages']),
      totalResults: asInt(j['total_results']),
    );
  }

  bool get hasMore => page < totalPages;
  bool get isEmpty => movies.isEmpty;
}

/// 'yyyy-MM-dd' for TMDB's date filters.
String tmdbDate(DateTime d) {
  final y = d.year.toString().padLeft(4, '0');
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '$y-$m-$day';
}

/// A from..to release-date filter. Computed from `DateTime.now()` on every
/// call - THIS is what makes "new movies" appear by themselves: the window
/// slides with the calendar, so the same rail returns different titles next
/// week without shipping an app update.
class DateWindow {
  final String from;
  final String to;

  const DateWindow(this.from, this.to);
}

/// "Released recently" - the last [days] days up to today.
DateWindow recentWindow(DateTime now, {int days = 75}) =>
    DateWindow(tmdbDate(now.subtract(Duration(days: days))), tmdbDate(now));

/// "Coming soon" - tomorrow up to [days] ahead.
DateWindow upcomingWindow(DateTime now, {int days = 150}) => DateWindow(
      tmdbDate(now.add(const Duration(days: 1))),
      tmdbDate(now.add(Duration(days: days))),
    );

class TmdbApi {
  static const String apiHost = 'api.themoviedb.org';
  static const String imageBase = 'https://image.tmdb.org/t/p/';

  /// TMDB genre ids we expose as chips (stable, documented values).
  static const Map<String, int> genreIds = <String, int>{
    'Action': 28,
    'Adventure': 12,
    'Animation': 16,
    'Comedy': 35,
    'Crime': 80,
    'Documentary': 99,
    'Drama': 18,
    'Family': 10751,
    'Fantasy': 14,
    'Horror': 27,
    'Mystery': 9648,
    'Romance': 10749,
    'Science Fiction': 878,
    'Thriller': 53,
    'War': 10752,
    'Western': 37,
  };

  final String apiKey;

  /// Titles/overviews language. 'en-IN' = English text with Indian context,
  /// so Bollywood titles read "Jawan" rather than "जवान".
  final String language;

  /// Release/cinema region for now-playing and date filters.
  final String region;

  final Duration timeout;

  const TmdbApi({
    this.apiKey = kTmdbApiKey,
    this.language = 'en-IN',
    this.region = 'IN',
    this.timeout = const Duration(seconds: 20),
  });

  bool get configured => apiKey.trim().isNotEmpty;

  TmdbApi copyWith({String? language, String? region}) => TmdbApi(
        apiKey: apiKey,
        language: language ?? this.language,
        region: region ?? this.region,
        timeout: timeout,
      );

  /// Full image URL. Sizes are deliberately small - our users are on
  /// 2 GB-RAM phones: w342 posters, w780 backdrops, w185 faces.
  static String? imageUrl(String? path, {String size = 'w342'}) {
    if (path == null || path.isEmpty) return null;
    final p = path.startsWith('/') ? path : '/$path';
    return '$imageBase$size$p';
  }

  /// Builds a signed request URI. Pure + testable (no network involved).
  Uri buildUri(String path, [Map<String, String> query = const {}]) {
    final params = <String, String>{
      'api_key': apiKey,
      'language': language,
      'include_adult': 'false',
    };
    params.addAll(query);
    return Uri.https(apiHost, '/3$path', params);
  }

  Future<Map<String, Object?>> _getJson(Uri uri) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12)
      ..userAgent = 'MaxPlayer/1.0 (Android)';
    try {
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(timeout);
      final body = await response
          .transform(const Utf8Decoder(allowMalformed: true))
          .join();
      if (response.statusCode == 401) {
        throw const TmdbException(
          'The movie service key is not valid for this build.',
          statusCode: 401,
        );
      }
      if (response.statusCode == 429) {
        throw const TmdbException(
          'Too many requests right now - try again in a moment.',
          statusCode: 429,
        );
      }
      if (response.statusCode != 200) {
        throw TmdbException(
          'Movie service error (${response.statusCode}).',
          statusCode: response.statusCode,
        );
      }
      final decoded = jsonDecode(body);
      if (decoded is! Map) {
        throw const TmdbException('Unexpected reply from the movie service.',
            statusCode: 200);
      }
      return decoded.cast<String, Object?>();
    } on TmdbException {
      rethrow;
    } on SocketException {
      throw const TmdbException('No internet connection.');
    } on HandshakeException {
      throw const TmdbException('Secure connection failed.');
    } on TimeoutException {
      throw const TmdbException('The movie service took too long to answer.');
    } on FormatException {
      throw const TmdbException('Could not read the movie service reply.',
          statusCode: 200);
    } finally {
      client.close(force: true);
    }
  }

  /// Raw JSON for a path - used by the cache layer, which stores exactly
  /// what the API returned.
  Future<Map<String, Object?>> fetchJson(
    String path, [
    Map<String, String> query = const {},
  ]) {
    if (!configured) {
      return Future<Map<String, Object?>>.error(
        const TmdbException('Movie catalogue is not configured in this build.',
            statusCode: 0),
      );
    }
    return _getJson(buildUri(path, query));
  }

  // ---------------------------------------------------------------------
  // Catalogue queries. Every one of them is a LIVE query: TMDB decides what
  // is trending/new today, so the app never ships a hardcoded movie list.
  // ---------------------------------------------------------------------

  /// /trending/movie/{day|week} - recomputed by TMDB continuously.
  Future<MoviePage> trending({String window = 'week', int page = 1}) async =>
      MoviePage.fromJson(
        await fetchJson('/trending/movie/$window', {'page': '$page'}),
      );

  /// The workhorse. `sortBy` defaults to popularity; `minVotes` keeps junk
  /// out of rating-sorted rails.
  Future<MoviePage> discover({
    String? originalLanguage,
    List<int> genres = const [],
    String sortBy = 'popularity.desc',
    DateWindow? window,
    int minVotes = 0,
    double? minRating,
    bool useRegion = false,
    int page = 1,
  }) async {
    final q = <String, String>{
      'sort_by': sortBy,
      'page': '$page',
      'include_video': 'false',
      'with_release_type': '2|3',
    };
    if (originalLanguage != null && originalLanguage.isNotEmpty) {
      q['with_original_language'] = originalLanguage;
    }
    if (genres.isNotEmpty) {
      q['with_genres'] = genres.join(',');
    }
    if (window != null) {
      q['primary_release_date.gte'] = window.from;
      q['primary_release_date.lte'] = window.to;
    }
    if (minVotes > 0) q['vote_count.gte'] = '$minVotes';
    if (minRating != null) q['vote_average.gte'] = minRating.toString();
    if (useRegion) q['region'] = region;
    return MoviePage.fromJson(await fetchJson('/discover/movie', q));
  }

  /// What is in cinemas in [region] right now.
  Future<MoviePage> nowPlaying({int page = 1}) async => MoviePage.fromJson(
        await fetchJson(
            '/movie/now_playing', {'page': '$page', 'region': region}),
      );

  Future<MoviePage> topRated({int page = 1}) async => MoviePage.fromJson(
        await fetchJson('/movie/top_rated', {'page': '$page'}),
      );

  Future<MoviePage> popular({int page = 1}) async => MoviePage.fromJson(
        await fetchJson('/movie/popular', {'page': '$page', 'region': region}),
      );

  Future<MoviePage> search(String query, {int page = 1}) async {
    final q = query.trim();
    if (q.isEmpty) return const MoviePage();
    return MoviePage.fromJson(
      await fetchJson('/search/movie', {'query': q, 'page': '$page'}),
    );
  }

  Future<MoviePage> similar(int movieId, {int page = 1}) async =>
      MoviePage.fromJson(
        await fetchJson('/movie/$movieId/similar', {'page': '$page'}),
      );

  /// Everything the detail screen needs in ONE request (trailers included).
  Future<MovieDetails> details(int movieId) async => MovieDetails.fromJson(
        await fetchJson('/movie/$movieId', {
          'append_to_response': 'videos,credits,external_ids,similar',
          // Ask for English trailers too: many Indian titles only tag their
          // trailer as en-US, and an empty trailer list looks broken.
          'include_video_language': 'en,hi,null',
        }),
      );
}
