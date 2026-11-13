import 'dart:convert';
import 'dart:io';

import 'crash_log.dart';
import 'm3u.dart';
import 'network_headers.dart' show kMaxPlayerUserAgent;
export 'network_headers.dart' show kMaxPlayerUserAgent;

class M3uSource {
  final bool isHls;
  final List<IptvChannel> channels;
  final String? error;
  const M3uSource({this.isHls = false, this.channels = const [], this.error});
}

M3uSource classifyM3u(String body, Uri source) {
  final text = body.replaceFirst('\uFEFF', '').trimLeft();
  if (!text.startsWith('#EXTM3U')) {
    return const M3uSource(
      error:
          'This address did not return an M3U playlist. Use a direct media or playlist link, not a website page.',
    );
  }
  if (isHlsManifest(text)) return const M3uSource(isHls: true);
  final channels = parseM3u(text, baseUri: source);
  return M3uSource(
    channels: channels,
    error: channels.isEmpty
        ? 'No playable network channels found in this playlist.'
        : null,
  );
}

/// Inspect playlist contents, never treat HLS variants/segments as channels.
/// Resolve IPTV entries against the final response URL after redirects.
Future<M3uSource> fetchM3uSource(String url) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
  try {
    final source = Uri.parse(url);
    if (!['http', 'https'].contains(source.scheme) || source.host.isEmpty) {
      return const M3uSource(
        error: 'A network playlist needs an HTTP or HTTPS address.',
      );
    }
    final req = await client
        .getUrl(source)
        .timeout(const Duration(seconds: 20));
    req.headers.set(HttpHeaders.userAgentHeader, kMaxPlayerUserAgent);
    final res = await req.close().timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) {
      return M3uSource(error: 'Playlist host returned HTTP ${res.statusCode}.');
    }
    var finalUri = source;
    for (final redirect in res.redirects) {
      finalUri = finalUri.resolveUri(redirect.location);
    }
    final bytes = <int>[];
    await for (final chunk in res.timeout(const Duration(seconds: 30))) {
      if (bytes.length + chunk.length > 24 * 1024 * 1024) {
        return const M3uSource(
          error: 'Playlist exceeds the 24 MiB safety limit.',
        );
      }
      bytes.addAll(chunk);
    }
    return classifyM3u(utf8.decode(bytes, allowMalformed: true), finalUri);
  } catch (e) {
    CrashLog.error('iptv.fetch_failed', e, {
      'host': Uri.tryParse(url)?.host ?? '',
    });
    return const M3uSource(
      error:
          'Could not fetch this playlist. Check your connection or try again later.',
    );
  } finally {
    client.close(force: true);
  }
}

Future<List<IptvChannel>> fetchM3uChannels(String url) async =>
    (await fetchM3uSource(url)).channels;
