import 'package:flutter/material.dart';
import '../utils/tmdb.dart';
import '../services/notification_destination.dart';
import 'movie_detail_screen.dart';

/// Opens the same full Discover details UI after resolving a validated TMDB ID.
class NotificationMovieScreen extends StatefulWidget {
  final Map<String, dynamic> data;
  final Future<TmdbFull?> Function()? detailLoader;
  const NotificationMovieScreen({
    super.key,
    required this.data,
    this.detailLoader,
  });
  @override
  State<NotificationMovieScreen> createState() => _NotificationMovieState();
}

class _NotificationMovieState extends State<NotificationMovieScreen> {
  late Future<TmdbFull?> _future;
  Future<TmdbFull?> _load() => validNotificationMovie(widget.data)
      ? widget.detailLoader?.call() ??
            TmdbClient().fullDetail(
              int.parse('${widget.data['movieId']}'),
              kind: widget.data['movieKind'] as String,
            )
      : Future.value(null);
  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<TmdbFull?>(
    future: _future,
    builder: (context, s) {
      if (s.connectionState != ConnectionState.done) {
        return Scaffold(
          appBar: AppBar(
            title: Text(
              widget.data['movieTitle'] as String? ?? 'Movie details',
            ),
          ),
          body: const Center(child: CircularProgressIndicator()),
        );
      }
      final full = s.data;
      if (full == null) {
        return Scaffold(
          appBar: AppBar(title: const Text('Movie details')),
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Could not load this title. Check your connection or try again later.',
                  ),
                ),
                FilledButton(
                  onPressed: () => setState(() {
                    _future = _load();
                  }),
                  child: const Text('Retry'),
                ),
                TextButton(
                  onPressed: () =>
                      Navigator.of(context).popUntil((r) => r.isFirst),
                  child: const Text('Go Home'),
                ),
              ],
            ),
          ),
        );
      }
      return MovieDetailScreen(
        movie: full.movie,
        localMatch: null,
        detailLoader: () async => full,
      );
    },
  );
}
