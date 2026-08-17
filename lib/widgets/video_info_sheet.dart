import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/native_bridge.dart';
import '../state/media_player_state.dart';
import '../state/theme_state.dart';
import '../utils/formatters.dart';

/// Bottom sheet with technical details about the video currently loaded in
/// the player (resolution, codec, bitrate, size, duration, path...).
/// Values are refreshed live from the native MediaMetadataRetriever.
class VideoInfoSheet extends StatelessWidget {
  final MediaPlayerState player;

  /// Provided by the wrapping DraggableScrollableSheet so the info list can
  /// be dragged/scrolled up to see every row (v20).
  final ScrollController? scrollController;

  const VideoInfoSheet({
    super.key,
    required this.player,
    this.scrollController,
  });

  static Future<void> show(BuildContext context, MediaPlayerState player) {
    // v20: isScrollControlled + DraggableScrollableSheet - the old
    // fixed-height sheet cropped the bottom rows on small screens and
    // could not be dragged up ("video info is not sliding"). Now it drags
    // between 30% and 90% of the screen and the rows scroll.
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1a1a24),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => VideoInfoSheet(
          player: player,
          scrollController: scrollController,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final track = player.currentTrack;
    final accent = themeState.accent;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
        // v20: scrollable content - pairs with the DraggableScrollableSheet
        // in show() so every row can be pulled up into view.
        child: SingleChildScrollView(
          controller: scrollController,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Video info',
                style: TextStyle(
                  color: accent,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              if (track == null)
                const Text('Nothing is loaded right now',
                    style: TextStyle(color: Colors.white38))
              else
                FutureBuilder<VideoMetadata>(
                  future: track.path.contains('://')
                      ? null
                      : NativeBridge.fetchMetadata(track.path),
                  builder: (context, snap) {
                    final meta = snap.data;
                    final w = meta?.width ?? track.width;
                    final h = meta?.height ?? track.height;
                    final sizeBytes =
                        track.sizeBytes ?? _fileSizeOrNull(track.path);
                    // v27: container from the file extension (MKV, MP4...).
                    final isStream = track.path.contains('://');
                    final container = isStream
                        ? null
                        : (track.path.contains('.')
                            ? track.path.split('.').last.toUpperCase()
                            : null);
                    final aspect = (w != null && h != null && w > 0 && h > 0)
                        ? formatAspectRatio(w, h)
                        : '';
                    // v27: "AAC · 2 ch · 48 kHz" style audio summary.
                    final audioParts = <String>[
                      if (meta?.audioCodec != null) meta!.audioCodec!,
                      if (meta?.audioChannels != null)
                        '${meta!.audioChannels} ch',
                      if (meta?.audioSampleRate != null)
                        '${(meta!.audioSampleRate! / 1000).toStringAsFixed(0)} kHz',
                    ];
                    final modified =
                        isStream ? null : _modifiedLabel(track.path);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _Row('Name', track.title),
                        _Row('Location', track.path, small: true),
                        if (container != null) _Row('Format', container),
                        _Row(
                          'Resolution',
                          (w != null && h != null && w > 0)
                              ? '$w × $h  ·  ${track.qualityLabel ?? ''}'
                                  '${aspect.isNotEmpty ? '  ·  $aspect' : ''}'
                              : 'Unknown',
                        ),
                        if (meta?.frameRate != null)
                          _Row('Frame rate', '${meta!.frameRate} fps'),
                        _Row(
                            'Duration',
                            formatDuration(meta?.duration ??
                                track.duration ??
                                player.duration)),
                        _Row(
                            'File size',
                            sizeBytes == null
                                ? 'Unknown'
                                : formatFileSize(sizeBytes)),
                        if (modified != null) _Row('Modified', modified),
                        if (meta?.codec != null)
                          _Row('Video codec', meta!.codec!.toUpperCase()),
                        if (hdrLabelFor(meta?.hdr) != null)
                          _Row('Video range', hdrLabelFor(meta!.hdr)!),
                        if (audioParts.isNotEmpty)
                          _Row('Audio', audioParts.join('  ·  ')),
                        if (meta?.bitrateBps != null && meta!.bitrateBps! > 0)
                          _Row('Bitrate',
                              '${(meta.bitrateBps! / 1000000).toStringAsFixed(1)} Mbps'),
                        _Row('Queue position',
                            '${player.currentIndex + 1} of ${player.playlist.length}'),
                      ],
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  int? _fileSizeOrNull(String path) {
    try {
      if (path.contains('://')) return null;
      return File(path).lengthSync();
    } catch (_) {
      return null;
    }
  }

  /// v27: "14 Aug 2026 · 03:10" for the Modified row.
  String? _modifiedLabel(String path) {
    try {
      final ts = File(path).lastModifiedSync();
      return DateFormat('dd MMM yyyy · HH:mm').format(ts);
    } catch (_) {
      return null;
    }
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  final bool small;

  const _Row(this.label, this.value, {this.small = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 106,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white38, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: Colors.white,
                fontSize: small ? 11.5 : 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
