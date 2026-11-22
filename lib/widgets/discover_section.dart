import '../theme.dart';
import 'remote_tap.dart';
import 'recent_search_field.dart';
import '../utils/app_language.dart';

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../screens/movie_detail_screen.dart';
import '../services/native_bridge.dart';
import '../utils/config.dart';
import '../utils/tmdb.dart';
import '../utils/tmdb_image.dart';
import 'ai_suggest_sheet.dart';
import 'discover_banner.dart';

/// Pure. Subtitle under the Discover page header — how much catalogue
/// sits behind the current filter/search ("10,000 titles" era, v1.0.1+20).
String catalogTitleCount(int totalPages) {
  final approx = totalPages * 20;
  if (approx >= 10000) {
    return '10,000+ titles - scroll for more';
  }
  if (approx >= 1000) {
    return '${(approx / 1000).toStringAsFixed(1)}k titles - scroll for more';
  }
  return '$approx titles - scroll for more';
}

/// The Library home banner. Tapping the arrow (or the banner itself)
/// opens the full [DiscoverPage].
class DiscoverSection extends StatelessWidget {
  const DiscoverSection({super.key});

  @override
  Widget build(BuildContext context) {
    if (AppConfig.tmdbToken.isEmpty) {
      return SizedBox.shrink();
    }
    return DiscoverBanner(onTap: () => DiscoverPage.open(context));
  }
}

/// Full Discover catalogue page: search bar (with voice), filter chips
/// (Trending / Upcoming / Animation / Hollywood / Bollywood / …) and a
/// two-column poster grid.
///
/// v1.0.1+20 REBUILD — this file is the fix for the "blank white cards
/// after searching" complaint. The card below NEVER inherits a surface
/// color: the card background, the poster background, the while-loading
/// placeholder and the on-error placeholder are all explicit dark
/// colors, so there is no theme/state under which a tile can render
/// white. Failed/missing posters degrade to a dark tile with a film icon
/// and the title text below always renders.
class DiscoverPage extends StatefulWidget {
  const DiscoverPage({super.key});

  static Future<void> open(BuildContext context) {
    return Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const DiscoverPage()));
  }

  @override
  State<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends State<DiscoverPage> {
  final TmdbClient _client = TmdbClient();
  final TextEditingController _searchCtrl = TextEditingController();
  final ScrollController _gridScroll = ScrollController();
  Timer? _debounce;

  // Browse state (chips)
  DiscoverFilter _filter = kDiscoverFilters.first;
  final List<TmdbMovie> _browse = [];
  final Set<int> _browseIds = {};
  int _browsePage = 0;
  int _browseTotalPages = 1;
  bool _browseLoading = false;
  int _browseEpoch = 0;

  // Search state
  String _query = '';
  final List<TmdbMovie> _results = [];
  final Set<int> _resultIds = {};
  int _queryPage = 0;
  int _queryTotalPages = 1;
  bool _queryLoading = false;
  bool _voiceSearching = false;

  bool get _searching => _query.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _gridScroll.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    final cachePath = await TmdbImage.initCacheDir();
    TmdbImage.configure(cachePath);
    if (cachePath != null) _client.cacheDir = Directory(cachePath);
    if (!mounted) return;
    // Instant first paint from the 24h disk cache, then network refresh.
    try {
      final cached = await _client.cachedBrowseFirstPage(_filter);
      final items = cached?.items ?? <TmdbMovie>[];
      if (items.isNotEmpty && _browse.isEmpty && mounted) {
        setState(() {
          for (final m in items) {
            if (_browseIds.add(m.id)) _browse.add(m);
          }
          _browsePage = 1;
        });
      }
    } catch (_) {}
    _browseMore(1);
  }

  // ------------------------------------------------------------ browse ---

  void _selectFilter(DiscoverFilter f) {
    if (f.key == _filter.key) return;
    _clearSearch();
    setState(() {
      _filter = f;
      _browse.clear();
      _browseIds.clear();
      _browsePage = 0;
      _browseTotalPages = 1;
      _browseEpoch++;
    });
    _browseMore(1);
  }

  Future<void> _browseMore(int page) async {
    if (_browseLoading || (page > 1 && _browsePage >= _browseTotalPages)) {
      return;
    }
    final epoch = _browseEpoch;
    _browseLoading = true;
    if (mounted && _browse.isEmpty) setState(() {});
    TmdbPage result;
    try {
      result = await _client
          .browse(_filter, page: page)
          .timeout(Duration(seconds: 15));
    } catch (_) {
      result = TmdbPage();
    }
    _browseLoading = false;
    if (!mounted || epoch != _browseEpoch) return;
    setState(() {
      _browsePage = result.page;
      _browseTotalPages = result.totalPages;
      for (final m in result.items) {
        if (_browseIds.add(m.id)) _browse.add(m);
      }
    });
    _prefetchDetails(result.items);
  }

  // ------------------------------------------------------------ search ---

  void _onSearchChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(Duration(milliseconds: 350), () {
      final q = v.trim();
      if (q != _query) _startSearch(q);
    });
  }

  void _clearSearch() {
    if (_query.isEmpty && _searchCtrl.text.isEmpty) return;
    _debounce?.cancel();
    _searchCtrl.clear();
    setState(() {
      _query = '';
      _results.clear();
      _resultIds.clear();
      _queryPage = 0;
      _queryTotalPages = 1;
    });
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
      result = await _client
          .searchMulti(_query, page: page)
          .timeout(Duration(seconds: 15));
    } catch (_) {
      result = TmdbPage();
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
    _prefetchDetails(result.items);
  }

  bool _onGridScroll(ScrollNotification n) {
    if (n.metrics.pixels >= n.metrics.maxScrollExtent - 600) {
      if (_searching) {
        _searchMore(_queryPage + 1);
      } else {
        _browseMore(_browsePage + 1);
      }
    }
    return false;
  }

  // -------------------------------------------------------------- misc ---

  Future<void> _startVoiceSearch() async {
    if (_voiceSearching) return;
    final mic = await Permission.microphone.request();
    if (!mounted) return;
    if (!mic.isGranted) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: LText('Microphone needed for voice search'),
            duration: Duration(milliseconds: 1800),
          ),
        );
      return;
    }
    setState(() => _voiceSearching = true);
    final query = await NativeBridge.launchSystemVoiceSearch();
    if (!mounted) return;
    setState(() => _voiceSearching = false);
    if (query != null && query.trim().isNotEmpty) {
      _searchCtrl.text = query;
      _onSearchChanged(query);
    }
  }

  Future<void> _aiSuggest() async {
    final movie = await AiSuggestSheet.show(context);
    if (movie != null && mounted) _openMovie(movie);
  }

  /// v1.0.1+22: warm the 24h detail cache for the first cards of every
  /// freshly loaded page, so tapping them opens the detail screen
  /// instantly instead of waiting on the network ("details load very
  /// slow"). Silent, fire-and-forget, never throws.
  void _prefetchDetails(List<TmdbMovie> items) {
    for (final m in items.take(6)) {
      unawaited(
        _client.fullDetail(m.id, kind: m.kind).catchError((Object _) => null),
      );
    }
  }

  void _openMovie(TmdbMovie movie) {
    MovieDetailScreen.open(
      context,
      movie: movie,
      localMatch: null,
      detailLoader: () => _client.fullDetail(movie.id, kind: movie.kind),
    );
  }

  // ----------------------------------------------------------------- ui ---

  @override
  Widget build(BuildContext context) {
    final totalPages = _searching
        ? (_queryTotalPages < 1 ? 1 : _queryTotalPages)
        : (_browseTotalPages < 1 ? 1 : _browseTotalPages);
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(totalPages),
            _buildSearchBar(),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 14),
              child: RecentSearchHistory(
                scope: 'discover',
                controller: _searchCtrl,
                onSelected: (value) {
                  _searchCtrl.text = value;
                  _onSearchChanged(value);
                },
              ),
            ),
            _buildChips(),
            Expanded(
              child: NotificationListener<ScrollNotification>(
                onNotification: _onGridScroll,
                child: _searching ? _buildSearchResults() : _buildBrowseGrid(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(int totalPages) {
    return Padding(
      padding: EdgeInsets.fromLTRB(4, 10, 8, 6),
      child: Row(
        children: [
          IconButton(
            icon: Icon(
              Icons.arrow_back_rounded,
              color: AppColors.textPrimary,
              size: 24,
            ),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          SizedBox(width: 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LText(
                  'Discover',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 25,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                  ),
                ),
                SizedBox(height: 1),
                Text(
                  catalogTitleCount(totalPages),
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'AI Suggestor',
            icon: Icon(
              Icons.auto_awesome_rounded,
              color: AppColors.textPrimary,
              size: 21,
            ),
            onPressed: _aiSuggest,
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: EdgeInsets.fromLTRB(14, 2, 14, 8),
      child: Container(
        height: 46,
        padding: EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(25),
        ),
        child: Row(
          children: [
            Icon(
              Icons.search_rounded,
              color: AppColors.textSecondary,
              size: 21,
            ),
            SizedBox(width: 9),
            Expanded(
              child: RecentSearchField(
                scope: 'discover',
                showHistory: false,
                controller: _searchCtrl,
                style: TextStyle(color: AppColors.textPrimary, fontSize: 14.5),
                decoration: LInputDecoration(
                  hintText: 'Search movies & series…',
                  hintStyle: TextStyle(
                    color: AppColors.textSecondary,
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
                onTap: _clearSearch,
                child: Padding(
                  padding: EdgeInsets.all(3),
                  child: Icon(
                    Icons.close_rounded,
                    color: AppColors.textSecondary,
                    size: 18,
                  ),
                ),
              )
            else
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: _startVoiceSearch,
                child: Padding(
                  padding: EdgeInsets.all(3),
                  child: _voiceSearching
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            color: AppColors.textSecondary,
                            strokeWidth: 2,
                          ),
                        )
                      : Icon(
                          Icons.mic_none_rounded,
                          color: AppColors.textSecondary,
                          size: 20,
                        ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildChips() {
    return SizedBox(
      height: 42,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.fromLTRB(14, 2, 14, 4),
        itemCount: kDiscoverFilters.length,
        itemBuilder: (context, i) {
          final f = kDiscoverFilters[i];
          final selected = f.key == _filter.key && !_searching;
          return Padding(
            padding: EdgeInsets.only(right: 8),
            child: RemoteTap(
              onTap: () => _selectFilter(f),
              child: AnimatedContainer(
                duration: Duration(milliseconds: 160),
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: selected ? AppColors.accent : AppColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  f.label,
                  style: TextStyle(
                    color: selected
                        ? AppColors.onAccent
                        : AppColors.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBrowseGrid() {
    if (_browse.isEmpty && _browseLoading) return _buildSkeleton();
    if (_browse.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(28),
          child: LText(
            'Nothing to show yet — check the connection and pull to retry.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
        ),
      );
    }
    return _buildGrid(_browse, loadingMore: _browseLoading);
  }

  Widget _buildSearchResults() {
    if (_results.isEmpty && _queryLoading) return _buildSkeleton();
    if (_results.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(28),
          child: LText(
            'No movies or series match that title.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
        ),
      );
    }
    return _buildGrid(_results, loadingMore: _queryLoading);
  }

  Widget _buildGrid(List<TmdbMovie> movies, {required bool loadingMore}) {
    return GridView.builder(
      controller: _gridScroll,
      padding: EdgeInsets.fromLTRB(14, 8, 14, 24),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.56,
        mainAxisSpacing: 14,
        crossAxisSpacing: 12,
      ),
      itemCount: movies.length + (loadingMore ? 1 : 0),
      itemBuilder: (context, i) {
        if (i >= movies.length) {
          return Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                color: AppColors.border,
                strokeWidth: 2.2,
              ),
            ),
          );
        }
        final m = movies[i];
        return DiscoverMovieCard(
          key: ValueKey('${m.kind}_${m.id}'),
          movie: m,
          onTap: () => _openMovie(m),
        );
      },
    );
  }

  /// Dark skeleton slots while the first page loads — clearly "empty
  /// slots", never white cards (v1.0.1+20).
  Widget _buildSkeleton() {
    return GridView.builder(
      padding: EdgeInsets.fromLTRB(14, 8, 14, 24),
      physics: NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.56,
        mainAxisSpacing: 14,
        crossAxisSpacing: 12,
      ),
      itemCount: 6,
      itemBuilder: (_, i) => const _SkeletonCard(),
    );
  }
}

/// One poster tile in the Discover grid. EVERY surface is an explicit
/// dark color — a tile can never render as a blank white card:
///   * card background        → #14141e
///   * poster background      → #1e1e2a (behind the image)
///   * while-loading          → #1e1e2a
///   * load failure / no URL  → #1e1e2a with a film icon
///   * title + year           → always visible text under the poster
class DiscoverMovieCard extends StatelessWidget {
  final TmdbMovie movie;
  final VoidCallback onTap;

  const DiscoverMovieCard({
    super.key,
    required this.movie,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final posterUrl = tmdbPosterUrl(movie.posterPath);
    return RemoteTap(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(color: AppColors.surface),
                  if (posterUrl.isNotEmpty)
                    TmdbImage(url: posterUrl, fit: BoxFit.cover)
                  else
                    Center(
                      child: Icon(
                        Icons.movie_outlined,
                        color: AppColors.textPrimary.withValues(alpha: 0.15),
                        size: 34,
                      ),
                    ),
                  if (movie.rating > 0)
                    Positioned(
                      top: 7,
                      left: 7,
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.72),
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.star_rounded,
                              color: Color(0xFFFFC948),
                              size: 13,
                            ),
                            SizedBox(width: 2),
                            Text(
                              tmdbRatingText(movie.rating),
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(8, 7, 8, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    movie.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    movie.year != null
                        ? '${movie.year}'
                        : (movie.kind == 'tv' ? 'Series' : ' '),
                    maxLines: 1,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 10.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Container(color: AppColors.surface)),
          Padding(
            padding: EdgeInsets.fromLTRB(8, 7, 8, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  height: 11,
                  width: 110,
                  decoration: BoxDecoration(
                    color: AppColors.textPrimary.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
                SizedBox(height: 5),
                Container(
                  height: 9,
                  width: 60,
                  decoration: BoxDecoration(
                    color: AppColors.textPrimary.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
