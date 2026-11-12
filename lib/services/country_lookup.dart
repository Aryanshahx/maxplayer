import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

String countryCodeFromResponse(String body) {
  try {
    final value = jsonDecode(body);
    if (value is! Map || value['country'] is! String) return '';
    final code = (value['country'] as String).toUpperCase();
    return RegExp(r'^[A-Z]{2}$').hasMatch(code) && !['XX', 'ZZ'].contains(code)
        ? code
        : '';
  } catch (_) {
    return '';
  }
}

/// The provider necessarily sees the connection IP. Only return the country;
/// never retain or forward the provider's `ip` field to Firebase.
Future<String> lookupIpCountry({
  http.Client? client,
  Duration timeout = const Duration(seconds: 5),
}) async {
  final connection = client ?? http.Client();
  try {
    return await (() async {
      final response = await connection.send(
        http.Request('GET', Uri.parse('https://api.country.is/'))
          ..followRedirects = false,
      );
      if (response.statusCode != 200 || (response.contentLength ?? 0) > 4096) {
        return '';
      }
      final bytes = <int>[];
      await for (final chunk in response.stream) {
        if (bytes.length + chunk.length > 4096) return '';
        bytes.addAll(chunk);
      }
      return countryCodeFromResponse(utf8.decode(bytes));
    })().timeout(timeout);
  } catch (_) {
    return '';
  } finally {
    connection.close();
  }
}
