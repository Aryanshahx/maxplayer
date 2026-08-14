import 'dart:io';

import 'package:flutter/material.dart';

import '../models/video_track.dart';
import '../state/theme_state.dart';
import '../utils/formatters.dart';
import 'fade_in_image.dart';

/// v29: multi-select video picker bottom sheet. Used by the Playlist tile
/// ("build a playlist from selected videos") and the Private folder's "+"
/// button. Returns the selected videos, or null when dismissed without
/// confirming.
class VideoPickerSheet extends StatefulWidget {
  final List<VideoTrack> videos;
  final String title;

  /// Verb on the confirm button ("Play", "Hide", ...).
  final String actionLabel;

  const VideoPickerSheet({
    super.key,
    required this.videos,
    required this.title,
    required this.actionLabel,
  });

  static Future<List<VideoTrack>?> show(
    BuildContext context,
    List<VideoTrack> videos, {
    required String title,
    required String actionLabel,
  }) {
    return showModalBottomSheet<List<VideoTrack>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1a1a24),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SizedBox(
        height: MediaQuery.of(sheetContext).size.height * 0.72,
        child: VideoPickerSheet(
          videos: videos,
          title: title,
          actionLabel: actionLabel,
        ),
      ),
    );
  }

  @override
  State<VideoPickerSheet> createState() => _VideoPickerSheetState();
}

class _VideoPickerSheetState extends State<VideoPickerSheet> {
  final Set<String> _selected = {};

  void _toggle(String path) {
    setState(() {
      if (!_selected.remove(path)) _selected.add(path);
    });
  }

  @override
  Widget build(BuildContext context) {
    final accent = themeState.accent;
    return SafeArea(
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 8, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: TextStyle(
                      color: accent,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      if (_selected.length == widget.videos.length) {
                        _selected.clear();
                      } else {
                        _selected
                          ..clear()
                          ..addAll(widget.videos.map((v) => v.path));
                      }
                    });
                  },
                  child: Text(
                    _selected.length == widget.videos.length
                        ? 'Clear all'
                        : 'Select all',
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: widget.videos.isEmpty
                ? const Center(
                    child: Text(
                      'No videos in the library yet - rescan first.',
                      style: TextStyle(color: Colors.white54),
                    ),
                  )
                : ListView.builder(
                    itemCount: widget.videos.length,
                    itemBuilder: (context, i) {
                      final v = widget.videos[i];
                      final selected = _selected.contains(v.path);
                      return InkWell(
                        onTap: () => _toggle(v.path),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 7),
                          child: Row(
                            children: [
                              _PickerThumb(
                                  path: v.thumbnailPath, accent: accent),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      v.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: selected
                                            ? accent
                                            : Colors.white,
                                        fontSize: 13.5,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${formatDuration(v.duration)}  ·  '
                                      '${formatFileSize(v.sizeBytes)}',
                                      style: const TextStyle(
                                          color: Colors.white38,
                                          fontSize: 11.5),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                selected
                                    ? Icons.check_circle
                                    : Icons.circle_outlined,
                                color:
                                    selected ? accent : Colors.white24,
                                size: 22,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          const Divider(height: 1, color: Colors.white12),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
            child: Row(
              children: [
                Text(
                  _selected.isEmpty
                      ? 'Tap videos to select'
                      : '${_selected.length} selected',
                  style: const TextStyle(color: Colors.white54),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: _selected.isEmpty
                      ? null
                      : () {
                          final picked = [
                            for (final v in widget.videos)
                              if (_selected.contains(v.path)) v,
                          ];
                          Navigator.of(context).pop(picked);
                        },
                  child: Text(
                    _selected.isEmpty
                        ? widget.actionLabel
                        : '${widget.actionLabel} (${_selected.length})',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PickerThumb extends StatelessWidget {
  final String? path;
  final Color accent;
  const _PickerThumb({required this.path, required this.accent});

  @override
  Widget build(BuildContext context) {
    final p = path;
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: 46,
        height: 28,
        child: p != null
            ? Image.file(
                File(p),
                fit: BoxFit.cover,
                cacheWidth: 96,
                frameBuilder: fadeInImageFrame,
                errorBuilder: (_, __, ___) => _fallback(),
              )
            : _fallback(),
      ),
    );
  }

  Widget _fallback() => Container(
        color: accent.withValues(alpha: 0.12),
        child: Icon(Icons.movie_outlined, size: 14, color: accent),
      );
}
