import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_player/player/android_controls.dart';
import 'package:hyper_player/player/audio_now_playing.dart';
import 'package:hyper_player/player/queue_order.dart';
import 'package:hyper_player/screens/playback_sheets.dart';

void main() {
  testWidgets('Audio now playing uses Android disc and circular transport',
      (tester) async {
    final state = ValueNotifier(const PlaybackSnapshot(
        duration: Duration(minutes: 3), position: Duration(seconds: 30)));
    addTearDown(state.dispose);
    bool play = false;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: AudioNowPlaying(
                playback: state,
                title: 'Example song',
                index: 1,
                count: 5,
                shuffle: false,
                repeat: QueueRepeat.off,
                canPrevious: true,
                canNext: true,
                onBack: () {},
                onQueue: () {},
                onSettings: () {},
                onPlayPause: () => play = true,
                onPrevious: () {},
                onNext: () {},
                onShuffle: () {},
                onRepeat: () {},
                onSpeed: () {},
                onSeek: (_) {},
                onVolume: (_) {}))));
    expect(find.text('Now playing'), findsOneWidget);
    expect(find.text('2 of 5'), findsOneWidget);
    expect(find.byIcon(Icons.music_note_rounded), findsOneWidget);
    await tester.tap(find.byTooltip('Play'));
    expect(play, isTrue);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Until end is functional when backend callback provided',
      (tester) async {
    bool picked = false;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: SleepTimerSheet(
                    untilEnd: true,
                    onMinutes: (_) {},
                    onEnd: () => picked = true)))));
    await tester.ensureVisible(find.text('Until end'));
    await tester.tap(find.text('Until end'));
    expect(picked, isTrue);
    expect(find.text('Turn off timer'), findsOneWidget);
  });
}
