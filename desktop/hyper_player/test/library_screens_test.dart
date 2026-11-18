import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hyper_player/local_media_index.dart';
import 'package:hyper_player/screens/library_screens.dart';
import 'package:hyper_player/screens/desktop_display_screen.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('Local scan is nonrecursive and ignores nonmedia', () async {
    final dir = await Directory.systemTemp.createTemp('hyper-scan-');
    try {
      await File('${dir.path}/song.MP3').writeAsBytes([1, 2]);
      await File('${dir.path}/movie.mp4').writeAsBytes([1]);
      await File('${dir.path}/notes.txt').writeAsString('test');
      final child = await Directory('${dir.path}/child').create();
      await File('${child.path}/hidden.mp3').writeAsBytes([1]);
      final result = await scanLocalMedia([dir.path, dir.path]);
      expect(result.folders.length, 1);
      expect(result.folders[dir.path]!.length, 2);
      expect(result.folders[dir.path]!.where((e) => isAudioPath(e.path)).length,
          1);
      expect(result.unavailable, isEmpty);
    } finally {
      await dir.delete(recursive: true);
    }
  });
  test('Scan reports missing directories without throwing', () async {
    final root = await Directory.systemTemp.createTemp('hyper-missing-');
    try {
      final result = await scanLocalMedia(['${root.path}/missing']);
      expect(result.unavailable.length, 1);
    } finally {
      await root.delete(recursive: true);
    }
  });
  test('Scan limit is reported explicitly', () async {
    final dir = await Directory.systemTemp.createTemp('hyper-limit-');
    try {
      await File('${dir.path}/a.mp3').writeAsBytes([1]);
      await File('${dir.path}/b.mp3').writeAsBytes([1]);
      final result = await scanLocalMedia([dir.path], limit: 1);
      expect(result.folders[dir.path]!.length, 1);
      expect(result.truncated, isTrue);
    } finally {
      await dir.delete(recursive: true);
    }
  });
  testWidgets('Folders displays Android style empty state and add control',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: DesktopFoldersScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Folders'), findsOneWidget);
    expect(find.text('Add folder'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
  });
  testWidgets('Audio is a real browsing page with search and rescan',
      (tester) async {
    await tester.pumpWidget(
        const MaterialApp(home: DesktopAudioScreen(knownSources: [])));
    await tester.pumpAndSettle();
    expect(find.text('Audio (0)'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byTooltip('Rescan'), findsOneWidget);
    expect(find.byTooltip('Open audio files'), findsOneWidget);
  });
  testWidgets('Display mode cards invoke the layout callback', (tester) async {
    bool? list;
    await tester.pumpWidget(MaterialApp(
        home: DesktopDisplayScreen(
            listMode: false,
            onChange: (value, sort) async {
              list = value;
            })));
    await tester.tap(find.text('List View'));
    await tester.pumpAndSettle();
    expect(list, isTrue);
    expect(find.text('LAYOUT & VIEW MODE'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
  });
}
