import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hyper_player/utils/player_settings.dart';
import 'package:hyper_player/player/android_controls.dart';
import 'package:hyper_player/player/fit.dart';
import 'package:hyper_player/player/queue_order.dart';
import 'package:hyper_player/player/video_zoom.dart';
import 'package:hyper_player/screens/player_settings_android.dart';

void main() {
  final settings = PlayerSettings.instance;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await settings.load();
  });
  test(
      'Android-adapted gesture settings persist and malformed values fall back',
      () async {
    await settings.setSeekStep(30);
    await settings.setLongPressRate(2.5);
    await settings.setPinchZoom(true);
    await settings.setScreenLock(false);
    await settings.load();
    expect(settings.seekStep, 30);
    expect(settings.longPressRate, 2.5);
    expect(settings.pinchZoom, isTrue);
    expect(settings.screenLock, isFalse);
    SharedPreferences.setMockInitialValues({
      'hyper.desktop.input.seekStep': 999,
      'hyper.desktop.input.longPressRate': 50.0
    });
    await settings.load();
    expect(settings.seekStep, 10);
    expect(settings.longPressRate, 2);
  });
  test('Focal zoom and pan are bounded; fit ladder wraps all six modes', () {
    expect(freeZoomFor(baseZoom: 1, scale: 9), 4);
    expect(wrapFitLadderPos(6, 6), 0);
    expect(wrapFitLadderPos(-1, 6), 5);
    expect(
        clampPanFor(
            pan: const Offset(999, -999), zoom: 2, size: const Size(800, 400)),
        const Offset(400, -200));
    expect(isTwoFingerTapReset(durationMs: 200, travelPx: 2, scaled: false),
        isTrue);
  });
  testWidgets('Copied settings exposes Android sections and keyboard manual',
      (tester) async {
    await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: PlayerSettingsSheet())));
    await tester.pumpAndSettle();
    expect(find.text('Gesture controls'), findsOneWidget);
    expect(find.text('Double-tap sides to seek'), findsOneWidget);
    await tester.tap(find.text('User manual · keyboard & mouse'));
    await tester.pumpAndSettle();
    expect(find.text('Player keyboard & mouse'), findsOneWidget);
  });
  Future<void> controls(WidgetTester tester,
      {ValueChanged<Duration>? seek,
      ValueChanged<double>? rate,
      void Function(double, Offset)? transform}) async {
    final playback = ValueNotifier(const PlaybackSnapshot(
        position: Duration(seconds: 30),
        duration: Duration(minutes: 5),
        rate: 1.25));
    addTearDown(playback.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: AndroidPlayerControls(
      playback: playback,
      title: 'Fixture',
      shuffle: false,
      repeat: QueueRepeat.off,
      fit: FitMode.fit,
      canPrevious: true,
      canNext: true,
      onBack: () {},
      onPlayPause: () {},
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
      onSeek: seek ?? (_) {},
      onVolume: (_) {},
      onTemporaryRate: rate,
      onTransform: transform,
    ))));
  }

  testWidgets('Long-press restores the exact prior playback rate on release',
      (tester) async {
    final rates = <double>[];
    await controls(tester, rate: rates.add);
    final finger = await tester.startGesture(const Offset(300, 220));
    await tester.pump(const Duration(milliseconds: 700));
    expect(rates, [2]);
    await finger.up();
    await tester.pump();
    expect(rates, [2, 1.25]);
  });
  testWidgets('Disabled horizontal gesture never seeks', (tester) async {
    settings.horizontalSeek = false;
    Duration? selected;
    await controls(tester, seek: (value) => selected = value);
    await tester.timedDragFrom(const Offset(200, 220), const Offset(200, 0),
        const Duration(milliseconds: 400));
    await tester.pump();
    expect(selected, isNull);
  });
  testWidgets(
      'Two-finger free pinch emits bounded zoom without seeking playback',
      (tester) async {
    settings.pinchZoom = true;
    final zooms = <double>[];
    Duration? seek;
    await controls(tester,
        seek: (value) => seek = value,
        transform: (zoom, pan) => zooms.add(zoom));
    final first = await tester.startGesture(const Offset(300, 220), pointer: 1);
    final second =
        await tester.startGesture(const Offset(500, 220), pointer: 2);
    await first.moveTo(const Offset(250, 220));
    await tester.pump();
    await second.moveTo(const Offset(550, 220));
    await tester.pump();
    await first.moveTo(const Offset(200, 220));
    await tester.pump();
    await second.moveTo(const Offset(600, 220));
    await tester.pump();
    await first.up();
    await second.up();
    await tester.pump(const Duration(milliseconds: 500));
    expect(zooms.any((zoom) => zoom > 1 && zoom <= 4), isTrue);
    expect(seek, isNull);
  });
}
