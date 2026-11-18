import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_player/screens/media_info_sheet.dart';

void main() {
  test('Info clock clamps negative remaining time', () {
    expect(mediaClock(const Duration(seconds: -5)), '0:00:00');
    expect(mediaClock(const Duration(seconds: 3661)), '1:01:01');
  });
  testWidgets('Info uses draggable selectable metadata and track sections',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: MediaInfoSheet(title: 'Example', rows: [
      MapEntry('Resolution', '1920 × 1080')
    ], tracks: {
      'Audio tracks': ['English • AAC']
    }))));
    expect(find.byType(DraggableScrollableSheet), findsOneWidget);
    expect(find.widgetWithText(SelectableText, '1920 × 1080'), findsOneWidget);
    expect(find.text('Audio tracks'), findsOneWidget);
    expect(find.text('English • AAC'), findsOneWidget);
  });
  testWidgets('Repeat controls show current points and preserve actions',
      (tester) async {
    String? action;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: RepeatControlSheet(
                a: const Duration(seconds: 5),
                b: const Duration(seconds: 15),
                onAction: (v) => action = v))));
    expect(find.text('Loop 0:00:05 – 0:00:15'), findsOneWidget);
    await tester.tap(find.text('Set B at current position'));
    expect(action, 'b');
    await tester.tap(find.text('Disable repeat'));
    expect(action, 'off');
  });
  testWidgets('Unset loop explains first step', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: RepeatControlSheet(onAction: (_) {}))));
    expect(
        find.text('Off · Set A to mark the start of a loop.'), findsOneWidget);
  });
}
