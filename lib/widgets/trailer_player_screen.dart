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

    final directUrl = await resolveTrailerUrl(videoKey);

    // Close the spinner regardless of outcome (and never pop the wrong
    // route if the user already cancelled).
    closeDialog();
    unawaited(dialogFuture);
    if (canceled || !context.mounted) return;

    if (directUrl != null && directUrl.isNotEmpty) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PlayerScreen.stream(path: directUrl, title: title),
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

    final directUrl = await resolveTrailerUrl(first.key);
    closeDialog();
    unawaited(dialogFuture);
    if (canceled || !context.mounted) return;

    if (directUrl != null && directUrl.isNotEmpty) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PlayerScreen.stream(
            path: directUrl,
            title: title,
            trailerVariants: variants,
            trailerCurrentKey: first.key,
            trailerResolver: resolveTrailerUrl,
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

/// Resolve a YouTube video id to its direct progressive (muxed) stream
/// URL with a hard 12s timeout. Shared by the initial trailer open AND
/// the in-player language switcher. Null on any failure. Never throws.
Future<String?> resolveTrailerUrl(String videoKey) async {
  // muxed (progressive 360p/720p with audio) is what mpv plays directly;
  // googlevideo URLs need no extra headers.
  final yt = YoutubeExplode();
  try {
    final manifest = await yt.videos.streams
        .getManifest(videoKey)
        .timeout(const Duration(seconds: 12));
    if (manifest.muxed.isNotEmpty) {
      return manifest.muxed.withHighestBitrate().url.toString();
    }
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
