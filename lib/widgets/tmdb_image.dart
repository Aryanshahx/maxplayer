import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'fade_in_image.dart';

/// v43: a poster/backdrop image for the Discover section with its own
/// perpetual DISK cache (permanent - movie TVDB/TMDB images don't change,
/// so one download is enough; the section stays fully offline afterwards).
///
/// Plain dart:io + Image.file/Image.memory - zero new dependencies.
/// Failed loads are remembered for the session so a dead URL is not
/// re-pounded on every scroll.
class TmdbImage extends StatefulWidget {
  final String url;
  final BoxFit fit;

  const TmdbImage({super.key, required this.url, this.fit = BoxFit.cover});

  static final Map<String, String> _resolved = {};
  static final Set<String> _failedUrls = {};
  static String? _cacheDirPath;

  /// Called once by the Discover screen (cache dir from NativeBridge).
  static void configure(String? cacheDirPath) => _cacheDirPath = cacheDirPath;

  @override
  State<TmdbImage> createState() => _TmdbImageState();
}

class _TmdbImageState extends State<TmdbImage> {
  String? _filePath;
  Uint8List? _bytes;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  static String _cacheNameFor(String url) {
    // hashCode can be negative; keep the filename filesystem-safe.
    final h = url.hashCode;
    return 'tmdb_img_${h < 0 ? 'n${-h}' : h}.jpg';
  }

  Future<void> _resolve() async {
    if (widget.url.isEmpty || TmdbImage._failedUrls.contains(widget.url)) {
      if (mounted) setState(() => _failed = true);
      return;
    }
    final known = TmdbImage._resolved[widget.url];
    if (known != null) {
      if (mounted) setState(() => _filePath = known);
      return;
    }
    final dir = TmdbImage._cacheDirPath;
    final path =
        dir == null ? null : '$dir${Platform.pathSeparator}${_cacheNameFor(widget.url)}';
    if (path != null) {
      try {
        if (await File(path).exists()) {
          TmdbImage._resolved[widget.url] = path;
          if (mounted) setState(() => _filePath = path);
          return;
        }
      } catch (_) {}
    }
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 5);
      try {
        final req = await client.getUrl(Uri.parse(widget.url));
        final res = await req.close().timeout(const Duration(seconds: 8));
        if (res.statusCode != 200) {
          throw HttpException('poster status ${res.statusCode}');
        }
        final bytes = await consolidateHttpClientResponseBytes(res);
        if (path != null) {
          try {
            await File(path).writeAsBytes(bytes, flush: true);
            TmdbImage._resolved[widget.url] = path;
          } catch (_) {}
          if (mounted) setState(() => _filePath = path);
        } else {
          // No cache dir (unexpected) - show from memory at least.
          if (mounted) setState(() => _bytes = bytes);
        }
      } finally {
        client.close(force: true);
      }
    } catch (_) {
      TmdbImage._failedUrls.add(widget.url);
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final path = _filePath;
    if (path != null) {
      return Image.file(
        File(path),
        fit: widget.fit,
        frameBuilder: fadeInImageFrame,
        errorBuilder: (_, __, ___) => const _PosterPlaceholder(),
      );
    }
    final bytes = _bytes;
    if (bytes != null) {
      return Image.memory(bytes, fit: widget.fit);
    }
    if (_failed) return const _PosterPlaceholder();
    // Loading shimmer (same block color family as the other placeholders).
    return Container(color: const Color(0xFF1e1e2a));
  }
}

class _PosterPlaceholder extends StatelessWidget {
  const _PosterPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1e1e2a),
      child: const Center(
        child: Icon(Icons.movie_outlined, size: 22, color: Colors.white24),
      ),
    );
  }
}
