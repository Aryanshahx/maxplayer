/// Visible library positions retain their original queue indices. Filtering must
/// never cause a card to start another file or remove hidden queue entries.
List<int> visibleLibraryIndices(List<String> queue,
    {required bool onlyFavourites,
    required Iterable<String> favourites,
    String sort = 'queue',
    String Function(String)? labelOf}) {
  final allowed = onlyFavourites ? favourites.toSet() : null;
  final indices = <int>[
    for (var i = 0; i < queue.length; i++)
      if (allowed == null || allowed.contains(queue[i])) i
  ];
  if (sort == 'nameAsc' || sort == 'nameDesc') {
    indices.sort((a, b) {
      final left = (labelOf?.call(queue[a]) ?? queue[a]).toLowerCase();
      final right = (labelOf?.call(queue[b]) ?? queue[b]).toLowerCase();
      final result =
          sort == 'nameDesc' ? right.compareTo(left) : left.compareTo(right);
      return result == 0 ? a.compareTo(b) : result;
    });
  }
  return indices;
}

class LibraryGroup {
  final String label;
  final List<int> indices;
  const LibraryGroup(this.label, this.indices);
}

/// Groups visible entries without inspecting files or changing playback order.
/// Both Windows and POSIX separators are accepted, independent of test host.
List<LibraryGroup> groupLibraryIndices(List<String> queue, List<int> indices,
    {required bool byFolder}) {
  if (!byFolder) return [LibraryGroup('', indices)];
  final buckets = <String, List<int>>{};
  for (final index in indices) {
    final source = queue[index];
    String folder;
    if (RegExp(r'^https?://', caseSensitive: false).hasMatch(source)) {
      folder = 'Network streams';
    } else {
      final path = source.replaceAll('\\', '/');
      final last = path.lastIndexOf('/');
      folder = last < 0
          ? 'Other local media'
          : last == 0
              ? '/'
              : path.substring(0, last);
    }
    buckets.putIfAbsent(folder, () => []).add(index);
  }
  final labels = buckets.keys.toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return [for (final label in labels) LibraryGroup(label, buckets[label]!)];
}
