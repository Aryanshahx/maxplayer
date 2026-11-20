import 'dart:convert';
import 'dart:io';

class StreamChannel {
  final String title, source;
  const StreamChannel(this.title, this.source);
}

List<StreamChannel> parseChannelPlaylist(String text, Uri base) {
  if (text.contains('#EXT-X-')) {
    return [];
  }
  var title = '';
  final channels = <StreamChannel>[];
  for (final raw in const LineSplitter().convert(text)) {
    final line = raw.trim();
    if (line.startsWith('#EXTINF:')) {
      var quoted = false, comma = -1;
      for (var i = 0; i < line.length; i++) {
        if (line[i] == '"') quoted = !quoted;
        if (line[i] == ',' && !quoted) {
          comma = i;
          break;
        }
      }
      title = comma < 0 ? '' : line.substring(comma + 1).trim();
      continue;
    }
    if (line.isEmpty || line.startsWith('#')) continue;
    final uri = base.resolve(line);
    if (!['http', 'https'].contains(uri.scheme) || uri.host.isEmpty) continue;
    channels.add(StreamChannel(
        title.isEmpty
            ? (uri.pathSegments.isEmpty ? uri.host : uri.pathSegments.last)
            : title,
        uri.toString()));
    title = '';
    if (channels.length >= 10000) break;
  }
  return channels;
}

Future<List<StreamChannel>> probeStreamChannels(String source) async {
  if (!['http', 'https'].contains(Uri.parse(source).scheme)) return [];
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  try {
    final request = await client
        .getUrl(Uri.parse(source))
        .timeout(const Duration(seconds: 10));
    request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-2097151');
    final response = await request.close().timeout(const Duration(seconds: 10));
    if (![200, 206].contains(response.statusCode)) {
      // Some actual media endpoints reject probes/ranges; playback may still work.
      return [];
    }
    var base = Uri.parse(source);
    for (final redirect in response.redirects) {
      base = base.resolveUri(redirect.location);
    }
    final bytes = <int>[];
    await for (final chunk in response.timeout(const Duration(seconds: 10))) {
      bytes.addAll(chunk);
      if (bytes.length > 2 * 1024 * 1024) {
        throw const FormatException('Channel playlist exceeds 2 MB.');
      }
      final sample = utf8
          .decode(bytes.take(4096).toList(), allowMalformed: true)
          .replaceFirst('\ufeff', '')
          .trimLeft();
      if (sample.startsWith('#EXTM3U') ||
          sample.startsWith('#EXTINF:') ||
          base.path.toLowerCase().endsWith('.m3u')) {
        if (sample.contains('#EXT-X-')) return [];
      } else if (bytes.length >= 32) {
        if (sample.toLowerCase().startsWith('<!doctype html') ||
            sample.toLowerCase().startsWith('<html')) {
          throw const FormatException(
              'This is a web page, not a direct media/playlist URL.');
        }
        return [];
      }
    }
    return parseChannelPlaylist(
        utf8.decode(bytes, allowMalformed: true).replaceFirst('\ufeff', ''),
        base);
  } on HandshakeException {
    throw const HandshakeException(
        'Certificate could not be verified. Check Windows trusted roots/proxy/time. Unsafe certificates are not accepted.');
  } finally {
    client.close(force: true);
  }
}
