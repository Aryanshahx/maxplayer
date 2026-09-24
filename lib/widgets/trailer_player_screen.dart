import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../screens/player_screen.dart';
import '../utils/crash_log.dart';
import '../utils/iptv.dart' show kMaxPlayerUserAgent;
import '../utils/tmdb.dart';

/// In-app trailer playback — YouTube embedding (WebView/iframe) gets blocked
/// on many videos (152-4 "content unavailable"), so instead the direct
/// progressive stream URL is resolved with youtube_explode and the trailer
/// plays in MaxPlayer's own MPV player.
///
/// v1.0.1+16: the resolver used to hang the loading dialog FOREVER on slow
/// or throttled connections — `getManifest` had no timeout. Now:
///   * hard 12s timeout on URL resolution,
///   * the dialog can be CANCELLED by the user (and the late resolver
///     result is then ignored instead of popping the wrong route),
///   * v1.0.1+23: the app NEVER hands off to YouTube any more — failed
///     resolution shows an in-app thumbnail panel with RETRY.
class TrailerPlayerScreen {
  TrailerPlayerScreen._();

  /// v1.0.1+27: the LAST trailer resolution error, in plain text, so the
  /// detail-card UI can show (and the user can paste) the REAL cause
  /// instead of a generic "couldn't be loaded".
  static String? lastResolveError;

  static Future<void> open(
    BuildContext context,
    String videoKey,
    String title,
  ) async {
    var canceled = false;
    var dialogOpen = true;

    void closeDialog() {
      if (!dialogOpen) return;
      dialogOpen = false;
      Navigator.of(context, rootNavigator: true).pop();
    }

    final dialogFuture = showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dlgCtx) => AlertDialog(
        backgroundColor: const Color(0xFF1c1c26),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        content: const Row(
          children: [
            SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(
                color: Colors.white70,
                strokeWidth: 2.6,
              ),
            ),
            SizedBox(width: 16),
            Expanded(
              child: Text(
                'Loading trailer…',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              canceled = true;
              closeDialog();
            },
            child: const Text('CANCEL'),
          ),
        ],
      ),
    );

    final streams = await resolveTrailerStreams(videoKey);

    // v1.0.1+25: DEVICE-SIDE PREFLIGHT — probe what the phone's own
    // network accepts (1KB range GET) and pick the first playable
    // candidate (720p+ pair first, muxed <=360p safety second) BEFORE
    // MPV ever sees a URL. The spinner stays up during the probe.
    var playStreams = streams != null && streams.videoUrl.isNotEmpty
        ? await deviceOrderedTrailerStreams(streams)
        : null;

    // Close the spinner regardless of outcome (and never pop the wrong
    // route if the user already cancelled).
    closeDialog();
    unawaited(dialogFuture);
    if (canceled || !context.mounted) return;

    if (playStreams != null) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PlayerScreen.stream(
            path: playStreams.videoUrl,
            title: title,
            trailerAudioUrl: playStreams.audioUrl,
            trailerThumbUrl: ytThumbUrl(videoKey),
            trailerFallbackUrl: playStreams.fallbackUrl,
          ),
        ),
      );
      return;
    }

    // v1.0.1+23: NEVER leave the app — show the in-app unavailable panel
    // (thumbnail + RETRY) instead of handing the user to YouTube.
    if (context.mounted) {
      final again = await showTrailerUnavailable(
        context,
        title: title,
        thumbKey: videoKey,
      );
      if (again && context.mounted) {
        await open(context, videoKey, title);
      }
    }
  }

  /// v1.0.1+19: open a trailer with its language variants wired through
  /// — [variants] comes from TMDB (Hindi first). The player shows the
  /// TRAILER-ONLY language button (never on device videos) and switches
  /// languages mid-play via [resolveTrailerUrl].
  static Future<void> openVariants(
    BuildContext context,
    List<TrailerVariant> variants,
    String title,
  ) async {
    if (variants.isEmpty) return;
    var canceled = false;
    var dialogOpen = true;

    void closeDialog() {
      if (!dialogOpen) return;
      dialogOpen = false;
      Navigator.of(context, rootNavigator: true).pop();
    }

    final dialogFuture = showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dlgCtx) => AlertDialog(
        backgroundColor: const Color(0xFF1c1c26),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        content: const Row(
          children: [
            SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(
                color: Colors.white70,
                strokeWidth: 2.6,
              ),
            ),
            SizedBox(width: 16),
            Expanded(
              child: Text(
                'Loading trailer…',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              canceled = true;
              closeDialog();
            },
            child: const Text('CANCEL'),
          ),
        ],
      ),
    );

    // v1.0.1+22: walk EVERY language variant (Hindi first) until one
    // resolves — a single region-locked / removed / members-only key
    // (very common for Hindi dubs) must not sink the trailer into the
    // YouTube fallback.
    final hit = await resolveFirstPlayableTrailer(variants);
    // v1.0.1+25: device-side preflight (see open()) — the spinner is
    // still up, so the probe is honest UI time.
    final playStreams = hit != null && hit.streams.videoUrl.isNotEmpty
        ? await deviceOrderedTrailerStreams(hit.streams)
        : null;
    closeDialog();
    unawaited(dialogFuture);
    if (canceled || !context.mounted) return;

    if (hit != null && playStreams != null) {
      final streams = playStreams;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PlayerScreen.stream(
            path: streams.videoUrl,
            title: title,
            trailerVariants: variants,
            trailerCurrentKey: hit.key,
            trailerResolver: resolveTrailerStreams,
            trailerAudioUrl: streams.audioUrl,
            trailerThumbUrl: ytThumbUrl(hit.key),
            trailerFallbackUrl: streams.fallbackUrl,
          ),
        ),
      );
      return;
    }

    // v1.0.1+23: NEVER leave the app.
    if (context.mounted) {
      final again = await showTrailerUnavailable(
        context,
        title: title,
        thumbKey: variants.first.key,
      );
      if (again && context.mounted) {
        await openVariants(context, variants, title);
      }
    }
  }
}

/// Manifest -> [TrailerStreams] mapping (separated for unit tests):
///  * a muxed (progressive) stream at >=720p wins outright — one file,
///    audio included;
///  * otherwise the best >=720p video-only DASH stream + the
///    highest-bitrate audio track, plus the best muxed (<=360p) stream as
///    the in-player safety fallback (v1.0.1+24);
///  * a sub-720p video-only stream yields to a taller muxed stream;
///  * finally, the plain best muxed stream, or null.
TrailerStreams? trailerStreamsFromManifest(StreamManifest manifest) {
  int byResThenBitrate(VideoStreamInfo a, VideoStreamInfo b) {
    final r = b.videoResolution.height.compareTo(a.videoResolution.height);
    return r != 0 ? r : b.bitrate.compareTo(a.bitrate);
  }

  final muxed = manifest.muxed.toList()..sort(byResThenBitrate);
  for (final m in muxed) {
    if (m.videoResolution.height >= 720) {
      return TrailerStreams(m.url.toString());
    }
  }

  final videoOnly = manifest.videoOnly.toList()..sort(byResThenBitrate);
  if (videoOnly.isNotEmpty && manifest.audioOnly.isNotEmpty) {
    var best = videoOnly.firstWhere(
      (s) => s.videoResolution.height >= 720,
      orElse: () => videoOnly.first,
    );
    if (muxed.isNotEmpty &&
        best.videoResolution.height <= muxed.first.videoResolution.height) {
      return TrailerStreams(muxed.first.url.toString());
    }
    final audio = manifest.audioOnly.withHighestBitrate();
    final fallbackUrl = muxed.isNotEmpty ? muxed.first.url.toString() : null;
    return TrailerStreams(
      best.url.toString(),
      audio.url.toString(),
      fallbackUrl,
    );
  }

  if (muxed.isNotEmpty) return TrailerStreams(muxed.first.url.toString());
  return null;
}

/// v1.0.1+27: YouTube keeps tightening PO-token / signature gates on
/// specific API clients — on a flagged device the default client can
/// fail for EVERY video ("No playable trailer stream") while other
/// clients still answer. Same remedy yt-dlp / NewPipe use: cycle the
/// client — library default (androidSdkless) -> androidVr -> tv ->
/// mediaConnect. Every failure lands in
/// [TrailerPlayerScreen.lastResolveError] so the card shows the REAL
/// cause. First success wins.
Future<TrailerStreams?> resolveTrailerStreams(String videoKey) async {
  final yt = YoutubeExplode();
  try {
    const clientLadder = <String, List<YoutubeApiClient>?>{
      'default': null,
      'androidVr': [YoutubeApiClient.androidVr],
      'tv': [YoutubeApiClient.tv],
      'mediaConnect': [YoutubeApiClient.mediaConnect],
    };
    for (final entry in clientLadder.entries) {
      try {
        final manifest = await yt.videos.streams
            .getManifest(videoKey, ytClients: entry.value)
            .timeout(const Duration(seconds: 10));
        final streams = trailerStreamsFromManifest(manifest);
        if (streams != null) {
          if (entry.key != 'default') {
            CrashLog.crumb('trailer.resolve_client_ok', {
              'key': videoKey,
              'client': entry.key,
            });
          }
          return streams;
        }
        CrashLog.crumb('trailer.resolve_empty', {
          'key': videoKey,
          'client': entry.key,
        });
      } on TimeoutException catch (e) {
        TrailerPlayerScreen.lastResolveError =
            '[${entry.key}] video-info request timed out';
        CrashLog.error('trailer.resolve_timeout', e, {
          'key': videoKey,
          'client': entry.key,
        });
      } catch (e) {
        TrailerPlayerScreen.lastResolveError = '[${entry.key}] $e';
        CrashLog.error('trailer.resolve_failed', e, {
          'key': videoKey,
          'client': entry.key,
        });
      }
    }
    return null;
  } finally {
    yt.close();
  }
}

/// Back-compat wrapper for [TrailerPlayerScreen.open]: the video URL
/// only (used when a title has no language variants).
Future<String?> resolveTrailerUrl(String videoKey) async =>
    (await resolveTrailerStreams(videoKey))?.videoUrl;

/// v1.0.1+22: resolve the first playable [TrailerVariant] — keys are
/// tried in the given order (the app's Hindi-first list), duplicates are
/// skipped, and at most four DISTINCT keys are attempted so a dead
/// network can't park the loading dialog for minutes. Returns the
/// streams together with the winning YouTube key (the player must mark
/// THAT variant as current), or null when every key fails / keys are
/// exhausted. Injectable resolver for tests.
Future<({TrailerStreams streams, String key})?> resolveFirstPlayableTrailer(
  List<TrailerVariant> variants, [
  Future<TrailerStreams?> Function(String youtubeKey)? resolver,
]) async {
  final res = resolver ?? resolveTrailerStreams;
  final seen = <String>{};
  var attempts = 0;
  // v1.0.1+27: hard WALL-CLOCK cap — with the client ladder each key can
  // take up to ~40s on a poisoned network; a dead network must never park
  // the inline card for minutes.
  final sw = Stopwatch()..start();
  for (final v in variants) {
    if (v.key.isEmpty || !seen.add(v.key)) continue;
    if (++attempts > 4) break;
    final s = await res(v.key);
    if (sw.elapsed > const Duration(seconds: 50)) {
      CrashLog.crumb('trailer.resolve_wall_cap', {'attempts': attempts});
      break;
    }
    if (s != null && s.videoUrl.isNotEmpty) {
      return (streams: s, key: v.key);
    }
  }
  return null;
}

/// Outcome of a device-side 1KB range probe against a resolved stream URL.
typedef TrailerPreflight = ({bool ok, int? status, String? error});

/// v1.0.1+25 — the anti-guessing change. This sandbox's curl always got
/// 206 while real phones still failed, so the DEVICE now proves each URL
/// itself: GET with `Range: bytes=0-1023`; any 2xx = playable. Only
/// device-verified URLs are ever handed to MPV.
Future<TrailerPreflight> preflightStreamUrl(String url) async {
  HttpClient? client;
  try {
    client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8)
      ..idleTimeout = const Duration(seconds: 8);
    final req = await client
        .getUrl(Uri.parse(url))
        .timeout(const Duration(seconds: 10));
    req.headers.set('User-Agent', kMaxPlayerUserAgent);
    req.headers.set('Range', 'bytes=0-1023');
    req.followRedirects = true;
    final res = await req.close().timeout(const Duration(seconds: 10));
    await res.drain<void>();
    final status = res.statusCode;
    final ok = status >= 200 && status < 300;
    return ok
        ? (ok: true, status: status, error: null)
        : (ok: false, status: status, error: 'HTTP $status');
  } on Object catch (e) {
    return (ok: false, status: null, error: e.toString());
  } finally {
    client?.close(force: true);
  }
}

/// v1.0.1+26: ADVISORY chooser behind [deviceOrderedTrailerStreams]
/// (unit-tested). Dart's HttpClient stack is neither curl nor MPV — a
/// probe false-negative must NEVER block playback. So: keep the primary
/// when the probe accepts it (or when the probe is inconclusive on both
/// candidates — MPV is the final arbiter); only swap to the muxed
/// <=360p safety URL when the probe REJECTED the primary and ACCEPTED
/// the fallback.
TrailerStreams pickPlayableTrailerStreams(
  TrailerStreams streams, {
  required bool videoOk,
  bool fallbackOk = false,
}) {
  final fb = streams.fallbackUrl;
  if (!videoOk &&
      fb != null &&
      fb.isNotEmpty &&
      fb != streams.videoUrl &&
      fallbackOk) {
    return TrailerStreams(fb);
  }
  return streams;
}

/// v1.0.1+25 -> +26: device-side probe over the primary URL (and, only
/// when the primary probe failed, the muxed fallback). ADVISORY ORDERING
/// ONLY — the returned value is always non-null: the probe reorders
/// candidates; MPV decides. (On-device evidence: on a phone where MPV
/// could open the streams, Dart's own probe failed for EVERY trailer —
/// a blocking probe only produced false "couldn't be loaded" panels.)
Future<TrailerStreams> deviceOrderedTrailerStreams(TrailerStreams s) async {
  final v = await preflightStreamUrl(s.videoUrl);
  final fb = s.fallbackUrl;
  TrailerPreflight? f;
  if (!v.ok && fb != null && fb.isNotEmpty && fb != s.videoUrl) {
    f = await preflightStreamUrl(fb);
  }
  final out = pickPlayableTrailerStreams(
    s,
    videoOk: v.ok,
    fallbackOk: f?.ok ?? false,
  );
  if (!v.ok) {
    if (out.videoUrl == s.videoUrl) {
      CrashLog.crumb('trailer.probe_inconclusive', {
        'first_status': v.status,
        'first_error': v.error,
        if (f != null) 'fallback_status': f.status,
      });
    } else {
      CrashLog.crumb('trailer.probe_degraded', {'to': 'muxed'});
    }
  }
  return out;
}

/// v1.0.1+29: build stamp shown on the trailer card so a screenshot
/// PROVES which build is installed (kills "did the fix even reach the
/// phone?" ambiguity forever).
const kAppVersionLabel = 'MaxPlayer 1.0.1+32';

/// v1.0.1+32: the plain YouTube WATCH url — the card's hand-off target.
/// The in-app WebView embed helpers were removed after the +31 field
/// verdict: YouTube hard-gates embedded playback inside this app's
/// WebView (error 152-4 on every video, every network, every origin
/// recipe) while the watch page works everywhere. The watch URL opens in
/// YouTube's own app — playback that cannot be webview-gated.
String youtubeWatchUrl(String key) => 'https://www.youtube.com/watch?v=$key';

/// Big YouTube thumbnail URL for a video [key] — `maxresdefault.jpg`
/// (1280x720; callers fall back to `hqdefault.jpg` on error). Pure.
String ytThumbUrl(String key) =>
    'https://i.ytimg.com/vi/$key/maxresdefault.jpg';

/// v1.0.1+23: the in-app "trailer unavailable" panel that replaces the
/// old YouTube hand-off — shows the trailer's thumbnail plus a RETRY
/// button. Returns true when the user chose RETRY.
Future<bool> showTrailerUnavailable(
  BuildContext context, {
  required String title,
  required String thumbKey,
}) async {
  final again = await showDialog<bool>(
    context: context,
    builder: (dlgCtx) => AlertDialog(
      backgroundColor: const Color(0xFF16161f),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: const Text(
        'Trailer unavailable',
        style: TextStyle(
          color: Colors.white,
          fontSize: 17,
          fontWeight: FontWeight.w700,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (thumbKey.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Container(
                  color: Colors.black,
                  child: Image.network(
                    ytThumbUrl(thumbKey),
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Image.network(
                      ytThumbUrl(thumbKey)
                          .replaceAll('maxresdefault', 'hqdefault'),
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 12),
          Text(
            '"$title" trailer could not be loaded right now. Check the connection and try again.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white60,
              fontSize: 13,
              height: 1.35,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dlgCtx).pop(false),
          child: const Text('CLOSE'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dlgCtx).pop(true),
          child: const Text('RETRY'),
        ),
      ],
    ),
  );
  return again ?? false;
}
