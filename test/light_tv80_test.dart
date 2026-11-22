import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maxplayer/services/native_bridge.dart';
import 'package:maxplayer/theme.dart';
import 'package:maxplayer/utils/tmdb.dart';
import 'package:maxplayer/widgets/cine_ui.dart';
import 'package:maxplayer/widgets/remote_tap.dart';

const movie = TmdbMovie(
  id: 80,
  title: 'A responsive movie',
  rating: 8.0,
  year: 2026,
  overview: 'Offline fixture without network images.',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() {
    AppColors.brightness = Brightness.dark;
    AppColors.accent = Colors.white;
    NativeBridge.isTelevision = false;
  });
  for (final brightness in Brightness.values) {
    test('switch thumb and track remain distinct in $brightness', () {
      for (final accent in [
        Colors.white,
        Colors.purple,
        Colors.cyan,
        Colors.amber,
      ]) {
        final theme = buildAppTheme(accent: accent, brightness: brightness);
        final sw = theme.switchTheme;
        for (final states in [
          <WidgetState>{},
          {WidgetState.selected},
          {WidgetState.selected, WidgetState.focused},
        ]) {
          final thumb = sw.thumbColor!.resolve(states)!;
          final track = sw.trackColor!.resolve(states)!;
          expect(thumb, isNot(track));
          if (states.contains(WidgetState.selected)) {
            final l1 = thumb.computeLuminance();
            final l2 = track.computeLuminance();
            final ratio =
                ((l1 > l2 ? l1 : l2) + .05) / ((l1 < l2 ? l1 : l2) + .05);
            expect(ratio, greaterThanOrEqualTo(4.5));
          }
        }
        expect(sw.thumbColor!.resolve({WidgetState.disabled}), isNotNull);
        expect(sw.trackColor!.resolve({WidgetState.disabled}), isNotNull);
      }
    });
  }
  test(
    'player overlay controls stay white in light theme; canvas is black',
    () {
      AppColors.brightness = Brightness.light;
      expect(AppColors.playerChrome.r, 1);
      expect(AppColors.playerForeground, Colors.white);
      final source = File(
        'lib/screens/player_screen_impl.dart',
      ).readAsStringSync();
      expect(source, contains('backgroundColor: Colors.black'));
      expect(source, isNot(contains('AppColors.playerChrome')));
      expect(
        source,
        contains('if (navigatingControl && (directional || activate))'),
      );
    },
  );
  test(
    'brand uses an opaque srcIn mask and no per-switch thumb overrides remain',
    () {
      final home = File('lib/screens/library_screen.dart').readAsStringSync();
      expect(home, contains('blendMode: BlendMode.srcIn'));
      for (final file in Directory(
        'lib',
      ).listSync(recursive: true).whereType<File>()) {
        if (file.path.endsWith('.dart')) {
          expect(
            file.readAsStringSync(),
            isNot(contains('activeThumbColor: AppColors.accent')),
            reason: file.path,
          );
        }
      }
    },
  );
  test(
    'TV mode comes from native UI mode and fails safely without platform',
    () async {
      const channel = MethodChannel('maxplayer/storage');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async => true);
      await NativeBridge.loadDeviceMode();
      expect(NativeBridge.isTelevision, isTrue);
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => throw PlatformException(code: 'unavailable'),
      );
      await NativeBridge.loadDeviceMode();
      expect(NativeBridge.isTelevision, isFalse);
      messenger.setMockMethodCallHandler(channel, null);
    },
  );
  test(
    'unified phone + TV launcher, banner and optional touch remain installed',
    () {
      final manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();
      for (final token in [
        'android.intent.category.LAUNCHER',
        'android.intent.category.LEANBACK_LAUNCHER',
        'android:banner="@drawable/tv_banner"',
        'android.hardware.touchscreen',
      ]) {
        expect(manifest, contains(token));
      }
      expect(
        File(
          'android/app/src/main/res/drawable-xhdpi/tv_banner.png',
        ).existsSync(),
        isTrue,
      );
      final home = File('lib/screens/library_screen.dart').readAsStringSync();
      expect(home, contains('[...kQuickTilesPage1, ...kQuickTilesPage2]'));
    },
  );
  testWidgets('remote arrows move focus and OK activates exactly once', (
    tester,
  ) async {
    var first = 0;
    var second = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              RemoteTap(
                onTap: () => first++,
                child: const SizedBox(
                  width: 120,
                  height: 80,
                  child: Text('First'),
                ),
              ),
              RemoteTap(
                onTap: () => second++,
                child: const SizedBox(
                  width: 120,
                  height: 80,
                  child: Text('Second'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final detector = tester.widget<FocusableActionDetector>(
      find.byType(FocusableActionDetector).first,
    );
    // Traverse into the first remote target, then use the actual arrow/OK path.
    expect(detector.enabled, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    expect(first, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    expect(second, 1);
    expect(first, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 200));
  });
  for (final size in [
    const Size(390, 844),
    const Size(960, 540),
    const Size(1920, 1080),
  ]) {
    testWidgets('light Discover hero and ranking fit $size without overflow', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      AppColors.brightness = Brightness.light;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(brightness: Brightness.light),
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  CineFeaturedHero(
                    items: const [movie],
                    onTap: (_) {},
                    onOpen: (_) {},
                  ),
                  CineTopTen(items: List.filled(10, movie), onTap: (_) {}),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
      expect(cineInk, AppColors.background);
      final rank = tester.widget<Text>(find.text('1'));
      expect(rank.style!.foreground!.color.computeLuminance(), lessThan(.8));
      expect(rank.style!.foreground!.color.a, greaterThan(.5));
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
