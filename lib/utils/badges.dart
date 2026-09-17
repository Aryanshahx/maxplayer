import 'package:photo_manager/photo_manager.dart';

import '../services/native_bridge.dart';

/// Pure quality-badge mapping (unit-tested): from video dimensions to a
/// short label shown on cards. Uses the LONG side so BOTH a landscape
/// 3840x2160 and a portrait 2160x3840 read "4K" — matching how YouTube/
/// MX label them (v0.8: some devices reported rotated dimensions).
///
/// v1.0.14: thresholds sit a hair UNDER the nominal sizes because real
/// encodes are cropped — a Blu-ray 1080p title is routinely 1916x1080
/// (or 1920x804 ultrawide), a 720p one 1274/1264 wide, 480p is 848x480.
/// With hard 1920/1280/854 gates those all fell one bucket and a 1080p
/// file showed "720p". The gaps between standards (1900 vs 720p max
/// ~1300; 1260 vs 480p max ~850) are wide, so this can't mislabel.
String qualityBadge(int width, int height) {
  final s = width > height ? width : height;
  if (s >= 3400) return '4K';
  if (s >= 2500) return '2K';
  if (s >= 1900) return '1080p';
  if (s >= 1260) return '720p';
  if (s >= 840) return '480p';
  return 'SD';
}

/// "1920×1080 · 1080p" — the display line used in rows/properties.
String resolutionLabel(int width, int height) =>
    '$width×$height · ${qualityBadge(width, height)}';

// ---------------------------------------------------------------------------
// Async best-known resolution (v29): MediaStore's WIDTH/HEIGHT columns are
// 0 (or stale) for many MKV / WebM / AVI files, so a real 1080p / 4K video
// could show as "SD". When the MediaStore size is unusable the actual codec
// dimensions are probed once through the native MediaMetadataRetriever
// (cached natively) and the badge is derived from those.
// ---------------------------------------------------------------------------

/// Real dimensions + quality badge for a library asset.
Future<({int w, int h, String badge})> resolvedVideoInfo(
    AssetEntity asset) async {
  var w = asset.width;
  var h = asset.height;
  if (w <= 0 || h <= 0) {
    try {
      final file = await asset.file;
      if (file != null) {
        final dims = await NativeBridge.videoDimensions(file.path);
        if (dims != null) {
          w = dims.$1;
          h = dims.$2;
        }
      }
    } catch (_) {
      // Never fail a whole tile over a probe error — keep the MediaStore
      // value (which may still be 0 -> "SD").
    }
  }
  return (w: w, h: h, badge: qualityBadge(w, h));
}

/// Just the badge string for a library asset (probes natively when the
/// MediaStore dimensions are unusable).
Future<String> resolvedQualityBadge(AssetEntity asset) async =>
    (await resolvedVideoInfo(asset)).badge;
