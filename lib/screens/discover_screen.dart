import 'dart:async';
import 'dart:io';

import 'package:photo_manager/photo_manager.dart';
import 'package:flutter/material.dart';

import '../services/recommendations.dart';
import '../theme.dart';
import '../utils/config.dart';
import '../utils/local_store.dart';
import '../utils/movie_match.dart';
import '../utils/tmdb.dart';
import '../utils/tmdb_image.dart';
import '../widgets/ai_suggest_sheet.dart';
import '../widgets/movie_detail_sheet.dart';

/// "Discover" — OTT-app home screen:
///
/// A Netflix / Prime-Video style front page: a big auto-trending HERO
/// carousel on top (backdrop + title + rating), then horizontal POSTER
/// RAILS — one per section (Trending, Upcoming, Hollywood, Bollywood,
/// Action… plus series rails) — each with its own lazy page loading when
/// it reaches the end. A search bar at the top fully replaces the home
/// with an infinite-scrolling results grid while you type. Tapping any
/// card opens the shared movie detail sheet. ✨ AI Suggestor lives as a
/// floating button.
///
/// Written fresh for v1.0.1+13 — shares only the data layer (TmdbClient,
/// TmdbImage disk cache, MovieDetailSheet) with the rest of the app.
class DiscoverScreen extends StatefulWidget {
  /// The already-scanned local library — used ONLY for "In my library"
  /// matching (read-only; the video scan is never touched).
  final List<AssetEntity> videos;

  const DiscoverScreen({super.key, required this.videos});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

/// Mutable state bucket per horizontal rail.
class _RailState {
  final DiscoverFilter filter;
  final ScrollController scroll;
  final List<TmdbMovie> items = [];
  final Set<int> seen = {};
  int page = 0;
  int totalPages = 1;
  bool loading = false;
  bool failed = false;

  _RailState(this.filter) : scroll = ScrollController();

  String get title => filter.tv ? '${filter.label} • Series' : filter.label;
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  final TmdbClient _client = TmdbClient();
  final TextEditingController _searchCtrl = TextEditingController();
  final PageController _heroCtrl = PageController(viewportFraction: 0.92);
  Timer? _searchDebounce;
  Timer? _heroTimer;

  /// Hero pages: trending titles that carry a backdrop image.
  List<TmdbMovie> _hero = [];
  int _heroIndex = 0;

  final List<_RailState> _rails = [for (final f in kAllFilters) _RailState(f)];

  // Search grid (home is hidden while searching, OTT-style "Search" tab).
  final ScrollController _grid = ScrollController();
  final List<TmdbMovie> _results = [];
  final Set<int> _resultIds = {};
  String _query = '';
  int _queryPage = 0;
  int _queryTotalPages = 1;
  bool _queryLoading = false;
  List<TmdbMovie> _similar = const [];

  RecentItem? _anchor;
  List<TmdbMovie> _pickedForYou = const [];

  bool _booting = true;
  bool _keyMissing = false;
  int _token = 0; // stale-response guard
  bool get _searching => _query.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _grid.addListener(_onGridEnd);
    _bootstrap();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _heroTimer?.cancel();
    _heroCtrl.dispose();
    _searchCtrl.dispose();
    _grid.dispose();
    for (final r in _rails) {
      r.scroll.dispose();
    }
    super.dispose();
  }

  // ---------------------------------------------------------------- boot

  Future<void> _bootstrap() async {
    final cachePath = await TmdbImage.initCacheDir();
    TmdbImage.configure(cachePath);
    if (cachePath != null) _client.cacheDir = Directory(cachePath);
    if (!mounted) return;
    if (AppConfig.tmdbToken.isEmpty) {
      setState(() {
        _keyMissing = true;
        _booting = false;
      });
      return;
    }

    // Instant first paint from TMDB's 24h disk cache (one per rail).
    for (final r in _rails) {
      final cached = await _client.cachedBrowseFirstPage(r.filter);
      if (!mounted) return;
      if (cached != null && r.items.isEmpty) {
        setState(() {
          for (final m in cached.items) {
            if (r.seen.add(m.id)) r.items.add(m);
          }
          r.page = 1;
          r.totalPages = cached.totalPages;
        });
      }
    }
    setState(() => _booting = false);
    _rebuildHero();

    // Live refresh of every rail — chunked so the first (Trending) rail
    // lands before the network fan-out continues.
    unawaited(_loadFirstPages());
    unawaited(_loadRecommendations());
  }

  Future<void> _loadFirstPages() async {
    final token = _token;
    const chunk = 4;
    for (var i = 0; i < _rails.length; i += chunk) {
      final slice = _rails.sublist(
        i,
        (i + chunk) > _rails.length ? _rails.length : (i + chunk),
      );
      await Future.wait(slice.map((r) => _fillRail(r, 1)));
      if (!mounted || token != _token) return;
      _rebuildHero();
    }
  }

  Future<void> _loadRecommendations() async {
    try {
      final history = await LocalStore().recent();
      final anchor = Recommendations.pickAnchor(history);
      if (anchor == null) return;
      final recs = await Recommendations.forAnchor(_client, anchor);
      if (!mounted) return;
      setState(() {
        _anchor = anchor;
        _pickedForYou = recs;
      });
    } catch (_) {}
  }

  // ---------------------------------------------------------------- rails

  Future<void> _fillRail(_RailState r, int page) async {
    if (r.loading || (page != 1 && r.page >= r.totalPages)) return;
    r.loading = true;
    TmdbPage result;
    try {
      result = await _client.browse(r.filter, page: page);
    } catch (_) {
      result = const TmdbPage();
    }
    r.loading = false;
    if (!mounted) return;
    setState(() {
      if (result.items.isEmpty) {
        r.failed = r.items.isEmpty;
        return;
      }
      r.page = result.page;
      r.totalPages = result.totalPages;
      r.failed = false;
      for (final m in result.items) {
        if (r.seen.add(m.id)) r.items.add(m);
      }
    });
  }

  void _attachRailEndProbing(_RailState r) {
    if (!r.scroll.hasClients) return;
    final pos = r.scroll.position;
    if (pos.pixels > pos.maxScrollExtent - 250 &&
        r.page < r.totalPages &&
        !r.loading) {
      _fillRail(r, r.page + 1);
    }
  }

  void _rebuildHero() {
    // Hero carries trending titles that have a TRUE backdrop (16:9) —
    // posters would crop badly in the wide frame.
    final trending = _rails.isEmpty ? const <TmdbMovie>[] : _rails.first.items;
    final withBackdrop = trending
        .where((m) => (m.backdropPath ?? '').isNotEmpty)
        .toList();
    if (withBackdrop.length > _hero.length || _hero.isEmpty) {
      setState(() => _hero = withBackdrop.take(6).toList());
      _restartHeroTimer();
    }
  }

  void _restartHeroTimer() {
    _heroTimer?.cancel();
    if (_hero.length < 2) return;
    _heroTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (!mounted || !_heroCtrl.hasClients || _hero.isEmpty) return;
      final next = (_heroIndex + 1) % _hero.length;
      _heroCtrl.animateToPage(
        next,
        duration: const Duration(milliseconds: 550),
        curve: Curves.easeInOutCubic,
      );
    });
  }

  // --------------------------------------------------------------- search

  void _onSearchChanged(String v) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      final q = v.trim();
      if (q != _query) _startSearch(q);
    });
  }

  Future<void> _startSearch(String q) async {
    setState(() {
      _query = q;
      _results.clear();
      _resultIds.clear();
      _queryPage = 0;
      _queryTotalPages = 1;
      _similar = const [];
    });
    if (q.isEmpty) return;
    await _searchMore(1);
    if (_results.isNotEmpty && mounted) {
      final first = _results.first;
      List<TmdbMovie> sim;
      try {
        sim = await _client.similar(first.id, kind: first.kind);
      } catch (_) {
        sim = const [];
      }
      if (mounted && _query == q) {
        setState(() => _similar = sim.take(12).toList());
      }
    }
  }

  Future<void> _searchMore(int page) async {
    if (_queryLoading ||
        _query.isEmpty ||
        (page > 1 && _queryPage >= _queryTotalPages)) {
      return;
    }
    _queryLoading = true;
    TmdbPage result;
    try {
      result = await _client.searchMulti(_query, page: page);
    } catch (_) {
      result = const TmdbPage();
    }
    _queryLoading = false;
    if (!mounted) return;
    setState(() {
      _queryPage = result.page;
      _queryTotalPages = result.totalPages;
      for (final m in result.items) {
        if (_resultIds.add(m.id)) _results.add(m);
      }
    });
  }

  void _onGridEnd() {
    if (!_grid.hasClients || _queryLoading) return;
    final pos = _grid.position;
    if (pos.pixels >= pos.maxScrollExtent - 350) {
      _searchMore(_queryPage + 1);
    }
  }

  // --------------------------------------------------------------- detail

  void _openMovie(TmdbMovie movie) {
    final match = findLocalMovie(movie.title, movie.year, widget.videos);
    MovieDetailSheet.show(
      context,
      movie: movie,
      localMatch: match,
      detailLoader: () => _client.fullDetail(movie.id, kind: movie.kind),
    );
  }

  Future<void> _aiSuggest() async {
    final movie = await AiSuggestSheet.show(context);
    if (movie != null && mounted) _openMovie(movie);
  }

  Future<void> _refreshAll() async {
    _token++;
    setState(() {
      for (final r in _rails) {
        r.items.clear();
        r.seen.clear();
        r.page = 0;
        r.totalPages = 1;
        r.failed = false;
      }
      _hero = const [];
      _pickedForYou = const [];
    });
    await Future.wait([
      for (final r in _rails) _fillRail(r, 1),
      _loadRecommendations(),
    ]);
    _rebuildHero();
  }

  // ----------------------------------------------------------------- ui

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0d0d12),
      floatingActionButton: _searching
          ? null
          : FloatingActionButton.small(
              heroTag: 'ai-suggest',
              backgroundColor: AppColors.accent,
              foregroundColor: AppColors.onAccent,
              tooltip: 'AI Suggestor',
              onPressed: _aiSuggest,
              child: const Text('✨', style: TextStyle(fontSize: 16)),
            ),
      body: _keyMissing
          ? _buildKeyMissing()
          : SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildSearchBar(),
                  Expanded(
                    child: _searching ? _buildSearchResults() : _buildOttHome(),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
            color: _searching
                ? AppColors.accent.withValues(alpha: 0.6)
                : Colors.white10,
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.search, color: Colors.white54, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _searchCtrl,
                style: const TextStyle(color: Colors.white, fontSize: 14.5),
                decoration: const InputDecoration(
                  hintText: 'Search movies & series…',
                  hintStyle: TextStyle(color: Colors.white30, fontSize: 14),
                  border: InputBorder.none,
                ),
                onChanged: _onSearchChanged,
              ),
            ),
            if (_searchCtrl.text.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white54, size: 19),
                onPressed: () {
                  _searchCtrl.clear();
                  _startSearch('');
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildKeyMissing() {
    return const SafeArea(
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.vpn_key_off, color: Colors.white24, size: 46),
              SizedBox(height: 14),
              Text(
                'TMDB key missing',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Build with --dart-define=TMDB_TOKEN=… to enable the OTT home.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white38, fontSize: 12.5),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------ OTT home

  Widget _buildOttHome() {
    if (_booting && _hero.isEmpty && _rails.every((r) => r.items.isEmpty)) {
      return const _OttSkeleton();
    }
    return RefreshIndicator(
      onRefresh: _refreshAll,
      color: AppColors.accent,
      backgroundColor: const Color(0xFF1a1a22),
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: _hero.isEmpty
                ? const SizedBox(
                    height: 210,
                    child: Center(
                      child: CircularProgressIndicator(color: Colors.white24),
                    ),
                  )
                : _HeroCarousel(
                    controller: _heroCtrl,
                    items: _hero,
                    onPageChanged: (i) => _heroIndex = i,
                    onTap: _openMovie,
                  ),
          ),
          if (_pickedForYou.isNotEmpty && _anchor != null)
            SliverToBoxAdapter(
              child: _PosterRail(
                title: 'Because you watched ${_anchor!.title}',
                movies: _pickedForYou,
                onTap: _openMovie,
              ),
            ),
          for (final r in _rails)
            SliverToBoxAdapter(
              child: NotificationListener<ScrollNotification>(
                onNotification: (n) {
                  if (n is ScrollUpdateNotification ||
                      n is ScrollEndNotification) {
                    _attachRailEndProbing(r);
                  }
                  return false;
                },
                child: _PosterRail(
                  title: r.title,
                  movies: r.items,
                  scrollController: r.scroll,
                  loading: r.loading,
                  failed: r.failed,
                  onRetry: () => _fillRail(r, 1),
                  onTap: _openMovie,
                ),
              ),
            ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 22),
              child: Text(
                'Posters & data via TMDB — tiles you own play in-app.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.25),
                  fontSize: 10.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------- search grid

  Widget _buildSearchResults() {
    if (_results.isEmpty && !_queryLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(28),
          child: Text(
            'No movies or series match that title.',
            style: TextStyle(color: Colors.white38, fontSize: 13),
          ),
        ),
      );
    }
    return CustomScrollView(
      controller: _grid,
      slivers: [
        if (_similar.isNotEmpty)
          SliverToBoxAdapter(
            child: _PosterRail(
              title: 'Similar to ${_results.first.title}',
              movies: _similar,
              onTap: _openMovie,
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 20),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 0.55,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
            ),
            delegate: SliverChildBuilderDelegate((context, i) {
              final m = _results[i];
              return _PosterCard(movie: m, onTap: () => _openMovie(m));
            }, childCount: _results.length),
          ),
        ),
        if (_queryLoading)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(18),
              child: Center(
                child: CircularProgressIndicator(color: Colors.white24),
              ),
            ),
          ),
      ],
    );
  }
}

// ============================================================================
// OTT visual blocks — all built fresh for this screen.
// ============================================================================

/// Auto-rotating 16:9 backdrop carousel — the "billboard" every OTT app
/// opens with (backdrop art, gradient scrim, title, rating, dots).
class _HeroCarousel extends StatelessWidget {
  final PageController controller;
  final List<TmdbMovie> items;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<TmdbMovie> onTap;

  const _HeroCarousel({
    required this.controller,
    required this.items,
    required this.onPageChanged,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 218,
          child: PageView.builder(
            controller: controller,
            itemCount: items.length,
            onPageChanged: onPageChanged,
            itemBuilder: (context, i) {
              final m = items[i];
              final url = tmdbBackdropUrl(m.backdropPath);
              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 5,
                  vertical: 10,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Container(color: const Color(0xFF1a1a24)),
                      if (url.isNotEmpty)
                        TmdbImage(url: url, fit: BoxFit.cover),
                      // bottom scrim
                      IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.78),
                              ],
                            ),
                          ),
                        ),
                      ),
                      // title / meta / tap
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => onTap(m),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                            child: Align(
                              alignment: Alignment.bottomLeft,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _MetaChips(movie: m),
                                  const SizedBox(height: 6),
                                  Text(
                                    m.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 20,
                                      fontWeight: FontWeight.w800,
                                      height: 1.1,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        _HeroDots(controller: controller, count: items.length),
      ],
    );
  }
}

class _HeroDots extends StatefulWidget {
  final PageController controller;
  final int count;
  const _HeroDots({required this.controller, required this.count});

  @override
  State<_HeroDots> createState() => _HeroDotsState();
}

class _HeroDotsState extends State<_HeroDots> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onScroll);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    if (!mounted || !widget.controller.hasClients) return;
    final p = widget.controller.page;
    if (p != null && p.round() != _index) {
      setState(() => _index = p.round().clamp(0, widget.count - 1));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < widget.count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            margin: const EdgeInsets.symmetric(horizontal: 2.5),
            width: i == _index ? 18 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: i == _index ? AppColors.accent : Colors.white24,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
      ],
    );
  }
}

/// One horizontal rail of posters with a section header. Cards show
/// poster art (disk-cached via TmdbImage), title, rating.
class _PosterRail extends StatelessWidget {
  final String title;
  final List<TmdbMovie> movies;
  final ScrollController? scrollController;
  final bool loading;
  final bool failed;
  final VoidCallback? onRetry;
  final ValueChanged<TmdbMovie> onTap;

  const _PosterRail({
    required this.title,
    required this.movies,
    this.scrollController,
    this.loading = false,
    this.failed = false,
    this.onRetry,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (movies.isEmpty && failed) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _RailHeader(title: title),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 18),
            child: InkWell(
              onTap: onRetry,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                height: 96,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white12),
                ),
                child: Text(
                  'Tap to retry',
                  style: TextStyle(
                    color: AppColors.accent.withValues(alpha: 0.85),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }
    if (movies.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _RailHeader(title: title),
          SizedBox(
            height: 196,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              scrollDirection: Axis.horizontal,
              itemCount: 6,
              itemBuilder: (_, _) => const _PosterSkeletonCard(),
              separatorBuilder: (_, _) => const SizedBox(width: 10),
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _RailHeader(title: title, onRefresh: null),
        SizedBox(
          height: 196,
          child: NotificationListener<ScrollNotification>(
            onNotification: (_) => false,
            child: ListView.builder(
              controller: scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              scrollDirection: Axis.horizontal,
              itemCount: movies.length,
              itemBuilder: (context, i) {
                final m = movies[i];
                return Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: _PosterCard(movie: m, onTap: () => onTap(m)),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _RailHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onRefresh;
  const _RailHeader({required this.title, this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: AppColors.accent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
              ),
            ),
          ),
          if (onRefresh != null)
            Icon(Icons.chevron_right, color: AppColors.accent, size: 19),
        ],
      ),
    );
  }
}

class _PosterCard extends StatelessWidget {
  final TmdbMovie movie;
  final VoidCallback onTap;

  const _PosterCard({required this.movie, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final posterUrl = tmdbPosterUrl(movie.posterPath);
    return SizedBox(
      width: 122,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 2 / 3,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Container(color: const Color(0xFF1c1c26)),
                    if (posterUrl.isNotEmpty)
                      TmdbImage(url: posterUrl, fit: BoxFit.cover),
                    if (movie.rating > 0)
                      Positioned(
                        bottom: 6,
                        left: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            '★ ${tmdbRatingText(movie.rating)}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              movie.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11.5,
                height: 1.15,
              ),
            ),
            if (movie.year != null)
              Text(
                '${movie.year}',
                style: const TextStyle(color: Colors.white38, fontSize: 10),
              ),
          ],
        ),
      ),
    );
  }
}

class _PosterSkeletonCard extends StatelessWidget {
  const _PosterSkeletonCard();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 122,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 2 / 3,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(color: Colors.white.withValues(alpha: 0.04)),
            ),
          ),
          const SizedBox(height: 6),
          Container(
            height: 11,
            width: 90,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 4),
          Container(
            height: 9,
            width: 34,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ],
      ),
    );
  }
}

/// The splash shown while the very first paint assembles — Netflix-style
/// "skeleton" home with a big hero block + three placeholder rails.
class _OttSkeleton extends StatelessWidget {
  const _OttSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 16),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Container(
              height: 198,
              color: Colors.white.withValues(alpha: 0.03),
            ),
          ),
          const SizedBox(height: 22),
          for (var r = 0; r < 3; r++)
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 12,
                    width: 120,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      for (var i = 0; i < 4; i++)
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(right: i == 3 ? 0 : 8),
                            child: AspectRatio(
                              aspectRatio: 2 / 3,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  color: Colors.white.withValues(alpha: 0.04),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Year + score + kind badges under the hero title.
class _MetaChips extends StatelessWidget {
  final TmdbMovie movie;
  const _MetaChips({required this.movie});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        if (movie.year != null) _chip('${movie.year}'),
        if (movie.rating > 0) _chip('★ ${tmdbRatingText(movie.rating)}'),
        _chip(movie.kind == 'tv' ? 'Series' : 'Movie'),
      ],
    );
  }

  Widget _chip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white24),
      ),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white, fontSize: 10.5),
      ),
    );
  }
}

