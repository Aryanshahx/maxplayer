import 'dart:convert';
import 'dart:io';

import 'crash_log.dart';
import 'm3u.dart';

/// Fetch an M3U playlist URL and return parsed channels.
/// Never throws — returns an empty list on network/parse failure and logs
/// a crash breadcrumb (Open Stream screen shows an inline hint then).
Future<List<IptvChannel>> fetchM3uChannels(String url) async {
  try {
    final req = await HttpClient()
        .getUrl(Uri.parse(url))
        .timeout(const Duration(seconds: 15));
    final res = await req.close().timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) return [];
    final body =
        await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 20));
    return parseM3u(body);
  } catch (e) {
    CrashLog.error('iptv.fetch_failed', e, {'url': url});
    return [];
  }
}
