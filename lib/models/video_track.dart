import 'package:path/path.dart' as p;

/// Mirrors the web app's VideoTrack type, adapted for local files on Android.
class VideoTrack {
  final String id;
  final String title;
  final String path; // absolute filesystem path (was `src` blob URL on web)
  final String? thumbnailPath; // cached jpg path, generated on scan
  final Duration? duration;
  final int? sizeBytes;
  final int? lastModifiedMs;
  final int? width; // pixels, from native metadata
  final int? height;
  /// v106: HTTP headers for authed streams (Google Drive Bearer token).
  /// Null for local files and open streams.
  final Map<String, String>? httpHeaders;

  const VideoTrack({
    required this.id,
    required this.title,
    required this.path,
    this.thumbnailPath,
    this.duration,
    this.sizeBytes,
    this.lastModifiedMs,
    this.width,
    this.height,
    this.httpHeaders,
  });

  /// Name of the folder containing this video (used by "Group by folder" and "Folders" quick-tile).
  String get folderName {
    final dir = p.dirname(path);
    final base = p.basename(dir);
    final lower = base.toLowerCase();
    if (lower == 'sent' || lower == 'private') {
      final parent = p.basename(p.dirname(dir));
      if (parent.isNotEmpty && parent != '/' && parent != '.') {
        return '$parent ($base)';
      }
    }
    return base.isEmpty ? dir : base;
  }

  /// Human resolution badge ("1080p", "4K", "SD", ...) based on the SHORTER
  /// side, so portrait videos get the same label as their landscape peers.
  /// Null when dimensions are unknown.
  String? get qualityLabel {
    final w = width ?? 0;
    final h = height ?? 0;
    final short = w < h ? (w == 0 ? h : w) : (h == 0 ? w : h);
    if (short <= 0) return null;
    if (short >= 2160) return '4K';
    if (short >= 1440) return '2K';
    if (short >= 1080) return '1080p';
    if (short >= 720) return '720p';
    if (short >= 480) return '480p';
    if (short >= 360) return '360p';
    return 'SD';
  }

  VideoTrack copyWith({
    String? thumbnailPath,
    Duration? duration,
    Map<String, String>? httpHeaders,
  }) {
    return VideoTrack(
      id: id,
      title: title,
      path: path,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      duration: duration ?? this.duration,
      sizeBytes: sizeBytes,
      lastModifiedMs: lastModifiedMs,
      width: width,
      height: height,
      httpHeaders: httpHeaders ?? this.httpHeaders,
    );
  }
}

enum RepeatMode { none, one, all }

enum SortMode { name, date, size, length }

enum ViewMode { grid, list }

enum GroupMode { none, name, folder }

/// What tapping a video does: queue every visible video, or just that file.
enum PlaybackAction { all, single }
