import 'package:flutter_test/flutter_test.dart';

import 'package:maxplayer/utils/quick_tiles.dart';

void main() {
  test('v1.0.20 Audio takes the Cloud Storage slot on page 1', () {
    expect(kQuickTilesPage1.map((t) => t.id).toList(), [
      'privateSpace',
      'playlists',
      'folders',
      'audio',
    ]);
  });

  test('v1.0.20 Cloud Storage moves to the old File Manager slot', () {
    expect(kQuickTilesPage2.map((t) => t.id).toList(), [
      'networkStorage',
      'cloudStorage',
      'openStream',
      'quickShare',
    ]);
  });

  test('File Manager is gone from both pages', () {
    final ids = [
      ...kQuickTilesPage1.map((t) => t.id),
      ...kQuickTilesPage2.map((t) => t.id),
    ];
    expect(ids, isNot(contains('fileManager')));
    expect(ids, isNot(contains('file_manager')));
  });
}
