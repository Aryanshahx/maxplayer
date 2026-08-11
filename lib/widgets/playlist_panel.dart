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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          leading: Icon(
            active ? Icons.equalizer : Icons.play_arrow,
            size: 18,
            color: active ? const Color(0xFFA855F7) : Colors.white38,
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
          subtitle: Text(formatFileSize(track.sizeBytes),
              style: const TextStyle(fontSize: 11, color: Colors.white38)),
          trailing: IconButton(
            icon: const Icon(Icons.close, size: 16, color: Colors.white38),
            onPressed: () => onRemove(i),
          ),
        );
      },
    );
  }
}
