import 'package:flutter_test/flutter_test.dart';

import 'package:maxplayer/services/quick_share_server.dart';

void main() {
  test('typical range "bytes=100-199"', () {
    expect(parseRangeHeader('bytes=100-199', 1000), [100, 199]);
  });

  test('open-ended and over-long ends clamp to length', () {
    expect(parseRangeHeader('bytes=950-', 1000), [950, 999]);
    expect(parseRangeHeader('bytes=0-5000', 1000), [0, 999]);
  });

  test('suffix range "bytes=-100" = last 100 bytes', () {
    expect(parseRangeHeader('bytes=-100', 1000), [900, 999]);
    expect(parseRangeHeader('bytes=-2000', 1000), [0, 999]);
  });

  test('garbage / multi-range / inverted => null (answer 200)', () {
    expect(parseRangeHeader('bytes=500-100', 1000), isNull);
    expect(parseRangeHeader('bytes=0-10,20-30', 1000), isNull);
    expect(parseRangeHeader('items=0-10', 1000), isNull);
    expect(parseRangeHeader('bytes=-', 1000), isNull);
    expect(parseRangeHeader(null, 1000), isNull);
    expect(parseRangeHeader('bytes=0-10', 0), isNull);
  });
}
