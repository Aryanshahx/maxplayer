import 'package:flutter_test/flutter_test.dart';

import 'package:maxplayer/utils/amazon_affiliate.dart';
import 'package:maxplayer/utils/tmdb.dart';

void main() {
  group('tmdbWatchHasPrime', () {
    test('prime anywhere (stream/rent/buy) counts', () {
      expect(
          tmdbWatchHasPrime(
              const TmdbWatchInfo(stream: ['Netflix', 'Amazon Prime Video'])),
          isTrue);
      expect(
          tmdbWatchHasPrime(const TmdbWatchInfo(rent: ['Amazon Video'])),
          isTrue);
      expect(
          tmdbWatchHasPrime(
              const TmdbWatchInfo(buy: ['Apple TV', 'Google Play Movies'],
                  stream: ['Amazon Prime Video with Ads'])),
          isTrue);
    });

    test('no prime provider => no CTA (never a dead-end link)', () {
      expect(
          tmdbWatchHasPrime(const TmdbWatchInfo(
              stream: ['Netflix'], buy: ['Apple TV'])),
          isFalse);
      expect(tmdbWatchHasPrime(const TmdbWatchInfo()), isFalse);
    });
  });

  group('amazonPrimeSearchUrl', () {
    test('carries our tag, scoped to Prime store, title+year query', () {
      final uri = Uri.parse(amazonPrimeSearchUrl('3 Idiots', year: 2009));
      expect(uri.host, 'www.amazon.in');
      expect(uri.path, '/s');
      expect(uri.queryParameters['tag'], kAmazonAssociateTag);
      expect(uri.queryParameters['tag'], 'maxplayer0a-21');
      expect(uri.queryParameters['i'], 'instant-video');
      expect(uri.queryParameters['k'], '3 Idiots 2009 movie');
    });

    test('no year => plain title query; whitespace trimmed', () {
      final uri = Uri.parse(amazonPrimeSearchUrl('  Dangal  '));
      expect(uri.queryParameters['k'], 'Dangal movie');
    });
  });
}
