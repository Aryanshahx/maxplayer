import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_player/library_projection.dart';

void main() {
  test('Folder groups preserve view order and separate network entries', () {
    final queue = [
      r'C:\Videos\B.mp4',
      '/media/A.mp4',
      'https://host/private?token=hidden',
      r'C:\Videos\A.mp4'
    ];
    final groups = groupLibraryIndices(queue, [3, 1, 0, 2], byFolder: true);
    expect(
        groups.map((g) => g.label), ['/media', 'C:/Videos', 'Network streams']);
    expect(groups[1].indices, [3, 0]);
    expect(groups.last.label.contains('token'), isFalse);
    expect(queue.length, 4);
  });
  test('Grouping supports root and relative files and empty views', () {
    expect(groupLibraryIndices([], [], byFolder: true), isEmpty);
    final groups =
        groupLibraryIndices(['/a.mp4', 'local.mp4'], [0, 1], byFolder: true);
    expect(groups.map((g) => g.label), ['/', 'Other local media']);
    expect(
        groupLibraryIndices(['z', 'a'], [1, 0], byFolder: false).single.indices,
        [1, 0]);
  });
  test(
      'View sorting never mutates playback queue and uses stable equal-name order',
      () {
    final queue = ['Zulu', 'alpha', 'ALPHA', 'Beta'];
    expect(
        visibleLibraryIndices(queue,
            onlyFavourites: false, favourites: [], sort: 'nameAsc'),
        [1, 2, 3, 0]);
    expect(
        visibleLibraryIndices(queue,
            onlyFavourites: false, favourites: [], sort: 'nameDesc'),
        [0, 3, 1, 2]);
    expect(queue, ['Zulu', 'alpha', 'ALPHA', 'Beta']);
  });
  test('Sort uses display labels and composes with favourites filtering', () {
    final queue = ['/z/Alpha.mp4', '/a/Zulu.mp4', '/b/Beta.mp4'];
    expect(
        visibleLibraryIndices(queue,
            onlyFavourites: true,
            favourites: queue.take(2),
            sort: 'nameAsc',
            labelOf: (path) => path.split('/').last),
        [0, 1]);
    expect(
        visibleLibraryIndices(queue,
            onlyFavourites: false, favourites: [], sort: 'invalid'),
        [0, 1, 2]);
  });
  test('Unfiltered library keeps every queue index including duplicate sources',
      () {
    expect(
        visibleLibraryIndices(['a', 'b', 'a'],
            onlyFavourites: false, favourites: []),
        [0, 1, 2]);
  });
  test('Favourite filtering preserves original playback indices and queue', () {
    final queue = ['first', 'fav', 'third', 'fav'];
    final visible = visibleLibraryIndices(queue,
        onlyFavourites: true, favourites: ['fav', 'absent']);
    expect(visible, [1, 3]);
    expect(queue[visible.first], 'fav');
    expect(queue.length, 4);
  });
  test('Empty favourites gives an empty projection without losing queued media',
      () {
    expect(visibleLibraryIndices(['a'], onlyFavourites: true, favourites: []),
        isEmpty);
  });
}
