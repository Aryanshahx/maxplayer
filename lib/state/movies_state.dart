/// v43 Discover: catalogue state - which rails exist, when they refresh,
/// what is cached, what is new since the user last looked.
///
/// HOW "NEW MOVIES APPEAR BY THEMSELVES":
///  * No movie list is ever hardcoded in the app. Every rail is a LIVE TMDB
///    query, and TMDB is updated continuously by its editors/feeds.
///  * Date-driven rails ("New releases", "Coming soon") compute their window
///    from `DateTime.now()` at call time, so the window slides with the
///    calendar - next month the same rail asks for next month's films.
///  * Results are cached with a per-rail TTL and served
///    stale-while-revalidate: the screen paints instantly from disk, then a
///    background refresh swaps in fresher data if the TTL has expired.
///  * Pull-to-refresh forces a network round trip for every rail.
///  * Titles the user has not seen before get a "NEW" ribbon, computed
///    against a persisted set of ids - no server or push notification
///    needed.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/movie.dart';
import '../services/movie_cache.dart';
import '../services/native_bridge.dart';
import '../services/tmdb_api.dart';

/// Fetches one page of a rail. [now] is injected so the date windows are
/// deterministic in tests.
typedef RailFetcher = Future<MoviePage> Function(
    TmdbApi api, int page, DateTime now);

/// A horizontal row on the Discover screen.
class MovieRail {
  final String id;
  final String title;
  final String subtitle;

  /// How long a cached page stays "fresh enough" to skip the network.
  final Duration ttl;
  final RailFetcher fetch;

  const MovieRail({
    required this.id,
    required this.title,
    required this.fetch,
    this.subtitle = '',
    this.ttl = const Duration(hours: 12),
  });
}

/// Language codes for the regional rails (TMDB `with_original_language`).
const String kLangEnglish = 'en';
const String kLangHindi = 'hi';
const String kLangTelugu = 'te';
const String kLangTamil = 'ta';
const String kLangKorean = 'ko';
const String kLangJapanese = 'ja';

/// The Discover line-up. Order = order on screen.
///
/// Kept as a function (not a const list) because each rail carries a
/// closure; also lets tests build a fresh copy.
List<MovieRail> buildMovieRails() => <MovieRail>[
      MovieRail(
        id: 'trending',
        title: 'Trending this week',
        subtitle: 'What everyone is watching',
        ttl: const Duration(hours: 6),
        fetch: (api, page, now) => api.trending(page: page),
      ),
      MovieRail(
        id: 'new_releases',
        title: 'New releases',
        subtitle: 'Out in the last few weeks',
        ttl: const Duration(hours: 12),
        fetch: (api, page, now) => api.discover(
          window: recentWindow(now),
          sortBy: 'popularity.desc',
          minVotes: 15,
          page: page,
        ),
      ),
      MovieRail(
        id: 'in_cinemas',
        title: 'In cinemas now',
        subtitle: 'Playing near you',
        ttl: const Duration(hours: 12),
        fetch: (api, page, now) => api.nowPlaying(page: page),
      ),
      MovieRail(
        id: 'hollywood',
        title: 'Hollywood',
        subtitle: 'Popular English films',
        fetch: (api, page, now) => api.discover(
          originalLanguage: kLangEnglish,
          minVotes: 100,
          page: page,
        ),
      ),
      MovieRail(
        id: 'bollywood',
        title: 'Bollywood',
        subtitle: 'Popular Hindi films',
        fetch: (api, page, now) => api.discover(
          originalLanguage: kLangHindi,
          minVotes: 20,
          page: page,
        ),
      ),
      MovieRail(
        id: 'south',
        title: 'South Indian',
        subtitle: 'Telugu & Tamil hits',
        fetch: (api, page, now) => api.discover(
          originalLanguage: '$kLangTelugu|$kLangTamil',
          minVotes: 20,
          page: page,
        ),
      ),
      MovieRail(
        id: 'top_rated',
        title: 'Top rated of all time',
        subtitle: 'Highest scored on TMDB',
        ttl: const Duration(days: 3),
        fetch: (api, page, now) => api.topRated(page: page),
      ),
      MovieRail(
        id: 'upcoming',
        title: 'Coming soon',
        subtitle: 'Releasing in the next months',
        fetch: (api, page, now) => api.discover(
          window: upcomingWindow(now),
          sortBy: 'popularity.desc',
          page: page,
        ),
      ),
      MovieRail(
        id: 'action',
        title: 'Action & adventure',
        fetch: (api, page, now) => api.discover(
          genres: [TmdbApi.genreIds['Action'] ?? 28],
          minVotes: 100,
          page: page,
        ),
      ),
      MovieRail(
        id: 'comedy',
        title: 'Comedy',
        fetch: (api, page, now) => api.discover(
          genres: [TmdbApi.genreIds['Comedy'] ?? 35],
          minVotes: 80,
          page: page,
        ),
      ),
      MovieRail(
        id: 'horror',
        title: 'Horror & thriller',
        fetch: (api, page, now) => api.discover(
          genres: [TmdbApi.genreIds['Horror'] ?? 27],
          minVotes: 60,
          page: page,
        ),
      ),
      MovieRail(
        id: 'animation',
        title: 'Animation & anime',
        fetch: (api, page, now) => api.discover(
          genres: [TmdbApi.genreIds['Animation'] ?? 16],
          minVotes: 60,
          page: page,
        ),
      ),
    ];

/// Live state of one rail.
class RailState {
  List<Movie> movies = const <Movie>[];
  bool loading = false;
  bool loadingMore = false;
  String? error;

  /// True while the shown data came from disk and has not been revalidated.
  bool fromCache = false;
  DateTime? updatedAt;
  int page = 1;
  int totalPages = 1;

  /// Ids the user has not seen in this rail before (the "NEW" ribbon).
  Set<int> newIds = <int>{};

  bool get hasMore => page < totalPages;
  bool get isEmpty => movies.isEmpty;
}

class MoviesState extends ChangeNotifier {
  static const String kEnabledKey = 'movies.enabled';
  static const String kSeenKey = 'movies.seen.v1';
  static const String kWatchlistKey = 'movies.watchlist.v1';

  /// Cap on remembered ids for the NEW ribbon (keeps the setting small).
  static const int seenCap = 800;

  final TmdbApi api;
  final MovieCache cache;
  final List<MovieRail> rails;

  /// Injected clock - tests pin "today" to keep date windows deterministic.
  DateTime Function() clock;

  final Map<String, RailState> _states = <String, RailState>{};
  final Map<String, MovieDetails> _details = <String, MovieDetails>{};

  /// Opt-in: Discover stays dark until the user agrees to go online once.
  bool enabled = false;
  bool settingsLoaded = false;
  bool _disposed = false;

  Set<int> _seen = <int>{};
  bool _seenKnown = false;
  List<Movie> _watchlist = <Movie>[];

  MoviesState({
    TmdbApi? api,
    MovieCache? cache,
    List<MovieRail>? rails,
    DateTime Function()? clock,
  })  : api = api ?? const TmdbApi(),
        cache = cache ?? movieCache,
        rails = rails ?? buildMovieRails(),
        clock = clock ?? DateTime.now;

  bool get configured => api.configured;

  List<Movie> get watchlist => List<Movie>.unmodifiable(_watchlist);

  RailState railState(String id) =>
      _states.putIfAbsent(id, () => RailState());

  MovieRail? railById(String id) {
    for (final r in rails) {
      if (r.id == id) return r;
    }
    return null;
  }

  void _ping() {
    if (!_disposed) notifyListeners();
  }

  // -------------------------------------------------------------------
  // Settings
  // -------------------------------------------------------------------

  Future<void> load() async {
    try {
      final s = await NativeBridge.loadSettings();
      enabled = s[kEnabledKey] == '1';
      final seenRaw = s[kSeenKey];
      if (seenRaw != null && seenRaw.isNotEmpty) {
        final decoded = jsonDecode(seenRaw);
        if (decoded is List) {
          _seen = <int>{for (final e in decoded) asInt(e)};
          _seenKnown = _seen.isNotEmpty;
        }
      }
      final wRaw = s[kWatchlistKey];
      if (wRaw != null && wRaw.isNotEmpty) {
        final decoded = jsonDecode(wRaw);
        if (decoded is List) {
          _watchlist = [
            for (final e in decoded)
              if (e is Map) Movie.fromJson(e.cast<String, Object?>()),
          ];
        }
      }
    } catch (_) {
      // First run / unreadable settings: defaults are fine.
    }
    settingsLoaded = true;
    _ping();
  }

  Future<void> setEnabled(bool value) async {
    enabled = value;
    _ping();
    await NativeBridge.saveSetting(kEnabledKey, value ? '1' : '0');
    if (value) unawaited(refreshAll());
  }

  // -------------------------------------------------------------------
  // Loading
  // -------------------------------------------------------------------

  /// Called when the Discover tab opens. Cached rails paint immediately;
  /// only the stale ones hit the network. [force] = pull-to-refresh.
  Future<void> refreshAll({bool force = false}) async {
    if (!enabled || !configured) return;
    // Three at a time: enough to feel instant, gentle on a 3G connection
    // and far under TMDB's rate limit.
    const int lanes = 3;
    final queue = List<MovieRail>.of(rails);
    final workers = <Future<void>>[];
    for (var i = 0; i < lanes; i++) {
      workers.add(() async {
        while (queue.isNotEmpty) {
          final rail = queue.removeAt(0);
          await loadRail(rail.id, force: force);
        }
      }());
    }
    await Future.wait(workers);
    unawaited(cache.pruneImages());
  }

  String _cacheKey(MovieRail rail, int page) =>
      'rail:${rail.id}:p$page:${api.language}:${api.region}';

  /// Loads page 1 of a rail: cache first, then network when stale.
  Future<void> loadRail(String id, {bool force = false}) async {
    final rail = railById(id);
    if (rail == null) return;
    final st = railState(id);
    if (st.loading) return;
    final now = clock();
    final key = _cacheKey(rail, 1);

    // 1) Disk - instant paint, works with no connection at all.
    Duration? age;
    if (st.movies.isEmpty) {
      final hit = await cache.readJson(key);
      if (hit != null) {
        final page = MoviePage.fromJson(hit.data);
        if (page.movies.isNotEmpty) {
          st.movies = page.movies;
          st.page = page.page;
          st.totalPages = page.totalPages;
          st.updatedAt = hit.savedAt;
          st.fromCache = true;
          st.error = null;
          _ping();
        }
        age = hit.ageFrom(now);
      }
    } else if (st.updatedAt != null) {
      age = now.difference(st.updatedAt!);
    }

    if (!shouldRefresh(age: age, ttl: rail.ttl, force: force)) return;

    // 2) Network - revalidate in the background.
    st.loading = true;
    if (st.movies.isEmpty) st.error = null;
    _ping();
    try {
      final page = await rail.fetch(api, 1, now);
      final fresh = _dedupe(page.movies);
      st.newIds = _markNew(fresh);
      st.movies = fresh;
      st.page = page.page;
      st.totalPages = page.totalPages;
      st.updatedAt = clock();
      st.fromCache = false;
      st.error = null;
      unawaited(cache.writeJson(key, _pageToJson(page)));
    } on TmdbException catch (e) {
      // Offline with cached content = stay quiet, just flag it.
      st.error = st.movies.isEmpty ? e.message : null;
      st.fromCache = st.movies.isNotEmpty;
    } catch (_) {
      st.error = st.movies.isEmpty ? 'Could not load movies.' : null;
    } finally {
      st.loading = false;
      _ping();
    }
  }

  /// "See all" grid / endless scroll.
  Future<void> loadMore(String id) async {
    final rail = railById(id);
    if (rail == null) return;
    final st = railState(id);
    if (st.loadingMore || st.loading || !st.hasMore) return;
    if (!enabled || !configured) return;
    st.loadingMore = true;
    _ping();
    final next = st.page + 1;
    try {
      final page = await rail.fetch(api, next, clock());
      final merged = _dedupe(<Movie>[...st.movies, ...page.movies]);
      st.movies = merged;
      st.page = page.page;
      st.totalPages = page.totalPages;
      unawaited(cache.writeJson(_cacheKey(rail, next), _pageToJson(page)));
    } on TmdbException catch (e) {
      st.error = e.message;
    } catch (_) {
      st.error = 'Could not load more movies.';
    } finally {
      st.loadingMore = false;
      _ping();
    }
  }

  Map<String, Object?> _pageToJson(MoviePage page) => <String, Object?>{
        'page': page.page,
        'total_pages': page.totalPages,
        'total_results': page.totalResults,
        'results': [for (final m in page.movies) m.toJson()],
      };

  /// TMDB can repeat a title across pages when popularity shifts mid-scroll.
  static List<Movie> _dedupe(List<Movie> input) {
    final seen = <int>{};
    final out = <Movie>[];
    for (final m in input) {
      if (m.id > 0 && seen.add(m.id)) out.add(m);
    }
    return out;
  }

  /// Ids in [movies] the user has never been shown. On a first-ever run
  /// nothing is "new" (otherwise every poster would wear a ribbon).
  Set<int> _markNew(List<Movie> movies) {
    final ids = <int>{for (final m in movies) m.id};
    final fresh = _seenKnown ? ids.difference(_seen) : <int>{};
    _seen.addAll(ids);
    _seenKnown = true;
    if (_seen.length > seenCap) {
      _seen = _seen.skip(_seen.length - seenCap).toSet();
    }
    unawaited(
      NativeBridge.saveSetting(kSeenKey, jsonEncode(_seen.toList())),
    );
    return fresh;
  }

  // -------------------------------------------------------------------
  // Details (cached 7 days - cast/runtime/trailers barely change)
  // -------------------------------------------------------------------

  static const Duration detailsTtl = Duration(days: 7);

  MovieDetails? cachedDetails(int movieId) => _details['$movieId'];

  Future<MovieDetails> details(int movieId, {bool force = false}) async {
    final memo = _details['$movieId'];
    if (memo != null && !force) return memo;
    final key = 'details:$movieId:${api.language}';
    if (!force) {
      final hit = await cache.readJson(key);
      if (hit != null && hit.isFresh(detailsTtl, now: clock())) {
        final parsed = MovieDetails.fromJson(hit.data);
        _details['$movieId'] = parsed;
        _ping();
        return parsed;
      }
    }
    final json = await api.fetchJson('/movie/$movieId', {
      'append_to_response': 'videos,credits,external_ids,similar',
      'include_video_language': 'en,hi,null',
    });
    final parsed = MovieDetails.fromJson(json);
    _details['$movieId'] = parsed;
    unawaited(cache.writeJson(key, json));
    _ping();
    return parsed;
  }

  // -------------------------------------------------------------------
  // Search
  // -------------------------------------------------------------------

  Future<MoviePage> search(String query, {int page = 1}) =>
      api.search(query, page: page);

  // -------------------------------------------------------------------
  // Watchlist
  // -------------------------------------------------------------------

  bool inWatchlist(int movieId) {
    for (final m in _watchlist) {
      if (m.id == movieId) return true;
    }
    return false;
  }

  void toggleWatchlist(Movie movie) {
    if (inWatchlist(movie.id)) {
      _watchlist = [for (final m in _watchlist) if (m.id != movie.id) m];
    } else {
      _watchlist = <Movie>[movie, ..._watchlist];
    }
    _ping();
    unawaited(NativeBridge.saveSetting(
      kWatchlistKey,
      jsonEncode([for (final m in _watchlist) m.toJson()]),
    ));
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// App-wide instance (same pattern as `playlistStore`).
final MoviesState moviesState = MoviesState();
