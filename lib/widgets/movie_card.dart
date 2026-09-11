import 'package:flutter/material.dart';

import '../theme.dart';
import '../screens/movie_detail_screen.dart';
import '../utils/tmdb.dart';

/// TMDB movie poster card + detail bottom sheet (network images with
/// graceful fallback; no crash offline).
class MoviePosterCard extends StatelessWidget {
  const MoviePosterCard({super.key, required this.movie, this.compact = false});

  final TmdbMovie movie;
  final bool compact;

  void _showDetails(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => MovieDetailScreen(movieId: movie.id)));
  }

  @override
  Widget build(BuildContext context) {
    final w = compact ? 104.0 : double.infinity;
    return GestureDetector(
      onTap: () => _showDetails(context),
      child: SizedBox(
        width: w,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: AspectRatio(
                  aspectRatio: 2 / 3,
                  child: movie.posterUrl.isEmpty
                      ? const _PosterFallback()
                      : Image.network(
                          movie.posterUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const _PosterFallback(),
                          loadingBuilder: (context, child, progress) =>
                              progress == null
                                  ? child
                                  : const ColoredBox(
                                      color: AppColors.surfaceAlt),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 5),
            Text(
              movie.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600),
            ),
            Row(
              children: [
                const Icon(Icons.star_rounded,
                    color: Color(0xFFFBBF24), size: 13),
                const SizedBox(width: 3),
                Text(
                  '${movie.rating.toStringAsFixed(1)}'
                  '${movie.year.isNotEmpty ? ' · ${movie.year}' : ''}',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 10.5),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PosterFallback extends StatelessWidget {
  const _PosterFallback();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: AppColors.surfaceAlt,
      child: Center(
        child: Icon(Icons.movie_outlined,
            color: AppColors.textSecondary, size: 30),
      ),
    );
  }
}

/// Landscape movie card for the home Discover grid: 16:9 backdrop (falls
/// back to the poster, then an icon), gold ★ rating badge top-left, and
/// title + year below — matching the home Discover Movies section.
class DiscoverMovieCard extends StatelessWidget {
  const DiscoverMovieCard({super.key, required this.movie});

  final TmdbMovie movie;

  void _open(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => MovieDetailScreen(movieId: movie.id)));
  }

  @override
  Widget build(BuildContext context) {
    final image =
        movie.backdropUrl.isNotEmpty ? movie.backdropUrl : movie.posterUrl;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _open(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  image.isEmpty
                      ? const _PosterFallback()
                      : Image.network(
                          image,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const _PosterFallback(),
                          loadingBuilder: (context, child, progress) =>
                              progress == null
                                  ? child
                                  : const ColoredBox(
                                      color: AppColors.surfaceAlt),
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
          ),
          const SizedBox(height: 6),
          Text(
            movie.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(movie.year.isEmpty ? '—' : movie.year,
              style:
                  const TextStyle(color: AppColors.textSecondary, fontSize: 11.5)),
        ],
      ),
    );
  }
}

