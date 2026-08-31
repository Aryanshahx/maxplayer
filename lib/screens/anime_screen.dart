import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';

import '../services/native_bridge.dart';
import '../services/tmdb_client.dart';
import '../state/media_player_state.dart';
import '../state/theme_state.dart';
import '../state/video_library_state.dart';
import '../widgets/movie_detail_sheet.dart';
import '../widgets/tmdb_image.dart';

/// v85: Dedicated "Watch Anime" screen with all anime posters, categories,
/// full details sheet, and "Watch Now" ready buttons.
class AnimeScreen extends StatefulWidget {
  final VideoLibraryState library;
  final MediaPlayerState player;

  const AnimeScreen({super.key, required this.library, required this.player});

  @override
  State<AnimeScreen> createState() => _AnimeScreenState();
}

class _AnimeScreenState extends State<AnimeScreen> {
  final TmdbClient _client = TmdbClient();
  final ScrollController _scrollCtrl = ScrollController();

  List<TmdbMovie> _items = [];
  bool _loading = true;
  bool _loadingMore = false;
  int _page = 1;
  int _totalPages = 1;
  String _category = 'all';

  @override
  void initState() {
    super.initState();
    _initCacheDir();
    _loadAnime();
    _scrollCtrl.addListener(_onScroll);
  }

  Future<void> _initCacheDir() async {
    final cachePath = await NativeBridge.cacheDirPath();
    if (cachePath != null) {
      _client.cacheDir = Directory(cachePath);
    }
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >= _scrollCtrl.position.maxScrollExtent - 400) {
      _loadMore();
    }
  }

  Future<void> _loadAnime({bool force = false}) async {
    setState(() {
      _loading = true;
      _page = 1;
    });
    final res = await _client.browseAnime(page: 1, category: _category, force: force);
    if (!mounted) return;
    setState(() {
      _items = res.items;
      _totalPages = res.totalPages;
      _loading = false;
    });
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _page >= _totalPages) return;
    setState(() => _loadingMore = true);
    final nextPage = _page + 1;
    final res = await _client.browseAnime(page: nextPage, category: _category);
    if (!mounted) return;
    setState(() {
      _page = nextPage;
      _items.addAll(res.items);
      _loadingMore = false;
    });
  }

  void _switchCategory(String cat) {
    if (_category == cat) return;
    setState(() => _category = cat);
    _loadAnime();
  }

  void _openAnimeDetails(TmdbMovie anime) {
    MovieDetailSheet.show(
      context,
      movie: anime,
      localMatch: null,
      player: widget.player,
      detailLoader: () => _client.fullDetail(anime.id, kind: anime.kind),
    );
  }

  void _watchNow(TmdbMovie anime) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Starting "${anime.title}" stream… (Direct link integration ready)'),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'Details',
          textColor: themeState.accent,
          onPressed: () => _openAnimeDetails(anime),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = themeState.accent;

    return Scaffold(
      backgroundColor: const Color(0xFF0e0e16),
      appBar: AppBar(
        backgroundColor: const Color(0xFF14141c),
        elevation: 0,
        title: Row(
          children: [
            Icon(Icons.smart_display, color: accent, size: 22),
            const SizedBox(width: 8),
            const Text(
              'Watch Anime',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Category chips
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                _chip('all', 'All Anime Series'),
                const SizedBox(width: 8),
                _chip('movies', 'Anime Movies'),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _items.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.movie_filter_outlined, size: 48, color: Colors.white24),
                            const SizedBox(height: 12),
                            const Text('No anime found', style: TextStyle(color: Colors.white54)),
                            const SizedBox(height: 12),
                            FilledButton.tonal(
                              onPressed: () => _loadAnime(force: true),
                              child: const Text('Refresh'),
                            ),
                          ],
                        ),
                      )
                    : GridView.builder(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.all(12),
                        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 200,
                          childAspectRatio: 0.58,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                        ),
                        itemCount: _items.length + (_loadingMore ? 1 : 0),
                        itemBuilder: (context, i) {
                          if (i >= _items.length) {
                            return const Center(child: CircularProgressIndicator());
                          }
                          final anime = _items[i];
                          return _AnimeCard(
                            anime: anime,
                            accent: accent,
                            onTap: () => _openAnimeDetails(anime),
                            onWatch: () => _watchNow(anime),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String key, String label) {
    final selected = _category == key;
    final accent = themeState.accent;
    return GestureDetector(
      onTap: () => _switchCategory(key),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? accent : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? accent : Colors.white12),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.white70,
            fontSize: 12.5,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

class _AnimeCard extends StatelessWidget {
  final TmdbMovie anime;
  final Color accent;
  final VoidCallback onTap;
  final VoidCallback onWatch;

  const _AnimeCard({
    required this.anime,
    required this.accent,
    required this.onTap,
    required this.onWatch,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                    child: TmdbImage(url: tmdbPosterUrl(anime.posterPath)),
                  ),
                  Positioned(
                    top: 6,
                    left: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.75),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '⭐ ${tmdbRatingText(anime.rating)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
              child: Text(
                anime.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                anime.year != null ? '${anime.year}  ·  Anime' : 'Anime',
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(6),
              child: SizedBox(
                width: double.infinity,
                height: 28,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.play_arrow, size: 14),
                  label: const Text('Watch Now', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  onPressed: onWatch,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
