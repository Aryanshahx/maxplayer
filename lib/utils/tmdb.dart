import 'dart:convert';
import 'dart:io';

import 'config.dart';

/// Tiny TMDB client over dart:io (zero new deps).
/// Fetches trending movies; parsing is a pure function (unit-tested).

class TmdbMovie {
  const TmdbMovie({
    required this.id,
    required this.title,
    required this.year,
    required this.rating,
    required this.overview,
    required this.posterUrl,
  });

  final int id;
  final String title;
  final String year;
  final double rating;
  final String overview;
  final String posterUrl;
}

String _poster(String? path) =>
    path == null ? '' : 'https://image.tmdb.org/t/p/w342$path';

/// Pure parser (unit-tested): TMDB trending JSON -> movies.
List<TmdbMovie> parseTrending(String body) {
  final json = jsonDecode(body) as Map<String, dynamic>;
  final results = (json['results'] as List?) ?? const [];
  return [
    for (final raw in results)
      if (raw is Map)
        TmdbMovie(
          id: (raw['id'] as num?)?.toInt() ?? 0,
          title: (raw['title'] ?? raw['name'] ?? 'Untitled') as String,
          year: ((raw['release_date'] ?? '') as String)
              .split('-')
              .firstWhere((e) => e.isNotEmpty, orElse: () => ''),
          rating: ((raw['vote_average'] as num?) ?? 0).toDouble(),
          overview: (raw['overview'] ?? '') as String,
          posterUrl: _poster(raw['poster_path'] as String?),
        ),
  ];
}

Future<List<TmdbMovie>> fetchTrending({String language = 'en-US'}) async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 10);
  try {
    final req = await client.getUrl(Uri.parse(
        'https://api.themoviedb.org/3/trending/movie/week?language=$language'));
    req.headers
        .set(HttpHeaders.authorizationHeader, 'Bearer ${AppConfig.tmdbToken}');
    req.headers.set(HttpHeaders.acceptHeader, 'application/json');
    final res = await req.close().timeout(const Duration(seconds: 15));
    final body = await utf8.decoder.bind(res).join();
    if (res.statusCode != 200) {
      throw HttpException('tmdb_http_${res.statusCode}');
    }
    return parseTrending(body);
  } finally {
    client.close();
  }
}
