/// CinePlayer — the full-screen playback modal (spec order preserved):
///   1) local stream (a device file match) -> native MPV player,
///   2) else YouTube trailer -> cinematic shell that hands off to the
///      YouTube app with the trailer watch URL,
///   3) else poster-based "stream coming soon" state.
///
/// HISTORY THAT SHAPES THIS FILE (do not regress):
///  • +28..+31 field results: YouTube REFUSES embedded playback inside a
///    WebView on this deployment network — error 153 without a parent
///    origin, and even WITH the sealed nocookie page it answers 152-4
///    inside the iframe (where no WebResourceError ever fires, so the
///    failure cannot even be detected). An in-app iframe therefore can
///    NEVER be reliable here; v1.0.1+39 shipped one and the field report
///    came back "old problem again — 152-4". v1.0.1+40 removes the
///    iframe entirely: trailers open the YouTube app (handoff), which is
///    the only path with a 100% success record.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:url_launcher/url_launcher.dart';

import '../utils/crash_log.dart';
import '../utils/tmdb.dart';
import '../utils/tmdb_image.dart';
import 'cine_ui.dart';
import 'trailer_player_screen.dart' show youtubeWatchUrl;
import 'video_grid.dart';

/// Decision order for [openCinePlayer] (pure):
/// local stream wins, then trailer, then the unavailable card.
enum CinePlayerMode { local, trailer, unavailable }

CinePlayerMode cinePlayerMode({
  required bool hasLocal,
  required String trailerKey,
}) {
  if (hasLocal) return CinePlayerMode.local;
  if (trailerKey.isNotEmpty) return CinePlayerMode.trailer;
  return CinePlayerMode.unavailable;
}

/// The YouTube watch URL for a trailer key (pure).
String cineTrailerWatchUrl(String key) => youtubeWatchUrl(key);

/// Entry point — picks the mode and routes (never returns a Future the
/// caller must await; fire and forget).
Future<void> openCinePlayer(
  BuildContext context, {
  required TmdbMovie movie,
  required AssetEntity? localMatch,
  required Future<TmdbFull?> Function() detailLoader,
}) async {
  // 1) LOCAL STREAM — the native MPV player (fullscreen etc. included).
  if (localMatch != null) {
    CrashLog.crumb('cineplayer.local', {'id': movie.id});
    unawaited(VideoGrid.openVideo(context, localMatch));
    return;
  }

  var trailerKey =
      movie.trailerKey ??
      (movie.trailerVariants.isNotEmpty ? movie.trailerVariants.first.key : '');

  // 2) TRAILER — resolve from detail if the list payload had none.
  if (trailerKey.isEmpty) {
    unawaited(
      _openShell(
        context,
        movie: movie,
        trailerKey: null, // loading; will resolve
        resolve: () async {
          final full = await detailLoader();
          if (full == null) return null;
          final m = full.movie;
          return m.trailerKey ??
              (m.trailerVariants.isNotEmpty ? m.trailerVariants.first.key : '');
        },
      ),
    );
    return;
  }

  CrashLog.crumb('cineplayer.trailer', {'id': movie.id, 'key': trailerKey});
  unawaited(
    _openShell(context, movie: movie, trailerKey: trailerKey, resolve: null),
  );
}

Future<void> _openShell(
  BuildContext context, {
  required TmdbMovie movie,
  required String? trailerKey,
  Future<String?> Function()? resolve,
}) {
  return Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder<void>(
      fullscreenDialog: true,
      opaque: true,
      barrierColor: Colors.black,
      transitionDuration: const Duration(milliseconds: 240),
      reverseTransitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (_, _, _) => _CinePlayerPage(
        movie: movie,
        trailerKey: trailerKey,
        resolve: resolve,
      ),
      transitionsBuilder: (_, anim, _, child) =>
          FadeTransition(opacity: anim, child: child),
    ),
  );
}

class _CinePlayerPage extends StatefulWidget {
  const _CinePlayerPage({
    required this.movie,
    required this.trailerKey,
    required this.resolve,
  });

  final TmdbMovie movie;
  final String? trailerKey;
  final Future<String?> Function()? resolve;

  @override
  State<_CinePlayerPage> createState() => _CinePlayerPageState();
}

class _CinePlayerPageState extends State<_CinePlayerPage> {
  String _key = '';
  CinePlayerMode _mode = CinePlayerMode.unavailable;
  bool _loading = true;
  bool _autoOpened = false;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    var key = widget.trailerKey ?? '';
    if (key.isEmpty && widget.resolve != null) {
      try {
        key = await widget.resolve!() ?? '';
      } catch (e) {
        CrashLog.error('cineplayer.resolve', e);
      }
    }
    if (!mounted) return;
    setState(() {
      _key = key;
      _mode = cinePlayerMode(hasLocal: false, trailerKey: key);
      _loading = false;
    });
    // One-tap flow: PLAY NOW landed here for a trailer, so open it in
    // YouTube immediately (v1.0.1+40 — in-app embeds are proven dead on
    // this network with 152-4).
    if (_mode == CinePlayerMode.trailer && !_autoOpened) {
      _autoOpened = true;
      unawaited(_openTrailer());
    }
  }

  Future<void> _openTrailer() async {
    final key = _key;
    final url = key.isEmpty
        ? 'https://www.youtube.com/results?search_query=${Uri.encodeComponent('${widget.movie.title} trailer')}'
        : cineTrailerWatchUrl(key);
    CrashLog.crumb('cineplayer.handoff', {'url': url});
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      CrashLog.error('cineplayer.handoff_failed', e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.movie;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // --- player area ---
          if (_loading)
            const Center(
              child: SizedBox(
                width: 44,
                height: 44,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: Colors.white,
                ),
              ),
            )
          else if (_mode == CinePlayerMode.trailer)
            _trailerBody()
          else
            _unavailableBody(),

          // --- cinematic gradient so chrome stays readable ---
          const IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xB3000000),
                    Colors.transparent,
                    Colors.transparent,
                    Color(0xD9000000),
                  ],
                  stops: [0.0, 0.18, 0.62, 1.0],
                ),
              ),
            ),
          ),

          // --- close (Android back / ESC equivalent) ---
          Positioned(
            top: 14,
            left: 14,
            child: Material(
              color: Colors.black.withValues(alpha: 0.5),
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => Navigator.of(context).maybePop(),
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(
                    Icons.close_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
              ),
            ),
          ),

          // --- metadata row: title + cyan TRAILER label ---
          if (_mode == CinePlayerMode.trailer)
            Positioned(
              left: 16,
              right: 16,
              bottom: 18,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      m.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: kCineCyan.withValues(alpha: 0.16),
                      border: Border.all(
                        color: kCineCyan.withValues(alpha: 0.5),
                      ),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'TRAILER',
                      style: TextStyle(
                        color: kCineCyan,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2.0,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Trailer mode: poster + WATCH TRAILER handoff (auto-fired once on
  /// open; the button is the explicit re-open path).
  Widget _trailerBody() {
    final m = widget.movie;
    final poster = tmdbPosterUrl(m.posterPath, big: true);
    return Column(
      children: [
        const SizedBox(height: 86),
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            width: 170,
            height: 255,
            child: poster.isEmpty
                ? const ColoredBox(color: Color(0xFF17171d))
                : TmdbImage(url: poster, fit: BoxFit.cover),
          ),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: () => unawaited(_openTrailer()),
          icon: const Icon(Icons.play_arrow_rounded, size: 18),
          label: const Text('WATCH TRAILER'),
          style: FilledButton.styleFrom(
            backgroundColor: kCineCyan,
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'OPENS IN THE YOUTUBE APP',
          style: TextStyle(
            fontFamily: kCineMono,
            fontSize: 9,
            letterSpacing: 2.2,
            color: Colors.white.withValues(alpha: 0.4),
          ),
        ),
      ],
    );
  }

  Widget _unavailableBody() {
    final m = widget.movie;
    final poster = tmdbPosterUrl(m.posterPath, big: true);
    return Column(
      children: [
        const SizedBox(height: 86),
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            width: 170,
            height: 255,
            child: poster.isEmpty
                ? const ColoredBox(color: Color(0xFF17171d))
                : TmdbImage(url: poster, fit: BoxFit.cover),
          ),
        ),
        const SizedBox(height: 18),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Text(
            m.title.toUpperCase(),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: kCineDisplay,
              fontSize: 26,
              color: Colors.white.withValues(alpha: 0.9),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'STREAM COMING SOON',
          style: TextStyle(
            fontFamily: kCineMono,
            fontSize: 10,
            letterSpacing: 2.4,
            color: kCineAmber.withValues(alpha: 0.85),
          ),
        ),
      ],
    );
  }
}
