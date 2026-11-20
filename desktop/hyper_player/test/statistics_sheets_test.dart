import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hyper_player/watch_days.dart';
import 'package:hyper_player/screens/statistics_screen.dart';
import 'package:hyper_player/screens/info_sheets.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('Daily totals persist without backfilling lifetime counters', () async {
    SharedPreferences.setMockInitialValues({'hyper.watch.seconds.v1': 9999});
    final stats = WatchDays();
    await stats.load();
    final now = DateTime(2026, 9, 5, 12);
    expect(stats.total(now, 7), 0);
    stats.record(now, 'movie.mp4');
    stats.record(now, 'movie.mp4');
    await stats.save();
    final restored = WatchDays();
    await restored.load();
    expect(restored.total(now, 7), 2);
    expect(restored.titles['movie.mp4'], 2);
  });
  test('Consecutive local calendar dates give accurate streak', () {
    final stats = WatchDays();
    final today = DateTime(2026, 9, 5);
    stats.record(DateTime(2026, 9, 3), 'a');
    stats.record(DateTime(2026, 9, 4), 'a');
    expect(stats.streak(today), 2);
    stats.record(today, 'a');
    expect(stats.streak(today), 3);
    expect(stats.total(today, 2), 2);
  });
  test('Invalid saved statistics are tolerated', () async {
    SharedPreferences.setMockInitialValues({'hyper.watch.days.v1': 'broken'});
    final stats = WatchDays();
    await stats.load();
    expect(stats.days, isEmpty);
  });
  test('Counters remain bounded', () {
    final stats = WatchDays();
    for (var i = 0; i < 400; i++) {
      stats.record(DateTime(2025, 1, 1 + i), 'title$i');
    }
    expect(stats.days.length, 366);
    expect(stats.titles.length, 100);
  });
  testWidgets('Statistics renders Android style cards and zero baseline',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: DesktopStatisticsScreen(
            stats: WatchDays(), lifetimeSeconds: 500, starts: 4)));
    expect(find.text('Statistics'), findsOneWidget);
    expect(find.text('watched this week'), findsOneWidget);
    expect(find.text('Daily average'), findsOneWidget);
    expect(find.text('Last 30 days'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
  });
  testWidgets('Manual opens as draggable Android style sheet', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () =>
                        showAndroidInfoSheet(context, 'User manual', ''),
                    child: const Text('Open'))))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byType(DraggableScrollableSheet), findsOneWidget);
    expect(find.text('User manual'), findsOneWidget);
    expect(find.text('HOME SCREEN'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
  });
}
