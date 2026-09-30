/// v1.0.1+46: full-screen grid for one Discover category (opened by
/// tapping a rail's "SEE ALL" header). Pages the SAME TMDB filter
/// indefinitely, deduped, with the identical tap-to-detail behaviour as
/// the home feed.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../theme.dart';
import '../utils/crash_log.dart';
import '../utils/movie_match.dart';
import '../utils/tmdb.dart';
import '../utils/tmdb_image.dart';
import 'movie_detail_screen.dart';

class CategoryScreen extends StatefulWidget {
  const CategoryScreen({
    super.key,
    required this.title,
    required this.filter,
    required this.videos,
  });

  final String title;
  final DiscoverFilter filter;

  /// Local library (read-only) for "already have it" matching on tap.
  final List<AssetEntity> videos;

  @override
  State<CategoryScreen> createState() => _CategoryScreenState();
}

class _CategoryScreenState extends State<CategoryScreen> {
  final _client = TmdbClient();
  final _scroll = ScrollController();
  final List<TmdbMovie> _items = [];
  final Set<int> _seen = {};
  int _page = 0;
  int _totalPages = 1;
  bool _loading = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    unawaited(_load(1));
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients || _loading || _page >= _totalPages) return;
    final pos = _scroll.position;
    if (pos.pixels > pos.maxScrollExtent - 420) {
      unawaited(_load(_page + 1));
    }
  }

  Future<void> _load(int page) async {
    if (_loading) return;
    _loading = true;
    TmdbPage result;
    try {
      result = await _client.browse(widget.filter, page: page);
    } catch (e) {
      CrashLog.error('category.load_failed', e, {'page': page});
      result = const TmdbPage();
    }
    _loading = false;
    if (!mounted) return;
    setState(() {
      if (result.items.isEmpty) {
        // Late empty page == exhausted (same fix as the home rails).
        if (page > 1) {
          _totalPages = _page;
        } else {
          _failed = true;
        }
        return;
      }
      _page = result.page;
      _totalPages = result.totalPages;
      _failed = false;
      for (final m in result.items) {
        if (_seen.add(m.id)) _items.add(m);
      }
    });
  }

  void _open(TmdbMovie movie) {
    final match = findLocalMovie(movie.title, movie.year, widget.videos);
    MovieDetailScreen.open(
      context,
      movie: movie,
      localMatch: match,
      detailLoader: () => _client.fullDetail(movie.id, kind: movie.kind),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0a0a10),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // header
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 14, 10),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.arrow_back_rounded,
                      color: Colors.white,
                    ),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  const SizedBox(width: 2),
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
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_loading && _items.isNotEmpty)
              LinearProgressIndicator(
                color: AppColors.accent,
                backgroundColor: Colors.white10,
                minHeight: 2,
              ),
            Expanded(
              child: _failed && _items.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.wifi_off_rounded,
                            color: Colors.white38,
                            size: 30,
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Could not load this category',
                            style: TextStyle(color: Colors.white54),
                          ),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: () => unawaited(_load(1)),
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    )
                  : _items.isEmpty
                  ? const Center(
                      child: CircularProgressIndicator(color: Colors.white24),
                    )
                  : GridView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(14, 4, 14, 18),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            childAspectRatio: 0.56,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 12,
                          ),
                      itemCount: _items.length,
                      itemBuilder: (context, i) =>
                          _CategoryCard(movie: _items[i], onTap: _open),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({required this.movie, required this.onTap});

  final TmdbMovie movie;
  final ValueChanged<TmdbMovie> onTap;

  @override
  Widget build(BuildContext context) {
    final poster = tmdbPosterUrl(movie.posterPath);
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => onTap(movie),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: double.infinity,
                  child: poster.isEmpty
                      ? const ColoredBox(color: Color(0xFF17171d))
                      : TmdbImage(url: poster, fit: BoxFit.cover),
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
                fontSize: 12,
                fontWeight: FontWeight.w700,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${movie.year ?? '—'}',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
