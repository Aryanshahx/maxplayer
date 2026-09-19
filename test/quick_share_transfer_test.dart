import 'package:flutter_test/flutter_test.dart';

import 'package:maxplayer/services/quick_share_client.dart';
import 'package:maxplayer/services/quick_share_server.dart';

void main() {
  test('manifest round-trip survives index/name/size', () {
    final files = [
      const QuickShareFileEntry(name: 'A.mp4', size: 123, path: '/x/A.mp4'),
      const QuickShareFileEntry(
          name: 'b (weird) [1].mkv', size: 0, path: '/s/b (weird) [1].mkv'),
    ];
    final decoded = decodeQuickShareManifest(encodeQuickShareManifest(files));
    expect(decoded.length, 2);
    expect(decoded[0],
        const RemoteShareFile(index: 0, name: 'A.mp4', size: 123));
    expect(decoded[1],
        const RemoteShareFile(index: 1, name: 'b (weird) [1].mkv', size: 0));
  });

  test('receiver-side address normalization', () {
    expect(QuickShareClient.normalizeBase('192.168.1.5'),
        'http://192.168.1.5:4747');
    expect(QuickShareClient.normalizeBase('http://10.0.0.2:4747/'),
        'http://10.0.0.2:4747');
    expect(() => QuickShareClient.normalizeBase('   '),
        throwsFormatException);
  });

  test('sanitizeShareFileName strips paths and header-breakers', () {
    expect(sanitizeShareFileName('/a/b/clip.mp4'), 'clip.mp4');
    expect(sanitizeShareFileName('C:\\x\\y\\v.mkv'), 'v.mkv');
    expect(sanitizeShareFileName('bad\r\nna"me.mp4'), 'bad__na_me.mp4');
    expect(sanitizeShareFileName(''), 'file');
  });
}
