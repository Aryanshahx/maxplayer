import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
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
///   * clean snackbar + YouTube-app fallback whenever resolution fails.
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
          ),
        ),
      );
      return;
    }

    // Hard fallback: hand off to the YouTube app/browser.
    if (context.mounted) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          const SnackBar(
            content: Text('In-app trailer failed — opening YouTube instead'),
            duration: Duration(seconds: 3),
          ),
        );
    }
    final uri = Uri.parse('https://www.youtube.com/watch?v=$videoKey');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
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
    final first = variants.first;
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

    final streams = await resolveTrailerStreams(first.key);
    closeDialog();
    unawaited(dialogFuture);
    if (canceled || !context.mounted) return;

    if (streams != null && streams.videoUrl.isNotEmpty) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PlayerScreen.stream(
            path: streams.videoUrl,
            title: title,
            trailerVariants: variants,
            trailerCurrentKey: first.key,
            trailerResolver: resolveTrailerStreams,
            trailerAudioUrl: streams.audioUrl,
          ),
        ),
      );
      return;
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          const SnackBar(
            content: Text('In-app trailer failed — opening YouTube instead'),
            duration: Duration(seconds: 3),
          ),
        );
    }
    final uri = Uri.parse('https://www.youtube.com/watch?v=${first.key}');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
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
