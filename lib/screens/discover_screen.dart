import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../models/history_entry.dart';
import '../services/native_bridge.dart';
import '../services/recommendations.dart';
import '../services/tmdb_client.dart';
import '../state/media_player_state.dart';
import '../state/theme_state.dart';
import '../state/video_library_state.dart';
import '../utils/movie_match.dart';
import '../widgets/ai_suggest_sheet.dart';
import '../widgets/movie_detail_sheet.dart';
import '../widgets/tmdb_image.dart';

/// v44 "Discover": a legal movie-discovery section, now MUCH bigger.
///
/// - MANY filters (Trending, Hollywood, Bollywood, Tamil, Telugu, Action,
///   Comedy, Drama, Horror, Romance, Thriller, Sci-Fi) instead of v43's 3.
/// - Its own SEARCH bar -> TMDB's whole catalogue.
/// - INFINITE SCROLL: every section pages through thousands of movies
///   (TMDB serves up to 500 pages per query, 20 per page).
/// - Pull-to-refresh REALLY reloads (and v44 fixes wrong/stale posters).
///
/// SOURCE: TMDB's free API (licensed for this, needs only the credit line -
/// we do NOT copy IMDb numbers). Posters + data cache on disk for 24h, so
/// the section refreshes itself daily and works fully offline in between.
///
/// TRAILERS: a tap opens the official YouTube app (Play-policy-safe). We
/// never play YouTube streams through our own player.
/// v58 grew it further: WEB SERIES got their own shelf (Movies | Series
/// switch + /tv endpoints), the grid paints INSTANTLY from the disk cache
/// on slow networks (live data then replaces it), and the ✨ AI Suggestor
/// turns "funny action like Dhoom" into real, tappable posters.
class DiscoverScreen extends StatefulWidget {
  final VideoLibraryState library;
  final MediaPlayerState player;

  const DiscoverScreen({
    super.key,
    required this.library,
    required this.player,
  });

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

  // v61 (user: "show infinite contents in EVERY filter"): page 1 alone
  // rarely fills a tall phone, and v60's single post-frame
  // _maybeLoadMore() only pulled ONE extra page. We now CHAIN page loads
  // after each page lands, until the grid is scrollable/fills the
  // viewport OR we hit the safety cap - then the normal scroll listener
  // at maxScrollExtent-350 takes over for "forever" paging.
  //
  // [_endlessPaging] is the in-flight guard (never two page requests at
  // once); [_endlessBurst] counts chained auto-loads so one burst can't
  // spin forever. Each chain captures the current [_loadToken], so
  // switching filters/search drops a stale chain on the next frame.
  bool _endlessPaging = false;
  int _endlessBurst = 0;
  static const int _kEndlessBurstCap = 5;

  /// v45: "search is poor - show related movies": similar titles of the
  /// top search hit, shown under the results in search mode.
  List<TmdbMovie> _related = const [];

  /// v65 A6: "Because you watched <title>" - on-device recommendations
  /// derived from the user's local watch history (TMDB similar of the best
  /// history match). Loaded once when Discover opens; hidden in search.
  List<TmdbMovie> _recommendations = const [];
  HistoryEntry? _recommendAnchor;

  /// Bumped every time the MODE (filter/search) changes; stale in-flight
  /// page loads check it and drop their results (no mixed-up grids).
  int _loadToken = 0;
  String _searchQuery = '';
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
    _scroll.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    final cachePath = await NativeBridge.cacheDirPath();
    TmdbImage.configure(cachePath);
    if (cachePath != null) _client.cacheDir = Directory(cachePath);
    if (!mounted) return;
    if (kTmdbApiKey.isEmpty) {
      setState(() {
        _keyMissing = true;
        _initialLoading = false;
      });
      return;
    }
    await _loadPage(1, force: true);
    // v65 A6: load on-device "because you watched" recommendations from
    // the local watch history (off the main grid's critical path).
    unawaited(_loadRecommendations());
  }

  Future<void> _loadRecommendations() async {
    try {
      final history = widget.player.history;
      final anchor = Recommendations.pickAnchor(history);
      if (anchor == null) return;
      final recs =
          await Recommendations.forAnchor(_client, anchor);
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
      // v58: instant first paint on bad networks - show the cached page
      // from disk RIGHT AWAY; the live fetch below replaces it.
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
      // v59: multi-search finds it in ALL shelves - movies AND series.
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
    // v45: in search mode, also fetch "you may also like" from the top
    // hit - a plain search word finds few direct matches otherwise.
    if (_searching && page == 1 && result.items.isNotEmpty) {
      _loadRelated(result.items.first.id, token,
          kind: result.items.first.kind);
    }
    // v61: "show infinite contents in EVERY filter" - after EVERY page
    // lands (not just page 1), schedule a post-frame check that keeps
    // loading the next page until the grid fills the viewport / becomes
    // scrollable or we hit the burst cap. The existing scroll listener
    // (_maybeLoadMore at maxScrollExtent-350) then keeps paging forever
    // as the user scrolls. [token] ties the chain to this filter/search.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && token == _loadToken) _scheduleEndlessFill(token);
    });
  }

  /// v61: chained auto-fill. Called after each page paints; if the grid
  /// still doesn't fill the viewport (or the user is already near the
  /// bottom) and more pages exist, fetch the next one - looping up to
  /// [_kEndlessBurstCap] pages per burst so we never fire unbounded
  /// requests. The in-flight [_loadingMore] guard plus [_endlessPaging]
  /// makes duplicate requests impossible.
  void _scheduleEndlessFill(int token) {
    if (!mounted || token != _loadToken) return;
    if (_initialLoading || _loadingMore || _endlessPaging) return;
    if (_page >= _totalPages) return; // nothing more to fetch
    if (_searching) {
      // Search keeps its single related-fetch behavior; no auto-chain
      // (results are usually specific enough to fill the screen).
      if (_endlessBurst != 0) _endlessBurst = 0;
      return;
    }
    // Decide whether the current content still needs more.
    var needsMore = true;
    if (_scroll.hasClients) {
      final pos = _scroll.position;
      // Content already comfortably fills / overflows the viewport AND
      // we're not near the bottom -> the scroll listener will take over,
      // so stop the auto-chain.
      needsMore = pos.maxScrollExtent <= pos.viewportDimension + 24 ||
          pos.pixels >= pos.maxScrollExtent - 350;
    }
    if (!needsMore) {
      _endlessBurst = 0; // screen is full; hand off to the scroll listener
      return;
    }
    if (_endlessBurst >= _kEndlessBurstCap) {
      // Safety stop for one burst; the next real scroll resumes paging.
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
    _endlessPaging = false; // v61: cancel any in-flight auto-fill chain
    _endlessBurst = 0;
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
    _searchCtrl.clear(); // leaving search mode when a chip is tapped
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

  /// v44: infinite scroll - near the bottom? fetch the next page.
  /// v61: a real user scroll resets the auto-fill burst counter so
  /// scrolling can keep paging "forever" (the cap only bounds the
  /// automatic burst right after a filter is opened).
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
    // Let RefreshIndicator stay up until page 1 actually finished.
    while (_initialLoading && mounted) {
      await Future<void>.delayed(const Duration(milliseconds: 60));
    }
  }

  void _openMovie(TmdbMovie movie) {
    // Match against the ALREADY-scanned library (read-only - the video
    // scan is not touched by Discover at all).
    final match =
        findLocalMovie(movie.title, movie.year, widget.library.allVideos);
    MovieDetailSheet.show(
      context,
      movie: movie,
      localMatch: match,
      player: widget.player,
      detailLoader: () => _client.fullDetail(movie.id, kind: movie.kind),
    );
  }

  /// v58/v59: the AI Suggestor - "describe your movie type" -> real
  /// posters. Lives in the AppBar (user: "move AI suggest to the top").
  Future<void> _openAiSuggest() async {
    final pick = await AiSuggestSheet.show(context);
    if (!mounted || pick == null) return;
    _openMovie(pick);
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
        // v59 (user): AI Suggest moved to the TOP.
        actions: [
          IconButton(
            tooltip: 'AI Suggest - describe your movie type',
            icon: Icon(Icons.auto_awesome, color: themeState.accent),
            onPressed: _openAiSuggest,
          ),
        ],
      ),
      body: _keyMissing
          ? const _SetupNote()
          : Column(
              children: [
                // v44: the section's own search bar (TMDB-wide).
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
                          color: themeState.accent, size: 20),
                      suffixIcon: _searchCtrl.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close,
                                  color: Colors.white54, size: 18),
                              onPressed: () {
                                _searchCtrl.clear();
                                _switchTo(query: '');
                              },
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
                // v59 (user): ONE filter row with EVERYTHING - movie
                // chips AND web series chips side by side (the old
                // Movies|Series toggle is gone).
                SizedBox(
                  height: 40,
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
                        const SizedBox(width: 8),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: RefreshIndicator(
                    color: themeState.accent,
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
      // Kept scrollable so pull-to-refresh always works.
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
            // v65 A6: "Because you watched" - on-device recs from local
            // history (only when not searching and we found matches).
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
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
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
                // v45: BIGGER cards (150 -> 200 wide) so posters actually
                // read like a movie app, not stamps.
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
                    // v44: stable per-MOVIE key -> a recycled cell never
                    // flashes the previous movie's poster after refresh.
                    key: ValueKey(movie.id),
                    movie: movie,
                    onTap: () => _openMovie(movie),
                  );
                },
              ),
            ),
            // v45: related movies under search results.
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
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
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
              color: themeState.accent,
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? themeState.accent
              : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? themeState.onAccent : Colors.white70,
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

/// Shown in local/dev builds where no TMDB key was injected (the store /
/// testers' builds from Codemagic have it). Never a crash, always a note.
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
              '(Developer note: pass the TMDB key via\n'
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
