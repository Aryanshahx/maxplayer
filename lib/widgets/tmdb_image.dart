import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'fade_in_image.dart';

/// Filesystem-safe, deterministic cache name for a poster URL.
///
/// v44 FIX (wrong posters): v43 used Dart's String.hashCode, which is not
/// a stable contract - and recycled grid cells kept showing whatever file
/// the reuse collision mapped to. Now the name keeps the REAL photo name
/// (and its size folder, so w342 never fights w500) plus a deterministic
/// 31-fold hash of the full URL. Pure for tests.
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

/// v43: a poster/backdrop image for the Discover section with its own
/// perpetual DISK cache (permanent - movie posters don't change, so one
/// download is enough; the section stays fully offline afterwards).
///
/// Plain dart:io + Image.file/Image.memory - zero new dependencies.
/// Failed loads are remembered for the session so a dead URL is not
/// re-pounded on every scroll.
class TmdbImage extends StatefulWidget {
  final String url;
  final BoxFit fit;

  const TmdbImage({super.key, required this.url, this.fit = BoxFit.cover});

  static final Map<String, String> _resolved = {};

  /// v45: failures are remembered WITH a time, not forever. v43/v44 kept
  /// them for the whole session, so one weak-network moment froze dead
  /// posters until the app restarted - part of why Discover "needed
  /// multiple refreshes". Now a failed poster retries after 45 seconds.
  static final Map<String, DateTime> _failedAt = {};
  static String? _cacheDirPath;

  /// v45: one shared keep-alive client (was: a fresh 5s client per poster)
  /// plus a tiny concurrency cap so 20 posters don't fight each other.
  static final HttpClient _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 12)
    ..idleTimeout = const Duration(seconds: 10);
  static int _inFlight = 0;
  static const int _maxInFlight = 4;

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

  @override
  void didUpdateWidget(covariant TmdbImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      // v44 FIX (wrong posters after refresh): the grid RECYCLES cells when
      // the list re-orders; without this reset the reused cell kept the OLD
      // movie's poster while the title already showed the new movie.
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
      // v45: cooldown over - give it another chance instead of staying dead.
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
    // v45: download with the shared client, one retry, and at most
    // _maxInFlight parallel downloads (queue by waiting a little).
    while (_TmdbImageState._slotsFull()) {
      await Future<void>.delayed(const Duration(milliseconds: 120));
      if (!mounted) return;
    }
    TmdbImage._inFlight++;
    try {
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          final req = await _TmdbImageState._httpGet(widget.url);
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
            // No cache dir (unexpected) - show from memory at least.
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
