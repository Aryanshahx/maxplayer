import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:maxplayer/theme.dart';
import 'package:maxplayer/utils/settings.dart';
import 'package:maxplayer/screens/display_settings_screen.dart';
import 'package:maxplayer/screens/onboarding_flow.dart';
import 'package:maxplayer/widgets/video_picker_sheet.dart';

double ratio(Color a, Color b) {
  final x = a.computeLuminance(), y = b.computeLuminance();
  return ((x > y ? x : y) + .05) / ((x < y ? x : y) + .05);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.instance.load();
  });
  tearDown(() {
    AppColors.brightness = Brightness.dark;
    AppColors.accent = Colors.white;
  });
  test('hex always has six digits, including leading zeros', () {
    expect(accentHex(const Color(0xFF00000A)), '#00000A');
    expect(accentHex(Colors.white), '#FFFFFF');
    expect(colourFromHue(120), isNot(colourFromHue(240)));
  });
  for (final brightness in Brightness.values) {
    testWidgets(
      'single slider and const-child preview rebuild live in $brightness',
      (tester) async {
        AppColors.brightness = brightness;
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(brightness: brightness),
            home: const DisplaySettingsScreen(),
          ),
        );
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('theme-colour-slider')),
          240,
        );
        expect(find.byType(Slider), findsOneWidget);
        for (final hue in [20.0, 120.0, 240.0]) {
          tester.widget<Slider>(find.byType(Slider)).onChanged!(hue);
          await tester.pumpAndSettle();
          final chosen = colourFromHue(hue);
          expect(
            tester
                .widget<SelectableText>(
                  find.byKey(const ValueKey('theme-colour-hex')),
                )
                .data,
            accentHex(chosen),
          );
          final swatch = tester.widget<Container>(
            find.byKey(const ValueKey('theme-colour-preview')),
          );
          expect((swatch.decoration as BoxDecoration).color, chosen);
          expect(
            tester.widget<Slider>(find.byType(Slider)).value,
            closeTo(HSVColor.fromColor(chosen).hue, .01),
          );
          expect(
            find.text(
              'Theme accent: ${accentHex(adaptiveAccent(chosen, brightness))}',
            ),
            findsOneWidget,
          );
        }
        final saved = AppSettings.instance.accentColor;
        await AppSettings.instance.load();
        expect(AppSettings.instance.accentColor, saved);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
    testWidgets(
      'welcome and all guide pages use readable text in $brightness',
      (tester) async {
        AppColors.brightness = brightness;
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(brightness: brightness),
            home: const OnboardingFlow(),
          ),
        );
        await tester.pumpAndSettle();
        for (var page = 0; page < 3; page++) {
          final label = [
            'Proudly Developed in India 🇮🇳',
            'How to use',
            'Video player',
          ][page];
          final text = tester.widget<Text>(find.text(label).last);
          expect(
            ratio(text.style!.color!, AppColors.background),
            greaterThanOrEqualTo(4.5),
          );
          expect(tester.takeException(), isNull);
          if (page < 2) {
            await tester.tap(find.text('Next'));
            await tester.pumpAndSettle();
          }
        }
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
    testWidgets('empty video picker text contrasts with sheet in $brightness', (
      tester,
    ) async {
      AppColors.brightness = brightness;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(brightness: brightness),
          home: Scaffold(
            backgroundColor: AppColors.surfaceAlt,
            body: const VideoPickerSheet(
              videos: [],
              title: 'Choose videos',
              actionLabel: 'Hide',
            ),
          ),
        ),
      );
      final text = tester.widget<Text>(
        find.text('No videos in the library yet - rescan first.'),
      );
      expect(
        ratio(text.style!.color!, AppColors.surfaceAlt),
        greaterThanOrEqualTo(4.5),
      );
      expect(tester.takeException(), isNull);
    });
  }
}
