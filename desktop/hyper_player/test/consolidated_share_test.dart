import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_player/local_share.dart';

void main() {
  test(
      'Remote filenames cannot traverse directories or use reserved Windows names',
      () {
    expect(safeShareName('../../movie.mp4'), 'movie.mp4');
    expect(safeShareName(r'C:\private\movie.mp4'), 'movie.mp4');
    expect(safeShareName('CON.mp4'), '_CON.mp4');
    expect(safeShareName('bad\r\nname.mp4'), 'bad__name.mp4');
  });
  test(
      'Address normalization preserves token path and rejects embedded credentials',
      () {
    expect(normalizeShareAddress('192.168.1.5').toString(),
        'http://192.168.1.5:4747/');
    expect(normalizeShareAddress('http://192.168.1.5:5000/secret').toString(),
        'http://192.168.1.5:5000/secret/');
    expect(() => normalizeShareAddress('http://user:pass@host/'),
        throwsFormatException);
    expect(() => normalizeShareAddress('file:///etc/passwd'),
        throwsFormatException);
    expect(() => normalizeShareAddress('http://host/?token=x'),
        throwsFormatException);
  });
  test(
      'Send server exposes only selected files behind a temporary private token',
      () async {
    final root = await Directory.systemTemp.createTemp('hyper-share-');
    addTearDown(() => root.delete(recursive: true));
    final file = File('${root.path}/movie.mp4');
    await file.writeAsString('selected bytes');
    final session = await LocalShareSession.start([file.path],
        bind: InternetAddress.loopbackIPv4);
    addTearDown(session.stop);
    final http = HttpClient();
    addTearDown(() => http.close(force: true));
    final blocked = await (await http.getUrl(
            Uri.parse('http://127.0.0.1:${session.port}/manifest.json')))
        .close();
    expect(blocked.statusCode, 404);
    await blocked.drain<void>();
    final allowed = await (await http
            .getUrl(Uri.parse('${session.url('127.0.0.1')}manifest.json')))
        .close();
    expect(allowed.statusCode, 200);
    expect(allowed.headers.value('cache-control'), 'no-store');
    final entries =
        jsonDecode(await allowed.transform(utf8.decoder).join()) as List;
    expect(entries.single['name'], 'movie.mp4');
    expect(entries.single.containsKey('path'), isFalse);
    expect(session.token.length, greaterThanOrEqualTo(32));
  });
  test(
      'Share client roundtrip downloads exact bytes without overwriting old files',
      () async {
    final root =
        await Directory.systemTemp.createTemp('hyper-share-roundtrip-');
    addTearDown(() => root.delete(recursive: true));
    final file = File('${root.path}/movie.mp4');
    final bytes = List.generate(200000, (i) => i % 251);
    await file.writeAsBytes(bytes);
    final session = await LocalShareSession.start([file.path],
        bind: InternetAddress.loopbackIPv4);
    addTearDown(session.stop);
    final client = LocalShareClient();
    addTearDown(client.cancel);
    final base = normalizeShareAddress(session.url('127.0.0.1'));
    final manifest = await client.manifest(base);
    expect(manifest.single.size, bytes.length);
    final destination = Directory('${root.path}/received');
    final first = await client.download(base, manifest.single, destination,
        onProgress: (_, total) {});
    final second = await client.download(base, manifest.single, destination,
        onProgress: (_, total) {});
    expect(first.path, isNot(second.path));
    expect(await first.readAsBytes(), bytes);
    expect(await second.readAsBytes(), bytes);
  });
  test('Cancel download closes connection and cleans incomplete file',
      () async {
    final root = await Directory.systemTemp.createTemp('hyper-share-cancel-');
    addTearDown(() => root.delete(recursive: true));
    final file = File('${root.path}/movie.mp4');
    await file.writeAsBytes(List.filled(2000000, 7));
    final session = await LocalShareSession.start([file.path],
        bind: InternetAddress.loopbackIPv4);
    addTearDown(session.stop);
    final client = LocalShareClient();
    addTearDown(client.cancel);
    final base = normalizeShareAddress(session.url('127.0.0.1'));
    final manifest = await client.manifest(base);
    final destination = Directory('${root.path}/received');
    await expectLater(
        client.download(base, manifest.single, destination,
            onProgress: (done, total) {
          if (done > 0) client.cancel();
        }),
        throwsA(isA<ShareCancelled>()));
    expect(await destination.list().toList(), isEmpty);
  });
  test(
      'Changed offered source is rejected instead of serving mismatched content',
      () async {
    final root = await Directory.systemTemp.createTemp('hyper-share-changed-');
    addTearDown(() => root.delete(recursive: true));
    final file = File('${root.path}/movie.mp4');
    await file.writeAsString('short');
    final session = await LocalShareSession.start([file.path],
        bind: InternetAddress.loopbackIPv4);
    addTearDown(session.stop);
    await file.writeAsString('much longer changed content');
    final http = HttpClient();
    addTearDown(() => http.close(force: true));
    final response = await (await http
            .getUrl(Uri.parse('${session.url('127.0.0.1')}file?i=0')))
        .close();
    expect(response.statusCode, 409);
    await response.drain<void>();
  });
  test('Invalid manifest indices and oversized files fail before saving',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode([
        {'i': -1, 'name': 'movie.mp4', 'size': maxShareBytes + 1}
      ]));
      await request.response.close();
    });
    final client = LocalShareClient();
    addTearDown(client.cancel);
    await expectLater(
        client.manifest(Uri.parse('http://127.0.0.1:${server.port}/')),
        throwsFormatException);
  });
  test('Expired session stops without any retained public endpoint', () async {
    final root = await Directory.systemTemp.createTemp('hyper-share-expire-');
    addTearDown(() => root.delete(recursive: true));
    final file = File('${root.path}/movie.mp4');
    await file.writeAsString('test');
    final session = await LocalShareSession.start([file.path],
        bind: InternetAddress.loopbackIPv4,
        lifetime: const Duration(milliseconds: 20));
    addTearDown(session.stop);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(session.closed, isTrue);
  });
}
