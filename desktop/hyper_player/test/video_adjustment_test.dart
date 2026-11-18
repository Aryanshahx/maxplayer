import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_player/screens/video_adjustment_sheets.dart';

Widget host(Widget child) =>
    MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));
void main() {
  testWidgets('Fit options retain working selection and callbacks',
      (tester) async {
    BoxFit? chosen;
    await tester.pumpWidget(host(
        VideoFitSheet(selected: BoxFit.cover, onSelect: (v) => chosen = v)));
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    await tester.tap(find.text('Stretch'));
    expect(chosen, BoxFit.fill);
    expect(find.textContaining('not implemented'), findsOneWidget);
  });
  testWidgets('Delay validates range without applying invalid input',
      (tester) async {
    int? applied;
    await tester.pumpWidget(host(SubtitleDelaySheet(onApply: (v) async {
      applied = v;
    })));
    await tester.enterText(find.byType(TextField), '60001');
    await tester.tap(find.text('Apply'));
    await tester.pump();
    expect(applied, isNull);
    expect(find.textContaining('Enter a whole number'), findsOneWidget);
  });
  testWidgets('Delay step and reset controls work', (tester) async {
    await tester.pumpWidget(host(SubtitleDelaySheet(onApply: (_) async {})));
    await tester.tap(find.text('−100 ms'));
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '-100');
    await tester.tap(find.text('Reset'));
    await tester.pump();
    expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text, '0');
  });
  testWidgets('Backend failure leaves delay sheet retryable', (tester) async {
    await tester.pumpWidget(host(SubtitleDelaySheet(
        onApply: (_) async => throw StateError('unavailable'))));
    await tester.enterText(find.byType(TextField), '-500');
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(find.text('Subtitle delay unavailable. Please try again.'),
        findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull);
  });
}
