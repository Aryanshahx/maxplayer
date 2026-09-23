import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../utils/tmdb.dart';
import '../widgets/movie_detail_sheet.dart';

/// Full-screen movie detail page — OTT apps open a dedicated page when a
/// banner/poster is tapped instead of a bottom sheet. v1.0.1+14.
class MovieDetailScreen extends StatelessWidget {
  final TmdbMovie movie;
  final AssetEntity? localMatch;
  final Future<TmdbFull?> Function() detailLoader;

  const MovieDetailScreen({
    super.key,
    required this.movie,
    required this.localMatch,
    required this.detailLoader,
  });

  static Future<void> open(
    BuildContext context, {
    required TmdbMovie movie,
    required AssetEntity? localMatch,
    required Future<TmdbFull?> Function() detailLoader,
  }) {
    return Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => MovieDetailScreen(
        movie: movie,
        localMatch: localMatch,
        detailLoader: detailLoader,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF14141c),
      appBar: AppBar(
        backgroundColor: const Color(0xFF14141c),
        title: Text(
          movie.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style:
              const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
      body: SingleChildScrollView(
        child: MovieDetailSheet(
          movie: movie,
          localMatch: localMatch,
          hostContext: context,
          detailLoader: detailLoader,
        ),
      ),
    );
  }
}

