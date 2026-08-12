import 'dart:io';

import 'package:flutter/material.dart';

import '../screens/player_screen.dart';
import '../state/media_player_state.dart';
import '../state/theme_state.dart';
import '../utils/formatters.dart';
import 'fade_in_image.dart';

/// Compact player bar pinned to the bottom of the home screen while something
/// is loaded in the player. Tap to return to the full player; close to stop.
class MiniPlayer extends StatelessWidget {
  final MediaPlayerState player;

  const MiniPlayer({super.key, required this.player});

  @override
  Widget build(BuildContext context) {
    final accent = themeState.accent;
    return AnimatedBuilder(
      animation: player,
      builder: (context, _) {
        final track = player.currentTrack;
        final total = player.duration.inMilliseconds;
        final progress = total > 0
            ? (player.position.inMilliseconds / total).clamp(0.0, 1.0)
            : 0.0;
        // Slides/grows in smoothly when playback starts, shrinks away on stop.
        return AnimatedSize(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: track == null
              ? const SizedBox(width: double.infinity)
              : Material(
                  color: const Color(0xFF12121a),
                  child: InkWell(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => PlayerScreen(player: player),
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        LinearProgressIndicator(
                          value: progress,
                          minHeight: 2,
                          backgroundColor: Colors.white10,
                          color: accent,
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                          child: Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: SizedBox(
                                  width: 56,
                                  height: 32,
                                  child: _thumb(track),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      track.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                      ),
                                    ),
                                    Text(
                                      '${formatDuration(player.position)} / ${formatDuration(player.duration)}',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Colors.white38,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: Icon(
                                  player.isPlaying
                                      ? Icons.pause_circle_filled
                                      : Icons.play_circle_filled,
                                  color: accent,
                                  size: 30,
                                ),
                                onPressed: player.togglePlay,
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.close,
                                  color: Colors.white38,
                                  size: 20,
                                ),
                                onPressed: player.stopMini,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
        );
      },
    );
  }

  Widget _thumb(dynamic track) {
    final thumb = track.thumbnailPath as String?;
    if (thumb != null) {
      return Image.file(
        File(thumb),
        fit: BoxFit.cover,
        frameBuilder: fadeInImageFrame,
        errorBuilder: (_, __, ___) => const _Placeholder(),
      );
    }
    return const _Placeholder();
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1e1e2a),
      child: const Center(
        child: Icon(Icons.movie_outlined, size: 16, color: Colors.white24),
      ),
    );
  }
}
