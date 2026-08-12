import 'dart:io';
import 'package:flutter/material.dart';
import '../models/video_track.dart';
import '../utils/formatters.dart';

class PlaylistPanel extends StatelessWidget {
  final List<VideoTrack> playlist;
  final int currentIndex;
  final ValueChanged<int> onPlay;
  final ValueChanged<int> onRemove;

  const PlaylistPanel({
    super.key,
    required this.playlist,
    required this.currentIndex,
    required this.onPlay,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    if (playlist.isEmpty) {
      return const Center(
        child: Text('Queue is empty', style: TextStyle(color: Colors.white38)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: playlist.length,
      itemBuilder: (context, i) {
        final track = playlist[i];
        final active = i == currentIndex;
        return ListTile(
          dense: true,
          onTap: () => onPlay(i),
          tileColor: active ? Colors.white.withValues(alpha: 0.08) : null,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          // Thumbnail with a small "now playing" badge on the active row.
          leading: SizedBox(
            width: 56,
            height: 34,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: _QueueThumb(track: track),
                ),
                if (active)
                  Positioned(
                    right: 2,
                    bottom: 2,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                        color: Colors.black87,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.equalizer,
                          size: 10, color: Color(0xFFA855F7)),
                    ),
                  ),
              ],
            ),
          ),
          title: Text(
            track.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              color: active ? Colors.white : Colors.white70,
              fontWeight: active ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
          subtitle: Text(
            _subtitleFor(track),
            style: const TextStyle(fontSize: 11, color: Colors.white38),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: IconButton(
            icon: const Icon(Icons.close, size: 16, color: Colors.white38),
            onPressed: () => onRemove(i),
          ),
        );
      },
    );
  }

  static String _subtitleFor(VideoTrack track) {
    final parts = <String>[
      if (track.qualityLabel != null) track.qualityLabel!,
      if (formatDuration(track.duration) != '--:--')
        formatDuration(track.duration),
      if (formatFileSize(track.sizeBytes).isNotEmpty)
        formatFileSize(track.sizeBytes),
    ];
    return parts.join('  ·  ');
  }
}

class _QueueThumb extends StatelessWidget {
  final VideoTrack track;
  const _QueueThumb({required this.track});

  @override
  Widget build(BuildContext context) {
    if (track.thumbnailPath != null) {
      return Image.file(
        File(track.thumbnailPath!),
        fit: BoxFit.cover,
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
