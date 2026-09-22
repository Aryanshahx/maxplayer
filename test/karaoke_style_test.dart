import 'package:flutter_test/flutter_test.dart';

import 'package:maxplayer/utils/srt.dart';

void main() {
  List<String> flat(List<SrtCue> cues) =>
      cues.map((c) => c.text).toList(growable: false);

  test('word order preserved + times stay inside the parent cue', () {
    final parent = [SrtCue(1000, 5000, 'one two three four five six seven')];
    final out = karaokeStyleCues(parent); // default groupSize 3
    expect(flat(out), ['one two three', 'four five six', 'seven']);
    expect(out.first.startMs, 1000);
    expect(out.last.endMs, 5000);
    // strictly non-decreasing timeline
    for (var i = 1; i < out.length; i++) {
      expect(out[i].startMs >= out[i - 1].startMs, isTrue);
    }
    for (final c in out) {
      expect(c.endMs > c.startMs, isTrue);
    }
  });

  test('short cues pass through untouched; empty text is dropped', () {
    final tiny = SrtCue(2000, 3000, 'just two');
    final out = karaokeStyleCues([tiny, SrtCue(3000, 4000, '   ')]);
    expect(out, hasLength(1));
    expect(out.single.text, 'just two');
    expect(out.single.startMs, 2000);
    expect(out.single.endMs, 3000);
  });

  test('zero/negative parent duration still yields valid micro-cues', () {
    final out = karaokeStyleCues([SrtCue(900, 900, 'aa bb cc dd')]);
    expect(out, hasLength(2));
    for (final c in out) {
      expect(c.endMs > c.startMs, isTrue);
    }
  });

  test('groupSize 2 respected', () {
    final out = karaokeStyleCues([SrtCue(0, 4000, 'a b c d')], groupSize: 2);
    expect(flat(out), ['a b', 'c d']);
  });
}
