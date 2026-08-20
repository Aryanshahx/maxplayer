import 'dart:async';
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
/// v47: the poster background now MOVES - a slow marquee that slides one
/// poster every couple of seconds in a seamless loop (the set is drawn
/// twice, so wrapping back one full set is invisible). The strip is also
/// draggable by hand; auto-scrolling pauses while the user is holding it.
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
  /// Width of one poster tile = one marquee step per tick.
  static const double _step = 74;

  final _client = TmdbClient();
  final _ctrl = ScrollController();
  Timer? _timer;
  List<String> _posters = const [];
  bool _userHolding = false;

  @override
  void initState() {
    super.initState();
    _boot();
    _timer =
        Timer.periodic(const Duration(milliseconds: 2200), (_) => _tick());
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
        for (final m in list.take(10))
          if (m.posterPath != null) tmdbPosterUrl(m.posterPath),
      ];
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _tick() {
    if (_userHolding || !_ctrl.hasClients || _posters.length < 2) return;
    final double loopWidth = _step * _posters.length;
    final pos = _ctrl.position;
    var from = pos.pixels;
    // Wrap point: the strip contains the same poster set twice, so at
    // loopWidth the visible content is identical to offset 0 and jumping
    // back one full set is invisible. On very wide screens the content can
    // be shorter than one set; then wrap at the end instead.
    final wrapAt =
        loopWidth <= pos.maxScrollExtent ? loopWidth : pos.maxScrollExtent;
    if (wrapAt > 0 && from >= wrapAt) {
      from -= loopWidth;
      if (from < 0) from = 0;
      if (from > pos.maxScrollExtent) from = pos.maxScrollExtent;
      _ctrl.jumpTo(from);
    }
    _ctrl.animateTo(
      from + _step,
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeInOut,
    );
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
                if (_posters.length >= 2)
                  Listener(
                    onPointerDown: (_) => _userHolding = true,
                    onPointerUp: (_) => _userHolding = false,
                    onPointerCancel: (_) => _userHolding = false,
                    child: ListView(
                      controller: _ctrl,
                      scrollDirection: Axis.horizontal,
                      children: [
                        // Two copies of the same set = seamless wrap.
                        for (final url in [..._posters, ..._posters])
                          SizedBox(
                            width: _step,
                            child: Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: TmdbImage(url: url),
                              ),
                            ),
                          ),
                      ],
                    ),
                  )
                else if (_posters.isNotEmpty)
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
