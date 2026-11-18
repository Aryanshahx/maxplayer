import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_player/screens/playback_sheets.dart';

Widget host(Widget child) =>
    MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));
void main() {
  testWidgets('Speed presets apply rate and update large readout',
      (tester) async {
    double? rate;
    await tester.pumpWidget(host(PlaybackSpeedSheet(
        rate: 1,
        onRate: (value) async {
          rate = value;
        })));
    await tester.tap(find.widgetWithText(ChoiceChip, '1.5×'));
    await tester.pumpAndSettle();
    expect(rate, 1.5);
    expect(find.text('1.5x'), findsOneWidget);
    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.divisions, 14);
    expect(slider.min, .5);
    expect(slider.max, 4);
  });
  testWidgets('Speed failure restores applied value', (tester) async {
    await tester.pumpWidget(host(PlaybackSpeedSheet(
        rate: 1, onRate: (_) async => throw StateError('failed'))));
    await tester.tap(find.widgetWithText(ChoiceChip, '2.0×'));
    await tester.pumpAndSettle();
    expect(find.text('1.0x'), findsOneWidget);
    expect(
        find.textContaining('Could not change playback speed'), findsOneWidget);
  });
  testWidgets('Timer preserves long presets and adds Android 10 minute option',
      (tester) async {
    int? picked;
    await tester
        .pumpWidget(host(SleepTimerSheet(onMinutes: (v) => picked = v)));
    expect(find.text('120 minutes'), findsOneWidget);
    expect(find.text('Turn off timer'), findsNothing);
    await tester.tap(find.text('10 minutes'));
    expect(picked, 10);
    expect(
        tester
            .widget<ListTile>(find.widgetWithText(ListTile, 'Until end'))
            .enabled,
        isFalse);
  });
  testWidgets('Active timer can be cancelled', (tester) async {
    int? picked;
    await tester.pumpWidget(host(SleepTimerSheet(
        deadline: DateTime(2026, 9, 5, 12, 30), onMinutes: (v) => picked = v)));
    await tester.tap(find.text('Turn off timer'));
    expect(picked, 0);
    expect(find.textContaining('Pauses at'), findsOneWidget);
  });
  testWidgets('Sheet returns selected timer and has rounded modal',
      (tester) async {
    int? picked;
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () async {
                      picked = await showPlaybackSheet<int>(
                          context,
                          Builder(
                              builder: (sheetContext) => SleepTimerSheet(
                                  onMinutes: (v) =>
                                      Navigator.pop(sheetContext, v))));
                    },
                    child: const Text('Open'))))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    await tester.tap(find.text('30 minutes'));
    await tester.pumpAndSettle();
    expect(picked, 30);
  });
}
