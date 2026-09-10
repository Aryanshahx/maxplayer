import 'package:flutter/material.dart';

import '../theme.dart';
import '../utils/tmdb.dart';

/// TMDB movie poster card + detail bottom sheet (network images with
/// graceful fallback; no crash offline).
class MoviePosterCard extends StatelessWidget {
  const MoviePosterCard({super.key, required this.movie, this.compact = false});

  final TmdbMovie movie;
  final bool compact;

  void _showDetails(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (context) => _MovieDetailSheet(movie: movie),
    );
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

class _MovieDetailSheet extends StatelessWidget {
  const _MovieDetailSheet({required this.movie});

  final TmdbMovie movie;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.62,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
        children: [
          Center(
            child: Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  width: 110,
                  height: 165,
                  child: movie.posterUrl.isEmpty
                      ? const _PosterFallback()
                      : Image.network(movie.posterUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) =>
                              const _PosterFallback()),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(movie.title,
                        style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.star_rounded,
                            color: Color(0xFFFBBF24), size: 18),
                        const SizedBox(width: 4),
                        Text(movie.rating.toStringAsFixed(1),
                            style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w700)),
                        if (movie.year.isNotEmpty) ...[
                          const SizedBox(width: 10),
                          Text(movie.year,
                              style: const TextStyle(
                                  color: AppColors.textSecondary)),
                        ],
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text('Trending this week on TMDB',
                        style: TextStyle(
                            color: AppColors.accent,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Text('Overview',
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(
            movie.overview.isEmpty ? 'No overview available.' : movie.overview,
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 13.5, height: 1.5),
          ),
        ],
      ),
    );
  }
}
