/// CinePlayer (v1.0.1+39) — the full-screen playback modal, ported from the
/// React spec. Decision order (pure, pin-tested):
///   1) local stream (a device file match) -> native MPV player,
///   2) else YouTube trailer -> sealed NO-COOKIE embed page, EXACT params,
///   3) else poster-based "stream coming soon" state.
///
/// HISTORY THAT SHAPES THIS FILE (do not regress):
///  • +28..+31 field results: YouTube REFUSES embedded playback inside a
///    bare WebView (error 153 without a parent origin; error 152-4 when it
///    decides the WebView's identity is not acceptable). The baseUrl'd
///    local page below is the +30 fix; the sealed navigation delegate is
///    the +30 "no hijack" fix. The OPEN IN YOUTUBE escape stays visible
///    because the network can still say no inside the iframe (152-4) —
///    the escape is honest, not decorative.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

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

/// The parent ORIGIN the sealed embed page is served from. Required —
/// without it YouTube answers error 153 ("Video player configuration
/// error"); this is the +30 lesson, kept.
const kCineEmbedBaseUrl = 'https://www.youtube.com';

/// The trailer embed page, using the EXACT iframe source the spec demands
/// (nocookie host, autoplay/rel/modestbranding/playsinline, full area,
/// absolute inset, full allow list, allowFullScreen) (pure).
String cineTrailerEmbedHtml(String key) =>
    '''
<!DOCTYPE html>
<html>
<head>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
html,body{margin:0;padding:0;background:#000;height:100%;overflow:hidden}
iframe{position:absolute;inset:0;width:100%;height:100%;border:0}
</style>
</head>
<body>
<iframe src="https://www.youtube-nocookie.com/embed/$key?autoplay=1&rel=0&modestbranding=1&playsinline=1" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share" allowfullscreen></iframe>
</body>
</html>''';

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
  WebViewController? _web;
  String _key = '';
  CinePlayerMode _mode = CinePlayerMode.unavailable;
  bool _loading = true;
  bool _failed = false;
  String _failDetail = '';
  bool _badgeVisible = true;

  @override
  void initState() {
    super.initState();
    _start();
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
    _key = key;
    _mode = cinePlayerMode(hasLocal: false, trailerKey: key);
    if (_mode == CinePlayerMode.trailer) {
      _loadTrailer(key);
    } else {
      setState(() => _loading = false);
    }
    // The "Trailer Preview" badge auto-fades so it never covers center
    // screen during playback (spec wants it centered briefly).
    Timer(const Duration(milliseconds: 2400), () {
      if (mounted) setState(() => _badgeVisible = false);
    });
  }

  void _loadTrailer(String key) {
    final controller =
        WebViewController.fromPlatformCreationParams(
            AndroidWebViewControllerCreationParams(),
          )
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..setBackgroundColor(Colors.black)
          ..setNavigationDelegate(
            NavigationDelegate(
              onPageFinished: (_) {
                if (mounted) setState(() => _loading = false);
              },
              onWebResourceError: (err) {
                if (err.isForMainFrame != true || !mounted) return;
                CrashLog.error(
                  'cineplayer.embed_error',
                  '${err.errorCode} ${err.description}',
                );
                setState(() {
                  _loading = false;
                  _failed = true;
                  _failDetail = '${err.errorCode}: ${err.description}';
                });
              },
              onNavigationRequest: (req) {
                // SEALED (+30 lesson): only sub-frame + about:blank ever
                // navigate; the YouTube "watch on youtube" hijack is refused.
                if (!req.isMainFrame) return NavigationDecision.navigate;
                if (req.url == 'about:blank') {
                  return NavigationDecision.navigate;
                }
                return NavigationDecision.prevent;
              },
            ),
          )
          ..loadHtmlString(
            cineTrailerEmbedHtml(key),
            baseUrl: kCineEmbedBaseUrl,
          );
    unawaited(
      (controller.platform as AndroidWebViewController)
          .setMediaPlaybackRequiresUserGesture(false),
    );
    setState(() => _web = controller);
  }

  @override
  void dispose() {
    unawaited(_web?.loadRequest(Uri.parse('about:blank')));
    super.dispose();
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
          if (_mode == CinePlayerMode.trailer && !_failed && _web != null)
            WebViewWidget(controller: _web!)
          else if (_mode == CinePlayerMode.trailer && _failed)
            _failedBody()
          else if (_loading)
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

          // --- "Trailer Preview" frosted badge (auto-fades) ---
          if (_mode == CinePlayerMode.trailer && !_failed)
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 600),
                  opacity: _badgeVisible ? 1 : 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.2),
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'TRAILER PREVIEW',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 10,
                          letterSpacing: 2.4,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // --- metadata row: title + cyan TRAILER label ---
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
                    border: Border.all(color: kCineCyan.withValues(alpha: 0.5)),
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

  Widget _failedBody() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.white54, size: 34),
            const SizedBox(height: 10),
            const Text(
              'The trailer could not be loaded.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (_failDetail.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                _failDetail,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ],
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: () {
                final url = _key.isEmpty
                    ? 'https://www.youtube.com/results?search_query=${Uri.encodeComponent('${widget.movie.title} trailer')}'
                    : youtubeWatchUrl(_key);
                unawaited(
                  launchUrl(
                    Uri.parse(url),
                    mode: LaunchMode.externalApplication,
                  ),
                );
              },
              icon: const Icon(Icons.open_in_new_rounded, size: 16),
              label: const Text('OPEN IN YOUTUBE'),
            ),
          ],
        ),
      ),
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
