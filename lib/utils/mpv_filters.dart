// Pure builders for MPV filter strings (unit-tested). The player feeds
// these into `setProperty('af'|'vf', ...)` on the MPV platform channel.

/// 5-band graphic equalizer, gains in dB (-12..12). Empty = no filtering.
String buildEqualizerFilter(List<double> gainsDb) {
  const freqs = [60, 230, 910, 3600, 14000];
  if (gainsDb.length != freqs.length) {
    throw ArgumentError('expected ${freqs.length} band gains');
  }
  final parts = <String>[];
  for (var i = 0; i < freqs.length; i++) {
    final g = gainsDb[i];
    if (g.abs() < 0.05) continue;
    parts.add(
        'equalizer=f=${freqs[i]}:t=h:w=2.0:g=${g.toStringAsFixed(1)}');
  }
  if (parts.isEmpty) return '';
  return 'lavfi=[${parts.join(',')}]';
}

/// Named presets (gains in dB for the 5 bands above).
const equalizerPresets = <String, List<double>>{
  'Flat': [0, 0, 0, 0, 0],
  'Bass+': [7, 5, 0, 0, -1],
  'Vocal': [-3, -1, 4, 6, 2],
  'Full': [5, 0, -1, 3, 5],
};

/// Equalizer-only chain. Dialogue Boost intentionally remains a Track Sheet feature.
String combineAudioFilters(List<double> gainsDb, {bool dialogueBoost = false}) {
  final chains = <String>[];
  if (dialogueBoost) {
    chains.add(
      'equalizer=f=1200:t=q:w=1.2:g=2.5,equalizer=f=3200:t=q:w=1.2:g=4.0',
    );
  }
  final eq = buildEqualizerFilter(gainsDb);
  if (eq.isNotEmpty) {
    chains.add(eq.substring(7, eq.length - 1));
  }
  if (chains.isEmpty) return '';
  return 'lavfi=[${chains.join(',')}]';
}


/// "Enhance video" — GPU sharpen + slight contrast/saturation push.
/// Returns the video-filter chain; the param equalizer (contrast/gamma/
/// saturation) is applied by the player via MPV properties.
String buildEnhanceFilter() => 'unsharp=5:5:0.55:5:5:0.0';
