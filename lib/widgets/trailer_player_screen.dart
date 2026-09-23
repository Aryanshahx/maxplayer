import 'package:flutter/material.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

/// In-app trailer player (YouTube iframe) — trailers never redirect the
/// user out of MaxPlayer to the YouTube app anymore (old UX complaint).
class TrailerPlayerScreen extends StatefulWidget {
  final String videoKey;
  final String title;

  const TrailerPlayerScreen({
    super.key,
    required this.videoKey,
    required this.title,
  });

  static Future<void> open(
      BuildContext context, String videoKey, String title) {
    return Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => TrailerPlayerScreen(videoKey: videoKey, title: title),
    ));
  }

  @override
  State<TrailerPlayerScreen> createState() => _TrailerPlayerScreenState();
}

class _TrailerPlayerScreenState extends State<TrailerPlayerScreen> {
  late final YoutubePlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = YoutubePlayerController.fromVideoId(
      videoId: widget.videoKey,
      autoPlay: true,
      params: const YoutubePlayerParams(
        showFullscreenButton: true,
        mute: false,
      ),
    );
  }

  @override
  void dispose() {
    _controller.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return YoutubePlayerScaffold(
      controller: _controller,
      builder: (context, player) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          title: Text(widget.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16)),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: Center(child: player),
              ),
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text(
                  'Trailer via YouTube — played inside MaxPlayer',
                  style: TextStyle(color: Colors.white30, fontSize: 11),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

