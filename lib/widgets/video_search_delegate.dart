import 'package:flutter/material.dart';

import '../models/video_track.dart';
import '../state/theme_state.dart';

/// Pure, testable: case-insensitive contains on the trimmed query; an
/// empty query returns everything. Used by the v44 full-screen search
/// page (opened from the new search ICON in the app bar).
List<T> filterLibraryItems<T>(
  Iterable<T> items,
  String query,
  String Function(T) titleOf,
) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return items.toList();
  return items.where((e) => titleOf(e).toLowerCase().contains(q)).toList();
}

/// v44: the library search MOVED here - a proper full-screen search page
/// (Flutter's built-in SearchDelegate) so the home screen has room for the
/// Discover banner. Same behaviour as the old search box: type, see your
/// videos filtered by title, tap to play.
class VideoSearchDelegate extends SearchDelegate<void> {
  final List<VideoTrack> videos;
  final void Function(VideoTrack track) onOpen;

  VideoSearchDelegate({required this.videos, required this.onOpen});

  @override
  ThemeData appBarTheme(BuildContext context) {
    final base = Theme.of(context);
    return base.copyWith(
      scaffoldBackgroundColor: const Color(0xFF0a0a0f),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF0a0a0f),
        foregroundColor: Colors.white,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        hintStyle: TextStyle(color: Colors.white38),
        border: InputBorder.none,
      ),
      textTheme: base.textTheme.copyWith(
        titleLarge: const TextStyle(color: Colors.white, fontSize: 18),
      ),
    );
  }

  @override
  String get searchFieldLabel => 'Search ${videos.length} videos...';

  @override
  List<Widget> buildActions(BuildContext context) => [
        if (query.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => query = '',
          ),
      ];

  @override
  Widget buildLeading(BuildContext context) => IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => close(context, null),
      );

  @override
  Widget buildResults(BuildContext context) => _buildList(context);

  @override
  Widget buildSuggestions(BuildContext context) => _buildList(context);

  Widget _buildList(BuildContext context) {
    final results = filterLibraryItems(videos, query, (v) => v.title);
    if (results.isEmpty) {
      return Center(
        child: Text(
          'No videos match "$query"',
          style: const TextStyle(color: Colors.white38),
        ),
      );
    }
    return ListView.separated(
      itemCount: results.length,
      separatorBuilder: (_, __) => const Divider(
          height: 1, color: Colors.white10, indent: 56),
      itemBuilder: (context, i) {
        final v = results[i];
        return ListTile(
          leading: Icon(Icons.play_circle_outline, color: themeState.accent),
          title: Text(
            v.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
          subtitle: Text(
            v.path,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
          onTap: () {
            close(context, null);
            onOpen(v);
          },
        );
      },
    );
  }
}
