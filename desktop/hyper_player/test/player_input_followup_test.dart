import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_player/player/android_controls.dart';
import 'package:hyper_player/player/fit.dart';
import 'package:hyper_player/player/queue_order.dart';
import 'package:hyper_player/player/player_sheets.dart';
import 'package:hyper_player/player/sleep_status.dart';

void main() {
  test(
      'Sleep label handles active deadline, until end, cancellation and expiry',
      () {
    final now = DateTime(2026, 9, 5);
    expect(sleepStatusLabel(now.add(const Duration(seconds: 125)), false, now),
        'Sleep 02:05');
    expect(sleepStatusLabel(null, true, now), 'Sleep · until end');
    expect(sleepStatusLabel(null, false, now), '');
    expect(
        sleepStatusLabel(now.subtract(const Duration(seconds: 1)), false, now),
        '');
  });
  testWidgets('Player settings opens the keyboard user manual', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: DesktopPlayerSettings(
                    autoHide: true,
                    resume: true,
                    onAutoHide: (_) {},
                    onResume: (_) {})))));
    final manual = find.text('User manual · keyboard & mouse');
    await tester.ensureVisible(manual);
    await tester.pumpAndSettle();
    await tester.tap(manual);
    await tester.pumpAndSettle();
    expect(find.text('Player keyboard & mouse'), findsOneWidget);
    expect(
        find.textContaining('Left / Right: seek 10 seconds'), findsOneWidget);
  });
  testWidgets(
      'Touch horizontal swipe seeks and right vertical swipe changes volume',
      (tester) async {
    final state = ValueNotifier(const PlaybackSnapshot(
        position: Duration(seconds: 30),
        duration: Duration(minutes: 5),
        volume: 40));
    addTearDown(state.dispose);
    Duration? seek;
    double? volume;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: AndroidPlayerControls(
      playback: state,
      title: 'Touch fixture',
      shuffle: false,
      repeat: QueueRepeat.off,
      fit: FitMode.fit,
      canPrevious: true,
      canNext: true,
      sleepUntilEnd: true,
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
      onSeek: (value) => seek = value,
      onVolume: (value) => volume = value,
    ))));
    expect(find.text('Sleep · until end'), findsOneWidget);
    await tester.timedDragFrom(const Offset(200, 220), const Offset(200, 0),
        const Duration(milliseconds: 500));
    await tester.pump();
    expect(seek, isNotNull);
    expect(seek!.inSeconds, greaterThan(30));
    await tester.timedDragFrom(const Offset(650, 300), const Offset(0, -100),
        const Duration(milliseconds: 500));
    await tester.pump();
    expect(volume, isNotNull);
    expect(volume!, greaterThan(40));
  });
}
