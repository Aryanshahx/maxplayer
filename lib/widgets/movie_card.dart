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

