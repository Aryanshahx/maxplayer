import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:maxplayer/features/vpn/vpn_disclosure.dart';
import 'package:maxplayer/screens/discover_screen.dart';
import 'package:maxplayer/widgets/discover_section.dart';
import 'package:maxplayer/theme.dart';
import 'package:maxplayer/utils/tmdb.dart';

/// v1.0.1+88 — the three fixes in this release:
///   1. Play-required VpnService prominent disclosure (shown before the
///      first connection, remembered afterwards).
///   2. Discover: system Back closes the search instead of leaving the
///      screen.
///   3. Discover rails: the poster year is never clipped on tablets.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppColors.brightness = Brightness.dark;
  });

  tearDown(() {
    AppColors.brightness = Brightness.dark;
  });

  group('VPN prominent disclosure', () {
    test('is not accepted on a fresh install, and is remembered afterwards',
        () async {
      expect(await VpnDisclosure.accepted(), isFalse);
      await VpnDisclosure.remember();
      expect(await VpnDisclosure.accepted(), isTrue);
    });

    test('copy names the VpnService and the data it handles', () {
      final copy = VpnDisclosure.points.join(' ');
      expect(copy, contains('Android VpnService'));
      expect(copy, contains('IP address'));
      expect(copy, contains('privacy policy'));
      // Play requires the disclosure to name the purpose, not just "VPN".
      expect(copy.toLowerCase(), contains('you choose'));
    });

    testWidgets('is shown before the first connection and can be declined',
        (tester) async {
      var allowed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                allowed = await VpnDisclosure.ensureAccepted(context);
              },
              child: const Text('connect'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('connect'));
      await tester.pumpAndSettle();
      expect(find.text('Why RunX Player needs a VPN connection'), findsOneWidget);
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(allowed, isFalse);
      // Declining must NOT store consent.
      expect(await VpnDisclosure.accepted(), isFalse);
    });

    testWidgets('accepting stores consent and allows the connection',
        (tester) async {
      var allowed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                allowed = await VpnDisclosure.ensureAccepted(context);
              },
              child: const Text('connect'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('connect'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Agree and connect'));
      await tester.pumpAndSettle();
      expect(allowed, isTrue);
      expect(await VpnDisclosure.accepted(), isTrue);
      // Second connection: no dialog any more.
      allowed = false;
      await tester.tap(find.text('connect'));
      await tester.pumpAndSettle();
      expect(find.text('Why RunX Player needs a VPN connection'), findsNothing);
      expect(allowed, isTrue);
    });
  });

  group('Discover tablet layout', () {
    testWidgets('rails switch to wider, taller cards on tablets',
        (tester) async {
      late ({double width, double height}) phone;
      late ({double width, double height}) tablet;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(size: const Size(390, 844)),
              child: Builder(
                builder: (ctx) {
                  phone = discoverRailCardSize(ctx);
                  return const SizedBox();
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                size: const Size(1280, 800),
              ),
              child: Builder(
                builder: (ctx) {
                  tablet = discoverRailCardSize(ctx);
                  return const SizedBox();
                },
              ),
            ),
          ),
        ),
      );
      expect(phone.width, 130);
      expect(phone.height, 244);
      expect(tablet.width, greaterThan(phone.width));
      expect(tablet.height, greaterThan(phone.height));
    });

    testWidgets('poster card keeps the year visible at 2x text scale',
        (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(1600, 1000),
              textScaler: TextScaler.linear(2.0),
            ),
            child: Scaffold(
              backgroundColor: AppColors.background,
              body: Center(
                child: DiscoverMovieCard(
                  movie: const TmdbMovie(
                    id: 1,
                    title: 'A Very Long Movie Title That Wraps',
                    year: 2026,
                    rating: 7.8,
                    kind: 'movie',
                  ),
                  onTap: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('2026'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
