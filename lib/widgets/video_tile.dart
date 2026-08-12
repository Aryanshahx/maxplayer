import 'dart:io';
import 'package:flutter/material.dart';
import '../models/video_track.dart';
import '../utils/formatters.dart';
import '../state/theme_state.dart';
import 'fade_in_image.dart';

class VideoTile extends StatelessWidget {
  final VideoTrack track;
  final bool isFavorite;
  final VoidCallback onTap;
  final VoidCallback onFavorite;

  const VideoTile({
    super.key,
    required this.track,
    required this.isFavorite,
    required this.onTap,
    required this.onFavorite,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (track.thumbnailPath != null)
                    Image.file(
                      File(track.thumbnailPath!),
                      fit: BoxFit.cover,
                      frameBuilder: fadeInImageFrame,
                      errorBuilder: (_, __, ___) => const _Placeholder(),
                    )
                  else
                    const _Placeholder(),
                  // Quality badge (e.g. "1080p"), top-left like VLC.
                  if (track.qualityLabel != null)
                    Positioned(
                      top: 4,
                      left: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          track.qualityLabel!,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  // Favourite toggle
                  Positioned(
                    top: 4,
                    right: 4,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: onFavorite,
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isFavorite ? Icons.favorite : Icons.favorite_border,
                          size: 15,
                          color: isFavorite
                              ? themeState.accent
                              : Colors.white70,
                        ),
                      ),
                    ),
                  ),
                  // Duration pill
                  if (track.duration != null)
                    Positioned(
                      right: 6,
                      bottom: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          formatDuration(track.duration),
                          style: const TextStyle(
                              fontSize: 11, color: Colors.white),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    formatFileSize(track.sizeBytes),
                    style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.5)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black45,
      child: const Center(
        child: Icon(Icons.movie_outlined, size: 32, color: Colors.white24),
      ),
    );
  }
}
