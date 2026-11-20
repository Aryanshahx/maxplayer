import 'dart:convert';
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_player/player/local_ai.dart';

void main() {
  test('Verified downloader reuses cache and rejects changed/corrupt bytes',
      () async {
    final temp = await Directory.systemTemp.createTemp('hyper-ai-test');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var requests = 0;
    var bytes = utf8.encode('fixture model, not executable');
    final expected = sha256.convert(bytes).toString();
    final subscription = server.listen((request) async {
      requests++;
      request.response.add(bytes);
      await request.response.close();
    });
    final job = LocalSpeechJob();
    try {
      final target = File('${temp.path}/model.bin');
      final url = 'http://127.0.0.1:${server.port}/model';
      await job.downloadVerified(url, target, expected, size: bytes.length);
      expect(await target.readAsBytes(), bytes);
      await job.downloadVerified(url, target, expected, size: bytes.length);
      expect(requests, 1);
      await target.writeAsString('tampered');
      await job.downloadVerified(url, target, expected, size: bytes.length);
      expect(requests, 2);
      await target.delete();
      bytes = utf8.encode('corrupt');
      await expectLater(
          job.downloadVerified(url, target, expected), throwsStateError);
      expect(await target.exists(), isFalse);
      expect(await File('${target.path}.partial').exists(), isFalse);
    } finally {
      job.dispose();
      await subscription.cancel();
      await server.close(force: true);
      await temp.delete(recursive: true);
    }
  });
  test('Cancellation never leaves a completed or partial model file', () async {
    final dir = await Directory.systemTemp.createTemp('hyper-ai-cancel');
    final job = LocalSpeechJob()..cancel();
    final target = File('${dir.path}/model.bin');
    try {
      await expectLater(
          job.downloadVerified(
              'https://example.invalid/model', target, '0' * 64),
          throwsStateError);
      expect(await target.exists(), isFalse);
      expect(await File('${target.path}.partial').exists(), isFalse);
    } finally {
      job.dispose();
      await dir.delete(recursive: true);
    }
  });
  test(
      'Tool extraction rejects archive traversal and never writes outside root',
      () async {
    expect(safeArchiveEntry('../outside.exe'), isFalse);
    expect(safeArchiveEntry('C:/outside.exe'), isFalse);
    expect(safeArchiveEntry(r'..\outside.exe'), isFalse);
    expect(safeArchiveEntry('/outside.exe'), isFalse);
    expect(safeArchiveEntry('Release/whisper-cli.exe'), isTrue);
    final root = await Directory.systemTemp.createTemp('hyper-ai-archive');
    try {
      final archive = Archive()..addFile(ArchiveFile('../outside.exe', 1, [1]));
      final zip = File('${root.path}/tool.zip')
        ..writeAsBytesSync(ZipEncoder().encode(archive));
      final destination = Directory('${root.path}/tools')..createSync();
      expect(() => extractSpeechTool(zip.path, destination.path),
          throwsStateError);
      expect(File('${root.path}/outside.exe').existsSync(), isFalse);
    } finally {
      await root.delete(recursive: true);
    }
  });
  test(
      'Large local models are optional separate downloads, not installer assets',
      () {
    expect(speechModels.map((m) => m.name),
        ['base-q5_1', 'base', 'small', 'medium']);
    expect(speechModels.last.bytes, greaterThan(speechModels.first.bytes));
    for (final model in speechModels) {
      expect(model.digest, matches(RegExp(r'^[a-f0-9]{64}$')));
    }
  });
}
