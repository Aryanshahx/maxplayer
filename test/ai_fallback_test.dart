import 'package:flutter_test/flutter_test.dart';

import 'package:maxplayer/utils/ai.dart';

void main() {
  test('no key in the build => no-key (rebuild hint, not "offline")', () {
    expect(
        aiFallbackReason(
            keyEmpty: true, httpStatuses: const [401], exceptionCount: 0),
        'no-key');
  });

  test('every model threw (DNS/socket) => offline', () {
    expect(
        aiFallbackReason(
            keyEmpty: false, httpStatuses: const [], exceptionCount: 6),
        'offline');
  });

  test('401 anywhere in the chain beats other codes', () {
    expect(
        aiFallbackReason(
            keyEmpty: false, httpStatuses: const [429, 401, 503],
            exceptionCount: 2),
        'http-401');
  });

  test('402 / 429 surfaced distinctly; unknown codes pass through', () {
    expect(
        aiFallbackReason(
            keyEmpty: false, httpStatuses: const [402], exceptionCount: 7),
        'http-402');
    expect(
        aiFallbackReason(
            keyEmpty: false, httpStatuses: const [429, 503], exceptionCount: 0),
        'http-429');
    expect(
        aiFallbackReason(
            keyEmpty: false, httpStatuses: const [503, 500], exceptionCount: 0),
        'http-503');
  });
}
