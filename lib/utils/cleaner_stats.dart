// v31 Cleaner: pure data + graph math for the cleaner sheet. The painters
// only draw what these functions return, so every byte that ends up in the
// graphs is unit-tested.

/// One coloured slice of the cleaner donut graph.
class CleanerSegment {
  final String label;
  final int bytes;

  /// ARGB colour value (wrapped in Color by the UI - keeps this util pure).
  final int colorValue;

  const CleanerSegment(this.label, this.bytes, this.colorValue);

  /// Share of the whole graph, 0..1 (0 when the graph is empty).
  double fractionOf(int total) => total <= 0 ? 0 : bytes / total;
}

/// Stable palette per cache kind - legend and graph always agree.
const Map<String, int> cleanerKindColors = {
  'thumbs': 0xFF7C4DFF, // deep purple
  'strips': 0xFF40C4FF, // light blue
  'temp': 0xFFFFAB40, // orange
  'models': 0xFF69F0AE, // green
  'device': 0xFFFF5252, // red
};

/// Builds the donut segments for the five reclaimable kinds, in a stable
/// order. Empty kinds are dropped so the graph never draws 0-width slices.
List<CleanerSegment> cleanerSegments({
  required int thumbs,
  required int strips,
  required int temp,
  required int models,
  required int deviceCache,
}) {
  final raw = <(String, String, int)>[
    ('thumbs', 'App thumbnails', thumbs),
    ('strips', 'Preview strips', strips),
    ('temp', 'Temporary AI files', temp),
    ('models', 'AI models', models),
    ('device', 'Gallery cache', deviceCache),
  ];
  return [
    for (final (kind, label, bytes) in raw)
      if (bytes > 0)
        CleanerSegment(label, bytes, cleanerKindColors[kind] ?? 0xFF9E9E9E),
  ];
}

/// What the big "Clean cache" button frees: every cache kind EXCEPT the AI
/// models (those are downloads - cleared from their own row with a warning
/// because they need mobile data to come back).
int cleanerCacheTotal({
  required int thumbs,
  required int strips,
  required int temp,
  required int deviceCache,
}) =>
    thumbs + strips + temp + deviceCache;

/// Everything the cleaner can reclaim, caches + models combined (used for
/// the "X reclaimable" headline and as the donut's total).
int cleanerGrandTotal({
  required int thumbs,
  required int strips,
  required int temp,
  required int models,
  required int deviceCache,
}) =>
    cleanerCacheTotal(
      thumbs: thumbs,
      strips: strips,
      temp: temp,
      deviceCache: deviceCache,
    ) +
    models;
