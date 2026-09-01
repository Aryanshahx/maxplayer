import 'dart:convert';
import 'dart:io';

/// TMDB API key, injected at build time:
/// `flutter build ... --dart-define=TMDB_API_KEY=<key>`.
const String _kDefaultTmdbKey = '2dca580c2a14b55200e784d157207b4d';
const String kTmdbApiKey =
    String.fromEnvironment('TMDB_API_KEY', defaultValue: _kDefaultTmdbKey);

/// One movie row from TMDB (trending / discover / search / detail).
class TmdbMovie {
  final int id;
  final String title;
  final int? year;

  /// TMDB user score 0..10.
  final double rating;
  final String? posterPath;
  final String? backdropPath;
  final String overview;

  /// Filled only by the detail call (the official YouTube trailer KEY).
  final String? trailerKey;

  /// 'movie' or 'tv' (web series).
  final String kind;

  const TmdbMovie({
    required this.id,
    required this.title,
    required this.rating,
    this.year,
    this.posterPath,
    this.backdropPath,
    this.overview = '',
    this.trailerKey,
    this.kind = 'movie',
  });

  TmdbMovie copyWith({String? trailerKey, String? kind}) => TmdbMovie(
        id: id,
        title: title,
        rating: rating,
        year: year,
        posterPath: posterPath,
        backdropPath: backdropPath,
        overview: overview,
        trailerKey: trailerKey ?? this.trailerKey,
        kind: kind ?? this.kind,
      );
}

/// One user-selectable filter chip for the Discover section.
class DiscoverFilter {
  final String key;
  final String label;
  final String language;
  final int? genreId;
  final bool trending;
  final bool upcoming;
  final bool tv;

  const DiscoverFilter({
    required this.key,
    required this.label,
    this.language = '',
    this.genreId,
    this.trending = false,
    this.upcoming = false,
    this.tv = false,
  });
}

const List<DiscoverFilter> kDiscoverFilters = [
  DiscoverFilter(key: 'trending', label: 'Trending', trending: true),
  DiscoverFilter(key: 'upcoming', label: 'Upcoming', upcoming: true),
  DiscoverFilter(key: 'animation', label: 'Animation', genreId: 16),
  DiscoverFilter(key: 'hollywood', label: 'Hollywood', language: 'en'),
  DiscoverFilter(key: 'bollywood', label: 'Bollywood', language: 'hi'),
  DiscoverFilter(key: 'tamil', label: 'Tamil', language: 'ta'),
  DiscoverFilter(key: 'telugu', label: 'Telugu', language: 'te'),
  DiscoverFilter(key: 'action', label: 'Action', genreId: 28),
  DiscoverFilter(key: 'comedy', label: 'Comedy', genreId: 35),
  DiscoverFilter(key: 'drama', label: 'Drama', genreId: 18),
  DiscoverFilter(key: 'horror', label: 'Horror', genreId: 27),
  DiscoverFilter(key: 'romance', label: 'Romance', genreId: 10749),
  DiscoverFilter(key: 'thriller', label: 'Thriller', genreId: 53),
  DiscoverFilter(key: 'scifi', label: 'Sci-Fi', genreId: 878),
];

const List<DiscoverFilter> kSeriesFilters = [
  DiscoverFilter(key: 'tv_hindi', label: 'Hindi', language: 'hi', tv: true),
  DiscoverFilter(key: 'tv_english', label: 'English', language: 'en', tv: true),
  DiscoverFilter(key: 'tv_korean', label: 'K-Drama', language: 'ko', tv: true),
  DiscoverFilter(key: 'tv_anime', label: 'Anime', language: 'ja', tv: true),
];

const List<DiscoverFilter> kAllFilters = [
  ...kDiscoverFilters,
  ...kSeriesFilters,
];

String discoverCacheName(DiscoverFilter f, int page) =>
    'tmdb_disc_${f.key}${f.tv ? '_tv' : ''}_p$page.json';

String tmdbEndpointPath(DiscoverFilter f) => f.trending
    ? (f.tv ? '/3/trending/tv/week' : '/3/trending/movie/week')
    : f.upcoming
        ? '/3/movie/upcoming'
        : (f.tv ? '/3/discover/tv' : '/3/discover/movie');

Map<String, String> tmdbDiscoverQuery(DiscoverFilter f, int page) => {
      'language': 'en-US',
      'page': '$page',
      'include_adult': 'false',
      'sort_by': 'popularity.desc',
      'vote_count.gte': '8',
      if (f.language.isNotEmpty) 'with_original_language': f.language,
      if (f.genreId != null) 'with_genres': '${f.genreId}',
    };

Map<String, String> tmdbSearchQuery(String query, int page) => {
      'language': 'en-US',
      'query': query,
      'include_adult': 'false',
      'page': '$page',
    };

String tmdbSearchCacheName(String query, int page) {
  var words = query.toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), '_');
  if (words.length > 30) words = words.substring(0, 30);
  if (words.isEmpty) words = 'q';
  var h = 0;
  for (final c in query.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return 'tmdb_search_${words}_${h.toRadixString(16)}_p$page.json';
}

class TmdbPage {
  final List<TmdbMovie> items;
  final int page;
  final int totalPages;
  final int totalResults;

  const TmdbPage({
    this.items = const [],
    this.page = 1,
    this.totalPages = 1,
    this.totalResults = 0,
  });
}

/// Cast member representation with profile photo.
class TmdbCastMember {
  final String name;
  final String character;
  final String? profilePath;

  const TmdbCastMember({
    required this.name,
    this.character = '',
    this.profilePath,
  });
}

/// Extra facts from the detail call (append_to_response=videos,credits).
class TmdbDetailExtras {
  final String director;
  final List<String> cast;
  final List<TmdbCastMember> castMembers;
  final int runtimeMinutes;
  final List<String> genres;
  final String tagline;
  final int voteCount;
  final String status;
  final String releaseDate;
  final String originalTitle;
  final int budgetUsd;
  final int revenueUsd;
  final List<String> companies;
  final List<String> countries;
  final String certification;
  final List<String> allLanguages;
  final List<String> spokenLanguages;

  const TmdbDetailExtras({
    this.director = '',
    this.cast = const [],
    this.castMembers = const [],
    this.runtimeMinutes = 0,
    this.genres = const [],
    this.tagline = '',
    this.voteCount = 0,
    this.status = '',
    this.releaseDate = '',
    this.originalTitle = '',
    this.budgetUsd = 0,
    this.revenueUsd = 0,
    this.companies = const [],
    this.countries = const [],
    this.certification = '',
    this.allLanguages = const [],
    this.spokenLanguages = const [],
  });
}

/// One episode of a TV / web series season with rating and duration.
class TmdbEpisode {
  final int episodeNumber;
  final String name;
  final String overview;
  final double rating;
  final int runtimeMinutes;
  final String? stillPath;
  final String? airDate;

  const TmdbEpisode({
    required this.episodeNumber,
    required this.name,
    this.overview = '',
    this.rating = 0.0,
    this.runtimeMinutes = 0,
    this.stillPath,
    this.airDate,
  });
}

/// Full season detail containing episode list, ratings and durations.
class TmdbSeasonDetail {
  final int seasonNumber;
  final String name;
  final double rating;
  final String overview;
  final List<TmdbEpisode> episodes;

  const TmdbSeasonDetail({
    required this.seasonNumber,
    required this.name,
    this.rating = 0.0,
    this.overview = '',
    this.episodes = const [],
  });
}

/// Detail bundle: movie + extras + screenshots + watch info + reviews + seasons.
class TmdbFull {
  final TmdbMovie movie;
  final TmdbDetailExtras extras;
  final List<String> screenshots;
  final TmdbWatchInfo watch;
  final List<TmdbReview> reviews;
  final List<TmdbSeason> seasons;

  const TmdbFull(
    this.movie,
    this.extras, {
    this.screenshots = const [],
    this.watch = const TmdbWatchInfo(),
    this.reviews = const [],
    this.seasons = const [],
  });
}

/// One part (season) of a web series with rating.
class TmdbSeason {
  final int number;
  final String name;
  final int episodes;
  final int? year;
  final double rating;

  const TmdbSeason({
    required this.number,
    required this.name,
    required this.episodes,
    this.year,
    this.rating = 0.0,
  });
}

List<TmdbSeason> parseTmdbSeasons(String jsonBody) {
  try {
    final decoded = jsonDecode(jsonBody);
    if (decoded is! Map) return const [];
    final list = decoded['seasons'];
    if (list is! List) return const [];
    final out = <TmdbSeason>[];
    for (final e in list) {
      if (e is! Map) continue;
      final n = e['season_number'] is num ? (e['season_number'] as num).toInt() : 0;
      final name = '${e['name'] ?? ''}'.trim();
      final eps = e['episode_count'] is num ? (e['episode_count'] as num).toInt() : 0;
      final air = '${e['air_date'] ?? ''}';
      final vote = e['vote_average'] is num ? (e['vote_average'] as num).toDouble() : 0.0;
      out.add(TmdbSeason(
        number: n,
        name: name.isEmpty ? (n == 0 ? 'Specials' : 'Season $n') : name,
        episodes: eps,
        year: air.length >= 4 ? int.tryParse(air.substring(0, 4)) : null,
        rating: vote,
      ));
    }
    return out;
  } catch (_) {
    return const [];
  }
}

TmdbSeasonDetail? parseTmdbSeasonDetail(String jsonBody, {int seasonNumber = 1}) {
  try {
    final decoded = jsonDecode(jsonBody);
    if (decoded is! Map) return null;
    final name = '${decoded['name'] ?? 'Season $seasonNumber'}'.trim();
    final vote = decoded['vote_average'] is num ? (decoded['vote_average'] as num).toDouble() : 0.0;
    final overview = '${decoded['overview'] ?? ''}'.trim();
    final rawEps = decoded['episodes'];
    final episodes = <TmdbEpisode>[];

    if (rawEps is List) {
      for (final ep in rawEps) {
        if (ep is! Map) continue;
        final epNum = ep['episode_number'] is num ? (ep['episode_number'] as num).toInt() : 0;
        final epName = '${ep['name'] ?? 'Episode $epNum'}'.trim();
        final epVote = ep['vote_average'] is num ? (ep['vote_average'] as num).toDouble() : 0.0;
        final epRuntime = ep['runtime'] is num ? (ep['runtime'] as num).toInt() : 0;
        final epOverview = '${ep['overview'] ?? ''}'.trim();
        final epStill = ep['still_path']?.toString();
        final epAir = ep['air_date']?.toString();

        episodes.add(TmdbEpisode(
          episodeNumber: epNum,
          name: epName,
          overview: epOverview,
          rating: epVote,
          runtimeMinutes: epRuntime,
          stillPath: epStill,
          airDate: epAir,
        ));
      }
    }

    return TmdbSeasonDetail(
      seasonNumber: seasonNumber,
      name: name,
      rating: vote,
      overview: overview,
      episodes: episodes,
    );
  } catch (_) {
    return null;
  }
}

class TmdbWatchInfo {
  final List<String> stream;
  final List<String> rent;
  final List<String> buy;

  const TmdbWatchInfo({
    this.stream = const [],
    this.rent = const [],
    this.buy = const [],
  });

  bool get isEmpty => stream.isEmpty && rent.isEmpty && buy.isEmpty;
}

class TmdbReview {
  final String author;
  final String text;
  final double? rating;

  const TmdbReview({
    required this.author,
    required this.text,
    this.rating,
  });
}

String tmdbPosterUrl(String? path, {bool big = false}) {
  if (path == null || path.isEmpty) return '';
  return big
      ? 'https://image.tmdb.org/t/p/w500$path'
      : 'https://image.tmdb.org/t/p/w342$path';
}

String tmdbScreenshotUrl(String path) =>
    path.isEmpty ? '' : 'https://image.tmdb.org/t/p/w500$path';

TmdbWatchInfo parseTmdbWatchProviders(String jsonBody, {String region = 'IN'}) {
  try {
    final decoded = jsonDecode(jsonBody);
    if (decoded is! Map) return const TmdbWatchInfo();
    final wp = decoded['watch/providers'];
    if (wp is! Map) return const TmdbWatchInfo();
    final results = wp['results'];
    if (results is! Map) return const TmdbWatchInfo();
    final area = results[region];
    if (area is! Map) return const TmdbWatchInfo();
    List<String> names(String key) {
      final list = area[key];
      if (list is! List) return const [];
      final out = <String>[];
      for (final p in list) {
        if (p is Map && p['provider_name'] != null) {
          final n = '${p['provider_name']}'.trim();
          if (n.isNotEmpty && !out.contains(n)) out.add(n);
        }
      }
      return out;
    }
    return TmdbWatchInfo(
      stream: names('flatrate'),
      rent: names('rent'),
      buy: names('buy'),
    );
  } catch (_) {
    return const TmdbWatchInfo();
  }
}

List<TmdbReview> parseTmdbReviews(String jsonBody) {
  try {
    final decoded = jsonDecode(jsonBody);
    if (decoded is! Map) return const [];
    final rev = decoded['reviews'];
    if (rev is! Map) return const [];
    final list = rev['results'];
    if (list is! List) return const [];
    final out = <TmdbReview>[];
    for (final r in list) {
      if (r is! Map) continue;
      final author = '${r['author'] ?? ''}'.trim();
      var content = '${r['content'] ?? ''}'.trim();
      if (content.isEmpty) continue;
      if (content.length > 500) content = '${content.substring(0, 500)}…';
      double? rating;
      final ad = r['author_details'];
      if (ad is Map && ad['rating'] is num) {
        rating = (ad['rating'] as num).toDouble();
      }
      out.add(TmdbReview(author: author, text: content, rating: rating));
    }
    return out;
  } catch (_) {
    return const [];
  }
}

List<String> parseTmdbScreenshots(String jsonBody) {
  try {
    final decoded = jsonDecode(jsonBody);
    if (decoded is! Map) return const [];
    final images = decoded['images'];
    if (images is! Map) return const [];
    final backdrops = images['backdrops'];
    if (backdrops is! List) return const [];
    final out = <String>[];
    for (final b in backdrops) {
      if (b is Map && b['file_path'] != null) {
        final p = '${b['file_path']}'.trim();
        if (p.isNotEmpty) out.add(p);
      }
    }
    return out;
  } catch (_) {
    return const [];
  }
}

TmdbPage parseTmdbPage(String jsonBody, {String kind = 'movie'}) {
  try {
    final decoded = jsonDecode(jsonBody);
    if (decoded is! Map) return const TmdbPage();
    final results = decoded['results'];
    final items = <TmdbMovie>[];
    if (results is List) {
      for (final e in results) {
        if (e is Map) {
          final m = _movieFromMap(e, kind: kind);
          if (m != null) items.add(m);
        }
      }
    }
    var totalPages = decoded['total_pages'] is num
        ? (decoded['total_pages'] as num).toInt()
        : 1;
    if (totalPages < 1) totalPages = 1;
    if (totalPages > 500) totalPages = 500;
    return TmdbPage(
      items: items,
      page: decoded['page'] is num ? (decoded['page'] as num).toInt() : 1,
      totalPages: totalPages,
      totalResults: decoded['total_results'] is num
          ? (decoded['total_results'] as num).toInt()
          : items.length,
    );
  } catch (_) {
    return const TmdbPage();
  }
}

TmdbPage parseTmdbMultiPage(String jsonBody) {
  try {
    final decoded = jsonDecode(jsonBody);
    if (decoded is! Map) return const TmdbPage();
    final results = decoded['results'];
    final items = <TmdbMovie>[];
    if (results is List) {
      for (final e in results) {
        if (e is! Map) continue;
        final type = '${e['media_type'] ?? ''}';
        final kind = type == 'tv' ? 'tv' : type == 'movie' ? 'movie' : null;
        if (kind == null) continue;
        final m = _movieFromMap(e, kind: kind);
        if (m != null) items.add(m);
      }
    }
    var totalPages = decoded['total_pages'] is num
        ? (decoded['total_pages'] as num).toInt()
        : 1;
    if (totalPages < 1) totalPages = 1;
    if (totalPages > 500) totalPages = 500;
    return TmdbPage(
      items: items,
      page: decoded['page'] is num ? (decoded['page'] as num).toInt() : 1,
      totalPages: totalPages,
      totalResults: decoded['total_results'] is num
          ? (decoded['total_results'] as num).toInt()
          : items.length,
    );
  } catch (_) {
    return const TmdbPage();
  }
}

List<TmdbMovie> parseTmdbList(String jsonBody, {String kind = 'movie'}) {
  return parseTmdbPage(jsonBody, kind: kind).items;
}

TmdbMovie? _movieFromMap(Map e, {String kind = 'movie'}) {
  final id = e['id'] is num ? (e['id'] as num).toInt() : null;
  if (id == null) return null;
  final title = '${e['title'] ?? e['name'] ?? ''}'.trim();
  if (title.isEmpty) return null;
  final date = '${e['release_date'] ?? e['first_air_date'] ?? ''}'.trim();
  int? year;
  if (date.length >= 4) {
    year = int.tryParse(date.substring(0, 4));
  }
  final rating = e['vote_average'] is num
      ? (e['vote_average'] as num).toDouble()
      : 0.0;
  final poster = e['poster_path']?.toString();
  final backdrop = e['backdrop_path']?.toString();
  final overview = '${e['overview'] ?? ''}'.trim();
  return TmdbMovie(
    id: id,
    title: title,
    rating: rating,
    year: year,
    posterPath: poster,
    backdropPath: backdrop,
    overview: overview,
    kind: kind,
  );
}

TmdbMovie? parseTmdbDetail(String jsonBody) {
  try {
    final decoded = jsonDecode(jsonBody);
    if (decoded is! Map) return null;
    final base = _movieFromMap(decoded);
    if (base == null) return null;
    final trailer = _extractTrailerKey(decoded);
    return base.copyWith(trailerKey: trailer);
  } catch (_) {
    return null;
  }
}

TmdbDetailExtras parseTmdbExtras(String jsonBody) {
  try {
    final decoded = jsonDecode(jsonBody);
    if (decoded is! Map) return const TmdbDetailExtras();
    String director = '';
    final cast = <String>[];
    final castMembers = <TmdbCastMember>[];
    final credits = decoded['credits'];
    if (credits is Map) {
      final crew = credits['crew'];
      if (crew is List) {
        for (final c in crew) {
          if (c is Map && c['job'] == 'Director') {
            director = '${c['name'] ?? ''}'.trim();
            if (director.isNotEmpty) break;
          }
        }
      }
      final castList = credits['cast'];
      if (castList is List) {
        for (final c in castList) {
          if (c is! Map) continue;
          final name = '${c['name'] ?? ''}'.trim();
          final character = '${c['character'] ?? ''}'.trim();
          final prof = c['profile_path']?.toString();
          if (name.isNotEmpty) {
            cast.add(name);
            castMembers.add(TmdbCastMember(
              name: name,
              character: character,
              profilePath: prof,
            ));
          }
          if (castMembers.length >= 20) break;
        }
      }
    }
    final genres = <String>[];
    final g = decoded['genres'];
    if (g is List) {
      for (final e in g) {
        if (e is Map) {
          final name = '${e['name'] ?? ''}'.trim();
          if (name.isNotEmpty) genres.add(name);
        }
      }
    }
    final langs = <String>[];
    final sl = decoded['spoken_languages'];
    if (sl is List) {
      for (final e in sl) {
        if (e is Map) {
          final name = '${e['english_name'] ?? e['name'] ?? ''}'.trim();
          if (name.isNotEmpty) langs.add(name);
        }
      }
    }
    List<String> namesList(dynamic raw) {
      if (raw is! List) return const [];
      final out = <String>[];
      for (final e in raw) {
        if (e is Map && e['name'] != null) {
          final n = '${e['name']}'.trim();
          if (n.isNotEmpty && !out.contains(n)) out.add(n);
        }
      }
      return out;
    }
    return TmdbDetailExtras(
      director: director,
      cast: cast,
      castMembers: castMembers,
      runtimeMinutes:
          decoded['runtime'] is num ? (decoded['runtime'] as num).toInt() : (decoded['episode_run_time'] is List && (decoded['episode_run_time'] as List).isNotEmpty ? ((decoded['episode_run_time'] as List).first as num).toInt() : 0),
      genres: genres,
      tagline: '${decoded['tagline'] ?? ''}'.trim(),
      voteCount: decoded['vote_count'] is num
          ? (decoded['vote_count'] as num).toInt()
          : 0,
      status: '${decoded['status'] ?? ''}'.trim(),
      releaseDate:
          '${decoded['release_date'] ?? decoded['first_air_date'] ?? ''}'
              .trim(),
      originalTitle: '${decoded['original_title'] ?? ''}'.trim(),
      budgetUsd: decoded['budget'] is num ? (decoded['budget'] as num).toInt() : 0,
      revenueUsd: decoded['revenue'] is num ? (decoded['revenue'] as num).toInt() : 0,
      companies: namesList(decoded['production_companies']),
      countries: namesList(decoded['production_countries']),
      certification: '',
      allLanguages: langs,
      spokenLanguages: langs,
    );
  } catch (_) {
    return const TmdbDetailExtras();
  }
}

String? _extractTrailerKey(Map decoded) {
  final videos = decoded['videos'];
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

class TmdbClient {
  static const String _host = 'api.themoviedb.org';
  static const List<String> _hosts = ['api.themoviedb.org', 'api.tmdb.org'];
  static String _activeHost = _hosts.first;

  static final HttpClient _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 12)
    ..idleTimeout = const Duration(seconds: 10);

  Directory? cacheDir;

  Future<String> _get(Uri uri) async {
    Object? lastError;
    for (var round = 0; round < 2; round++) {
      for (final host
          in [_activeHost, ..._hosts.where((h) => h != _activeHost)]) {
        try {
          final req = await _http
              .getUrl(uri.replace(host: host))
              .timeout(const Duration(seconds: 8));
          final res = await req.close().timeout(const Duration(seconds: 14));
          if (res.statusCode != 200) {
            throw HttpException('TMDB status ${res.statusCode}');
          }
          final body = await res.transform(utf8.decoder).join();
          _activeHost = host;
          return body;
        } catch (e) {
          lastError = e;
          await Future<void>.delayed(const Duration(milliseconds: 350));
        }
      }
    }
    throw HttpException('TMDB request failed: $lastError');
  }

  File? _cacheFile(String name) {
    final dir = cacheDir;
    if (dir == null) return null;
    return File('${dir.path}${Platform.pathSeparator}$name');
  }

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
      } catch (_) {}
      return body;
    } catch (_) {
      try {
        if (f != null && await f.exists()) return await f.readAsString();
      } catch (_) {}
      return null;
    }
  }

  Future<TmdbPage> browse(DiscoverFilter f,
      {int page = 1, bool force = false}) async {
    if (kTmdbApiKey.isEmpty) return const TmdbPage();
    final String cacheName = discoverCacheName(f, page);
    final Uri uri;
    if (f.trending || f.upcoming) {
      uri = Uri.https(_host, tmdbEndpointPath(f), {
        'api_key': kTmdbApiKey,
        'language': 'en-US',
        'region': 'IN',
        'page': '$page',
      });
    } else {
      uri = Uri.https(_host, tmdbEndpointPath(f), {
        'api_key': kTmdbApiKey,
        ...tmdbDiscoverQuery(f, page),
      });
    }
    final body = await _fetch(cacheName, uri,
        ttl: force ? Duration.zero : const Duration(hours: 24));
    return body == null
        ? const TmdbPage()
        : parseTmdbPage(body, kind: f.tv ? 'tv' : 'movie');
  }

  Future<TmdbPage> browseAnime({int page = 1, String category = 'all', bool force = false}) async {
    if (kTmdbApiKey.isEmpty) return const TmdbPage();
    final cacheName = 'tmdb_anime_${category}_p$page.json';
    final isMovie = category == 'movies';
    final uri = Uri.https(_host, isMovie ? '/3/discover/movie' : '/3/discover/tv', {
      'api_key': kTmdbApiKey,
      'language': 'en-US',
      'page': '$page',
      'sort_by': 'popularity.desc',
      'with_genres': '16',
      'with_original_language': 'ja',
      'vote_count.gte': '5',
      'include_adult': 'false',
    });
    final body = await _fetch(cacheName, uri,
        ttl: force ? Duration.zero : const Duration(hours: 24));
    return body == null ? const TmdbPage() : parseTmdbPage(body, kind: isMovie ? 'movie' : 'tv');
  }

  Future<TmdbPage?> cachedBrowseFirstPage(DiscoverFilter f) async {
    try {
      final dir = cacheDir;
      if (dir == null) return null;
      final file = File('${dir.path}/${discoverCacheName(f, 1)}');
      if (!await file.exists()) return null;
      final page = parseTmdbPage(await file.readAsString(),
          kind: f.tv ? 'tv' : 'movie');
      return page.items.isEmpty ? null : page;
    } catch (_) {
      return null;
    }
  }

  Future<TmdbPage> searchMovies(String query,
      {int page = 1, bool force = false}) async {
    final q = query.trim();
    if (kTmdbApiKey.isEmpty || q.isEmpty) return const TmdbPage();
    final uri = Uri.https(_host, '/3/search/movie', {
      'api_key': kTmdbApiKey,
      ...tmdbSearchQuery(q, page),
    });
    final body = await _fetch(tmdbSearchCacheName(q, page), uri,
        ttl: force ? Duration.zero : const Duration(hours: 24));
    return body == null ? const TmdbPage() : parseTmdbPage(body);
  }

  Future<TmdbPage> searchMulti(String query,
      {int page = 1, bool force = false}) async {
    final q = query.trim();
    if (kTmdbApiKey.isEmpty || q.isEmpty) return const TmdbPage();
    final uri = Uri.https(_host, '/3/search/multi', {
      'api_key': kTmdbApiKey,
      ...tmdbSearchQuery(q, page),
    });
    final body = await _fetch(tmdbSearchCacheName('multi_$q', page), uri,
        ttl: force ? Duration.zero : const Duration(hours: 24));
    return body == null ? const TmdbPage() : parseTmdbMultiPage(body);
  }

  Future<TmdbFull?> fullDetail(int id,
      {String kind = 'movie', bool force = false}) async {
    if (kTmdbApiKey.isEmpty) return null;
    final isTv = kind == 'tv';
    final uri = Uri.https(_host, '/3/$kind/$id', {
      'api_key': kTmdbApiKey,
      'language': 'en-US',
      'append_to_response': isTv
          ? 'videos,credits,images,watch/providers,reviews,'
              'content_ratings,translations'
          : 'videos,credits,images,watch/providers,reviews,'
              'release_dates,translations',
      'include_image_language': 'en,null',
    });
    final body = await _fetch(
        isTv ? 'tmdb_tv_v5_$id.json' : 'tmdb_movie_v5_$id.json', uri,
        ttl: force ? Duration.zero : const Duration(hours: 24));
    if (body == null) return null;
    final parsed = parseTmdbDetail(body);
    if (parsed == null) return null;
    final movie = isTv ? parsed.copyWith(kind: 'tv') : parsed;
    return TmdbFull(
      movie,
      parseTmdbExtras(body),
      screenshots: parseTmdbScreenshots(body),
      watch: parseTmdbWatchProviders(body),
      reviews: parseTmdbReviews(body),
      seasons: isTv ? parseTmdbSeasons(body) : const [],
    );
  }

  Future<List<TmdbMovie>> similar(int id,
      {String kind = 'movie', bool force = false}) async {
    if (kTmdbApiKey.isEmpty) return const [];
    final uri = Uri.https(_host, '/3/$kind/$id/similar', {
      'api_key': kTmdbApiKey,
      'language': 'en-US',
    });
    final body = await _fetch(
        kind == 'tv' ? 'tmdb_tv_similar_$id.json' : 'tmdb_similar_$id.json',
        uri,
        ttl: force ? Duration.zero : const Duration(hours: 24));
    return body == null ? const [] : parseTmdbList(body, kind: kind);
  }

  Future<TmdbSeasonDetail?> seasonDetail(int tvId, int seasonNumber, {bool force = false}) async {
    if (kTmdbApiKey.isEmpty) return null;
    final cacheName = 'tmdb_tv_${tvId}_s${seasonNumber}_detail.json';
    final uri = Uri.https(_host, '/3/tv/$tvId/season/$seasonNumber', {
      'api_key': kTmdbApiKey,
      'language': 'en-US',
    });
    final body = await _fetch(cacheName, uri, ttl: force ? Duration.zero : const Duration(hours: 24));
    if (body == null) return null;
    return parseTmdbSeasonDetail(body, seasonNumber: seasonNumber);
  }
}
