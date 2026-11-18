import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hyper_player/desktop_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('Collections persist independently from queue', () async {
    final store = DesktopStore();
    store.favourites.add('movie.mp4');
    store.playlists['Evening'] = ['movie.mp4'];
    await store.record('movie.mp4');
    await store.record('movie.mp4');
    final restored = DesktopStore();
    await restored.load();
    expect(restored.history, ['movie.mp4']);
    expect(restored.favourites, ['movie.mp4']);
    expect(restored.playlists['Evening'], ['movie.mp4']);
  });
  test('M3U relative streams resolve against playlist URL', () {
    expect(
        parseM3u('#EXTM3U\n#EXTINF:-1,News\nchannel/live.m3u8\n',
            Uri.parse('https://example.com/tv/list.m3u')),
        ['https://example.com/tv/channel/live.m3u8']);
  });
  test('Unsafe schemes ignored and HLS manifests are not channels', () {
    expect(
        parseM3u('javascript:alert(1)', Uri.parse('https://example.com/list')),
        isEmpty);
    expect(
        () => parseM3u('#EXT-X-TARGETDURATION:10\npart.ts',
            Uri.parse('https://example.com/live.m3u8')),
        throwsFormatException);
  });
  test('Corrupt collections do not break loading', () async {
    SharedPreferences.setMockInitialValues({'hyper.collections.v1': 'broken'});
    final store = DesktopStore();
    await store.load();
    expect(store.history, isEmpty);
  });
}
