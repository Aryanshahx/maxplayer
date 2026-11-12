import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:maxplayer/services/country_lookup.dart';

void main() {
  test('extracts only country, not IP', () {
    expect(
      countryCodeFromResponse('{"ip":"203.0.113.1","country":"IN"}'),
      'IN',
    );
  });
  test('rejects missing, unknown and malformed countries', () {
    for (final body in [
      '{}',
      'null',
      '[]',
      'not json',
      '{"country":"ZZ"}',
      '{"country":"IND"}',
      '{"country":7}',
    ]) {
      expect(countryCodeFromResponse(body), '');
    }
  });
  test('requests IP country endpoint and returns code', () async {
    final client = MockClient((request) async {
      expect(request.url.toString(), 'https://api.country.is/');
      expect(request.followRedirects, isFalse);
      return http.Response('{"country":"US","ip":"203.0.113.1"}', 200);
    });
    expect(await lookupIpCountry(client: client), 'US');
  });
  test('rate limit and offline return unknown, not locale fallback', () async {
    expect(
      await lookupIpCountry(
        client: MockClient((_) async => http.Response('limit', 429)),
      ),
      '',
    );
    expect(
      await lookupIpCountry(
        client: MockClient((_) async => throw http.ClientException('offline')),
      ),
      '',
    );
  });
  test('caps response size', () async {
    expect(
      await lookupIpCountry(
        client: MockClient((_) async => http.Response('x' * 4097, 200)),
      ),
      '',
    );
  });
  test('country request has a bounded timeout', () async {
    expect(
      await lookupIpCountry(
        client: MockClient((_) async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          return http.Response('{"country":"IN"}', 200);
        }),
        timeout: const Duration(milliseconds: 5),
      ),
      '',
    );
  });
}
