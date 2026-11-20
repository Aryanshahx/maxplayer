import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
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
      ValueChanged<double>? volume,
      VoidCallback? fullscreen,
      VoidCallback? playPause,
      VoidCallback? fitAction,
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
      onPlayPause: playPause ?? () {},
      onPrevious: () {},
      onNext: () {},
      onShuffle: () {},
      onRepeat: () {},
      onFit: fitAction ?? () {},
      onSpeed: () {},
      onExtras: () {},
      onQueue: () {},
      onSettings: () {},
      onFullscreen: () async {
        fullscreen?.call();
      },
      onMenu: (_) {},
      onSeek: seek ?? (_) {},
      onVolume: volume ?? (_) {},
      onTemporaryRate: rate,
      onTransform: transform,
    ))));
  }

  testWidgets(
      'Brightness shortcut and slider controls are visible and volume emits real callback',
      (tester) async {
    double? volume;
    await controls(tester, volume: (value) => volume = value);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    expect(volume, 100);
    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await tester.pump();
    expect(find.text('Video brightness 95%'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.pumpAndSettle();
    expect(find.text('Brightness & volume'), findsOneWidget);
    expect(find.byType(Slider), findsWidgets);
  });
  test('Legacy default boost is migrated off once; explicit choice persists',
      () async {
    SharedPreferences.setMockInitialValues(
        {'hyper.desktop.input.volumeBoost': true});
    await settings.load();
    expect(settings.volumeBoost, isFalse);
    await settings.setVolumeBoost(true);
    await settings.load();
    expect(settings.volumeBoost, isTrue);
  });
  testWidgets('Wheel left dims without volume; wheel right changes only volume',
      (tester) async {
    final volumes = <double>[];
    await controls(tester, volume: volumes.add);
    await tester.sendEventToBinding(const PointerScrollEvent(
        position: Offset(100, 220), scrollDelta: Offset(0, 20)));
    await tester.pump();
    expect(volumes, isEmpty);
    expect(find.text('Video brightness 95%'), findsOneWidget);
    await tester.sendEventToBinding(const PointerScrollEvent(
        position: Offset(700, 220), scrollDelta: Offset(0, 20)));
    await tester.pump();
    expect(volumes, [95]);
    expect(find.text('Volume 95%'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
  });
  testWidgets(
      'Windowed mouse double click seeks sides without entering fullscreen',
      (tester) async {
    Duration? seek;
    var fullscreenCalls = 0, playCalls = 0;
    await controls(tester,
        seek: (v) => seek = v,
        fullscreen: () => fullscreenCalls++,
        playPause: () => playCalls++);
    await tester.tapAt(const Offset(100, 220), kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tapAt(const Offset(100, 220), kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(milliseconds: 320));
    expect(seek, const Duration(seconds: 20));
    expect(fullscreenCalls, 0);
    await tester.tapAt(const Offset(400, 220), kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tapAt(const Offset(400, 220), kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(milliseconds: 320));
    expect(playCalls, 1);
    expect(fullscreenCalls, 0);
    expect(find.byTooltip('Brightness & volume (B)'), findsNothing);
  });
  testWidgets('Windowed mouse drag adjusts video brightness with feedback',
      (tester) async {
    await controls(tester);
    final mouse = await tester.startGesture(const Offset(180, 320),
        kind: PointerDeviceKind.mouse);
    await mouse.moveBy(const Offset(0, 40));
    await tester.pump(const Duration(milliseconds: 40));
    await mouse.moveBy(const Offset(0, 80));
    await tester.pump(const Duration(milliseconds: 40));
    await mouse.up();
    await tester.pump();
    expect(find.textContaining('Video brightness'), findsWidgets);
  });
  testWidgets(
      'New brightness and zoom keys work; old bracket shortcut is removed',
      (tester) async {
    final zooms = <double>[];
    await controls(tester, transform: (zoom, pan) => zooms.add(zoom));
    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await tester.pump();
    expect(find.text('Video brightness 95%'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
    await tester.pump();
    expect(find.text('Video brightness 100%'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.equal);
    await tester.pump();
    expect(zooms.last, 1.25);
    await tester.sendKeyEvent(LogicalKeyboardKey.minus);
    await tester.pump();
    expect(zooms.last, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.bracketLeft);
    await tester.pump();
    expect(find.text('Zoom 1.00x'), findsOneWidget);
  });
  testWidgets('Left/right gesture origin is locked to the actual surface half',
      (tester) async {
    final volumes = <double>[];
    await controls(tester, volume: volumes.add);
    final left = await tester.startGesture(const Offset(120, 250));
    await left.moveBy(const Offset(10, 30));
    await tester.pump();
    await left.moveBy(const Offset(25, 100));
    await tester.pump();
    await left.up();
    await tester.pump();
    expect(volumes, isEmpty);
    expect(find.textContaining('Video brightness'), findsOneWidget);
    final right = await tester.startGesture(const Offset(670, 250));
    await right.moveBy(const Offset(-10, 30));
    await tester.pump();
    await right.moveBy(const Offset(-25, 100));
    await tester.pump();
    await right.up();
    await tester.pump();
    expect(volumes, isNotEmpty);
    expect(find.textContaining('Volume'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 500));
  });
  testWidgets('Fit shortcut continues through two complete six-mode loops',
      (tester) async {
    var current = FitMode.fit;
    final seen = <FitMode>[];
    await controls(tester, fitAction: () {
      current = nextFitMode(current);
      seen.add(current);
    });
    for (var i = 0; i < 12; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.pump();
    }
    expect(current, FitMode.fit);
    expect(seen.take(6), [
      FitMode.crop,
      FitMode.stretch,
      FitMode.sixteenNine,
      FitMode.fourThree,
      FitMode.original,
      FitMode.fit
    ]);
    expect(seen.skip(6), seen.take(6));
  });
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
