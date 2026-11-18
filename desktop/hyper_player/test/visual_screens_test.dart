import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hyper_player/desktop_store.dart';
import 'package:hyper_player/screens/collection_screens.dart';
import 'package:hyper_player/screens/stream_screen.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('History uses a full screen and Android empty state',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: SourceCollectionScreen(title: 'History', sources: [])));
    expect(find.byType(Scaffold), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(
        find.text('Nothing watched yet.\nVideos you open will show up here.'),
        findsOneWidget);
  });
  testWidgets('History removal updates stored list', (tester) async {
    final store = DesktopStore();
    store.history.add('movie.mp4');
    await tester.pumpWidget(MaterialApp(
        home: SourceCollectionScreen(
            title: 'History', sources: store.history, onSave: store.save)));
    await tester.tap(find.byTooltip('Remove from list'));
    await tester.pumpAndSettle();
    expect(store.history, isEmpty);
    final restored = DesktopStore();
    await restored.load();
    expect(restored.history, isEmpty);
  });
  testWidgets('New playlist screen creates named persistent queue',
      (tester) async {
    final store = DesktopStore();
    await tester.pumpWidget(MaterialApp(
        home: DesktopPlaylistsScreen(
            store: store, currentQueue: const ['movie.mp4'])));
    await tester.tap(find.text('New'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Evening');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(store.playlists['Evening'], ['movie.mp4']);
    expect(find.text('Evening'), findsOneWidget);
  });
  testWidgets('Stream screen rejects unsupported protocols', (tester) async {
    await tester
        .pumpWidget(const MaterialApp(home: DesktopStreamScreen(recent: [])));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'javascript:alert(1)');
    await tester.pump();
    await tester.tap(find.text('Play Stream'));
    await tester.pumpAndSettle();
    expect(
        find.text('Enter a direct HTTP or HTTPS media URL.'), findsOneWidget);
    expect(find.byType(Scaffold), findsOneWidget);
  });
}
