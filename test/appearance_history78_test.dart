// ignore_for_file: deprecated_member_use
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:maxplayer/theme.dart';
import 'package:maxplayer/utils/settings.dart';
import 'package:maxplayer/utils/recent_searches.dart';
import 'package:maxplayer/utils/privacy_policy.dart';
import 'package:maxplayer/widgets/recent_search_field.dart';
import 'package:maxplayer/widgets/about_sheet.dart';
import 'package:maxplayer/widgets/user_manual_sheet.dart';
import 'package:maxplayer/screens/appearance_screen.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.instance.load();
    AppColors.brightness = Brightness.dark;
  });
  tearDown(() {
    AppColors.brightness = Brightness.dark;
    AppColors.accent = Colors.white;
  });
  test(
    'Theme defaults to system, explicit modes persist, invalid preference falls back',
    () async {
      expect(AppSettings.instance.themeMode, ThemeMode.system);
      await AppSettings.instance.setThemeMode(ThemeMode.light);
      await AppSettings.instance.load();
      expect(AppSettings.instance.themeMode, ThemeMode.light);
      await AppSettings.instance.setThemeMode(ThemeMode.dark);
      await AppSettings.instance.load();
      expect(AppSettings.instance.themeMode, ThemeMode.dark);
      SharedPreferences.setMockInitialValues({'disp.themeMode.v1': 'broken'});
      await AppSettings.instance.load();
      expect(AppSettings.instance.themeMode, ThemeMode.system);
    },
  );
  test('Both palettes have readable default accent/text over surfaces', () {
    for (final brightness in Brightness.values) {
      AppColors.brightness = brightness;
      AppColors.accent = Colors.white;
      final theme = buildAppTheme(accent: Colors.white, brightness: brightness);
      expect(theme.brightness, brightness);
      double contrast(Color a, Color b) {
        final x = a.computeLuminance(), y = b.computeLuminance();
        return x > y ? (x + .05) / (y + .05) : (y + .05) / (x + .05);
      }

      expect(
        contrast(AppColors.textPrimary, AppColors.background),
        greaterThan(7),
      );
      expect(
        contrast(theme.colorScheme.primary, theme.colorScheme.surface),
        greaterThan(7),
      );
      expect(AppColors.surfaceAlt, isNot(AppColors.background));
    }
  });
  testWidgets(
    'System mode follows platform brightness and manual light overrides it',
    (tester) async {
      final dispatcher = tester.binding.platformDispatcher;
      addTearDown(dispatcher.clearPlatformBrightnessTestValue);
      dispatcher.platformBrightnessTestValue = Brightness.dark;
      await tester.pumpWidget(
        MaterialApp(
          themeMode: ThemeMode.system,
          theme: buildAppTheme(brightness: Brightness.light),
          darkTheme: buildAppTheme(),
          home: const Scaffold(body: Text('Probe')),
        ),
      );
      expect(
        Theme.of(tester.element(find.text('Probe'))).brightness,
        Brightness.dark,
      );
      dispatcher.platformBrightnessTestValue = Brightness.light;
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.text('Probe'))).brightness,
        Brightness.light,
      );
      dispatcher.platformBrightnessTestValue = Brightness.dark;
      await tester.pumpWidget(
        MaterialApp(
          themeMode: ThemeMode.light,
          theme: buildAppTheme(brightness: Brightness.light),
          darkTheme: buildAppTheme(),
          home: const Scaffold(body: Text('Probe')),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.text('Probe'))).brightness,
        Brightness.light,
      );
    },
  );
  testWidgets('Appearance choices update and save the preference', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(theme: buildAppTheme(), home: const AppearanceScreen()),
    );
    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();
    expect(AppSettings.instance.themeMode, ThemeMode.light);
    await tester.tap(find.text('System default'));
    await tester.pumpAndSettle();
    expect(AppSettings.instance.themeMode, ThemeMode.system);
  });
  test(
    'Recent searches trim, deduplicate and cap at three; scopes stay local and separate',
    () async {
      var list = <String>[];
      for (final text in ['one', 'two', 'three', 'four', ' THREE ']) {
        list = RecentSearches.prepend(list, text);
      }
      expect(list, ['THREE', 'four', 'two']);
      expect(RecentSearches.prepend(list, '   '), list);
      await RecentSearches.save('library', list);
      await RecentSearches.save('discover', ['Movie']);
      expect(await RecentSearches.load('library'), list);
      expect(await RecentSearches.load('discover'), ['Movie']);
    },
  );
  testWidgets(
    'Recent dropdown recalls a query, shows at most three and clears persistently',
    (tester) async {
      await RecentSearches.save('test', ['Alpha', 'Beta', 'Gamma', 'Delta']);
      final ctrl = TextEditingController();
      addTearDown(ctrl.dispose);
      String? query;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(20),
              child: RecentSearchField(
                scope: 'test',
                controller: ctrl,
                onChanged: (value) => query = value,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Delta'), findsNothing);
      await tester.tap(find.text('Beta'));
      await tester.pumpAndSettle();
      expect(ctrl.text, 'Beta');
      expect(query, 'Beta');
      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();
      expect(find.text('Recent searches'), findsOneWidget);
      await tester.tap(find.byTooltip('Clear recent searches'));
      await tester.pumpAndSettle();
      expect(await RecentSearches.load('test'), isEmpty);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(await RecentSearches.load('test'), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Typed history persists after debounce without adding empty queries',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: RecentSearchField(scope: 'typed')),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'My video');
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(await RecentSearches.load('typed'), ['My video']);
      await tester.enterText(find.byType(TextField), '');
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(await RecentSearches.load('typed'), ['My video']);
    },
  );
  for (final page in ['privacy', 'manual', 'about']) {
    testWidgets(
      '$page opens a full-screen route with back navigation in light mode',
      (tester) async {
        AppColors.brightness = Brightness.light;
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(brightness: Brightness.light),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () {
                    if (page == 'privacy') {
                      showPrivacyPolicyDialog(context);
                    } else if (page == 'manual') {
                      UserManualSheet.show(context);
                    } else {
                      AboutSheet.show(context);
                    }
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(find.byType(BottomSheet), findsNothing);
        expect(find.byType(BackButton), findsOneWidget);
        expect(find.byType(AppBar), findsOneWidget);
        if (page == 'privacy') {
          expect(find.byType(SelectableText), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.text('Open'), findsOneWidget);
      },
    );
  }
  test(
    'Home menu is routed full screen, shortcuts have backgrounds, search histories exclude PIN/URL fields',
    () {
      final home = File('lib/screens/library_screen.dart').readAsStringSync();
      expect(home, isNot(contains('PopupMenuButton')));
      expect(home, contains('Settings and more'));
      expect(home, contains('AppearanceScreen'));
      expect(home, contains('color: AppColors.surfaceAlt'));
      for (final file in [
        'private_screen',
        'network_storage_screen',
        'open_stream_screen',
      ]) {
        expect(
          File('lib/screens/$file.dart').readAsStringSync(),
          isNot(contains('RecentSearchField')),
        );
      }
      final main = File('lib/main.dart').readAsStringSync();
      expect(main, contains('didChangePlatformBrightness'));
      expect(main, contains('themeMode: mode'));
    },
  );
}
