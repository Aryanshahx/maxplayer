import 'package:flutter_test/flutter_test.dart';

import 'package:maxplayer/utils/audio_player.dart';

void main() {
  test('decoder/codec errors get the friendly decode line', () {
    expect(describeAudioEngineError('Error decoding audio'),
        contains('Decode hiccup'));
    expect(describeAudioEngineError('Decoder init failed: xyz'),
        contains('Decode hiccup'));
    expect(describeAudioEngineError('unsupported codec foobar'),
        contains('Decode hiccup'));
  });

  test('stall/timeout family', () {
    expect(describeAudioEngineError('Stream timed out'),
        contains('stopped responding'));
    expect(describeAudioEngineError('unexpected EOF'),
        contains('stopped responding'));
  });

  test('network family passes through a connection line', () {
    expect(
        describeAudioEngineError('SocketException: failed host lookup'),
        contains('Connection problem'));
  });

  test('unknown text passes through; blank gets generic', () {
    expect(describeAudioEngineError('something weird'), 'something weird');
    expect(describeAudioEngineError('   '), 'Playback error');
  });
}
