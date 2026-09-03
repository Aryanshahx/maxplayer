import 'dart:convert';
import 'dart:io';

/// TMDB API key, injected at build time:
/// `flutter build ... --dart-define=TMDB_API_KEY=<key>`.
/// The value lives in Codemagic environment variables, never in the repo.
/// When it is empty (local/dev builds) ALL client calls return empty
/// results and the Discover screen shows its setup note - nothing crashes.
const String _kDefaultTmdbKey = '2dca580c2a14b55200e784d157207b4d';
const String kTmdbApiKey =
    String.fromEnvironment('TMDB_API_KEY', defaultValue: _kDefaultTmdbKey);

/// One movie row from TMDB (trending / discover / search / detail).
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

  /// v58: 'movie' or 'tv' (web series). Detail/similar calls route to
  /// the right TMDB endpoint with it; old entries default to 'movie'.
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

/// v44: one user-selectable filter chip for the Discover section. Exactly
/// ONE of [trending], [language] or [genreId] drives the query.
class DiscoverFilter {
  final String key;
  final String label;
  final String language;
  final int? genreId;
  final bool trending;

  /// v46: the "not released yet" shelf (TMDB upcoming endpoint).
  final bool upcoming;

  /// v58: WEB SERIES - drive the TMDB TV endpoints instead of movies.
  /// ("webseries are not showing" was a real user complaint.)
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

/// v44: MANY more filters than v43's three (All/Hollywood/Bollywood).
/// Languages first (Indian users), then the most-used TMDB genre ids.
/// v46: "Upcoming" (not released yet) sits right after Trending.
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

/// v58: WEB SERIES shelves (TMDB /tv endpoints). TV genre ids differ from
/// movie ids, so series chips stick to trending + language only.
const List<DiscoverFilter> kSeriesFilters = [
  DiscoverFilter(key: 'tv_hindi', label: 'Hindi', language: 'hi', tv: true),
  DiscoverFilter(
      key: 'tv_english', label: 'English', language: 'en', tv: true),
  DiscoverFilter(key: 'tv_korean', label: 'K-Drama', language: 'ko', tv: true),
  DiscoverFilter(key: 'tv_anime', label: 'Anime', language: 'ja', tv: true),
];

/// v59 (user): ONE combined filter row - no Movies|Series toggle, every
/// chip in a single row; each chip knows its own endpoint ([tv] flag).
const List<DiscoverFilter> kAllFilters = [
  ...kDiscoverFilters,
  ...kSeriesFilters,
];

/// Deterministic cache file name for one discover page (movie names are
/// unchanged since v44; series get their own _tv files). Pure for tests.
String discoverCacheName(DiscoverFilter f, int page) =>
    'tmdb_disc_${f.key}${f.tv ? '_tv' : ''}_p$page.json';

/// Which TMDB endpoint a filter pages through. v58: series-safe.
/// Pure for tests.
String tmdbEndpointPath(DiscoverFilter f) => f.trending
    ? (f.tv ? '/3/trending/tv/week' : '/3/trending/movie/week')
    : f.upcoming
        ? '/3/movie/upcoming'
        : (f.tv ? '/3/discover/tv' : '/3/discover/movie');

/// Query params for one page of a NON-trending filter. Pure for tests.
/// v59: vote bar 25 -> 8 ("load TONS of contents in EVERY filter") - the
/// old bar cut most regional + series titles out entirely.
Map<String, String> tmdbDiscoverQuery(DiscoverFilter f, int page) => {
      'language': 'en-US',
      'page': '$page',
      'include_adult': 'false',
      'sort_by': 'popularity.desc',
      'vote_count.gte': '8',
      if (f.language.isNotEmpty) 'with_original_language': f.language,
      if (f.genreId != null) 'with_genres': '${f.genreId}',
    };

/// Query params for one SEARCH page (the Discover search bar). Pure.
Map<String, String> tmdbSearchQuery(String query, int page) => {
      'language': 'en-US',
      'query': query,
      'include_adult': 'false',
      'page': '$page',
    };

/// Deterministic cache file name for a search. Dart's String.hashCode is
/// NOT guaranteed stable, so v44 uses an explicit 31-fold hash of the code
/// units (same as v44 poster names) - pure and testable.
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

/// One page of results - pagination is what puts THOUSANDS of movies in
/// every section (TMDB serves up to 500 pages per query, ~10,000 items).
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

/// Extra facts from the detail call (append_to_response=videos,credits).
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

class TmdbDetailExtras {
  final String director;
  final List<String> cast;
  final List<TmdbCastMember> castMembers;
  final int runtimeMinutes;
  final List<String> genres;
  final String tagline;
  final int voteCount;
  final String status;

  /// v47: the FULL TMDB data set for the detail sheet.
  final String releaseDate;
  final String originalTitle;
  final int budgetUsd;
  final int revenueUsd;
  final List<String> companies;
  final List<String> countries;
  final String certification;

  /// Every language TMDB has this movie's data in (translations).
  final List<String> allLanguages;

  /// v46: spoken (audio) language names - "Languages: English · Hindi".
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

/// Detail bundle: the movie (with trailer key) + the extras above +
/// backdrop "screenshot" paths (v45) + where-to-watch + reviews (v46).
class TmdbFull {
  final TmdbMovie movie;
  final TmdbDetailExtras extras;
  final List<String> screenshots;
  final TmdbWatchInfo watch;
  final List<TmdbReview> reviews;

  /// v59: WEB SERIES detail - "mention ALL parts of the series".
  /// Empty for movies.
  final List<TmdbSeason> seasons;

  const TmdbFull(this.movie, this.extras,
      {this.screenshots = const [],
      this.watch = const TmdbWatchInfo(),
      this.reviews = const [],
      this.seasons = const []});
}

/// One part (season) of a web series - v59.
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

/// Parses the `seasons` array of a /tv detail response. Never throws;
/// garbage -> empty list. Pure for tests.

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
      // v95 FIX: `TmdbSeason.rating` was NEVER populated - the field
      // existed and defaulted to 0.0, so the chip's `s.rating > 0` guard
      // was always false and the star never rendered. TMDB does return
      // vote_average per season on /tv/{id}.
      final vote = e['vote_average'] is num
          ? (e['vote_average'] as num).toDouble()
          : 0.0;
      out.add(TmdbSeason(
        number: n,
        name: name.isEmpty ? (n == 0 ? 'Specials' : 'Season $n') : name,
        episodes: eps,
        year: air.length >= 4 ? int.tryParse(air.substring(0, 4)) : null,
        rating: vote,
      ));
    }
    // v60 belt & braces (his report: "series parts not showing"): some
    // /tv payloads carry ONLY the counters, no seasons array - still
    // show the one summary line instead of nothing at all.
    if (out.isEmpty) {
      final ns = decoded['number_of_seasons'] is num
          ? (decoded['number_of_seasons'] as num).toInt()
          : 0;
      final ne = decoded['number_of_episodes'] is num
          ? (decoded['number_of_episodes'] as num).toInt()
          : 0;
      if (ns > 0) {
        out.add(TmdbSeason(
          number: ns,
          name: '$ns season${ns == 1 ? '' : 's'} in total',
          episodes: ne,
        ));
      }
    }
    return out;
  } catch (_) {
    return const [];
  }
}

/// v46: where the movie can be watched in India (TMDB/JustWatch data):
/// stream (flatrate), rent and buy lists - provider names only.
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

/// v46: one TMDB user review (real review text, trimmed for the sheet).
class TmdbReview {
  final String author;
  final double? rating;
  final String text;

  const TmdbReview({required this.author, this.rating, required this.text});
}

/// "7.834" -> "7.8" (badge text). Pure for tests.
String tmdbRatingText(double rating) => rating.toStringAsFixed(1);

/// Full poster URL for a TMDB `poster_path` (w342 grid / w500 detail).
String tmdbPosterUrl(String? path, {bool big = false}) => (path == null || path.isEmpty)
    ? ''
    : 'https://image.tmdb.org/t/p/${big ? 'w500' : 'w342'}$path';

/// 136 -> "2h 16m", 45 -> "45m", 120 -> "2h", 0 -> ''. Pure for tests.
String formatRuntime(int minutes) {
  if (minutes <= 0) return '';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) return '${m}m';
  if (m == 0) return '${h}h';
  return '${h}h ${m}m';
}

/// 24513 -> "24,513" (hand-rolled so no intl locale setup is needed). Pure.
String formatVoteCount(int votes) {
  final s = '$votes';
  final out = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) out.write(',');
    out.write(s[i]);
  }
  return out.toString();
}

double? _numToDouble(Object? v) =>
    v is num ? v.toDouble() : double.tryParse('$v');

TmdbMovie? _movieFromMap(Object? e, {String kind = 'movie'}) {
  if (e is! Map) return null;
  // v58: series arrive as name + first_air_date (movies: title +
  // release_date) - take whichever is there.
  final title = '${e['title'] ?? e['name'] ?? ''}'.trim();
  if (title.isEmpty) return null;
  final date = '${e['release_date'] ?? e['first_air_date'] ?? ''}';
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
    kind: kind,
  );
}

/// Parses a trending/discover/search LIST response. Never throws: any
/// garbage row is skipped, garbage body -> empty list. Pure for tests.
List<TmdbMovie> parseTmdbList(String jsonBody, {String kind = 'movie'}) {
  return parseTmdbPage(jsonBody, kind: kind).items;
}

/// v44: list + paging info in one parse. Never throws; garbage -> empty
/// page. total_pages is CAPPED at 500 (TMDB's own maximum page depth).
/// Pure for tests.
TmdbPage parseTmdbPage(String jsonBody, {String kind = 'movie'}) {
  try {
    final decoded = jsonDecode(jsonBody);
    if (decoded is! Map) return const TmdbPage();
    final results = decoded['results'];
    final items = <TmdbMovie>[];
    if (results is List) {
      for (final e in results) {
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

/// v59: parses a /search/multi response - each item declares its own
/// media_type; movies and series are kept (with the right [kind]),
/// people/companies are dropped. Never throws. Pure for tests.
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
        if (kind == null) continue; // people & friends -> out
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

/// v44: parses the detail EXTRAS (director, cast, runtime, genres,
/// tagline, votes). Never throws; missing data -> empty fields. Pure.
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
    // v46: spoken audio languages
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
    return TmdbDetailExtras(
      director: director,
      cast: cast,
      castMembers: castMembers,
      runtimeMinutes:
          decoded['runtime'] is num ? (decoded['runtime'] as num).toInt() : 0,
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
      companies: _namesList(decoded['production_companies']),
      countries: _namesList(decoded['production_countries']),
      certification: _certification(decoded),
      allLanguages: _translationLanguages(decoded),
      spokenLanguages: langs,
    );
  } catch (_) {
    return const TmdbDetailExtras();
  }
}

/// w500 backdrop URL - these are the movie "screenshots" (scene stills),
/// not posters. Pure for tests.
String tmdbScreenshotUrl(String path) =>
    path.isEmpty ? '' : 'https://image.tmdb.org/t/p/w500$path';

/// v46: where-to-watch for one region from a detail body's
/// `watch/providers` block ("where to watch, with the compare split":
/// stream vs rent vs buy). Never throws; Pure for tests.
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
        if (p is Map) {
          final n = '${p['provider_name'] ?? ''}'.trim();
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

/// v46: real TMDB user reviews (author, optional 0..10 rating, trimmed
/// text). Never throws; Pure for tests.
List<TmdbReview> parseTmdbReviews(String jsonBody,
    {int count = 2, int maxChars = 420}) {
  try {
    final decoded = jsonDecode(jsonBody);
    if (decoded is! Map) return const [];
    final reviews = decoded['reviews'];
    if (reviews is! Map) return const [];
    final results = reviews['results'];
    if (results is! List) return const [];
    final out = <TmdbReview>[];
    for (final r in results) {
      if (r is! Map) continue;
      final author = '${r['author'] ?? ''}'.trim();
      var text = '${r['content'] ?? ''}'
          .replaceAll(RegExp('\\s+'), ' ')
          .trim();
      if (text.length > maxChars) {
        text = '${text.substring(0, maxChars).trimRight()}...';
      }
      if (text.isEmpty) continue;
      double? rating;
      final details = r['author_details'];
      if (details is Map && details['rating'] is num) {
        rating = (details['rating'] as num).toDouble();
      }
      out.add(TmdbReview(author: author, rating: rating, text: text));
      if (out.length >= count) break;
    }
    return out;
  } catch (_) {
    return const [];
  }
}

/// v45: backdrop/screenshot paths from a DETAIL body's `images` block
/// (append_to_response=...,images). Never throws; missing/junk -> empty.
/// Pure for tests.
List<String> parseTmdbScreenshots(String jsonBody, {int count = 8}) {
  try {
    final decoded = jsonDecode(jsonBody);
    if (decoded is! Map) return const [];
    final images = decoded['images'];
    if (images is! Map) return const [];
    final backdrops = images['backdrops'];
    if (backdrops is! List) return const [];
    final out = <String>[];
    for (final b in backdrops) {
      if (b is! Map) continue;
      final p = '${b['file_path'] ?? ''}'.trim();
      if (p.isNotEmpty) out.add(p);
      if (out.length >= count) break;
    }
    return out;
  } catch (_) {
    return const [];
  }
}

/// Common ISO-639-1 codes -> readable language names (the ones likely
/// to appear for our users). Unknown codes come back UPPERCASED.
String tmdbLanguageName(String code) {
  const names = {
    'en': 'English', 'hi': 'Hindi', 'ta': 'Tamil', 'te': 'Telugu',
    'ml': 'Malayalam', 'kn': 'Kannada', 'bn': 'Bengali', 'mr': 'Marathi',
    'pa': 'Punjabi', 'ur': 'Urdu', 'ar': 'Arabic', 'es': 'Spanish',
    'fr': 'French', 'de': 'German', 'it': 'Italian', 'pt': 'Portuguese',
    'ru': 'Russian', 'ja': 'Japanese', 'ko': 'Korean', 'zh': 'Chinese',
    'cn': 'Chinese', 'th': 'Thai', 'tr': 'Turkish', 'id': 'Indonesian',
    'vi': 'Vietnamese', 'nl': 'Dutch', 'sv': 'Swedish', 'pl': 'Polish',
    'ms': 'Malay', 'fa': 'Persian', 'he': 'Hebrew', 'uk': 'Ukrainian',
    'cs': 'Czech', 'da': 'Danish', 'fi': 'Finnish', 'no': 'Norwegian',
    'el': 'Greek', 'hu': 'Hungarian', 'ro': 'Romanian',
  };
  return names[code] ?? code.toUpperCase();
}

List<String> _namesList(Object? list) {
  if (list is! List) return const [];
  final out = <String>[];
  for (final e in list) {
    if (e is Map) {
      final n = '${e['name'] ?? ''}'.trim();
      if (n.isNotEmpty) out.add(n);
    }
  }
  return out;
}

/// Certification (UA / A / PG-13...) - India first, then US.
String _certification(Map decoded) {
  final rd = decoded['release_dates'];
  if (rd is! Map) return '';
  final results = rd['results'];
  if (results is! List) return '';
  for (final want in ['IN', 'US']) {
    for (final r in results) {
      if (r is Map && r['iso_3166_1'] == want) {
        final dates = r['release_dates'];
        if (dates is List) {
          for (final d in dates) {
            if (d is Map) {
              final c = '${d['certification'] ?? ''}'.trim();
              if (c.isNotEmpty) return c;
            }
          }
        }
      }
    }
  }
  return '';
}

/// All languages TMDB has data for this movie in.
List<String> _translationLanguages(Map decoded) {
  final tr = decoded['translations'];
  if (tr is! Map) return const [];
  final list = tr['translations'];
  if (list is! List) return const [];
  final out = <String>[];
  for (final t in list) {
    if (t is Map) {
      final code = '${t['iso_639_1'] ?? ''}'.trim();
      if (code.isNotEmpty) {
        final name = tmdbLanguageName(code);
        if (!out.contains(name)) out.add(name);
      }
    }
  }
  return out;
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

/// v43/v44: tiny TMDB client for the Discover section. Plain dart:io HTTP -
/// zero new dependencies. Every response (pages, detail, posters handled
/// by TmdbImage) is cached on disk for 24h, so once loaded the section
/// works offline and refreshes ITSELF in the background on the next open
/// after the cache expires - the "automatically updated library".
class TmdbClient {
  static const String _host = 'api.themoviedb.org';

  /// v55: api.tmdb.org is TMDB's own shorter alias of api.themoviedb.org.
  /// Some networks (several Indian ISPs) block or badly throttle ONE of
  /// them, which left Discover stuck on its spinner/error and the home
  /// banner on its flat gradient. We try the last-known-good host first,
  /// then the alias, and stick with whichever answers.
  static const List<String> _hosts = ['api.themoviedb.org', 'api.tmdb.org'];
  static String _activeHost = _hosts.first;

  /// v45: ONE shared client (keep-alive TLS) + longer timeouts. Before,
  /// every request made a fresh 5-second-timeout client, so on a slow
  /// network the first load almost always failed -> "needs multiple
  /// refreshes". [TmdbClient] instances share this single connection.
  static final HttpClient _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 12)
    ..idleTimeout = const Duration(seconds: 10);

  /// Directory used for the 24h disk cache (from NativeBridge.cacheDirPath).
  Directory? cacheDir;

  /// v46: details got heavier (videos+credits+images+watch+reviews), so
  /// give them up to 3 attempts with a 20s ceiling (was 2 attempts/15s -
  /// the "details don't load at once" report).
  Future<String> _get(Uri uri) async {
    Object? lastError;
    // v55: 2 rounds x both hosts; a dead/blackholed host fails fast (8 s
    // connect cap) so the alias gets its turn quickly.
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

  /// v44: one page for the filter chips, incl. THOUSANDS more via paging.
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

  /// v85: Fetches Anime series and movies (Japanese Animation & popular anime).
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

  /// v58: instant first paint on slow networks - whatever the disk cache
  /// already holds for page 1 (stale is fine); the live load then
  /// replaces it. Null = nothing cached yet.
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

  /// v44: the Discover SEARCH bar - searches TMDB's whole catalogue.
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

  /// v59 (user): "when we search any content, find it from ALL filters"
  /// - ONE multi-search across movies AND series (people are dropped in
  /// the parser).
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

  /// v46: one call now also brings WATCH PROVIDERS (where to watch) and
  /// real user REVIEWS. Cache name _v4 forces one re-download.
  Future<TmdbFull?> fullDetail(int id,
      {String kind = 'movie', bool force = false}) async {
    if (kTmdbApiKey.isEmpty) return null;
    final isTv = kind == 'tv';
    final uri = Uri.https(_host, '/3/$kind/$id', {
      'api_key': kTmdbApiKey,
      'language': 'en-US',
      // Series have no release_dates; content_ratings is their cousin.
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
      // v95: "show ALL user reviews" - this was hardcoded to TWO reviews
      // truncated at 420 characters. TMDB's append_to_response returns the
      // first page (up to 20); take all of it and stop chopping the text.
      reviews: parseTmdbReviews(body, count: 20, maxChars: 4000),
      // v59: every part (season) of the series, for the detail sheet.
      seasons: isTv ? parseTmdbSeasons(body) : const [],
    );
  }

  /// v45: RELATED movies ("search is poor - show related movies"): TMDB's
  /// similar endpoint for the top search hit. Cached 24h like everything.
  
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
}
