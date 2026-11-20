import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hyper_player/cloud_import.dart';
import 'package:hyper_player/screens/cloud_storage_screen.dart';
import 'package:hyper_player/screens/user_manual_android.dart';

void main() {
  test(
      'Import copies exact bytes, uses distinct paths and removes partial suffix',
      () async {
    final root = await Directory.systemTemp.createTemp('hyper-import-');
    addTearDown(() => root.delete(recursive: true));
    final source = File('${root.path}/Sample video.mp4');
    final bytes = List.generate(200000, (i) => i % 256);
    await source.writeAsBytes(bytes);
    final progress = <int>[];
    final output = await importVideoFile(
        source, Directory('${root.path}/library'),
        cancellation: ImportCancellation(), onProgress: (done, total) {
      progress.add(done);
      expect(total, bytes.length);
    });
    expect(await output.readAsBytes(), bytes);
    expect(progress.first, 0);
    expect(progress.last, bytes.length);
    expect(source.existsSync(), isTrue);
    expect(output.path.endsWith('.mp4'), isTrue);
    expect(
        (await output.parent.list().toList())
            .whereType<File>()
            .any((f) => f.path.endsWith('.part')),
        isFalse);
  });
  test('Cancel during copy removes partial but never touches source', () async {
    final root = await Directory.systemTemp.createTemp('hyper-import-cancel-');
    addTearDown(() => root.delete(recursive: true));
    final source = File('${root.path}/movie.mp4');
    await source.writeAsBytes(List.filled(500000, 8));
    final token = ImportCancellation();
    final library = Directory('${root.path}/library');
    await expectLater(
        importVideoFile(source, library, cancellation: token,
            onProgress: (done, total) {
          if (done > 0) token.cancel();
        }),
        throwsA(isA<ImportCancelled>()));
    expect(await library.list().toList(), isEmpty);
    expect(await source.length(), 500000);
  });
  test('Pre-cancelled import does not create destination or overwrite files',
      () async {
    final root =
        await Directory.systemTemp.createTemp('hyper-import-pre-cancel-');
    addTearDown(() => root.delete(recursive: true));
    final source = File('${root.path}/movie.mp4');
    await source.writeAsString('source');
    final token = ImportCancellation()..cancel();
    final library = Directory('${root.path}/library');
    await expectLater(
        importVideoFile(source, library,
            cancellation: token, onProgress: (_, total) {}),
        throwsA(isA<ImportCancelled>()));
    expect(library.existsSync(), isFalse);
  });
  test('Repeated imports never overwrite prior imported copies', () async {
    final root = await Directory.systemTemp.createTemp('hyper-import-repeat-');
    addTearDown(() => root.delete(recursive: true));
    final source = File('${root.path}/movie.mp4');
    await source.writeAsString('first');
    final library = Directory('${root.path}/library');
    final first = await importVideoFile(source, library,
        cancellation: ImportCancellation(), onProgress: (_, total) {});
    await source.writeAsString('second');
    final second = await importVideoFile(source, library,
        cancellation: ImportCancellation(), onProgress: (_, total) {});
    expect(first.path, isNot(second.path));
    expect(await first.readAsString(), 'first');
    expect(await second.readAsString(), 'second');
  });
  test('Missing provider source fails without creating completed import',
      () async {
    final root = await Directory.systemTemp.createTemp('hyper-import-missing-');
    addTearDown(() => root.delete(recursive: true));
    final library = Directory('${root.path}/library');
    await expectLater(
        importVideoFile(File('${root.path}/missing.mp4'), library,
            cancellation: ImportCancellation(), onProgress: (_, total) {}),
        throwsA(isA<FileSystemException>()));
    expect(library.existsSync(), isFalse);
  });
  testWidgets(
      'Cloud screen uses Android import composition with truthful PC text',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester
        .pumpWidget(const MaterialApp(home: DesktopCloudStorageScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Import a video'), findsOneWidget);
    expect(find.text('Choose a video to import'), findsOneWidget);
    expect(find.textContaining('Hyper Player does not request cloud passwords'),
        findsOneWidget);
    expect(find.text('No videos imported yet.'), findsOneWidget);
  });
  testWidgets('Manual uses actual Android sections with PC guidance',
      (tester) async {
    await tester
        .pumpWidget(const MaterialApp(home: Scaffold(body: UserManualSheet())));
    expect(find.text('HOME SCREEN'), findsOneWidget);
    expect(find.text('Quick tiles under Discover'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('KEYBOARD & MOUSE'), 350);
    expect(find.text('KEYBOARD & MOUSE'), findsOneWidget);
    expect(find.textContaining('Android-only touch gestures are not presented'),
        findsOneWidget);
  });
}
