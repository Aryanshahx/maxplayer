import 'dart:async';

import 'package:flutter/material.dart';

import '../theme.dart';
import '../utils/tmdb.dart';
import 'movie_detail_screen.dart';

/// Full Discover browser — the reference layout: search bar, category
/// chips (Trending/Upcoming/Animation/Hollywood/Bollywood) and a 2-column
/// poster grid with ★ badges, paging until TMDB runs dry.
class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  final _movies = <TmdbMovie>[];
  final _searchCtrl = TextEditingController();
  final _scroll = ScrollController();
  String _category = 'Trending';
  int _page = 1;
  int _total = 0;
  bool _loading = false;
  bool _hasMore = true;
  String? _fatal;
  Timer? _debounce;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load(reset: true);
    _scroll.addListener(() {
      if (_scroll.position.pixels >
              _scroll.position.maxScrollExtent - 400 &&
          !_loading &&
          _hasMore) {
        _load();
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading) return;
    _loading = true;
    if (mounted && reset) setState(() {});
    try {
      if (reset) {
        _page = 1;
        _movies.clear();
        _hasMore = true;
        _fatal = null;
      }
      if (_query.isNotEmpty) {
        final res = await searchMovies(_query, _page);
        if (!mounted) return;
        setState(() {
          _movies.addAll(res.movies);
          _total = res.total;
          _hasMore = res.movies.isNotEmpty && _page < 50;
          _page++;
          _loading = false;
          if (_total == 0 && res.movies.isEmpty && _page == 2) {
            _fatal = null; // search legitimately empty
          }
        });
      } else {
        final res =
            await fetchCategoryPage(tmdbCategories[_category]!, _page);
        if (!mounted) return;
        setState(() {
          _movies.addAll(res.movies);
          _total = res.total;
          _hasMore = res.hasMore;
          _page++;
          _loading = false;
          if (_movies.isEmpty && reset) {
            _fatal = 'No movies — check internet or TMDB key.';
          }
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          if (reset) _fatal = 'No movies — check internet or TMDB key.';
        });
      }
    }
  }

  void _pickCategory(String c) {
    if (c == _category && _query.isEmpty) return;
    setState(() {
      _category = c;
      _query = '';
      _searchCtrl.clear();
    });
    _load(reset: true);
  }

  void _onQuery(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      final prev = _query;
      _query = q.trim();
      if (_query != prev) _load(reset: true);
    });
  }

  String _fmtTotal() {
    final t = _total > 0 ? _total : 0;
    final s = '$t';
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Discover',
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
            Text(
              '${_total > 0 ? _fmtTotal() : '…'} titles - scroll for more',
              style: const TextStyle(
                  fontSize: 11.5, color: AppColors.textSecondary),
            ),
          ],
        ),
        actions: [
          Icon(Icons.auto_awesome_rounded,
              color: AppColors.accent, size: 20),
          const SizedBox(width: 16),
        ],
      ),
      body: Column(
        children: [
          // search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  const Icon(Icons.search_rounded,
                      color: AppColors.textSecondary, size: 21),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      style: const TextStyle(
                          color: AppColors.textPrimary, fontSize: 14.5),
                      decoration: const InputDecoration(
                        hintText: 'Search movies & series...',
                        hintStyle:
                            TextStyle(color: AppColors.textSecondary),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding:
                            EdgeInsets.symmetric(vertical: 13),
                      ),
                      onChanged: _onQuery,
                    ),
                  ),
                  const Icon(Icons.mic_rounded,
                      color: AppColors.textSecondary, size: 20),
                ],
              ),
            ),
          ),
          // category chips
          SizedBox(
            height: 38,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final c in tmdbCategories.keys)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(c),
                      selected: _category == c && _query.isEmpty,
                      onSelected: (_) => _pickCategory(c),
                      showCheckmark: false,
                      labelStyle: TextStyle(
                        color: _category == c && _query.isEmpty
                            ? AppColors.onAccent
                            : AppColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      selectedColor: AppColors.textPrimary,
                      backgroundColor: AppColors.surface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: const BorderSide(color: AppColors.border),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // grid
          Expanded(
            child: _movies.isEmpty && _fatal != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(_fatal!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: AppColors.textSecondary)),
                    ),
                  )
                : GridView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 0.56,
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 14,
                    ),
                    itemCount:
                        _movies.length + (_loading ? 2 : 0),
                    itemBuilder: (context, i) {
                      if (i >= _movies.length) {
                        return const _GridSkeleton();
                      }
                      final m = _movies[i];
                      return _DiscoverCard(movie: m);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _DiscoverCard extends StatelessWidget {
  const _DiscoverCard({required this.movie});

  final TmdbMovie movie;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => MovieDetailScreen(movieId: movie.id))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: movie.posterUrl.isEmpty
                      ? const _PosterBlank()
                      : Image.network(
                          movie.posterUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) =>
                              const _PosterBlank(),
                          loadingBuilder:
                              (context, child, progress) =>
                                  progress == null
                                      ? child
                                      : const _PosterBlank(),
                        ),
                ),
                if (movie.rating > 0)
                  Positioned(
                    left: 8,
                    top: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.72),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.star_rounded,
                              color: Color(0xFFFACC15), size: 14),
                          const SizedBox(width: 3),
                          Text(movie.rating.toStringAsFixed(1),
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            movie.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13.5,
                fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(movie.year.isEmpty ? '—' : movie.year,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 12)),
        ],
      ),
    );
  }
}

class _PosterBlank extends StatelessWidget {
  const _PosterBlank();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surfaceAlt,
      alignment: Alignment.center,
      child: const Icon(Icons.movie_outlined,
          color: AppColors.textSecondary, size: 34),
    );
  }
}

class _GridSkeleton extends StatelessWidget {
  const _GridSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Container(
            height: 10, width: 90, color: AppColors.surfaceAlt),
        const SizedBox(height: 4),
        Container(height: 8, width: 40, color: AppColors.surfaceAlt),
      ],
    );
  }
}
