// Small pure formatting helpers (unit-tested).

/// 0 -> "0:00", 65 -> "1:05", 3723 -> "1:02:03"
String formatDuration(Duration d) {
  if (d.isNegative) d = Duration.zero;
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '${int.parse(m)}:$s';
}

/// Countdown display for the sleep-timer chip: always minutes:seconds,
/// rounding UP so "29:59" is what you see the second after arming 30 min.
/// 0 -> "0:00", 125s -> "2:05", 3700s -> "1:01:40"
String formatCountdown(Duration d) {
  if (d.isNegative) d = Duration.zero;
  var s = d.inSeconds;
  if (d.inMilliseconds.remainder(1000) > 0) s += 1; // ceil to whole seconds
  final h = s ~/ 3600;
  final m = ((s % 3600) ~/ 60).toString().padLeft(2, '0');
  final ss = (s % 60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$ss' : '${int.parse(m)}:$ss';
}

/// 1536 -> "1.5 KB", 734003200 -> "700.0 MB"
String formatBytes(int bytes) {
  if (bytes < 0) bytes = 0;
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return unit == 0 ? '${bytes}B' : '${value.toStringAsFixed(1)} ${units[unit]}';
}

/// True when [name] looks like a video file (extension check on the
/// basename — used by the file manager and vault).
bool isVideoFile(String name) {
  final base = name.split('/').last;
  final dot = base.lastIndexOf('.');
  if (dot <= 0) return false;
  final ext = base.substring(dot).toLowerCase();
  const videoExts = {
    '.mp4', '.mkv', '.webm', '.avi', '.mov', '.wmv', '.flv', '.ts', '.m2ts',
    '.mpg', '.mpeg', '.3gp', '.vob', '.m4v', '.mts', '.f4v',
  };
  return videoExts.contains(ext);
}
