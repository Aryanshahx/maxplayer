import 'dart:convert';
import 'dart:io';

import 'crash_log.dart';
import 'm3u.dart';

/// Browser-style UA: several playlist/CDN hosts 403-empty the default
/// Dart/11 HttpClient agent (iptv-org mirrors included).
const String kMaxPlayerUserAgent =
    'MaxPlayer/1.0 (Linux; Android) like MX Player';

/// Fetch an M3U playlist URL and return parsed channels.
/// Never throws — returns an empty list on network/parse failure and logs
/// a crash breadcrumb (Open Stream screen shows an inline hint then).
Future<List<IptvChannel>> fetchM3uChannels(String url) async {
  try {
    final client = HttpClient()
      // Big iptv-org index (~5–20 MB) lists need generous limits.
      ..connectionTimeout = const Duration(seconds: 20);
    final req = await client
        .getUrl(Uri.parse(url))
        .timeout(const Duration(seconds: 20));
    req.headers.set(HttpHeaders.userAgentHeader, kMaxPlayerUserAgent);
    final res = await req.close().timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) {
      client.close();
      return [];
    }
    final body = await res
        .transform(utf8.decoder)
        .join()
        .timeout(const Duration(seconds: 90));
    client.close();
    return parseM3u(body);
  } catch (e) {
    CrashLog.error('iptv.fetch_failed', e, {'url': url});
    return [];
  }
}

