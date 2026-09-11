import 'dart:async';

import 'package:flutter/material.dart';

import '../screens/discover_screen.dart';
import '../theme.dart';
import '../utils/crash_log.dart';
import '../utils/tmdb.dart';
import 'movie_card.dart';

/// Home "Discover movies" section: a 2-column grid of landscape movie cards
/// with gold ★ rating badges, straight from TMDB trending. Hidden entirely
/// when offline or on error (home never breaks).
class DiscoverSection extends StatefulWidget {
  const DiscoverSection({super.key});

  static List<TmdbMovie>? cache;

  @override
  State<DiscoverSection> createState() => _DiscoverSectionState();
}

class _DiscoverSectionState extends State<DiscoverSection> {
  List<TmdbMovie>? _movies;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _movies = DiscoverSection.cache;
    if (_movies == null) _fetch();
  }

  Future<void> _fetch() async {
    try {
      final movies = await fetchTrending();
      if (!mounted) return;
      setState(() {
        _movies = movies;
        DiscoverSection.cache = movies;
      });
      CrashLog.crumb('discover.loaded', {'count': movies.length});
    } catch (e) {
      CrashLog.error('discover.fetch_failed', e);
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final movies = _movies;
    if (_failed || movies == null || movies.isEmpty) {
      return const SizedBox.shrink(); // invisible until we have posters
    }
    final grid = movies.length > 4 ? movies.sublist(0, 4) : movies;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Discover movies',
                        style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w800)),
                    Text('Latest posters, ratings & details',
                        style: TextStyle(
                            color: AppColors.textSecondary, fontSize: 11.5)),
                  ],
                ),
              ),
              InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const DiscoverScreen())),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.surfaceAlt,
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Icon(Icons.arrow_forward_rounded,
                      color: AppColors.textPrimary, size: 19),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
          child: GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            // 16:9 image + title/rating lines ≈ 1.3 width:height.
            childAspectRatio: 1.3,
            children: [for (final m in grid) DiscoverMovieCard(movie: m)],
          ),
        ),
      ],
    );
  }
}
