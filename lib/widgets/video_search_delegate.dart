
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/video_track.dart';
import '../services/native_bridge.dart';
import 'video_thumb.dart';

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
/// Discover banner. v45: results are a BIG-THUMBNAIL grid now (the old
/// text-only rows were hard to scan).
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
          )
        else
          IconButton(
            icon: const Icon(Icons.mic_none_outlined, color: Colors.white70),
            tooltip: 'Voice search',
            onPressed: () async {
              final mic = await Permission.microphone.request();
              if (!mic.isGranted) {
                // ignore: use_build_context_synchronously
                ScaffoldMessenger.of(context)
                  ..clearSnackBars()
                  ..showSnackBar(
                    const SnackBar(
                      content: Text('Microphone needed for voice search'),
                      duration: Duration(milliseconds: 1800),
                    ),
                  );
                return;
              }
              final res = await NativeBridge.launchSystemVoiceSearch();
              if (res != null && res.trim().isNotEmpty) {
                query = res.trim();
                // ignore: use_build_context_synchronously
                showResults(context);
              }
            },
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
    // v45: big-thumbnail grid - 2 columns on a phone.
    return GridView.builder(
      padding: const EdgeInsets.all(10),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 230,
        childAspectRatio: 0.80,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
      ),
      itemCount: results.length,
      itemBuilder: (context, i) {
        final v = results[i];
        return GestureDetector(
          onTap: () {
            close(context, null);
            onOpen(v);
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox.expand(child: _BigThumb(track: v)),
                ),
              ),
              const SizedBox(height: 5),
              Text(
                v.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// v45: the large search-result thumbnail (same cached JPEG the library
/// tiles show, just displayed much bigger here).
class _BigThumb extends StatelessWidget {
  final VideoTrack track;

  const _BigThumb({required this.track});

  @override
  Widget build(BuildContext context) {
    // v47: the same self-healing thumbnail as the home grid
    return VideoThumb(track: track, cacheWidth: 470);
  }
}
