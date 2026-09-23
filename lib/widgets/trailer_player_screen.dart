import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../screens/player_screen.dart';
import '../utils/crash_log.dart';

/// In-app trailer playback — YouTube embedding (WebView/iframe) gets blocked
/// on many videos (152-4 "content unavailable"), so instead the direct
/// progressive stream URL is resolved with youtube_explode and the trailer
/// plays in MaxPlayer's own MPV player. Falls back to the YouTube app/tab
/// only when every resolver path fails. v1.0.1+15.
class TrailerPlayerScreen {
  TrailerPlayerScreen._();

  static Future<void> open(
    BuildContext context,
    String videoKey,
    String title,
  ) async {
    final loading = showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          const Center(child: CircularProgressIndicator(color: Colors.white)),
    );
    String? directUrl;
    try {
      final yt = YoutubeExplode();
      try {
        final manifest = await yt.videos.streams.getManifest(videoKey);
        // muxed (progressive 360p/720p with audio) is what mpv needs.
        final best = manifest.muxed.withHighestBitrate();
        directUrl = best.url.toString();
      } catch (e) {
        CrashLog.error('trailer.resolve_failed', e, {'key': videoKey});
      }
      yt.close();
    } catch (e) {
      CrashLog.error('trailer.resolve_hard_failed', e, {'key': videoKey});
    }

    // Close the spinner regardless of outcome.
    if (context.mounted) Navigator.of(context, rootNavigator: true).maybePop();
    await loading;

    if (directUrl != null && directUrl.isNotEmpty) {
      if (!context.mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PlayerScreen.stream(path: directUrl!, title: title),
        ),
      );
      return;
    }
    // Hard fallback: hand off to the YouTube app/browser (resolver failed).
    final uri = Uri.parse('https://www.youtube.com/watch?v=$videoKey');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('In-app trailer failed — opening YouTube instead'),
        ),
      );
    }
  }
}

