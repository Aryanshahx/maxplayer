import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_player/stream_probe.dart';
import 'package:hyper_player/playlist.dart';
import 'package:hyper_player/player/local_ai.dart';
import 'package:hyper_player/screens/ftp_screen.dart';

void main() {
  test('IPTV parser preserves channel names, relative URLs and quoted commas',
      () {
    final channels = parseChannelPlaylist(
        '#EXTM3U\n#EXTINF:-1 tvg-logo="https://example.com/a,b.png",News HD\nchannel/live.m3u8\n#EXTINF:-1,Sports\nhttps://media.example/sports\n',
        Uri.parse('https://example.com/list/playlist.m3u'));
    expect(channels.map((c) => c.title), ['News HD', 'Sports']);
    expect(channels.first.source, 'https://example.com/list/channel/live.m3u8');
    expect(
        parseChannelPlaylist(
            '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1000\nlow/index.m3u8',
            Uri.parse('https://example.com/')),
        isEmpty);
    expect(
        parseChannelPlaylist(
            '#EXTM3U\nfile:///private.txt\njavascript:alert(1)',
            Uri.parse('https://example.com/')),
        isEmpty);
  });
  test('Real HTTP probe loads channel playlists, but plays HLS/media directly',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final subscription = server.listen((request) async {
      switch (request.uri.path) {
        case '/channels':
          request.response.write('#EXTM3U\n#EXTINF:-1,News\nnews.m3u8\n');
        case '/hls':
          request.response.write(
              '#EXTM3U\n#EXT-X-TARGETDURATION:10\n#EXTINF:10,\nsegment.ts\n');
        case '/movie':
          request.response.add(List.filled(256, 0));
        case '/page':
          request.response
              .write('<!DOCTYPE html><html>Not a video page</html>');
      }
      await request.response.close();
    });
    final root = 'http://127.0.0.1:${server.port}';
    try {
      final channels = await probeStreamChannels('$root/channels');
      expect(channels.single.title, 'News');
      expect(channels.single.source, '$root/news.m3u8');
      expect(await probeStreamChannels('$root/hls'), isEmpty);
      expect(await probeStreamChannels('$root/movie'), isEmpty);
      await expectLater(
          probeStreamChannels('$root/page'), throwsFormatException);
      expect(await probeStreamChannels('rtsp://example.invalid/live'), isEmpty);
    } finally {
      await subscription.cancel();
      await server.close(force: true);
    }
  });
  test('Supported stream schemes exclude scripts and local-file masquerades',
      () {
    for (final scheme in [
      'http',
      'https',
      'rtsp',
      'rtmp',
      'rtmps',
      'udp',
      'rtp'
    ]) {
      expect(validStream('$scheme://example.com/live'), isTrue);
    }
    expect(validStream('javascript:alert(1)'), isFalse);
    expect(validStream('file:///C:/private'), isFalse);
  });
  test(
      'Windows download fallback never disables certificates or permits insecure redirects',
      () {
    final args = windowsSecureDownloadArgs(
        'https://example.com/model.bin', r'C:\cache with spaces\model.partial');
    expect(args, isNot(contains('--insecure')));
    expect(args, isNot(contains('-k')));
    expect(args[args.indexOf('--proto') + 1], '=https');
    expect(args[args.indexOf('--proto-redir') + 1], '=https');
    expect(args[args.indexOf('--output') + 1],
        r'C:\cache with spaces\model.partial');
    expect(() => windowsSecureDownloadArgs('http://example.com/model', 'out'),
        throwsFormatException);
  });
  test('Android-like speech settings actually change inference arguments', () {
    final args = whisperArguments('model.bin', 'audio.wav', 'subtitle',
        language: 'hi', translate: true, karaokeStyle: true);
    expect(args[args.indexOf('-l') + 1], 'hi');
    expect(args, containsAll(['-tr', '-sow', '-ml', '-osrt']));
    expect(whisperArguments('model', 'audio', 'out'), isNot(contains('-tr')));
    expect(() => whisperArguments('model', 'audio', 'out', language: '--bad'),
        throwsFormatException);
  });
  test(
      'FTP stdin config escapes quotes/backslashes and rejects injected commands',
      () {
    expect(curlConfigValue('a"b\\c'), 'a\\"b\\\\c');
    expect(() => curlConfigValue('user\noutput="other-file"'),
        throwsFormatException);
    expect(() => curlConfigValue('password\r\n'), throwsFormatException);
    expect(utf8.encode(curlConfigValue('normal-password')), isNotEmpty);
  });
}
