import 'package:flutter_test/flutter_test.dart';

import 'package:maxplayer/utils/audio_player.dart';
import 'package:maxplayer/utils/format.dart';

void main() {
  test('audioNextIndex: linear advance, stop at end (repeat off)', () {
    expect(
        audioNextIndex(
            current: 0, count: 3, shuffle: false, repeat: AudioRepeatMode.off),
        1);
    expect(
        audioNextIndex(
            current: 2, count: 3, shuffle: false, repeat: AudioRepeatMode.off),
        -1);
  });

  test('audioNextIndex: repeat-all wraps, repeat-one sticks, shuffle injected',
      () {
    expect(
        audioNextIndex(
            current: 2, count: 3, shuffle: false, repeat: AudioRepeatMode.all),
        0);
    expect(
        audioNextIndex(
            current: 2, count: 3, shuffle: false, repeat: AudioRepeatMode.one),
        2);
    // Injected RNG returning "same as current" must bounce to the next one
    // so shuffle never replays the current song.
    expect(
        audioNextIndex(
            current: 1,
            count: 3,
            shuffle: true,
            repeat: AudioRepeatMode.all,
            rand: (_) => 1),
        2);
  });

  test('audioPrevIndex: wrap only under repeat-all', () {
    expect(audioPrevIndex(current: 0, count: 3, repeat: AudioRepeatMode.all),
        2);
    expect(audioPrevIndex(current: 0, count: 3, repeat: AudioRepeatMode.off),
        0);
    expect(audioPrevIndex(current: 2, count: 3, repeat: AudioRepeatMode.off),
        1);
  });

  test('formatCountdown: ceil-to-second mm:ss / h:mm:ss', () {
    expect(formatCountdown(const Duration(minutes: 30) - const Duration(
        milliseconds: 1)), '30:00');
    expect(formatCountdown(const Duration(seconds: 125)), '2:05');
    expect(formatCountdown(const Duration(hours: 1, seconds: 10)),
        '1:00:10');
    expect(formatCountdown(Duration.zero), '0:00');
  });
}
