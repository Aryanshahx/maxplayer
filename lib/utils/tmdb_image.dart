import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

/// Filesystem-safe, deterministic cache name for a poster URL.
///
/// Keeps the REAL photo name (and its size folder, so w342 never fights
/// w500) plus a deterministic 31-fold hash of the full URL — never Dart's
/// unstable String.hashCode. Pure for tests.
String tmdbImageCacheName(String url) {
  final segs = Uri.tryParse(url)?.pathSegments ?? const <String>[];
  var base = segs.isNotEmpty ? segs.last : '';
  base = base.replaceAll(RegExp('[^A-Za-z0-9._-]'), '_');
  if (base.isEmpty) base = 'img';
  final size = segs.length >= 2 ? segs[segs.length - 2] : '';
  var h = 0;
  for (final c in url.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return 'tmdb_img_${size}_${h.toRadixString(16)}_$base';
}

/// Shared [Image.frameBuilder]: thumbnails fade in softly (~220ms).
Widget fadeInImageFrame(
  BuildContext context,
  Widget child,
  int? frame,
  bool wasSynchronouslyLoaded,
) {
  if (wasSynchronouslyLoaded) return child;
  return AnimatedOpacity(
    opacity: frame == null ? 0 : 1,
    duration: const Duration(milliseconds: 220),
    curve: Curves.easeOut,
    child: child,
  );
}

/// A poster/backdrop image for the Discover section with its own perpetual
/// DISK cache (permanent — posters don't change, one download is enough;
/// the section stays fully offline afterwards).
///
/// Plain dart:io + Image.file — zero new dependencies. Failed loads are
/// remembered for the session (with a 45s cooldown) so a dead URL is not
/// re-pounded on every scroll.
class TmdbImage extends StatefulWidget {
  final String url;
  final BoxFit fit;

  const TmdbImage({super.key, required this.url, this.fit = BoxFit.cover});

  static final Map<String, String> _resolved = {};
  static final Map<String, DateTime> _failedAt = {};
  static String? _cacheDirPath;

  /// One shared keep-alive client + a tiny concurrency cap so 20 posters
  /// don't fight each other.
  static final HttpClient _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 12)
    ..idleTimeout = const Duration(seconds: 10);
  static int _inFlight = 0;
  static const int _maxInFlight = 4;

  /// Called once by the Discover screens (cache dir from path_provider).
  static void configure(String? cacheDirPath) => _cacheDirPath = cacheDirPath;

  /// Resolves a persistent, app-private cache directory under the app
  /// documents dir (survives restarts; never auto-cleared like /cache).
  static Future<String?> initCacheDir() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory('${docs.path}${Platform.pathSeparator}tmdb');
      await dir.create(recursive: true);
      return dir.path;
    } catch (_) {
      return null;
    }
  }

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

  @override
  void didUpdateWidget(covariant TmdbImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      // Recycled grid cells must never flash the previous movie's poster.
      _filePath = null;
      _bytes = null;
      _failed = false;
      _resolve();
    }
  }

  Future<void> _resolve() async {
    if (widget.url.isEmpty) {
      if (mounted) setState(() => _failed = true);
      return;
    }
    final failedAt = TmdbImage._failedAt[widget.url];
    if (failedAt != null) {
      if (DateTime.now().difference(failedAt) <
          const Duration(seconds: 45)) {
        if (mounted) setState(() => _failed = true);
        return;
      }
      TmdbImage._failedAt.remove(widget.url);
    }
    final known = TmdbImage._resolved[widget.url];
    if (known != null) {
      if (mounted) setState(() => _filePath = known);
      return;
    }
    final dir = TmdbImage._cacheDirPath;
    final path = dir == null
        ? null
        : '$dir${Platform.pathSeparator}${tmdbImageCacheName(widget.url)}';
    if (path != null) {
      try {
        if (await File(path).exists()) {
          TmdbImage._resolved[widget.url] = path;
          if (mounted) setState(() => _filePath = path);
          return;
        }
      } catch (_) {}
    }
    while (_slotsFull()) {
      await Future<void>.delayed(const Duration(milliseconds: 120));
      if (!mounted) return;
    }
    TmdbImage._inFlight++;
    try {
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          final req = await _httpGet(widget.url);
          final res = await req.close().timeout(const Duration(seconds: 20));
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
            if (mounted) setState(() => _bytes = bytes);
          }
          return;
        } catch (_) {
          if (attempt == 0) {
            await Future<void>.delayed(const Duration(milliseconds: 400));
          }
        }
      }
      TmdbImage._failedAt[widget.url] = DateTime.now();
      if (mounted) setState(() => _failed = true);
    } finally {
      TmdbImage._inFlight--;
    }
  }

  static bool _slotsFull() => TmdbImage._inFlight >= TmdbImage._maxInFlight;

  static Future<HttpClientRequest> _httpGet(String url) =>
      TmdbImage._http.getUrl(Uri.parse(url));

  @override
  Widget build(BuildContext context) {
    final path = _filePath;
    if (path != null) {
      return Image.file(
        File(path),
        fit: widget.fit,
        frameBuilder: fadeInImageFrame,
        errorBuilder: (_, _, _) => const _PosterPlaceholder(),
      );
    }
    final bytes = _bytes;
    if (bytes != null) {
      return Image.memory(bytes, fit: widget.fit);
    }
    if (_failed) return const _PosterPlaceholder();
    return Container(color: const Color(0xFF1e1e2a));
  }
}

/// Neutral dark placeholder while a poster is missing or failed.
class _PosterPlaceholder extends StatelessWidget {
  const _PosterPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1e1e2a),
      alignment: Alignment.center,
      child: Icon(Icons.movie_outlined,
          color: Colors.white.withValues(alpha: 0.15)),
    );
  }
}
