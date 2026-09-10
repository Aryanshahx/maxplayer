// Pure list helpers (unit-tested).

/// Appends items from [batch] not already present (by [keyOf]),
/// preserving order. Guards against duplicate MediaStore pages when
/// overlapping page fetches race.
List<T> appendUnique<T>(List<T> existing, List<T> batch, Object Function(T e) keyOf) {
  final seen = existing.map(keyOf).toSet();
  final out = [...existing];
  for (final e in batch) {
    if (seen.add(keyOf(e))) out.add(e);
  }
  return out;
}
