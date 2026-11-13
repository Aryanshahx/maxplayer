import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:maxplayer/utils/iptv.dart';
import 'package:maxplayer/utils/m3u.dart';

void main() {
  const master =
      '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1000000\nurl_0/hd.m3u8\n#EXT-X-STREAM-INF:BANDWIDTH=200000\nurl_2/ld.m3u8\n';
  final base = Uri.parse('https://example.test/live/index.m3u8?token=fixture');
  test('HLS master variants are one stream, never fake channels', () {
    expect(classifyM3u(master, base).isHls, true);
    expect(classifyM3u(master, base).channels, isEmpty);
    expect(parseM3u(master), isEmpty);
  });
  test('HLS media segments are not channel entries', () {
    const media =
        '#EXTM3U\n#EXT-X-TARGETDURATION:10\n#EXTINF:10,\nsegment001.ts\n#EXT-X-ENDLIST\n';
    expect(classifyM3u(media, base).isHls, true);
    expect(parseM3u(media), isEmpty);
  });
  test('BOM and leading whitespace do not hide HLS markers', () {
    expect(classifyM3u('\uFEFF  $master', base).isHls, true);
  });
  test('IPTV channel list stays a list and resolves relative URLs and logos', () {
    final r = classifyM3u(
      '#EXTM3U\n#EXTINF:-1 tvg-logo="logos/a.png",News\nchannels/news.m3u8\n#EXTINF:-1,Radio\nhttps://other.test/radio\n',
      base,
    );
    expect(r.isHls, false);
    expect(r.channels.length, 2);
    expect(r.channels[0].url, 'https://example.test/live/channels/news.m3u8');
    expect(r.channels[0].logo, 'https://example.test/live/logos/a.png');
    expect(r.channels[1].url, 'https://other.test/radio');
  });
  test('parent and scheme-relative entries resolve as network addresses', () {
    final c = parseM3u(
      '#EXTM3U\n../other/master.m3u8\n//cdn.test/live.m3u8\n',
      baseUri: base,
    );
    expect(c[0].url, 'https://example.test/other/master.m3u8');
    expect(c[1].url, 'https://cdn.test/live.m3u8');
  });
  test('remote playlist cannot turn file/data entries into Android paths', () {
    final c = classifyM3u(
      '#EXTM3U\n#EXTINF:-1,Bad\nfile:///data/private\n#EXTINF:-1,Bad\ndata:text/plain,hello\n',
      base,
    );
    expect(c.channels, isEmpty);
    expect(c.error, isNotNull);
  });
  test('HTML or empty response gives a website/playlist explanation', () {
    for (final body in ['<!doctype html><html>Website</html>', '']) {
      final r = classifyM3u(body, base);
      expect(r.error, contains('not a website'));
      expect(r.channels, isEmpty);
      expect(r.isHls, false);
    }
  });
  test(
    'redirected channel list resolves against final response directory',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final origin = 'http://${server.address.address}:${server.port}';
      final task = server.listen((req) async {
        if (req.uri.path == '/start.m3u') {
          req.response.statusCode = 302;
          req.response.headers.set('location', '/actual/list.m3u');
        } else {
          req.response.write(
            '#EXTM3U\n#EXTINF:-1,Fixture\nrelative/live.m3u8\n',
          );
        }
        await req.response.close();
      });
      try {
        final r = await fetchM3uSource('$origin/start.m3u');
        expect(r.error, isNull);
        expect(r.channels.single.url, '$origin/actual/relative/live.m3u8');
      } finally {
        await task.cancel();
        await server.close(force: true);
      }
    },
  );
  test('fetcher recognises HLS response without exposing variants', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final task = server.listen((req) async {
      req.response.write(master);
      await req.response.close();
    });
    try {
      final r = await fetchM3uSource(
        'http://${server.address.address}:${server.port}/master.m3u8',
      );
      expect(r.isHls, true);
      expect(r.channels, isEmpty);
    } finally {
      await task.cancel();
      await server.close(force: true);
    }
  });
}
