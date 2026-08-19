import 'package:flutter/material.dart';

import '../models/video_track.dart';
import '../screens/player_screen.dart';
import '../services/native_bridge.dart';
import '../services/tmdb_client.dart';
import '../state/media_player_state.dart';
import '../state/theme_state.dart';
import 'tmdb_image.dart';

/// v43: the Discover detail sheet - poster, TMDB rating (with credit),
/// story, and up to two actions:
///
///  - "Watch trailer on YouTube": opens the official YouTube app on the
///    trailer (Play-policy-safe; we never stream YouTube in-app).
///  - "In my library": shown ONLY when the movie is already on the phone -
///    then Max Player plays it instantly, offline. This is the moment the
///    discovery ends in OUR player.
///
/// DraggableScrollableSheet like every other sheet since v35 (landscape
/// safe, every control stays reachable).
class MovieDetailSheet extends StatelessWidget {
  final TmdbMovie movie;
  final VideoTrack? localMatch;
  final MediaPlayerState player;

  /// Lazily resolves the trailer key (detail call is cached 24h).
  final Future<String?> Function() trailerLoader;

  const MovieDetailSheet({
    super.key,
    required this.movie,
    required this.localMatch,
    required this.player,
    required this.trailerLoader,
  });

  static Future<void> show(
    BuildContext context, {
    required TmdbMovie movie,
    required VideoTrack? localMatch,
    required MediaPlayerState player,
    required Future<String?> Function() trailerLoader,
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
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (_, controller) => SingleChildScrollView(
          controller: controller,
          child: MovieDetailSheet(
            movie: movie,
            localMatch: localMatch,
            player: player,
            trailerLoader: trailerLoader,
          ),
        ),
      ),
    );
  }

  Future<void> _playLocal(BuildContext context) async {
    final track = localMatch;
    if (track == null) return;
    await player.setPlaylistAndPlay([track], 0);
    if (!context.mounted) return;
    Navigator.of(context).pop();
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PlayerScreen(player: player)),
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
                  child:
                      TmdbImage(url: tmdbPosterUrl(movie.posterPath, big: true)),
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
          const SizedBox(height: 14),
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
            child: FutureBuilder<String?>(
              future: trailerLoader(),
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
                final key = snap.data;
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
          if (localMatch != null) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: () => _playLocal(context),
                icon: const Icon(Icons.video_library),
                label: Text('In my library - play "${localMatch!.title}" now',
                    maxLines: 1, overflow: TextOverflow.ellipsis),
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
