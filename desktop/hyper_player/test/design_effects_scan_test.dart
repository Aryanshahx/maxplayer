import 'package:hyper_player/player/native_properties.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hyper_player/app_design.dart';
import 'package:hyper_player/windows_drives.dart';
import 'package:hyper_player/discover/moving_poster_strip.dart';
import 'package:hyper_player/player/karaoke.dart';
import 'package:hyper_player/player/srt.dart';
import 'package:hyper_player/player/karaoke_overlay.dart';
import 'package:hyper_player/player/android_controls.dart';
import 'package:hyper_player/player/mpv_filters.dart';
import 'package:hyper_player/screens/gesture_illustrations.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });
  test('Three whole-app designs persist independently of media data', () async {
    final design = AppDesign();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('hyper.queue.fixture', ['video.mp4']);
    for (final mode in AppDesignMode.values) {
      await design.select(mode);
      final reloaded = AppDesign();
      await reloaded.load();
      expect(reloaded.mode, mode);
    }
    expect(prefs.getStringList('hyper.queue.fixture'), ['video.mp4']);
    final base = ThemeData.dark();
    await design.select(AppDesignMode.compact);
    final compact = design.theme(base);
    final width = design.mediaExtent;
    await design.select(AppDesignMode.cinema);
    final cinema = design.theme(base);
    expect(compact.visualDensity, isNot(cinema.visualDensity));
    expect(compact.cardTheme.shape, isNot(cinema.cardTheme.shape));
    expect(design.mediaExtent, greaterThan(width));
  });
  test('Unknown saved design safely falls back to Android-style default',
      () async {
    SharedPreferences.setMockInitialValues({'hyper.design.v1': 'invalid'});
    final design = AppDesign();
    await design.load();
    expect(design.mode, AppDesignMode.android);
  });
  test(
      'All-drive discovery selects local fixed drives, never network/removable',
      () {
    final roots = fixedDriveRootsFromMask(
        (1 << 2) | (1 << 3) | (1 << 4),
        (root) => root.startsWith('C')
            ? 3
            : root.startsWith('D')
                ? 4
                : 2);
    expect(roots, [r'C:\']);
    expect(fixedDriveRootsFromMask(0, (_) => throw StateError('not called')),
        isEmpty);
  });
  test('Native property readback rejects silent property failures', () {
    expect(propertyMatches('contrast', '14', '14.000000'), isTrue);
    expect(propertyMatches('tone-mapping', 'hable', ''), isFalse);
    expect(propertyMatches('vf', buildEnhanceFilter(), ''), isFalse);
    expect(
        propertyMatches(
            'vf', buildEnhanceFilter(), 'lavfi=[unsharp=5:5:0.55:5:5:0.0]'),
        isTrue);
    expect(propertyMatches('mute', 'no', 'yes'), isFalse);
  });
  test('Enhance filter uses real lavfi syntax, not an unused UI flag', () {
    expect(buildEnhanceFilter(), 'lavfi=[unsharp=5:5:0.55:5:5:0.0]');
  });
  test('Karaoke timing highlights actual timed text and skips music-only cues',
      () {
    const cue = SrtCue(1000, 4000, 'one two three');
    expect(karaokeWordIndex(cue, 1000), 0);
    expect(karaokeWordIndex(cue, 3900), 2);
    expect(karaokeCueAt(cue, null, 5000), isNull);
    expect(karaokeActiveCue([const SrtCue(0, 2000, '[Music]')], 1000), isNull);
  });
  testWidgets(
      'Karaoke overlay follows cue position without generating subtitles',
      (tester) async {
    final cue =
        ValueNotifier<SrtCue?>(const SrtCue(1000, 4000, 'one two three'));
    final playback =
        ValueNotifier(const PlaybackSnapshot(position: Duration(seconds: 2)));
    addTearDown(cue.dispose);
    addTearDown(playback.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: KaraokeOverlay(playback: playback, cue: cue))));
    expect(find.text('one two three', findRichText: true), findsOneWidget);
    playback.value = const PlaybackSnapshot(position: Duration(seconds: 6));
    await tester.pump();
    expect(find.text('one two three', findRichText: true), findsNothing);
  });
  testWidgets('Poster background moves automatically, not only on mouse scroll',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: SizedBox(
                height: 150,
                child: MovingPosterStrip(posters: [
                  ColoredBox(color: Colors.red),
                  ColoredBox(color: Colors.blue)
                ])))));
    Matrix4 transform() => tester
        .widget<Transform>(find.byKey(const ValueKey('poster-motion')))
        .transform;
    final before = transform().getTranslation().x;
    await tester.pump(const Duration(seconds: 1));
    expect(transform().getTranslation().x, lessThan(before));
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('Every Android touch gesture has its own vector illustration',
      (tester) async {
    for (final kind in GestureKind.values) {
      await tester.pumpWidget(
          MaterialApp(home: Scaffold(body: GestureIllustration(kind: kind))));
      expect(find.byType(CustomPaint), findsWidgets);
      expect(tester.takeException(), isNull);
    }
  });
}
