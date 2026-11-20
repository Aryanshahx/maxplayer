import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_player/local_media_index.dart';

void main() {
  test(
      'Recursive scan includes nested media and keeps inaccessible sibling errors',
      () async {
    final root = await Directory.systemTemp.createTemp('hyper-recursive-');
    addTearDown(() => root.delete(recursive: true));
    final child =
        await Directory('${root.path}/one/two').create(recursive: true);
    await File('${root.path}/top.mp4').writeAsString('fixture');
    await File('${child.path}/deep.mkv').writeAsString('fixture');
    await File('${child.path}/ignore.txt').writeAsString('fixture');
    if (!Platform.isWindows) await Link('${child.path}/loop').create(root.path);
    final scan = await scanLocalMedia([root.path, '${root.path}/missing'],
        recursive: true);
    final media = scan.folders.values.expand((rows) => rows).toList();
    expect(media.length, 2);
    expect(media.map((e) => e.path.split(Platform.pathSeparator).last),
        containsAll(['top.mp4', 'deep.mkv']));
    expect(scan.unavailable, contains('${root.path}/missing'));
    expect(scan.truncated, isFalse);
  });
  test('Recursive directory limit and cancellation are explicit', () async {
    final root = await Directory.systemTemp.createTemp('hyper-scan-bounds-');
    addTearDown(() => root.delete(recursive: true));
    await Directory('${root.path}/child').create();
    final limited =
        await scanLocalMedia([root.path], recursive: true, directoryLimit: 1);
    expect(limited.truncated, isTrue);
    final cancelled = await scanLocalMedia([root.path],
        recursive: true, cancelled: () => true);
    expect(cancelled.truncated, isTrue);
    expect(cancelled.folders, isEmpty);
  });
}
