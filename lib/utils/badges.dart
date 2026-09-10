/// Pure quality-badge mapping (unit-tested): from video dimensions to a
/// short label shown on cards. Uses the LONG side so BOTH a landscape
/// 3840x2160 and a portrait 2160x3840 read "4K" — matching how YouTube/
/// MX label them. (v0.8 fix: some devices reported rotated dimensions.)
String qualityBadge(int width, int height) {
  final s = width > height ? width : height;
  if (s >= 3400) return '4K';
  if (s >= 2560) return '2K';
  if (s >= 1920) return '1080p';
  if (s >= 1280) return '720p';
  if (s >= 854) return '480p';
  return 'SD';
}

/// "1920×1080 · 1080p" — the display line used in rows/properties.
String resolutionLabel(int width, int height) =>
    '$width×$height · ${qualityBadge(width, height)}';
