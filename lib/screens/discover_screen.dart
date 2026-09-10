import 'package:flutter/material.dart';

import '../utils/tmdb.dart';
import '../widgets/movie_card.dart';

/// Full Discover screen: all trending posters in a grid.
class DiscoverScreen extends StatelessWidget {
  const DiscoverScreen({super.key, required this.movies});

  final List<TmdbMovie> movies;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Discover movies')),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final cols = (constraints.maxWidth / 140).floor().clamp(3, 8);
          return GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              childAspectRatio: 0.62,
            ),
            itemCount: movies.length,
            itemBuilder: (context, i) => MoviePosterCard(movie: movies[i]),
          );
        },
      ),
    );
  }
}
