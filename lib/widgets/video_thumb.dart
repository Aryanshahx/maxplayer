import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../models/video_track.dart';
import '../services/native_bridge.dart';

/// v47: the shared video thumbnail for the home grid / list / search.
///
/// FIX "no thumbnails on the home screen from the start": before, if the
/// scan-time frame capture came back null, the tile showed the placeholder
/// FOREVER and nothing ever tried again. Now every tile asks ONE more time
/// when it becomes visible (native regenerates + disk-caches the JPEG, so
/// this costs a retriever read only once per video), and the answer is
/// remembered for the session.
class VideoThumb extends StatefulWidget {
  final VideoTrack track;
  final int cacheWidth;

  const VideoThumb({super.key, required this.track, this.cacheWidth = 360});

  /// path -> resolved thumbnail path (null = asked, still none)
  static final Map<String, String?> _lazy = {};
  static final Set<String> _inFlight = {};

  /// v60 (old-phone pack): capped native frame decodes running at once -
  /// one task per visible grid tile was spiking low-RAM phones. Queued
  /// tiles just keep the placeholder a moment longer.
  /// v74: raised 2 -> 4. The grab is mostly waiting on the decoder/disk,
  /// not spinning the CPU, so 2 was the main reason thumbnails trickled
  /// in noticeably slower than VLC while scrolling a big library.
  static int _thumbJobsRunning = 0;
  static final List<Completer<void>> _thumbWaiters = [];

  static Future<void> acquireThumbSlot() async {
    if (_thumbJobsRunning < 2) {
      _thumbJobsRunning++;
      return;
    }
    final c = Completer<void>();
    _thumbWaiters.add(c);
    await c.future;
  }

  static void releaseThumbSlot() {
    if (_thumbWaiters.isNotEmpty) {
      _thumbWaiters.removeAt(0).complete();
    } else {
      _thumbJobsRunning--;
    }
  }

  @override
  State<VideoThumb> createState() => _VideoThumbState();
}

class _VideoThumbState extends State<VideoThumb> {
  String? _thumbPath;
  bool _asked = false;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant VideoThumb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.track.path != widget.track.path) {
      _thumbPath = null;
      _asked = false;
      _resolve();
    }
  }

  void _resolve() {
    final t = widget.track.thumbnailPath;
    if (t != null) {
      _thumbPath = t;
      return;
    }
    final cached = VideoThumb._lazy[widget.track.path];
    if (cached != null) {
      _thumbPath = cached;
      return;
    }
    if (_asked || !VideoThumb._inFlight.add(widget.track.path)) return;
    _asked = true;
    () async {
      await VideoThumb.acquireThumbSlot();
      try {
        var meta = await NativeBridge.fetchMetadata(widget.track.path);
        if (meta.thumbnailPath == null) {
          // v60: ONE retry after a breath - some files expose a frame a
          // beat late. Never loops forever, never crashes over a thumb.
          await Future<void>.delayed(const Duration(milliseconds: 350));
          if (mounted) {
            meta = await NativeBridge.fetchMetadata(widget.track.path);
          }
        }
        VideoThumb._lazy[widget.track.path] = meta.thumbnailPath;
        if (meta.thumbnailPath == null) return;
        if (mounted) setState(() => _thumbPath = meta.thumbnailPath);
      } catch (_) {
        // keep the placeholder - nothing crashes over a thumbnail
      } finally {
        VideoThumb._inFlight.remove(widget.track.path);
        VideoThumb.releaseThumbSlot();
      }
    }();
  }

  @override
  Widget build(BuildContext context) {
    final p = _thumbPath;
    if (p != null) {
      return Image.file(
        File(p),
        fit: BoxFit.cover,
        cacheWidth: widget.cacheWidth,
        errorBuilder: (_, __, ___) => const VideoThumbPlaceholder(),
      );
    }
    return const VideoThumbPlaceholder();
  }
}

class VideoThumbPlaceholder extends StatelessWidget {
  const VideoThumbPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1e1e2a),
      alignment: Alignment.center,
      child: Icon(Icons.videocam_outlined,
          size: 40, color: Colors.white.withValues(alpha: 0.18)),
    );
  }
}
