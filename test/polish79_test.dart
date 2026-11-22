// ignore_for_file: deprecated_member_use
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:maxplayer/screens/home_menu_screen.dart';
import 'package:maxplayer/screens/appearance_screen.dart';
import 'package:maxplayer/theme.dart';
import 'package:maxplayer/utils/config.dart';
import 'package:maxplayer/utils/settings.dart';
import 'package:maxplayer/utils/recent_searches.dart';
import 'package:maxplayer/widgets/recent_search_field.dart';

class _NavigationLog extends NavigatorObserver {
  final events = <String>[];
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      events.add('push:${route.settings.name}');
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      events.add('pop:${route.settings.name}');
}

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
  testWidgets(
    'Menu stays below child page; rapid taps open one route; Back returns to menu then Home',
    (tester) async {
      final log = _NavigationLog();
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [log],
          theme: buildAppTheme(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                child: const Text('Open menu'),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    settings: const RouteSettings(name: 'menu'),
                    builder: (_) => HomeMenuScreen(
                      onSelected: (menuContext, action) async {
                        calls++;
                        await Navigator.push<void>(
                          menuContext,
                          MaterialPageRoute(
                            settings: RouteSettings(name: action),
                            builder: (_) => const AppearanceScreen(),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open menu'));
      await tester.pumpAndSettle();
      final tile = tester.widget<ListTile>(
        find.ancestor(
          of: find.text('Appearance'),
          matching: find.byType(ListTile),
        ),
      );
      tile.onTap!();
      tile.onTap!();
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(log.events, ['push:/', 'push:menu', 'push:appearance']);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Settings and more'), findsOneWidget);
      expect(find.text('Open menu'), findsNothing);
      expect(log.events.last, 'pop:appearance');
      await tester.tap(find.text('Language'));
      await tester.pumpAndSettle();
      expect(calls, 2);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Open menu'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  test(
    'Text, selected chips and primary controls contrast in both palettes for every accent',
    () {
      double contrast(Color a, Color b) {
        final x = a.computeLuminance(), y = b.computeLuminance();
        return x > y ? (x + .05) / (y + .05) : (y + .05) / (x + .05);
      }

      for (final brightness in Brightness.values) {
        AppColors.brightness = brightness;
        for (final accent in accentPalette) {
          AppColors.accent = accent;
          final theme = buildAppTheme(accent: accent, brightness: brightness),
              scheme = buildAppTheme(
                accent: accent,
                brightness: brightness,
              ).colorScheme;
          expect(
            contrast(scheme.onSurface, scheme.surface),
            greaterThanOrEqualTo(4.5),
          );
          expect(
            contrast(scheme.onSurfaceVariant, scheme.surface),
            greaterThanOrEqualTo(4.5),
          );
          expect(
            contrast(scheme.onPrimary, scheme.primary),
            greaterThanOrEqualTo(4.5),
          );
          expect(
            contrast(
              WidgetStateProperty.resolveAs<TextStyle?>(
                theme.chipTheme.labelStyle,
                {WidgetState.selected},
              )!.color!,
              theme.chipTheme.selectedColor!,
            ),
            greaterThanOrEqualTo(4.5),
          );
          expect(
            contrast(AppColors.rating, AppColors.background),
            greaterThanOrEqualTo(4.5),
          );
        }
      }
    },
  );
  testWidgets(
    'Recent searches use their own scroll space above Hot searches on a narrow large-text screen',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await RecentSearches.save('discover-layout', [
        'A very long recent movie search name that must ellipsize',
        'Second movie',
        'Third movie',
      ]);
      final ctrl = TextEditingController();
      addTearDown(ctrl.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(brightness: Brightness.light),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!,
          ),
          home: Scaffold(
            body: SafeArea(
              child: Column(
                children: [
                  RecentSearchField(
                    scope: 'discover-layout',
                    controller: ctrl,
                    showHistory: false,
                  ),
                  Expanded(
                    child: ListView(
                      children: [
                        RecentSearchHistory(
                          key: const ValueKey('recent'),
                          scope: 'discover-layout',
                          controller: ctrl,
                          onSelected: (_) {},
                        ),
                        const Text('Hot searches', key: ValueKey('hot')),
                        const ListTile(title: Text('A trending movie')),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.byKey(const ValueKey('recent'))).bottom,
        lessThanOrEqualTo(
          tester.getRect(find.byKey(const ValueKey('hot'))).top,
        ),
      );
      expect(find.text('Recent searches'), findsOneWidget);
      expect(
        File('lib/widgets/recent_search_field.dart').readAsStringSync(),
        isNot(contains('OverlayPortal')),
      );
      expect(find.byType(ActionChip), findsNWidgets(3));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Fixed-height search field does not expand a dropdown over nearby content',
    (tester) async {
      await RecentSearches.save('fixed', ['one', 'two', 'three']);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                SizedBox(
                  height: 44,
                  child: RecentSearchField(
                    scope: 'fixed',
                    showHistory: false,
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                    ),
                  ),
                ),
                Text('Hot searches'),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      expect(find.text('Recent searches'), findsNothing);
      expect(find.text('Hot searches'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Clearing history invalidates an outstanding edit rather than resurrecting it',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: RecentSearchField(scope: 'clear-pending')),
        ),
      );
      await tester.enterText(find.byType(TextField), 'Unfinished search');
      await RecentSearches.clear('clear-pending');
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(await RecentSearches.load('clear-pending'), isEmpty);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(await RecentSearches.load('clear-pending'), isEmpty);
    },
  );
  test(
    'Instagram endpoint and visible handle are updated; menu does not pop before opening child',
    () {
      expect(
        kMaxInstagramUrl,
        'https://www.instagram.com/maxplayer_official2026?evlk=MTR6NjljZGZtZ2NvdA==',
      );
      expect(
        File('lib/widgets/cine_ui.dart').readAsStringSync(),
        contains('@maxplayer_official2026'),
      );
      final menu = File('lib/screens/home_menu_screen.dart').readAsStringSync();
      expect(menu, isNot(contains('Navigator.pop')));
      final app = File('lib/main.dart').readAsStringSync();
      expect(app, contains('themeAnimationDuration: Duration.zero'));
    },
  );
}
