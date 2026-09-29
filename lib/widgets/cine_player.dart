/// CinePlayer — the full-screen playback modal. Decision ladder (field
/// note v1.0.1+41, exactly this order):
///   1) local stream (a device file match) -> native MPV player,
///   2) else VERIFIED-EMBEDDABLE YouTube trailer -> sealed nocookie embed,
///   3) else poster fallback with a direct "Watch on YouTube" link,
///   4) else poster-based "stream coming soon" state.
///
/// 152-4 ROOT CAUSE (uploader-disabled embeds): some trailer IDs in the
/// catalog point at videos whose owner turned OFF "Allow embedding";
/// those ALWAYS fail inside an iframe with error 150/152, and no
/// WebResourceError fires to detect it. Gate: before building the iframe
/// we probe YouTube's oEmbed endpoint — 200 = embeddable, 401/403/
/// network-error = blocked -> we skip the iframe entirely and go
/// straight to the poster fallback (step 3), so the user NEVER sees the
/// broken red YouTube error again. A runtime watchdog + main-frame error
/// delegate demote to the same fallback if an embeddable video still
/// refuses to load in the page.
///
/// Sealed-embed history kept alive: the local HTML page is served from
/// the youtube.com parent origin (without it YouTube answers error 153),
/// and the navigation delegate refuses main-frame hijacks (+30 lesson).
library;

import 'dart:async';
import 'dart:io';

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
/// error"); the +30 lesson, kept.
const kCineEmbedBaseUrl = 'https://www.youtube.com';

/// oEmbed gate: 200 => embeddable, 401/403 => uploader disabled iframe
/// embedding (the 150/152 root cause). Probed BEFORE we build a webview
/// so the broken red screen never renders (pure).
String cineOembedCheckUrl(String key) =>
    'https://www.youtube.com/oembed'
    '?url=https://www.youtube.com/watch?v=$key&format=json';

/// The YouTube watch URL for a trailer key (pure) — used by the poster
/// fallback's "Watch on YouTube" link.
String cineTrailerWatchUrl(String key) => youtubeWatchUrl(key);

/// The trailer embed page, using the EXACT iframe the spec demands
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

  /// true = the oEmbed gate said NO (or the live embed broke) -> show the
  /// poster fallback with the direct YouTube link. This is why the user
  /// never sees YouTube's own red error screen again.
  bool _fallback = false;

  bool _badgeVisible = true;
  Timer? _watchdog;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  @override
  void dispose() {
    _watchdog?.cancel();
    unawaited(_web?.loadRequest(Uri.parse('about:blank')));
    super.dispose();
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
      // THE 152-4 GATE: probe embeddability BEFORE building the iframe.
      final embeddable = await _embedAllowed(key);
      if (!mounted) return;
      if (!embeddable) {
        CrashLog.crumb('cineplayer.not_embeddable', {'key': key});
        setState(() {
          _loading = false;
          _fallback = true;
        });
        return;
      }
      _loadTrailer(key);
    } else {
      setState(() => _loading = false);
    }
    // The "Trailer Preview" badge auto-fades so it never covers center
    // screen during playback.
    Timer(const Duration(milliseconds: 2400), () {
      if (mounted) setState(() => _badgeVisible = false);
    });
  }

  /// oEmbed probe: 200 => the uploader allows iframe embedding.
  Future<bool> _embedAllowed(String key) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    try {
      final req = await client
          .getUrl(Uri.parse(cineOembedCheckUrl(key)))
          .timeout(const Duration(seconds: 6));
      final res = await req.close().timeout(const Duration(seconds: 6));
      await res.drain<void>();
      CrashLog.crumb('cineplayer.oembed', {
        'key': key,
        'status': res.statusCode,
      });
      return res.statusCode == 200;
    } catch (e) {
      CrashLog.error('cineplayer.oembed_failed', e);
      return false; // unreachable host -> safe fallback, never the error
    } finally {
      client.close(force: true);
    }
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
                _watchdog?.cancel();
                if (mounted) setState(() => _loading = false);
              },
              onWebResourceError: (err) {
                if (err.isForMainFrame != true || !mounted) return;
                CrashLog.error(
                  'cineplayer.embed_error',
                  '${err.errorCode} ${err.description}',
                );
                _watchdog?.cancel();
                setState(() {
                  _loading = false;
                  _fallback = true;
                });
              },
              onNavigationRequest: (req) {
                // SEALED (+30 lesson): only sub-frames + about:blank ever
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
    // Watchdog: if the embed page never finishes (region block, dead
    // network), demote to the fallback instead of spinning forever.
    _watchdog = Timer(const Duration(seconds: 20), () {
      if (mounted && _loading) {
        setState(() {
          _loading = false;
          _fallback = true;
        });
      }
    });
    setState(() => _web = controller);
  }

  Future<void> _openOnYoutube() async {
    final url = _key.isEmpty
        ? 'https://www.youtube.com/results?search_query=${Uri.encodeComponent('${widget.movie.title} trailer')}'
        : cineTrailerWatchUrl(_key);
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
          if (_mode == CinePlayerMode.trailer && !_fallback && _web != null)
            WebViewWidget(controller: _web!)
          else if (_loading && !_fallback)
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
            _trailerFallbackBody()
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
          if (_mode == CinePlayerMode.trailer && !_fallback && _web != null)
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

  /// Step-3 fallback (per the +41 field note): the trailer is NOT
  /// embeddable (or the live embed broke) -> hide any iframe, show the
  /// poster + a direct "Watch on YouTube" link. The red 152-4 screen can
  /// no longer be reached.
  Widget _trailerFallbackBody() {
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
            "TRAILER CAN'T PLAY HERE",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: kCineMono,
              fontSize: 10,
              letterSpacing: 2.2,
              color: Colors.white.withValues(alpha: 0.55),
            ),
          ),
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: () => unawaited(_openOnYoutube()),
          icon: const Icon(Icons.open_in_new_rounded, size: 16),
          label: const Text('WATCH ON YOUTUBE'),
          style: FilledButton.styleFrom(
            backgroundColor: kCineCyan,
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
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
