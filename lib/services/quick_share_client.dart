import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../utils/crash_log.dart';
import 'quick_share_server.dart';

/// Receiver side of v1.0.21 direct Quick Share: given a sender address
/// ("192.168.1.5:4747" or a full URL), fetch the manifest and download
/// chosen files with byte progress. The caller then hands the temp file
/// to NativeBridge.saveToGallery so it lands inside the video library.
class QuickShareClient {
  /// Normalizes "192.168.1.5" / "192.168.1.5:4747" / "http://…" into a
  /// base URL the getters can use. Throws FormatException on junk.
  static String normalizeBase(String input) {
    var t = input.trim();
    if (t.isEmpty) throw const FormatException('empty address');
    if (!t.contains('://')) t = 'http://$t';
    final uri = Uri.parse(t);
    if (uri.host.isEmpty) throw const FormatException('no host');
    final port = uri.hasPort ? uri.port : QuickShareSession.kPort;
    return 'http://${uri.host}:$port';
  }

  HttpClient _newClient() => HttpClient()
    ..connectionTimeout = const Duration(seconds: 6)
    ..idleTimeout = const Duration(seconds: 30);

  Future<List<RemoteShareFile>> fetchManifest(String base) async {
    final client = _newClient();
    try {
      final req = await client.getUrl(Uri.parse('$base/manifest.json'));
      final res = await req.close().timeout(const Duration(seconds: 10));
      if (res.statusCode != HttpStatus.ok) {
        throw HttpException('sender replied ${res.statusCode}');
      }
      final body = await res.transform(utf8.decoder).join();
      return decodeQuickShareManifest(body);
    } finally {
      client.close(force: true);
    }
  }

  /// Streams one file into the temp dir and returns its File.
  /// [onProgress] gets (bytesReceived, bytesTotal) per chunk.
  Future<File> download(
    String base,
    RemoteShareFile remote, {
    void Function(int received, int total)? onProgress,
  }) async {
    final client = _newClient();
    IOSink? sink;
    try {
      final req =
          await client.getUrl(Uri.parse('$base/file?i=${remote.index}'));
      final res = await req.close();
      if (res.statusCode != HttpStatus.ok) {
        throw HttpException('sender replied ${res.statusCode}');
      }
      final dir = await getTemporaryDirectory();
      final safeName = sanitizeShareFileName(remote.name);
      final out = File(
          '${dir.path}/qsr_${DateTime.now().millisecondsSinceEpoch}_$safeName');
      sink = out.openWrite();
      var received = 0;
      final total = res.contentLength > 0 ? res.contentLength : remote.size;
      await for (final chunk in res) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
      await sink.flush();
      await sink.close();
      sink = null;
      CrashLog.crumb('quickshare.downloaded',
          {'name': safeName, 'bytes': received});
      return out;
    } catch (e) {
      CrashLog.error('quickshare.download_failed', e);
      rethrow;
    } finally {
      try {
        await sink?.close();
      } catch (_) {}
      client.close(force: true);
    }
  }
}
