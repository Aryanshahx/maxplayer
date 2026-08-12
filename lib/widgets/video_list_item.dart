import 'dart:io';
import 'package:flutter/material.dart';
import '../models/video_track.dart';
import '../utils/formatters.dart';
import '../state/theme_state.dart';
import 'fade_in_image.dart';

/// List-mode row for the library (see "Display in list" in the settings
/// sheet): small thumbnail, title, size + duration, and a favourite toggle.
class VideoListItem extends StatelessWidget {
  final VideoTrack track;
  final bool isFavorite;
  final VoidCallback onTap;
  final VoidCallback onFavorite;

  const VideoListItem({
    super.key,
    required this.track,
    required this.isFavorite,
    required this.onTap,
    required this.onFavorite,
  });

  @override
  Widget build(BuildContext context) {
    final duration = formatDuration(track.duration);
    final size = formatFileSize(track.sizeBytes);
    final parts = <String>[
      if (track.qualityLabel != null) track.qualityLabel!,
      if (duration != '--:--') duration,
      if (size.isNotEmpty) size,
    ];
    final subtitle = parts.join('  ·  ');

    return ListTile(
      onTap: onTap,
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 96,
          height: 54,
          child: _Thumb(track: track),
        ),
      ),
      title: Text(
        track.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
            fontSize: 14, color: Colors.white, fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(fontSize: 12, color: Colors.white38),
      ),
      trailing: IconButton(
        icon: Icon(
          isFavorite ? Icons.favorite : Icons.favorite_border,
          size: 20,
          color: isFavorite ? themeState.accent : Colors.white38,
        ),
        onPressed: onFavorite,
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  final VideoTrack track;
  const _Thumb({required this.track});

  @override
  Widget build(BuildContext context) {
    if (track.thumbnailPath != null) {
      return Image.file(
        File(track.thumbnailPath!),
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
      color: const Color(0xFF12121a),
      child: const Center(
        child: Icon(Icons.movie_outlined, size: 22, color: Colors.white24),
      ),
    );
  }
}
