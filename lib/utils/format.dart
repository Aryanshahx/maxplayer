// Small pure formatting helpers (unit-tested).

/// 0 -> "0:00", 65 -> "1:05", 3723 -> "1:02:03"
String formatDuration(Duration d) {
  if (d.isNegative) d = Duration.zero;
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '${int.parse(m)}:$s';
}

/// "Sleep: 15:00" style countdown label for the sleep timer (unit-tested).
/// 15 min -> "Sleep: 15:00", 59 s -> "Sleep: 00:59".
String formatSleepLabel(Duration remaining) {
  if (remaining.isNegative) remaining = Duration.zero;
  final total = remaining.inSeconds;
  final minutes = (total ~/ 60).toString().padLeft(2, '0');
  final seconds = (total % 60).toString().padLeft(2, '0');
  return 'Sleep: $minutes:$seconds';
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
