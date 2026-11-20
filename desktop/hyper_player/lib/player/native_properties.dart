import 'package:media_kit/media_kit.dart';

/// media_kit 1.2.6's public NativePlayer.setProperty does not check libmpv's
/// return code. Readback is required before reporting a property as accepted.
bool propertyMatches(String key, String requested, String actual) {
  if (key == 'vf') {
    if (requested.isEmpty) return actual.isEmpty || actual == '[]';
    if (requested.contains('unsharp')) return actual.contains('unsharp');
    return actual == requested;
  }
  final target = double.tryParse(requested);
  final value = double.tryParse(actual);
  if (target != null && value != null) return (target - value).abs() < .05;
  if (requested == 'no') return ['no', 'false', '0'].contains(actual);
  if (requested == 'yes') return ['yes', 'true', '1'].contains(actual);
  return requested == actual;
}

Future<void> setCheckedProperty(
    NativePlayer player, String key, String value) async {
  await player.setProperty(key, value);
  final actual = await player.getProperty(key);
  if (!propertyMatches(key, value, actual)) {
    throw StateError('Native property did not retain requested value: $key');
  }
}
