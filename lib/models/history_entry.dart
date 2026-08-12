/// One row in the watch-history list. Persisted as JSON inside the native
/// settings store (SharedPreferences) by MediaPlayerState.
class HistoryEntry {
  final String path;
  final String title;
  final String? thumbnailPath;

  /// Where playback stopped (0 = finished / never started meaningfully).
  int lastPositionSecs;

  /// Total length if known (drives the little progress bar in the list).
  final int durationSecs;

  /// Last time the video was opened (ms since epoch).
  int playedAtMs;

  HistoryEntry({
    required this.path,
    required this.title,
    this.thumbnailPath,
    this.lastPositionSecs = 0,
    this.durationSecs = 0,
    required this.playedAtMs,
  });

  double get progress =>
      durationSecs > 0 ? (lastPositionSecs / durationSecs).clamp(0.0, 1.0) : 0.0;

  Map<String, dynamic> toJson() => {
        'path': path,
        'title': title,
        if (thumbnailPath != null) 'thumb': thumbnailPath,
        'pos': lastPositionSecs,
        'dur': durationSecs,
        'at': playedAtMs,
      };

  factory HistoryEntry.fromJson(Map<String, dynamic> j) => HistoryEntry(
        path: j['path'] as String? ?? '',
        title: j['title'] as String? ?? '',
        thumbnailPath: j['thumb'] as String?,
        lastPositionSecs: (j['pos'] as num?)?.toInt() ?? 0,
        durationSecs: (j['dur'] as num?)?.toInt() ?? 0,
        playedAtMs: (j['at'] as num?)?.toInt() ?? 0,
      );
}
