/// Pure quality-badge mapping (unit-tested): from video dimensions to a
/// short label shown on cards. Uses the SHORT side so portrait 1080x1920
/// and landscape 1920x1080 both read "1080p".
String qualityBadge(int width, int height) {
  final s = width < height ? width : height;
  if (s >= 2160) return '4K';
  if (s >= 1440) return '2K';
  if (s >= 1080) return '1080p';
  if (s >= 720) return '720p';
  if (s >= 480) return '480p';
  return 'SD';
}
