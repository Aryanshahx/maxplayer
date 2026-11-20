import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_player/player/android_controls.dart';
import 'package:hyper_player/player/fit.dart';
import 'package:hyper_player/player/queue_order.dart';
import 'package:hyper_player/player/player_sheets.dart';
import 'package:hyper_player/player/mpv_filters.dart';

void main() {
  test('All six Android fits retain exact frame and pixel semantics', () {
    expect(FitMode.values.length, 6);
    expect(FitMode.sixteenNine.aspectRatio, 16 / 9);
    expect(FitMode.fourThree.aspectRatio, 4 / 3);
    expect(FitMode.original.boxFit, BoxFit.none);
    expect(nextFitMode(FitMode.original), FitMode.fit);
  });
  test('Queue off all one and manual next have distinct end behaviour', () {
    final order = QueueOrder()..select(2, 3);
    expect(order.next(2, 3, completed: true), isNull);
    order.repeat = QueueRepeat.one;
    expect(order.next(2, 3, completed: true), 2);
    expect(order.next(2, 3), isNull);
    order.repeat = QueueRepeat.all;
    expect(order.next(2, 3, completed: true), 0);
    expect(order.previous(0, 3), 2);
  });
  test('Shuffle consumes bag once and previous follows actual history', () {
    final order = QueueOrder(random: Random(5))
      ..setShuffle(true, current: 0, length: 5);
    final seen = {0};
    var current = 0;
    for (var i = 0; i < 4; i++) {
      final next = order.next(current, 5)!;
      expect(seen.add(next), isTrue);
      order.select(next, 5);
      current = next;
    }
    expect(order.next(current, 5), isNull);
    final previous = order.previous(current, 5)!;
    expect(previous, isNot(current));
    order.select(previous, 5);
    expect(order.next(previous, 5), current);
  });
  test('Empty queue and one-item shuffle never select invalid indices', () {
    final order = QueueOrder()..setShuffle(true, current: 0, length: 1);
    expect(order.next(0, 1), isNull);
    order.repeat = QueueRepeat.all;
    expect(order.next(0, 1), 0);
    expect(order.next(-1, 0), isNull);
    expect(order.previous(0, 0), isNull);
  });
  test('Audio filters are real Android builder strings', () {
    expect(combineAudioFilters([0, 0, 0, 0, 0]), '');
    expect(combineAudioFilters([0, 0, 0, 0, 0], dialogueBoost: true),
        contains('f=1200'));
    expect(buildEqualizerFilter(equalizerPresets['Bass+']!), contains('f=60'));
    expect(() => buildEqualizerFilter([0]), throwsArgumentError);
  });
  test('Playback clock handles unknown and hour-long media', () {
    expect(playbackClock(const Duration(seconds: -1)), '00:00');
    expect(playbackClock(const Duration(seconds: 3661)), '1:01:01');
  });
  testWidgets('Six-mode picker exposes Original and 16:9 actions',
      (tester) async {
    FitMode? chosen;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: SixModeFitSheet(
                    selected: FitMode.fit, onSelect: (v) => chosen = v)))));
    await tester.tap(find.text('16:9'));
    expect(chosen, FitMode.sixteenNine);
    expect(find.text('Original'), findsOneWidget);
  });
  testWidgets('EQ preset passes real band gains and handles failure',
      (tester) async {
    List<double>? applied;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: EqualizerSheet(
                    initial: const [0, 0, 0, 0, 0],
                    dialogue: false,
                    onApply: (bands, boost) async {
                      applied = bands;
                      throw StateError('failed');
                    })))));
    await tester.tap(find.text('Bass+'));
    await tester.pumpAndSettle();
    expect(applied, equalizerPresets['Bass+']);
    expect(find.text('Audio filter unavailable. Previous settings kept.'),
        findsOneWidget);
  });
  testWidgets('Android controls expose transport/extras and keyboard seeking',
      (tester) async {
    final state = ValueNotifier(const PlaybackSnapshot(
        position: Duration(seconds: 20), duration: Duration(seconds: 60)));
    addTearDown(state.dispose);
    Duration? seek;
    bool play = false;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: AndroidPlayerControls(
                playback: state,
                title: 'Example',
                shuffle: false,
                repeat: QueueRepeat.off,
                fit: FitMode.fit,
                canPrevious: true,
                canNext: true,
                onBack: () {},
                onPlayPause: () => play = true,
                onPrevious: () {},
                onNext: () {},
                onShuffle: () {},
                onRepeat: () {},
                onFit: () {},
                onSpeed: () {},
                onExtras: () {},
                onQueue: () {},
                onSettings: () {},
                onFullscreen: () async {},
                onMenu: (_) {},
                onSeek: (v) => seek = v,
                onVolume: (_) {}))));
    await tester.pump();
    expect(find.byTooltip('Playlists'), findsOneWidget);
    expect(find.byTooltip('Previous video'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    expect(seek, const Duration(seconds: 30));
    await tester.tap(find.byTooltip('Play'));
    expect(play, isTrue);
    await tester.tap(find.byTooltip('Lock controls (Escape to unlock)'));
    await tester.pump();
    expect(find.byTooltip('Play'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byTooltip('Play'), findsOneWidget);
  });
}
