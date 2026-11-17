import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_player/playlist.dart';
void main() {
  test('Media extensions ignore case', () {
    expect(isMediaPath(r'C:\Videos\Movie.MKV'), isTrue);
    expect(isMediaPath('notes.txt'), isFalse);
  });
  test('Streams must be HTTP(S) with a host', () {
    expect(validStream('https://example.com/live.m3u8'), isTrue);
    expect(validStream('file:///etc/passwd'), isFalse);
    expect(validStream('javascript:alert(1)'), isFalse);
    expect(validStream('https:'), isFalse);
  });
  test('Queue parsing tolerates invalid data', () {
    expect(decodeQueue('bad json'), isEmpty);
    expect(decodeQueue('{}'), isEmpty);
    expect(decodeQueue('["a",1,"",null,"b"]'), ['a', 'b']);
  });
  test('Labels support Windows paths and stream URLs', () {
    expect(labelFor(r'C:\Movies\movie.mp4'), 'movie.mp4');
    expect(labelFor('https://example.com/live.m3u8?token=secret'), 'live.m3u8');
  });
}
