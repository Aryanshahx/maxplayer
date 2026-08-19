import 'dart:io';

import 'package:flutter/material.dart';

import '../services/native_bridge.dart';
import '../services/tmdb_client.dart';
import '../state/theme_state.dart';
import 'tmdb_image.dart';

/// v44: the library's "Discover" button - a wide banner whose BACKGROUND is
/// a strip of the latest trending movie posters (dark scrim on top so the
/// text always reads). It replaced the old search TextField (search moved
/// to an icon in the app bar).
///
/// Posters come from the same 24h disk cache as the Discover screen, so
/// after the first online visit the banner also works fully offline. With
/// no key / no posters yet it quietly falls back to a themed gradient.
class DiscoverBanner extends StatefulWidget {
  final VoidCallback onTap;

  const DiscoverBanner({super.key, required this.onTap});

  @override
  State<DiscoverBanner> createState() => _DiscoverBannerState();
}

class _DiscoverBannerState extends State<DiscoverBanner> {
  final _client = TmdbClient();
  List<String> _posters = const [];

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    final cachePath = await NativeBridge.cacheDirPath();
    TmdbImage.configure(cachePath);
    if (cachePath != null) _client.cacheDir = Directory(cachePath);
    if (!mounted || kTmdbApiKey.isEmpty) return;
    List<TmdbMovie> list;
    try {
      // Trending page 1 - cached 24h, so this is instant after first load
      // and refreshes itself on the next day.
      list = (await _client.browse(kDiscoverFilters.first)).items;
    } catch (_) {
      list = const [];
    }
    if (!mounted) return;
    setState(() {
      _posters = [
        for (final m in list.take(4))
          if (m.posterPath != null) tmdbPosterUrl(m.posterPath),
      ];
    });
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          height: 118,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            // Fallback when posters have not loaded yet.
            gradient: const LinearGradient(
              colors: [Color(0xFF241d3d), Color(0xFF16222e)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (_posters.isNotEmpty)
                  Row(
                    children: [
                      for (final url in _posters)
                        Expanded(child: TmdbImage(url: url)),
                    ],
                  ),
                // Scrim: strong on the left (text side), light on the right
                // so the posters still shine through.
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [Color(0xE6000000), Color(0x59000000)],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Discover movies',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Latest posters, ratings & trailers',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.7),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: themeState.accent,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.arrow_forward,
                            color: themeState.onAccent, size: 18),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
