import 'package:flutter/material.dart';
import '../local_thumbnail.dart';
import '../playlist.dart';

/// Android video_grid organisation: edge-to-edge thumbnail, quality/favourite
/// badges, duration, resume bar, then filename and metadata. No fake metadata.
class AndroidVideoTile extends StatelessWidget {
  final String source, details;
  final String? quality, duration;
  final double progress;
  final bool favourite;
  final VoidCallback play, actions, toggleFavourite;
  const AndroidVideoTile(
      {super.key,
      required this.source,
      required this.details,
      required this.play,
      required this.actions,
      required this.toggleFavourite,
      this.quality,
      this.duration,
      this.progress = 0,
      this.favourite = false});
  Widget pill(String value) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
          color: Colors.black87, borderRadius: BorderRadius.circular(4)),
      child: Text(value,
          style: const TextStyle(fontSize: 10, color: Colors.white)));
  @override
  Widget build(BuildContext context) => GestureDetector(
        onSecondaryTap: actions,
        child: Card(
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: play,
              onLongPress: actions,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                        child: Stack(fit: StackFit.expand, children: [
                      LocalThumbnail(source),
                      if (quality != null)
                        Positioned(top: 5, left: 5, child: pill(quality!)),
                      Positioned(
                          top: 2,
                          right: 2,
                          child: IconButton(
                              tooltip: favourite
                                  ? 'Remove favourite'
                                  : 'Add favourite',
                              onPressed: toggleFavourite,
                              style: IconButton.styleFrom(
                                  backgroundColor: Colors.black54,
                                  minimumSize: const Size(30, 30),
                                  padding: const EdgeInsets.all(5)),
                              icon: Icon(
                                  favourite
                                      ? Icons.favorite
                                      : Icons.favorite_border,
                                  size: 16,
                                  color: favourite
                                      ? Theme.of(context).colorScheme.primary
                                      : Colors.white))),
                      if (duration != null)
                        Positioned(bottom: 6, right: 6, child: pill(duration!)),
                      if (progress > 0)
                        Positioned(
                            bottom: 0,
                            left: 0,
                            right: 0,
                            child: LinearProgressIndicator(
                                value: progress.clamp(0, 1), minHeight: 3)),
                    ])),
                    Padding(
                        padding: const EdgeInsets.fromLTRB(10, 8, 10, 2),
                        child: Text(labelFor(source),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600))),
                    Padding(
                        padding: const EdgeInsets.fromLTRB(10, 0, 10, 9),
                        child: Text(details,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 10, color: Colors.white54))),
                  ]),
            )),
      );
}
