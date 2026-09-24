import 'dart:async';

import 'package:flutter/material.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../screens/player_screen.dart';
import '../utils/crash_log.dart';
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

    // Close the spinner regardless of outcome (and never pop the wrong
    // route if the user already cancelled).
    closeDialog();
    unawaited(dialogFuture);
    if (canceled || !context.mounted) return;

    if (streams != null && streams.videoUrl.isNotEmpty) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PlayerScreen.stream(
            path: streams.videoUrl,
            title: title,
            trailerAudioUrl: streams.audioUrl,
            trailerThumbUrl: ytThumbUrl(videoKey),
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
    closeDialog();
    unawaited(dialogFuture);
    if (canceled || !context.mounted) return;

    if (hit != null) {
      final streams = hit.streams;
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

/// v1.0.1+20: resolve a YouTube video id to its direct stream(s) with a
/// hard 12s timeout — NEVER below 720p when the video has 720p or better
/// at all. Selection order:
///   1. muxed (audio+video) at >=720p — mpv plays it directly;
///   2. otherwise the best video-only stream (>=720p when available)
///      paired with the best audio track — mpv attaches the audio via
///      its `audio-file` property in the player;
///   3. last resort (very old <720p-only uploads): best muxed stream so
///      playback still works instead of failing hard.
/// Shared by the initial trailer open AND the in-player language
/// switcher. Null on any failure. Never throws.
Future<TrailerStreams?> resolveTrailerStreams(String videoKey) async {
  final yt = YoutubeExplode();
  try {
    final manifest = await yt.videos.streams
        .getManifest(videoKey)
        .timeout(const Duration(seconds: 12));

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
      // If even the best video-only stream is below 720p but a muxed
      // stream exists at the same height, prefer the one-file muxed URL.
      if (muxed.isNotEmpty &&
          best.videoResolution.height <= muxed.first.videoResolution.height) {
        return TrailerStreams(muxed.first.url.toString());
      }
      final audio = manifest.audioOnly.withHighestBitrate();
      return TrailerStreams(best.url.toString(), audio.url.toString());
    }

    if (muxed.isNotEmpty) return TrailerStreams(muxed.first.url.toString());
    return null;
  } on TimeoutException catch (e) {
    CrashLog.error('trailer.resolve_timeout', e, {'key': videoKey});
    return null;
  } catch (e) {
    CrashLog.error('trailer.resolve_failed', e, {'key': videoKey});
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
  for (final v in variants) {
    if (v.key.isEmpty || !seen.add(v.key)) continue;
    if (++attempts > 4) break;
    final s = await res(v.key);
    if (s != null && s.videoUrl.isNotEmpty) {
      return (streams: s, key: v.key);
    }
  }
  return null;
}

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
                      ytThumbUrl(
                        thumbKey,
                      ).replaceAll('maxresdefault', 'hqdefault'),
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
