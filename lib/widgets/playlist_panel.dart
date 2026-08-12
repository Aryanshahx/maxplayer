import 'dart:io';
import 'package:flutter/material.dart';
import '../models/video_track.dart';
import '../utils/formatters.dart';
import '../state/theme_state.dart';

class PlaylistPanel extends StatelessWidget {
  final List<VideoTrack> playlist;
  final int currentIndex;
  final ValueChanged<int> onPlay;
  final ValueChanged<int> onRemove;

  /// Collapses the side panel (the ✕ button in the header).
  final VoidCallback onClose;

  const PlaylistPanel({
    super.key,
    required this.playlist,
    required this.currentIndex,
    required this.onPlay,
    required this.onRemove,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Panel header with an ALWAYS-visible collapse button (previously
        // there was no way to close the panel except the same toolbar icon
        // that opened it - easy to miss).
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
          child: Row(
            children: [
              Icon(Icons.queue_music, size: 18, color: themeState.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Queue · ${playlist.length}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Collapse playlist',
                icon: const Icon(
                  Icons.last_page,
                  size: 20,
                  color: Colors.white70,
                ),
                onPressed: onClose,
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: Colors.white12),
        Expanded(
          child: playlist.isEmpty
              ? const Center(
                  child: Text(
                    'Queue is empty',
                    style: TextStyle(color: Colors.white38),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: playlist.length,
                  itemBuilder: (context, i) {
                    final track = playlist[i];
                    final active = i == currentIndex;
                    return ListTile(
                      dense: true,
                      onTap: () => onPlay(i),
                      tileColor: active
                          ? Colors.white.withValues(alpha: 0.08)
                          : null,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
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
                                  child: Icon(
                                    Icons.equalizer,
                                    size: 10,
                                    color: themeState.accent,
                                  ),
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
                          fontWeight: active
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                      subtitle: Text(
                        _subtitleFor(track),
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white38,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: IconButton(
                        icon: const Icon(
                          Icons.close,
                          size: 16,
                          color: Colors.white38,
                        ),
                        onPressed: () => onRemove(i),
                      ),
                    );
                  },
                ),
        ),
      ],
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
