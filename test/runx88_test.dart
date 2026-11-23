import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:maxplayer/screens/display_settings_screen.dart';
import 'package:maxplayer/theme.dart';
import 'package:maxplayer/utils/settings.dart';
import 'package:maxplayer/utils/recent_searches.dart';
import 'package:maxplayer/widgets/recent_search_field.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.instance.load();
    AppColors.brightness = Brightness.light;
  });

  test('player control glyphs follow the theme accent in both themes', () {
    for (final brightness in Brightness.values) {
      AppColors.brightness = brightness;
      AppColors.accent = Colors.white;
      expect(AppColors.playerForeground, AppColors.accent);
      AppColors.accent = const Color(0xFF8B5CF6);
      final theme = buildAppTheme(
        accent: AppColors.accent,
        brightness: brightness,
      );
      expect(AppColors.playerForeground, theme.colorScheme.primary);
      expect(AppColors.playerForeground, isNot(Colors.white));
    }
    AppColors.accent = Colors.white;
  });

  test('recent presets keep five newest, never eat the white preset', () async {
    expect(AppSettings.instance.accentPresets.first, Colors.white);
    for (final c in [
      const Color(0xFF110000),
      const Color(0xFF220000),
      const Color(0xFF330000),
      const Color(0xFF440000),
      const Color(0xFF550000),
      const Color(0xFF660000),
    ]) {
      await AppSettings.instance.setCustomAccent(c);
    }
    final presets = AppSettings.instance.accentPresets;
    expect(presets.first, Colors.white);
    expect(presets.length, recentAccentLimit + 1);
    expect(presets[1], const Color(0xFF660000));
    expect(presets.contains(const Color(0xFF110000)), isFalse);
    // picking a preset promotes it, no duplicates
    await AppSettings.instance.setCustomAccent(const Color(0xFF440000));
    expect(
      AppSettings.instance.accentPresets.where(
        (c) => c.toARGB32() == 0xFF440000,
      ).length,
      1,
    );
    // white preset returns to default but keeps the recent picks
    await AppSettings.instance.useWhitePreset();
    expect(AppSettings.instance.usingWhitePreset, isTrue);
    expect(AppSettings.instance.accentColor, Colors.white);
    expect(AppSettings.instance.accentPresets.length, greaterThan(1));
  });

  testWidgets('white preset chip is always shown and switches back', (
    tester,
  ) async {
    await AppSettings.instance.setCustomAccent(const Color(0xFF22D3EE));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(brightness: Brightness.light),
        home: const DisplaySettingsScreen(),
      ),
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('accent-preset-white')),
      260,
    );
    expect(find.byKey(const ValueKey('accent-preset-white')), findsOneWidget);
    expect(find.byKey(const ValueKey('accent-preset-1')), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const ValueKey('accent-preset-white')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('accent-preset-white')));
    await tester.pumpAndSettle();
    expect(AppSettings.instance.accentColor, Colors.white);
    expect(tester.takeException(), isNull);
  });

  testWidgets('recent search chips use readable on-surface text', (
    tester,
  ) async {
    for (final brightness in Brightness.values) {
      AppColors.brightness = brightness;
      final theme = buildAppTheme(brightness: brightness);
      await RecentSearches.save('readability', ['Dune', 'Sicario']);
      final ctrl = TextEditingController();
      addTearDown(ctrl.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: RecentSearchField(scope: 'readability', controller: ctrl),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final chip = tester.widget<ActionChip>(find.byType(ActionChip).first);
      final label = chip.label as Text;
      expect(label.style?.color, theme.colorScheme.onSurface);
      expect(chip.backgroundColor, theme.colorScheme.surfaceContainerLow);
      expect(
        label.style!.color!.computeLuminance(),
        isNot(closeTo(chip.backgroundColor!.computeLuminance(), 0.05)),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
  });
}
