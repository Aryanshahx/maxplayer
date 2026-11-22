import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:maxplayer/theme.dart';
import 'package:maxplayer/utils/settings.dart';
import 'package:maxplayer/utils/privacy_policy.dart';
import 'package:maxplayer/widgets/cine_ui.dart';
import 'package:maxplayer/screens/display_settings_screen.dart';

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
  test(
    'custom RGB persists exactly and preset removes custom selection',
    () async {
      final s = AppSettings.instance;
      await s.setCustomAccent(const Color(0xFF123456));
      await s.load();
      expect(s.accentColor.toARGB32(), 0xFF123456);
      s.setAccentIndex(2);
      await Future<void>.delayed(Duration.zero);
      await s.load();
      expect(s.customAccent, isNull);
      expect(s.accentColor, accentPalette[2]);
    },
  );
  test(
    'old preset installations and missing preferences load safely',
    () async {
      SharedPreferences.setMockInitialValues({'disp.accent': 9999});
      await AppSettings.instance.load();
      expect(AppSettings.instance.accentIndex, accentPalette.length - 1);
      expect(AppSettings.instance.customAccent, isNull);
    },
  );
  for (final brightness in Brightness.values) {
    test('arbitrary accent text and selected chip contrast in $brightness', () {
      for (final raw in [
        Colors.black,
        Colors.white,
        const Color(0xFF123456),
        Colors.yellow,
        Colors.red,
        Colors.grey,
      ]) {
        final theme = buildAppTheme(accent: raw, brightness: brightness);
        final chip = theme.chipTheme;
        final style = WidgetStateProperty.resolveAs<TextStyle?>(
          chip.labelStyle,
          {WidgetState.selected},
        )!;
        expect(
          ratio(style.color!, chip.selectedColor!),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          ratio(chip.checkmarkColor!, chip.selectedColor!),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          ratio(theme.colorScheme.primary, theme.colorScheme.surface),
          greaterThanOrEqualTo(4.5),
        );
      }
    });
    test('player chrome is translucent in $brightness and fades to clear', () {
      AppColors.brightness = brightness;
      expect(AppColors.playerChrome.a, lessThan(.65));
      expect(AppColors.playerChrome.a, greaterThan(0));
      final source = File(
        'lib/screens/player_screen_impl.dart',
      ).readAsStringSync();
      expect(
        'AppColors.playerChrome.withValues(alpha: 0)'.allMatches(source).length,
        2,
      );
    });
  }
  testWidgets('Discover boot retains neon gradient progress in either theme', (
    tester,
  ) async {
    for (final brightness in Brightness.values) {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(brightness: brightness),
          home: CineBoot(key: ValueKey(brightness), onFinished: () {}),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      final boxes = tester.widgetList<DecoratedBox>(
        find.descendant(
          of: find.byType(CineBoot),
          matching: find.byType(DecoratedBox),
        ),
      );
      expect(
        boxes.any(
          (b) =>
              b.decoration is BoxDecoration &&
              (b.decoration as BoxDecoration).gradient is LinearGradient &&
              ((b.decoration as BoxDecoration).gradient as LinearGradient)
                      .colors
                      .join() ==
                  [kCineCyan, kCinePurple, kCinePink].join(),
        ),
        isTrue,
      );
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });
  test('carousel art veils are absent in light mode and retained in dark', () {
    AppColors.brightness = Brightness.light;
    expect(cineVeil, Colors.transparent);
    AppColors.brightness = Brightness.dark;
    expect(cineVeil, kCineInk);
  });
  testWidgets('custom accent sliders remain usable on narrow screens', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(theme: buildAppTheme(), home: const DisplaySettingsScreen()),
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('accent-channel-0')),
      250,
    );
    expect(find.byType(Slider), findsNWidgets(3));
    final slider = tester.widget<Slider>(find.byType(Slider).first);
    slider.onChanged!(37);
    await tester.pump();
    expect((AppSettings.instance.accentColor.r * 255).round(), 37);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  test(
    'privacy surfaces match and manual no longer directs to removed tile',
    () {
      expect(File('PRIVACY_POLICY.md').readAsStringSync(), kPrivacyPolicyText);
      final encoded = const HtmlEscape(
        HtmlEscapeMode.element,
      ).convert(kPrivacyPolicyText);
      expect(File('privacy/index.html').readAsStringSync(), contains(encoded));
      expect(
        kPrivacyPolicyText,
        contains('not the VPN Keystore-backed encrypted store'),
      );
      final manual = File(
        'lib/widgets/user_manual_sheet.dart',
      ).readAsStringSync();
      expect(manual, isNot(contains('Library → Cloud Storage')));
      expect(manual, contains('Red, Green and Blue sliders'));
      expect(manual, contains('There is no in-app kill switch'));
    },
  );
}
