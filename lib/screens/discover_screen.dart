import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../services/recommendations.dart';
import '../theme.dart';
import '../utils/config.dart';
import '../utils/local_store.dart';
import '../utils/movie_match.dart';
import '../utils/tmdb.dart';
import '../utils/tmdb_image.dart';
import '../widgets/ai_suggest_sheet.dart';
import '../widgets/movie_detail_sheet.dart';

/// "Discover" — a legal movie-discovery section, ported from the canonical
/// old app's `discover_screen.dart`:
///
/// - MANY filters (Trending, Upcoming, Animation, Hollywood, Bollywood,
///   Tamil, Telugu, Action, Comedy, Drama, Horror, Romance, Thriller,
///   Sci-Fi) + web-series shelves (Hindi, English, K-Drama, Anime) in ONE
///   combined chip row.
/// - Its own SEARCH bar -> TMDB's whole catalogue (movies AND series via
///   /search/multi).
/// - INFINITE SCROLL: every section pages through thousands of titles.
/// - Pull-to-refresh REALLY reloads.
/// - On-device "Because you watched" recommendations from local history.
/// - The ✨ AI Suggestor sheet turns "funny action like Dhoom" into real,
///   tappable posters.
class DiscoverScreen extends StatefulWidget {
  /// The already-scanned local library — used ONLY for "In my library"
  /// matching (read-only; the video scan is never touched).
  final List<AssetEntity> videos;

  const DiscoverScreen({super.key, required this.videos});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  final _client = TmdbClient();
  final _scroll = ScrollController();
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  DiscoverFilter _filter = kAllFilters.first;
  final List<TmdbMovie> _movies = [];
  final Set<int> _seenIds = {};
  int _page = 0;
  int _totalPages = 1;
  int _totalResults = 0;
  bool _initialLoading = true;
  bool _loadingMore = false;
  String? _error;
  bool _keyMissing = false;

  // Chain page loads after each page lands until the grid fills the
  // viewport OR we hit the safety cap — then the normal scroll listener at
  // maxScrollExtent-350 takes over for "forever" paging.
  bool _endlessPaging = false;
  int _endlessBurst = 0;
  static const int _kEndlessBurstCap = 5;

  /// Similar titles of the top search hit, shown under results in search.
  List<TmdbMovie> _related = const [];

  /// "Because you watched <title>" — on-device recommendations.
  List<TmdbMovie> _recommendations = const [];
  RecentItem? _recommendAnchor;

  /// Bumped every time the MODE (filter/search) changes; stale in-flight
  /// page loads check it and drop their results.
  int _loadToken = 0;
  String _searchQuery = '';

  /// First-load self-cure: page-1 empties auto-retry with 2s/4s/8s backoff.
  int _bootRetries = 0;
  Timer? _bootRetryTimer;
  static const int _kBootRetryCap = 3;
  bool get _searching => _searchQuery.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_maybeLoadMore);
    _boot();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _bootRetryTimer?.cancel();
    _scroll.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    final cachePath = await TmdbImage.initCacheDir();
    TmdbImage.configure(cachePath);
    if (cachePath != null) _client.cacheDir = Directory(cachePath);
    if (!mounted) return;
    if (AppConfig.tmdbToken.isEmpty) {
      setState(() {
        _keyMissing = true;
        _initialLoading = false;
      });
      return;
    }
    await _loadPage(1, force: true);
    unawaited(_loadRecommendations());
  }

  Future<void> _loadRecommendations() async {
    try {
      final history = await LocalStore().recent();
      final anchor = Recommendations.pickAnchor(history);
      if (anchor == null) return;
      final recs = await Recommendations.forAnchor(_client, anchor);
      if (!mounted) return;
      setState(() {
        _recommendAnchor = anchor;
        _recommendations = recs;
      });
    } catch (_) {}
  }

  /// Loads ONE page of the current mode and appends it (deduped by id).
  Future<void> _loadPage(int page, {bool force = false}) async {
    final token = _loadToken;
    if (page == 1) {
      if (mounted) setState(() => _initialLoading = true);
      // Instant first paint on bad networks — show the cached page from
      // disk RIGHT AWAY; the live fetch below replaces it.
      if (!_searching && _movies.isEmpty) {
        final cached = await _client.cachedBrowseFirstPage(_filter);
        if (!mounted || token != _loadToken) return;
        if (cached != null && _movies.isEmpty) {
          setState(() {
            for (final m in cached.items) {
              if (_seenIds.add(m.id)) _movies.add(m);
            }
            _error = null;
          });
        }
      }
    } else {
      if (mounted) setState(() => _loadingMore = true);
    }
    TmdbPage result;
    try {
      result = _searching
          ? await _client.searchMulti(_searchQuery, page: page, force: force)
          : await _client.browse(_filter, page: page, force: force);
    } catch (_) {
      result = const TmdbPage();
    }
    if (!mounted || token != _loadToken) return;
    setState(() {
      _initialLoading = false;
      _loadingMore = false;
      _page = result.page;
      _totalPages = result.totalPages;
      _totalResults = result.totalResults;
      for (final m in result.items) {
        if (_seenIds.add(m.id)) _movies.add(m);
      }
      if (page == 1 && _movies.isEmpty) {
        _error = _searching
            ? 'No movies or series match "$_searchQuery" on TMDB.'
            : 'Could not load movies or series - connect the internet once, '
                'then pull down to retry.';
      } else if (_movies.isNotEmpty) {
        _error = null;
      }
    });
    if (_searching && page == 1 && result.items.isNotEmpty) {
      _loadRelated(result.items.first.id, token,
          kind: result.items.first.kind);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && token == _loadToken) _scheduleEndlessFill(token);
    });
    if (page != 1 || _searching || token != _loadToken) return;
    if (result.items.isNotEmpty || _bootRetries >= _kBootRetryCap) return;
    final delay = Duration(seconds: 2 << _bootRetries); // 2s, 4s, 8s
    _bootRetries++;
    _bootRetryTimer?.cancel();
    _bootRetryTimer = Timer(delay, () {
      if (!mounted || token != _loadToken) return;
      _loadPage(1, force: true);
    });
  }

  void _scheduleEndlessFill(int token) {
    if (!mounted || token != _loadToken) return;
    if (_initialLoading || _loadingMore || _endlessPaging) return;
    if (_page >= _totalPages) return;
    if (_searching) {
      if (_endlessBurst != 0) _endlessBurst = 0;
      return;
    }
    var needsMore = true;
    if (_scroll.hasClients) {
      final pos = _scroll.position;
      needsMore = pos.maxScrollExtent <= pos.viewportDimension + 24 ||
          pos.pixels >= pos.maxScrollExtent - 350;
    }
    if (!needsMore) {
      _endlessBurst = 0;
      return;
    }
    if (_endlessBurst >= _kEndlessBurstCap) {
      _endlessBurst = 0;
      return;
    }
    _endlessPaging = true;
    _endlessBurst++;
    _loadPage(_page + 1).whenComplete(() {
      if (mounted) _endlessPaging = false;
    });
  }

  Future<void> _loadRelated(int movieId, int token,
      {String kind = 'movie'}) async {
    List<TmdbMovie> rel;
    try {
      rel = await _client.similar(movieId, kind: kind);
    } catch (_) {
      rel = const [];
    }
    if (!mounted || token != _loadToken || !_searching) return;
    setState(() => _related = rel.take(12).toList());
  }

  /// Hard switch of browse/search mode: clears the grid, invalidates any
  /// in-flight loads, then fetches page 1. [force] skips the 24h cache.
  void _switchTo({DiscoverFilter? filter, String? query, bool force = false}) {
    _loadToken++;
    _endlessPaging = false;
    _endlessBurst = 0;
    _bootRetries = 0;
    _bootRetryTimer?.cancel();
    _bootRetryTimer = null;
    setState(() {
      if (filter != null) _filter = filter;
      if (query != null) _searchQuery = query;
      _movies.clear();
      _seenIds.clear();
      _page = 0;
      _totalPages = 1;
      _totalResults = 0;
      _error = null;
      _related = const [];
    });
    _loadPage(1, force: force);
  }

  void _selectFilter(DiscoverFilter f) {
    if (!_searching && _filter == f) return;
    _searchCtrl.clear();
    _switchTo(filter: f, query: '');
  }

  void _onSearchChanged(String v) {
    setState(() {}); // show/hide the clear (x) button immediately
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      final q = v.trim();
      if (q == _searchQuery) return;
      _switchTo(query: q);
    });
  }

  /// Infinite scroll — near the bottom? fetch the next page.
  void _maybeLoadMore() {
    if (!_scroll.hasClients || _initialLoading || _loadingMore) return;
    if (_page >= _totalPages) return;
    final pos = _scroll.position;
    if (pos.pixels >= pos.maxScrollExtent - 350) {
      _endlessBurst = 0;
      _loadPage(_page + 1);
    }
  }

  Future<void> _refresh() async {
    _switchTo(force: true);
    while (_initialLoading && mounted) {
      await Future<void>.delayed(const Duration(milliseconds: 60));
    }
  }

  void _openMovie(TmdbMovie movie) {
    final match = findLocalMovie(movie.title, movie.year, widget.videos);
    MovieDetailSheet.show(
      context,
      movie: movie,
      localMatch: match,
      detailLoader: () => _client.fullDetail(movie.id, kind: movie.kind),
    );
  }

  /// The AI Suggestor — "describe your movie type" -> real posters.
  Future<void> _openAiSuggest() async {
    final pick = await AiSuggestSheet.show(context);
    if (!mounted || pick == null) return;
    _openMovie(pick);
  }

  void _startVoiceSearch() {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(const SnackBar(
        content: Text('Voice search is not available in this build'),
        duration: Duration(milliseconds: 1800),
      ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF12121a),
      appBar: AppBar(
        backgroundColor: const Color(0xFF12121a),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Discover', style: TextStyle(fontSize: 18)),
            if (_totalResults > 0)
              Text(
                _searching
                    ? '${_movies.length} of ~${formatVoteCount(_totalResults)} results'
                    : '${formatVoteCount(_totalResults)} titles - scroll for more',
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'AI Suggest - describe your movie type',
            icon: Icon(Icons.auto_awesome, color: AppColors.accent),
            onPressed: _openAiSuggest,
          ),
        ],
      ),
      body: _keyMissing
          ? const _SetupNote()
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: _onSearchChanged,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Search movies & series...',
                      hintStyle: const TextStyle(color: Colors.white38),
                      prefixIcon: Icon(Icons.search,
                          color: AppColors.accent, size: 20),
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_searchCtrl.text.isNotEmpty)
                            IconButton(
                              icon: const Icon(Icons.close,
                                  color: Colors.white54, size: 18),
                              onPressed: () {
                                _searchCtrl.clear();
                                _switchTo(query: '');
                              },
                            ),
                          IconButton(
                            icon: Icon(Icons.mic_none_outlined,
                                color: AppColors.accent, size: 20),
                            tooltip: 'Voice search',
                            onPressed: _startVoiceSearch,
                          ),
                        ],
                      ),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.06),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  height: 34,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: [
                      for (final f in kAllFilters) ...[
                        _FilterChip(
                          label: f.label,
                          selected: !_searching && _filter == f,
                          onTap: () => _selectFilter(f),
                        ),
                        const SizedBox(width: 6),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: RefreshIndicator(
                    color: AppColors.accent,
                    onRefresh: _refresh,
                    child: _buildBody(),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildBody() {
    if (_initialLoading && _movies.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_movies.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 120),
          Icon(Icons.cloud_off_outlined,
              size: 44, color: Colors.white.withValues(alpha: 0.3)),
          const SizedBox(height: 14),
          Text(
            _error ?? 'No movies to show yet.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white54, height: 1.4),
          ),
        ],
      );
    }
    return Stack(
      children: [
        CustomScrollView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            if (!_searching && _recommendations.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                  child: Row(
                    children: [
                      const Icon(Icons.auto_awesome,
                          size: 16, color: Colors.white70),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Because you watched '
                          '"${_recommendAnchor?.title ?? ''}"',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 224,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    itemCount: _recommendations.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 10),
                    itemBuilder: (context, i) => SizedBox(
                      width: 128,
                      child: _PosterCard(
                        key: ValueKey('rec_${_recommendations[i].id}'),
                        movie: _recommendations[i],
                        onTap: () => _openMovie(_recommendations[i]),
                      ),
                    ),
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 4)),
            ],
            SliverPadding(
              padding: const EdgeInsets.all(10),
              sliver: SliverGrid.builder(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 200,
                  childAspectRatio: 0.60,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                ),
                itemCount: _movies.length,
                itemBuilder: (context, i) {
                  final movie = _movies[i];
                  return _PosterCard(
                    key: ValueKey(movie.id),
                    movie: movie,
                    onTap: () => _openMovie(movie),
                  );
                },
              ),
            ),
            if (_searching && _related.isNotEmpty) ...[
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(12, 10, 12, 8),
                  child: Text(
                    'Related to your search',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 224,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _related.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 10),
                    itemBuilder: (context, i) => SizedBox(
                      width: 128,
                      child: _PosterCard(
                        key: ValueKey('rel_${_related[i].id}'),
                        movie: _related[i],
                        onTap: () => _openMovie(_related[i]),
                      ),
                    ),
                  ),
                ),
              ),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 16)),
          ],
        ),
        if (_loadingMore)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: LinearProgressIndicator(
              minHeight: 3,
              color: AppColors.accent,
              backgroundColor: Colors.transparent,
            ),
          ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.accent
              : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? AppColors.onAccent : Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _PosterCard extends StatelessWidget {
  final TmdbMovie movie;
  final VoidCallback onTap;

  const _PosterCard({super.key, required this.movie, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  TmdbImage(url: tmdbPosterUrl(movie.posterPath)),
                  Positioned(
                    top: 6,
                    left: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '⭐ ${tmdbRatingText(movie.rating)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            movie.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
          if (movie.year != null)
            Text(
              '${movie.year}',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 11,
              ),
            ),
        ],
      ),
    );
  }
}

/// Shown in local/dev builds where no TMDB token was injected.
class _SetupNote extends StatelessWidget {
  const _SetupNote();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.movie_filter,
                size: 44, color: Colors.white.withValues(alpha: 0.3)),
            const SizedBox(height: 14),
            const Text(
              'Discover starts in the store build.\n\n'
              '(Developer note: pass the TMDB token via\n'
              '--dart-define=TMDB_API_KEY=... - see README. '
              'Everything else in the app works without it.)',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}
