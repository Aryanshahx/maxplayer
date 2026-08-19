import 'dart:io';

import 'package:flutter/material.dart';

import '../services/native_bridge.dart';
import '../services/tmdb_client.dart';
import '../state/media_player_state.dart';
import '../state/theme_state.dart';
import '../state/video_library_state.dart';
import '../utils/movie_match.dart';
import '../widgets/movie_detail_sheet.dart';
import '../widgets/tmdb_image.dart';

/// v43 "Discover": a legal movie-discovery section.
///
/// SOURCE: TMDB's free API (licensed for this, needs only the credit line -
/// we do NOT copy IMDb numbers and we never show "Max Player rating" for
/// someone else's data). Posters + ratings + stories are cached on disk:
/// the grid refreshes ITSELF once a day in the background and keeps working
/// fully offline in between ("always automatically updated library").
///
/// TRAILERS: a tap opens the official YouTube app (Play-policy-safe). We
/// never play YouTube streams through our own player - that would break
/// YouTube's terms and get the app banned.
///
/// The killer bit is "In my library" on the detail sheet: if the movie is
/// ALREADY on the phone, Max Player plays it instantly, offline.
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
  static const _langs = <String, String>{'': 'All', 'en': 'Hollywood', 'hi': 'Bollywood'};

  final _client = TmdbClient();
  String _lang = '';
  List<TmdbMovie>? _movies;
  bool _loading = true;
  String? _error;
  bool _keyMissing = false;
  int _loadToken = 0;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    final cachePath = await NativeBridge.cacheDirPath();
    TmdbImage.configure(cachePath);
    if (cachePath != null) _client.cacheDir = Directory(cachePath);
    if (!mounted) return;
    if (kTmdbApiKey.isEmpty) {
      setState(() {
        _keyMissing = true;
        _loading = false;
      });
      return;
    }
    _load();
  }

  Future<void> _load({bool force = false}) async {
    final token = ++_loadToken;
    setState(() {
      _loading = true;
      _error = null;
    });
    List<TmdbMovie> list;
    try {
      list = await _client.trending(language: _lang, force: force);
    } catch (_) {
      list = const [];
    }
    if (!mounted || token != _loadToken) return;
    setState(() {
      _loading = false;
      _movies = list;
      if (list.isEmpty) {
        _error = 'Could not load movies - connect the internet once, '
            'then pull down to retry.';
      }
    });
  }

  void _openMovie(TmdbMovie movie) {
    // Match against the ALREADY-scanned library (read-only - v43 does not
    // touch the video scan at all).
    final match =
        findLocalMovie(movie.title, movie.year, widget.library.allVideos);
    MovieDetailSheet.show(
      context,
      movie: movie,
      localMatch: match,
      player: widget.player,
      trailerLoader: () => _client.details(movie.id).then((d) => d?.trailerKey),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF12121a),
      appBar: AppBar(
        backgroundColor: const Color(0xFF12121a),
        title: const Text('Discover', style: TextStyle(fontSize: 18)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(44),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Row(
              children: [
                for (final e in _langs.entries) ...[
                  _LangChip(
                    label: e.value,
                    selected: _lang == e.key,
                    onTap: () {
                      if (_lang == e.key) return;
                      setState(() => _lang = e.key);
                      _load();
                    },
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
        ),
      ),
      body: _keyMissing
          ? const _SetupNote()
          : RefreshIndicator(
              color: themeState.accent,
              onRefresh: () => _load(force: true),
              child: _buildBody(),
            ),
    );
  }

  Widget _buildBody() {
    final movies = _movies;
    if (_loading && movies == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (movies == null || movies.isEmpty) {
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
    return GridView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 150,
        childAspectRatio: 0.58,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      itemCount: movies.length,
      itemBuilder: (context, i) => _PosterCard(
        movie: movies[i],
        onTap: () => _openMovie(movies[i]),
      ),
    );
  }
}

class _LangChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _LangChip({
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

  const _PosterCard({required this.movie, required this.onTap});

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
