import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:photo_manager/photo_manager.dart';

import '../services/native_bridge.dart';
import '../services/recommendations.dart';
import '../theme.dart';
import '../utils/config.dart';
import '../utils/local_store.dart';
import '../utils/movie_match.dart';
import '../utils/tmdb.dart';
import '../utils/tmdb_image.dart';
import '../widgets/ai_suggest_sheet.dart';
import 'movie_detail_screen.dart';

/// "Discover" — OTT platform home, rebuilt from scratch (v1.0.1+15).
///
/// Layout, top to bottom:
///   1. Search bar row — search field + mic (voice search) + gradient
///      "AI" Suggestor pill. Auto-hides while scrolling the feed down and
///      reappears on scroll-up; ALWAYS visible while search is focused.
///   2. Full-bleed HERO carousel of trending titles (16:9-ish backdrop,
///      title + chips + Details button, dot indicators, auto-advance).
///   3. Horizontal poster rails, one per TMDB section (now also: Indian
///      regional movies + Indian serial/TV rails).
///   4. While typing, the home swaps for an infinite results grid.
///
/// Cards are laid out with FULLY-reserved text space (2 title lines + year
/// line) so titles can't be clipped, on ALL display sizes.
class DiscoverScreen extends StatefulWidget {
  /// The already-scanned local library, used ONLY for "in my library"
  /// matching on tap (read-only; the scan itself is never touched).
  final List<AssetEntity> videos;

  const DiscoverScreen({super.key, required this.videos});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

/// Per-rail mutable state.
class _RailState {
  final DiscoverFilter filter;
  final ScrollController scroll = ScrollController();
  final List<TmdbMovie> items = [];
  final Set<int> seen = {};
  int page = 0;
  int totalPages = 1;
  bool loading = false;
  bool failed = false;

  _RailState(this.filter);

  String get title => filter.tv ? '${filter.label} • Series' : filter.label;
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  final TmdbClient _client = TmdbClient();
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  final PageController _heroCtrl = PageController();
  final ScrollController _homeScroll = ScrollController();
  Timer? _searchDebounce;
  Timer? _heroTimer;

  /// Top bar auto-hide: slides away while scrolling down, instantly back
  /// when scrolling up (and always visible while the search field has
  /// focus or a query is active). v1.0.1+16.
  bool _topBarVisible = true;
  double _lastHomePixels = 0;

  List<TmdbMovie> _hero = [];
  int _heroIndex = 0;

  final List<_RailState> _rails = [for (final f in kAllFilters) _RailState(f)];

  RecentItem? _anchor;
  List<TmdbMovie> _pickedForYou = const [];

  // Search-mode state
  String _query = '';
  final List<TmdbMovie> _results = [];
  final Set<int> _resultIds = {};
  int _queryPage = 0;
  int _queryTotalPages = 1;
  bool _queryLoading = false;
  final ScrollController _gridScroll = ScrollController();

  bool _booting = true;
  bool _keyMissing = false;
  bool _voiceSearching = false;
  int _token = 0;

  bool get _searching => _query.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _gridScroll.addListener(_onGridEnd);
    _homeScroll.addListener(_onHomeScroll);
    _searchFocus.addListener(_onSearchFocus);
    _bootstrap();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _heroTimer?.cancel();
    _heroCtrl.dispose();
    _homeScroll.dispose();
    _gridScroll.dispose();
    _searchFocus.dispose();
    _searchCtrl.dispose();
    for (final r in _rails) {
      r.scroll.dispose();
    }
    super.dispose();
  }

  // ------------------------------------------------------------- data ---

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

    // First paint: whatever TMDB's 24h disk cache holds (stale-ok).
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
    unawaited(_loadFirstPages());
    unawaited(_loadRecommendations());
  }

  Future<void> _loadFirstPages() async {
    final token = _token;
    const chunk = 4;
    for (var i = 0; i < _rails.length; i += chunk) {
      final end = (i + chunk) > _rails.length ? _rails.length : (i + chunk);
      await Future.wait(_rails.sublist(i, end).map((r) => _fillRail(r, 1)));
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

  Future<void> _fillRail(_RailState r, int page) async {
    if (r.loading || (page != 1 && (r.page >= r.totalPages || page > 2))) {
      return;
    }
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

  void _rebuildHero() {
    final trending = _rails.isEmpty ? const <TmdbMovie>[] : _rails.first.items;
    final withBackdrop = trending
        .where((m) => (m.backdropPath ?? '').isNotEmpty)
        .toList();
    if (withBackdrop.length >= _hero.length || _hero.isEmpty) {
      setState(() => _hero = withBackdrop.take(7).toList());
      _restartHeroTimer();
    }
  }

  void _restartHeroTimer() {
    _heroTimer?.cancel();
    if (_hero.length < 2) return;
    _heroTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (!mounted || !_heroCtrl.hasClients || _hero.isEmpty) return;
      // If the user is currently interacting, skip this frame.
      if (_heroCtrl.position.isScrollingNotifier.value) return;
      final next = (_heroIndex + 1) % _hero.length;
      _heroCtrl.animateToPage(
        next,
        duration: const Duration(milliseconds: 550),
        curve: Curves.easeInOutCubic,
      );
    });
  }

  // ----------------------------------------------------------- search ---

  void _onSearchFocus() {
    if (mounted) setState(() {});
  }

  /// Auto-hide top bar on downward scroll; always re-shows on the way up.
  void _onHomeScroll() {
    if (!_homeScroll.hasClients) return;
    final pixels = _homeScroll.position.pixels;
    final delta = pixels - _lastHomePixels;
    if (delta.abs() < 8) return;
    _lastHomePixels = pixels;
    final shouldShow = delta < 0 || pixels < 80;
    if (shouldShow != _topBarVisible) {
      setState(() => _topBarVisible = shouldShow);
    }
  }

  void _onSearchChanged(String v) {
    setState(() {}); // swap clear-button visibility instantly
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      final q = v.trim();
      if (q != _query) _startSearch(q);
    });
  }

  Future<void> _startVoiceSearch() async {
    if (_voiceSearching) return;
    final mic = await Permission.microphone.request();
    if (!mounted) return;
    if (!mic.isGranted) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          const SnackBar(
            content: Text('Microphone needed for voice search'),
            duration: Duration(milliseconds: 1800),
          ),
        );
      return;
    }
    setState(() => _voiceSearching = true);
    final query = await NativeBridge.launchSystemVoiceSearch();
    if (!mounted) return;
    setState(() => _voiceSearching = false);
    if (query == null || query.isEmpty) return;
    _searchCtrl.text = query;
    _onSearchChanged(query);
  }

  Future<void> _startSearch(String q) async {
    setState(() {
      _query = q;
      _results.clear();
      _resultIds.clear();
      _queryPage = 0;
      _queryTotalPages = 1;
    });
    if (q.isEmpty) return;
    await _searchMore(1);
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
    if (!_gridScroll.hasClients || _queryLoading) return;
    final pos = _gridScroll.position;
    if (pos.pixels >= pos.maxScrollExtent - 350) {
      _searchMore(_queryPage + 1);
    }
  }

  // -------------------------------------------------------- navigation ---

  void _openMovie(TmdbMovie movie) {
    final match = findLocalMovie(movie.title, movie.year, widget.videos);
    MovieDetailScreen.open(
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

  // ----------------------------------------------------------------- ui ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0a0a10),
      body: _keyMissing
          ? const _NoKeyBody()
          : SafeArea(
              child: Column(
                children: [
                  // Top bar slides away when scrolling the home feed
                  // down and returns the moment the user scrolls back
                  // up. NEVER hides while search is focused/active.
                  AnimatedSize(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeInOutCubic,
                    alignment: Alignment.topCenter,
                    child:
                        (_topBarVisible || _searching || _searchFocus.hasFocus)
                        ? _buildSearchBar()
                        : const SizedBox(width: double.infinity),
                  ),
                  Expanded(
                    child: _searching
                        ? _buildSearchResults()
                        : (_searchFocus.hasFocus
                              ? _buildHotSearches()
                              : _buildOttHome()),
                  ),
                ],
              ),
            ),
    );
  }

  /// Pinned top bar — a fixed-height row, always on screen no matter how
  /// far the OTT home scrolls: search field, voice mic, ✨ AI Suggestor.
  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0a0a10),
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
        ),
      ),
      child: Row(
        children: [
          // Search field
          Expanded(
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: _searching
                      ? AppColors.accent.withValues(alpha: 0.6)
                      : Colors.white10,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.search,
                    color: _searching ? AppColors.accent : Colors.white54,
                    size: 19,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      focusNode: _searchFocus,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14.5,
                      ),
                      decoration: const InputDecoration(
                        hintText: 'Search movies, series…',
                        hintStyle: TextStyle(
                          color: Colors.white30,
                          fontSize: 14,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                      ),
                      onChanged: _onSearchChanged,
                    ),
                  ),
                  if (_searchCtrl.text.isNotEmpty)
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        _searchCtrl.clear();
                        _startSearch('');
                      },
                      child: const Padding(
                        padding: EdgeInsets.all(3),
                        child: Icon(
                          Icons.close,
                          color: Colors.white54,
                          size: 18,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          // Voice search
          SizedBox(
            width: 40,
            height: 40,
            child: IconButton(
              icon: _voiceSearching
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        color: Colors.white54,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(
                      Icons.mic_none_rounded,
                      color: Colors.white70,
                      size: 21,
                    ),
              tooltip: 'Voice search',
              onPressed: _startVoiceSearch,
            ),
          ),
          // AI Suggestor — gradient pill (redesigned v1.0.1+16; the small
          // ✨-in-a-circle read as an accident, not a button).
          Tooltip(
            message: 'AI Suggestor',
            child: InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: _aiSuggest,
              child: Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 13),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF7B61FF), Color(0xFFE553B3)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF7B61FF).withValues(alpha: 0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.auto_awesome, color: Colors.white, size: 16),
                    SizedBox(width: 6),
                    Text(
                      'AI',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ home ---

  Widget _buildOttHome() {
    final contentEmpty = _hero.isEmpty && _rails.every((r) => r.items.isEmpty);
    if (_booting && contentEmpty) return const _OttSkeleton();

    return RefreshIndicator(
      onRefresh: _refreshAll,
      color: AppColors.accent,
      backgroundColor: const Color(0xFF1a1a22),
      child: CustomScrollView(
        controller: _homeScroll,
        slivers: [
          SliverToBoxAdapter(
            child: _hero.isEmpty
                ? const SizedBox(
                    height: 236,
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
                    if (r.scroll.hasClients) {
                      final pos = r.scroll.position;
                      if (pos.pixels > pos.maxScrollExtent - 250 &&
                          r.page < r.totalPages &&
                          !r.loading) {
                        _fillRail(r, r.page + 1);
                      }
                    }
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
          // v1.0.1+16: TMDB credit line removed per request — plain
          // bottom padding instead.
          const SliverToBoxAdapter(child: SizedBox(height: 26)),
        ],
      ),
    );
  }

  // -------------------------------------------------------- results ---

  /// 🔥 Hot searches — shown the moment the search field gets focus,
  /// before anything is typed: TMDB's current trending titles. Fixes the
  /// "tapping search shows a blank container" complaint (v1.0.1+16).
  Widget _buildHotSearches() {
    final source = _hero.isNotEmpty
        ? _hero
        : (_rails.isNotEmpty ? _rails.first.items : const <TmdbMovie>[]);
    if (source.isEmpty) return _buildOttHome();
    final items = source.take(12).toList();
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 24),
      itemCount: items.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) {
          return const Padding(
            padding: EdgeInsets.fromLTRB(4, 4, 4, 10),
            child: Row(
              children: [
                Icon(
                  Icons.local_fire_department_rounded,
                  color: Colors.deepOrangeAccent,
                  size: 21,
                ),
                SizedBox(width: 7),
                Text(
                  'Hot searches',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          );
        }
        final m = items[i - 1];
        final hot = i <= 3;
        return InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            _searchCtrl.text = m.title;
            _onSearchChanged(m.title);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 9),
            child: Row(
              children: [
                SizedBox(
                  width: 30,
                  child: hot
                      ? const Icon(
                          Icons.local_fire_department_rounded,
                          color: Colors.deepOrangeAccent,
                          size: 17,
                        )
                      : Text(
                          '$i',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.35),
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    m.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 13.5,
                      fontWeight: hot ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${m.kind == 'tv' ? 'Series' : 'Movie'}'
                  '${m.year != null ? ' • ${m.year}' : ''}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.35),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Placeholder poster grid while the first search page loads — the old
  /// code left a big blank container with a spinner at the bottom.
  Widget _buildSearchSkeleton() {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 20),
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.56,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
      ),
      itemCount: 9,
      itemBuilder: (_, i) => const _SearchSkeletonTile(),
    );
  }

  Widget _buildSearchResults() {
    if (_results.isEmpty && _queryLoading) {
      return _buildSearchSkeleton();
    }
    if (_results.isEmpty) {
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
      controller: _gridScroll,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 20),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 0.56,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, i) => _PosterCard(movie: _results[i]),
            ),
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

// ==========================================================================
// visual parts (all fresh code for this screen)
// ==========================================================================

/// Full-width auto-rotating trending billboard: backdrop art, gradient
/// scrim, title + chips + Details CTA, plus dot indicators under it.
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
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 222,
          child: PageView.builder(
            controller: controller,
            itemCount: items.length,
            onPageChanged: onPageChanged,
            itemBuilder: (context, i) {
              final m = items[i];
              final url = tmdbBackdropUrl(m.backdropPath);
              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Container(color: const Color(0xFF181822)),
                      if (url.isNotEmpty)
                        TmdbImage(url: url, fit: BoxFit.cover),
                      // bottom scrim
                      IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              stops: const [0.35, 1.0],
                              colors: [
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.85),
                              ],
                            ),
                          ),
                        ),
                      ),
                      // content
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => onTap(m),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Spacer(),
                                _MetaChips(movie: m),
                                const SizedBox(height: 7),
                                Text(
                                  m.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 21,
                                    fontWeight: FontWeight.w900,
                                    height: 1.1,
                                    letterSpacing: 0.15,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Text(
                                    'DETAILS',
                                    style: TextStyle(
                                      color: Colors.black,
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 1.1,
                                    ),
                                  ),
                                ),
                              ],
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
    if (p != null) {
      final idx = p.round().clamp(0, widget.count - 1);
      if (idx != _index) setState(() => _index = idx);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < widget.count; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              margin: const EdgeInsets.symmetric(horizontal: 2.5),
              width: i == _index ? 16 : 5,
              height: 5,
              decoration: BoxDecoration(
                color: i == _index
                    ? AppColors.accent
                    : Colors.white.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
        ],
      ),
    );
  }
}

/// One horizontal rail of posters, sized so TWO title lines + year always
/// fit: poster(130*1.5=195) + 6 + title(30) + 2 + year(11) = 244.
class _PosterRail extends StatelessWidget {
  static const double cardWidth = 130;
  static const double cardHeight = 244;

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
      return _RailError(title: title, onRetry: onRetry);
    }
    if (movies.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _RailHeader(title: title),
          SizedBox(
            height: _PosterRail.cardHeight,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              scrollDirection: Axis.horizontal,
              itemCount: 5,
              itemBuilder: (_, _) => const _PosterSkeleton(),
              separatorBuilder: (_, _) => const SizedBox(width: 10),
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _RailHeader(title: title),
        SizedBox(
          height: _PosterRail.cardHeight,
          child: ListView.builder(
            controller: scrollController,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            scrollDirection: Axis.horizontal,
            itemCount: movies.length,
            itemBuilder: (context, i) => Padding(
              padding: const EdgeInsets.only(right: 10),
              child: _PosterCard(movie: movies[i]),
            ),
          ),
        ),
      ],
    );
  }
}

class _RailHeader extends StatelessWidget {
  final String title;
  const _RailHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 9),
      child: Row(
        children: [
          Container(
            width: 11,
            height: 11,
            decoration: BoxDecoration(
              color: AppColors.accent,
              borderRadius: BorderRadius.circular(2.5),
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
                fontSize: 15,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
              ),
            ),
          ),
          Icon(
            Icons.chevron_right,
            color: Colors.white.withValues(alpha: 0.35),
            size: 18,
          ),
        ],
      ),
    );
  }
}

class _RailError extends StatelessWidget {
  final String title;
  final VoidCallback? onRetry;
  const _RailError({required this.title, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _RailHeader(title: title),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 16),
          child: InkWell(
            onTap: onRetry,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              height: 84,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white10),
              ),
              child: Text(
                'Could not load — tap to retry',
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
}

/// Poster card used on rails and in the search grid: art + EXACTLY two
/// reserved title lines + one year line. Tap goes to the detail screen via
/// the shared helper below.
class _PosterCard extends StatelessWidget {
  final TmdbMovie movie;

  const _PosterCard({required this.movie});

  @override
  Widget build(BuildContext context) {
    final posterUrl = tmdbPosterUrl(movie.posterPath);
    return SizedBox(
      width: _PosterRail.cardWidth,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _openMovieDefault(context, movie),
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
                      Container(color: const Color(0xFF1a1a26)),
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
                              color: Colors.black.withValues(alpha: 0.6),
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
              SizedBox(
                // exactly two full lines at 11.5/1.15 — never clipped
                height: 30,
                child: Text(
                  movie.title,
                  maxLines: 2,
                  softWrap: true,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11.5,
                    height: 1.15,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              SizedBox(
                height: 11,
                child: Text(
                  movie.year != null ? '${movie.year}' : ' ',
                  maxLines: 1,
                  style: const TextStyle(color: Colors.white38, fontSize: 10),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Default tap when the card is used without a custom handler (search grid
/// cases where the state object isn't visible to the handler): opens the
/// detail page through a BuildContext that carries the scanned library.
void _openMovieDefault(BuildContext context, TmdbMovie movie) {
  final state = context.findAncestorStateOfType<_DiscoverScreenState>();
  if (state != null) {
    state._openMovie(movie);
  }
}

class _PosterSkeleton extends StatelessWidget {
  const _PosterSkeleton();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _PosterRail.cardWidth,
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
            height: 10,
            width: 90,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 5),
          Container(
            height: 10,
            width: 60,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ],
      ),
    );
  }
}

/// Splash skeleton while first paint assembles.
class _OttSkeleton extends StatelessWidget {
  const _OttSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 16),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Container(
              height: 202,
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
                    width: 130,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      for (var i = 0; i < 3; i++)
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(right: i == 2 ? 0 : 8),
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
        color: Colors.white.withValues(alpha: 0.14),
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

class _NoKeyBody extends StatelessWidget {
  const _NoKeyBody();

  @override
  Widget build(BuildContext context) {
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
                'Build with --dart-define=TMDB_TOKEN=… to enable Discover.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white38, fontSize: 12.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Placeholder tile used by the search skeleton grid (v1.0.1+16) — same
/// 2:3-ish card proportions as the real poster cards.
class _SearchSkeletonTile extends StatelessWidget {
  const _SearchSkeletonTile();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        const SizedBox(height: 6),
        FractionallySizedBox(
          widthFactor: 0.75,
          child: Container(
            height: 12,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(5),
            ),
          ),
        ),
        const SizedBox(height: 5),
        FractionallySizedBox(
          widthFactor: 0.4,
          child: Container(
            height: 9,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
      ],
    );
  }
}

