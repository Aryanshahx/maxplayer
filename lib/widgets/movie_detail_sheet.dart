import 'package:flutter/material.dart';

import '../models/video_track.dart';
import '../screens/player_screen.dart';
import '../services/native_bridge.dart';
import '../services/tmdb_client.dart';
import '../state/media_player_state.dart';
import '../state/theme_state.dart';
import 'tmdb_image.dart';

/// v44: the Discover detail sheet - poster, TMDB rating (with credit),
/// and now the FULL story: tagline, runtime, genres, director, cast,
/// vote count, plus the same two actions:
///
///  - "Watch trailer on YouTube": opens the official YouTube app on the
///    trailer (Play-policy-safe; we never stream YouTube in-app).
///  - "In my library": shown ONLY when the movie is already on the phone -
///    then Max Player plays it instantly, offline.
///
/// DraggableScrollableSheet like every other sheet since v35 (landscape
/// safe, every control stays reachable).
class MovieDetailSheet extends StatefulWidget {
  final TmdbMovie movie;
  final VideoTrack? localMatch;
  final MediaPlayerState player;

  /// Lazily resolves trailer + extras in ONE call (detail is cached 24h).
  final Future<TmdbFull?> Function() detailLoader;

  const MovieDetailSheet({
    super.key,
    required this.movie,
    required this.localMatch,
    required this.player,
    required this.detailLoader,
  });

  static Future<void> show(
    BuildContext context, {
    required TmdbMovie movie,
    required VideoTrack? localMatch,
    required MediaPlayerState player,
    required Future<TmdbFull?> Function() detailLoader,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1a1a24),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.62,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (_, controller) => SingleChildScrollView(
          controller: controller,
          child: MovieDetailSheet(
            movie: movie,
            localMatch: localMatch,
            player: player,
            detailLoader: detailLoader,
          ),
        ),
      ),
    );
  }

  @override
  State<MovieDetailSheet> createState() => _MovieDetailSheetState();
}

class _MovieDetailSheetState extends State<MovieDetailSheet> {
  // Fired once - never inside build(), so no refetch on every rebuild.
  late final Future<TmdbFull?> _detailFuture = widget.detailLoader();

  Future<void> _playLocal(BuildContext context) async {
    final track = widget.localMatch;
    if (track == null) return;
    await widget.player.setPlaylistAndPlay([track], 0);
    if (!context.mounted) return;
    Navigator.of(context).pop();
    Navigator.of(context).push(
      MaterialPageRoute(
          builder: (_) => PlayerScreen(player: widget.player)),
    );
  }

  Future<void> _openTrailer(String key) async {
    final ok = await NativeBridge.openYouTube(key);
    if (!ok) {
      // Exceptionally rare (no browser?!) - keep it silent, the button
      // simply does nothing visible instead of crashing the sheet.
    }
  }

  @override
  Widget build(BuildContext context) {
    final movie = widget.movie;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 110,
                height: 165,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: TmdbImage(
                      url: tmdbPosterUrl(movie.posterPath, big: true)),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      movie.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      [
                        if (movie.year != null) '${movie.year}',
                        '⭐ ${tmdbRatingText(movie.rating)} / 10',
                      ].join('  ·  '),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Rating & data: TMDB',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.35),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          // v44: the extra facts arrive with the trailer lookup (one call).
          FutureBuilder<TmdbFull?>(
            future: _detailFuture,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'Loading details...',
                    style: TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                );
              }
              final full = snap.data;
              if (full == null) return const SizedBox(height: 8);
              return _ExtrasBlock(extras: full.extras);
            },
          ),
          if (movie.overview.isNotEmpty)
            Text(
              movie.overview,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
                height: 1.5,
              ),
            )
          else
            Text(
              'No story summary available for this movie yet.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 13,
                height: 1.5,
              ),
            ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FutureBuilder<TmdbFull?>(
              future: _detailFuture,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return OutlinedButton.icon(
                    onPressed: null,
                    icon: const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    label: const Text('Finding trailer...'),
                  );
                }
                final key = snap.data?.movie.trailerKey;
                if (key == null || key.isEmpty) {
                  return const Text(
                    'No official trailer is available for this one.',
                    style: TextStyle(color: Colors.white38, fontSize: 12),
                  );
                }
                return FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: themeState.accent,
                    foregroundColor: themeState.onAccent,
                  ),
                  onPressed: () => _openTrailer(key),
                  icon: const Icon(Icons.smart_display),
                  label: const Text('Watch trailer on YouTube'),
                );
              },
            ),
          ),
          if (widget.localMatch != null) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: () => _playLocal(context),
                icon: const Icon(Icons.video_library),
                label: Text(
                    'In my library - play "${widget.localMatch!.title}" now',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
            ),
          ],
          const SizedBox(height: 14),
          Center(
            child: Text(
              'Movie data & ratings: TMDB (themoviedb.org).\n'
              'This product uses the TMDB API but is not endorsed or '
              'certified by TMDB.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.3),
                fontSize: 10,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// v44: tagline, runtime, genres, votes, director, cast - everything TMDB
/// gives us beyond the poster. Any missing piece is simply skipped.
class _ExtrasBlock extends StatelessWidget {
  final TmdbDetailExtras extras;

  const _ExtrasBlock({required this.extras});

  @override
  Widget build(BuildContext context) {
    final meta = <String>[
      if (formatRuntime(extras.runtimeMinutes).isNotEmpty)
        formatRuntime(extras.runtimeMinutes),
      if (extras.voteCount > 0) '${formatVoteCount(extras.voteCount)} votes',
      if (extras.status.isNotEmpty && extras.status != 'Released')
        extras.status,
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (extras.tagline.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '"${extras.tagline}"',
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 13,
                  fontStyle: FontStyle.italic,
                  height: 1.4,
                ),
              ),
            ),
          if (meta.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                meta.join('  ·  '),
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ),
          if (extras.genres.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final g in extras.genres.take(4))
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        g,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 11),
                      ),
                    ),
                ],
              ),
            ),
          if (extras.director.isNotEmpty)
            Text(
              'Director: ${extras.director}',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          if (extras.cast.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                'Cast: ${extras.cast.join(', ')}',
                style: const TextStyle(
                    color: Colors.white54, fontSize: 12, height: 1.4),
              ),
            ),
        ],
      ),
    );
  }
}
