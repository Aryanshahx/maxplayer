import 'package:flutter_test/flutter_test.dart';
import 'package:maxplayer/services/push_service.dart';

void main() {
  test('push images accept HTTPS URLs independent of host', () {
    expect(
      validPushImage(
        'https://raw.githubusercontent.com/Aryanshahx/maxplayer/notice-images/notices/id.jpg',
      ),
      isTrue,
    );
    expect(validPushImage('https://images.example.org/picture?id=123'), isTrue);
  });
  test('push images reject unsafe or invalid URL schemes', () {
    for (final value in [
      '',
      'http://example.org/x.jpg',
      'file:///tmp/x',
      'data:image/png;base64,abc',
      'https:///x',
      'https://user:pass@example.org/x',
      'javascript:alert(1)',
    ]) {
      expect(validPushImage(value), isFalse, reason: value);
    }
  });
}
