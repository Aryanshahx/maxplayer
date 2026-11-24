import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maxplayer/theme.dart';
import 'package:maxplayer/widgets/gesture_illustrations.dart';

double contrast(Color a, Color b) {
  final x = a.computeLuminance(), y = b.computeLuminance();
  return ((x > y ? x : y) + .05) / ((x < y ? x : y) + .05);
}

void main() {
  for (final brightness in Brightness.values) {
    test('gesture ink and badges contrast in $brightness', () {
      for (final accent in [
        Colors.white,
        Colors.black,
        Colors.red,
        Colors.blue,
        Colors.amber,
      ]) {
        final p = GestureDiagramPalette.fromTheme(
          buildAppTheme(accent: accent, brightness: brightness),
        );
        for (final bg in [p.screenStart, p.screenEnd]) {
          expect(contrast(p.muted, bg), greaterThanOrEqualTo(4.5));
          expect(contrast(p.accent, bg), greaterThanOrEqualTo(4.5));
        }
        expect(contrast(p.onAccent, p.accent), greaterThanOrEqualTo(4.5));
      }
    });
    testWidgets(
      'all gesture illustrations render in $brightness without errors',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(brightness: brightness),
            home: Scaffold(
              body: ListView(
                children: [
                  for (final kind in GestureKind.values)
                    GestureIllustration(kind: kind, height: 58),
                ],
              ),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'theme change repaints the same gesture even with identical global accent',
    (tester) async {
      const key = ValueKey('diagram');
      Future<CustomPainter> show(Brightness brightness) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(brightness: brightness),
            home: const Scaffold(
              body: GestureIllustration(key: key, kind: GestureKind.swipeSeek),
            ),
          ),
        );
        await tester.pumpAndSettle();
        return tester
            .widget<CustomPaint>(
              find.descendant(
                of: find.byKey(key),
                matching: find.byType(CustomPaint),
              ),
            )
            .painter!;
      }

      final dark = await show(Brightness.dark),
          light = await show(Brightness.light);
      expect(light.shouldRepaint(dark), isTrue);
    },
  );
}
