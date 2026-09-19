import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../utils/crash_log.dart';

/// One file offered by a Quick Share send session.
class QuickShareFileEntry {
  const QuickShareFileEntry(
      {required this.name, required this.size, required this.path});

  final String name;
  final int size;
  final String path;
}

/// Pure manifest encoding (unit-tested — the receiver parses exactly this).
String encodeQuickShareManifest(List<QuickShareFileEntry> files) =>
    jsonEncode([
      for (var i = 0; i < files.length; i++)
        {'i': i, 'name': files[i].name, 'size': files[i].size},
    ]);

/// Receiver-side manifest row (unit-tested round-trip).
class RemoteShareFile {
  const RemoteShareFile(
      {required this.index, required this.name, required this.size});

  final int index;
  final String name;
  final int size;

  @override
  bool operator ==(Object other) =>
      other is RemoteShareFile &&
      other.index == index &&
      other.name == name &&
      other.size == size;

  @override
  int get hashCode => Object.hash(index, name, size);
}

/// Pure manifest decoding — tolerant of trailing junk, strict on shape.
List<RemoteShareFile> decodeQuickShareManifest(String body) {
  final raw = jsonDecode(body);
  if (raw is! List) throw const FormatException('manifest is not a list');
  return [
    for (final e in raw)
      if (e is Map)
        RemoteShareFile(
          index: (e['i'] as num).toInt(),
          name: e['name']?.toString() ?? 'file',
          size: (e['size'] as num?)?.toInt() ?? 0,
        ),
  ];
}

/// Basename + header-safe cleanup for the Content-Disposition header.
String sanitizeShareFileName(String path) {
  var base = path.split(RegExp(r'[\\/]')).last.trim();
  base = base.replaceAll(RegExp(r'[\r\n"]'), '_');
  if (base.isEmpty) base = 'file';
  return base;
}

/// Where the receiver should point its client.
String quickShareBaseUrl(String host, int port) => 'http://$host:$port';

/// Pure parser for `Range: bytes=a-b` (single range only — multi-range
/// gets null so we answer a normal 200). Returns [start, endInclusive]
/// clamped to [totalLength], or null when no single range was requested.
/// Browsers issue Range requests for big downloads/streaming; answering
/// 200 to a browser that expected 206 is exactly what made "download
/// takes forever, then restarts" — v1.0.2 fix.
List<int>? parseRangeHeader(String? header, int totalLength) {
  if (header == null || totalLength <= 0) return null;
  final h = header.trim();
  if (!h.startsWith('bytes=') || h.contains(',')) return null;
  final spec = h.substring(6).split('-');
  if (spec.length != 2) return null;
  final a = int.tryParse(spec[0].trim());
  final b = int.tryParse(spec[1].trim());
  if (a == null && b == null) return null;
  if (a == null) {
    // Suffix form "bytes=-N": the LAST N bytes.
    final count = b!;
    if (count <= 0) return null;
    final start = totalLength - count;
    return [start < 0 ? 0 : start, totalLength - 1];
  }
  final end = (b == null || b >= totalLength) ? totalLength - 1 : b;
  if (a > end || a >= totalLength) return null;
  return [a, end];
}

/// In-app direct device-to-device sharing (v1.0.21) — no third-party app
/// needed on either side: this hosts the selected files over HTTP on the
/// local network; the receiver uses Max Player's Receive mode or literally
/// any browser (the / page is plain HTML with download links).
class QuickShareSession {
  QuickShareSession._(
      this._server, this.files, this.hosts, this.onEvent);

  final HttpServer _server;
  final List<QuickShareFileEntry> files;

  /// Candidate IPv4 addresses of this device (wifi/hotspot), best first.
  final List<String> hosts;
  final void Function(String event)? onEvent;

  static const int kPort = 4747;

  StreamSubscription<HttpRequest>? _sub;
  int get port => _server.port;

  static Future<QuickShareSession> start(
    List<QuickShareFileEntry> files, {
    void Function(String event)? onEvent,
  }) async {
    // Port fallback: 4747 can already be held by another share app / a
    // previous zombie session — a blind bind failure used to kill the
    // whole share with an unhelpful error. Try a small range instead.
    HttpServer? server;
    Object? bindError;
    for (var port = kPort; port < kPort + 10; port++) {
      try {
        server = await HttpServer.bind(InternetAddress.anyIPv4, port);
        break;
      } catch (e) {
        bindError = e;
      }
    }
    final srv = server;
    if (srv == null) {
      CrashLog.error('quickshare.bind_failed', '$bindError');
      throw StateError(
          'ports $kPort-${kPort + 9} all busy (close other share apps): $bindError');
    }
    final hosts = await _shareHosts();
    final session = QuickShareSession._(srv, files, hosts, onEvent);
    session._sub = srv.listen(session._serve);
    CrashLog.crumb('quickshare.server_started',
        {'port': srv.port, 'files': files.length, 'hosts': hosts});
    return session;
  }

  /// Best-guess local IPv4s (wifi wlan*/ap* first, then other non-vpn).
  static Future<List<String>> _shareHosts() async {
    final wlan = <String>[];
    final others = <String>[];
    try {
      final ifaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final i in ifaces) {
        final name = i.name.toLowerCase();
        for (final a in i.addresses) {
          if (a.isLoopback) continue;
          final ip = a.address;
          if (name.contains('wlan') ||
              name.contains('ap') ||
              name.contains('wifi')) {
            wlan.add(ip);
          } else if (!name.contains('tun') && !name.contains('ppp')) {
            others.add(ip);
          }
        }
      }
    } catch (e) {
      CrashLog.error('quickshare.ifaces_failed', e);
    }
    return [...wlan, ...others];
  }

  String get primaryUrl =>
      hosts.isEmpty ? 'http://DEVICE-IP:$port' : quickShareBaseUrl(hosts.first, port);

  /// Does this server answer when called through its OWN advertised IP?
  /// true  -> server is fine; an unreachable browser means the receiver is
  ///          on the wrong network / VPN / router client-isolation.
  /// false -> the ROM is blocking it (even) locally — re-toggle Wi-Fi.
  Future<bool> selfTest() async {
    if (hosts.isEmpty) return false;
    final host = hosts.first;
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 3);
    try {
      final req = await client
          .getUrl(Uri.parse('http://$host:$port/healthz'))
          .timeout(const Duration(seconds: 4));
      final res = await req.close().timeout(const Duration(seconds: 4));
      final body = await res.transform(utf8.decoder).join();
      final ok = res.statusCode == 200 && body.trim() == 'ok';
      CrashLog.crumb('quickshare.selftest', {'host': host, 'ok': ok});
      return ok;
    } catch (e) {
      CrashLog.error('quickshare.selftest_failed', e);
      return false;
    } finally {
      client.close();
    }
  }

  Future<void> _serve(HttpRequest req) async {
    final res = req.response;
    try {
      final path = req.uri.path;
      if (path == '/' || path.isEmpty) {
        res.headers.contentType =
            ContentType('text', 'html', charset: 'utf-8');
        res.write(_indexHtml());
        onEvent?.call('served index page to ${req.connectionInfo?.remoteAddress.address}');
      } else if (path == '/manifest.json') {
        res.headers.contentType =
            ContentType('application', 'json', charset: 'utf-8');
        res.write(encodeQuickShareManifest(files));
      } else if (path == '/healthz') {
        // Self-test: the sender's own sheet pings this through the
        // advertised IP to prove the server answers BEFORE we blame the
        // receiver's network for "link not reachable".
        res.write('ok');
      } else if (path == '/file') {
        final i = int.tryParse(req.uri.queryParameters['i'] ?? '') ?? -1;
        if (i < 0 || i >= files.length) {
          res.statusCode = HttpStatus.notFound;
          onEvent?.call('404 bad index $i');
        } else {
          final entry = files[i];
          final f = File(entry.path);
          final len = await f.length();
          final name = sanitizeShareFileName(entry.name);
          // v1.0.2: honor single byte ranges -> 206 partial content, so
          // browsers can resume/progress large downloads instead of
          // restarting from byte 0 (the "takes too long" complaint).
          final range =
              parseRangeHeader(req.headers.value(HttpHeaders.rangeHeader), len);
          final start = range?[0] ?? 0;
          final end = range?[1] ?? (len - 1);
          res.statusCode = range == null
              ? HttpStatus.ok
              : HttpStatus.partialContent;
          res.headers.contentType =
              ContentType('application', 'octet-stream');
          res.headers.contentLength = end - start + 1;
          res.headers.set('Accept-Ranges', 'bytes');
          if (range != null) {
            res.headers.set(
                HttpHeaders.contentRangeHeader, 'bytes $start-$end/$len');
          }
          res.headers.set('Content-Disposition',
              'attachment; filename="$name"; filename*=UTF-8\'\'${Uri.encodeComponent(name)}');
          onEvent?.call(range == null
              ? 'sending $name to ${req.connectionInfo?.remoteAddress.address}'
              : 'sending $name (bytes $start-$end) to ${req.connectionInfo?.remoteAddress.address}');
          await res.addStream(
              range == null ? f.openRead() : f.openRead(start, end + 1));
          onEvent?.call('done $name');
        }
      } else {
        res.statusCode = HttpStatus.notFound;
      }
    } catch (e) {
      CrashLog.error('quickshare.serve_failed', e);
      try {
        res.statusCode = HttpStatus.internalServerError;
      } catch (_) {}
    } finally {
      try {
        await res.close();
      } catch (_) {}
    }
  }

  String _indexHtml() {
    final items = StringBuffer();
    for (var i = 0; i < files.length; i++) {
      final e = files[i];
      final mb = (e.size / (1024 * 1024)).toStringAsFixed(1);
      items.write(
          '<a class="card" href="/file?i=$i" download><div class="n">'
          '${_esc(e.name)}</div><div class="s">$mb MB · tap to download</div></a>');
    }
    return '<!doctype html><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width, initial-scale=1">'
        '<title>Max Player Quick Share</title>'
        '<style>body{font-family:system-ui;background:#0b0b0d;color:#eee;padding:16px}'
        '.card{display:block;background:#18181c;border-radius:14px;padding:14px;'
        'margin:10px 0;text-decoration:none;color:#eee}'
        '.n{font-weight:600;word-break:break-all}.s{color:#9aa;font-size:12px;margin-top:4px}'
        'h1{font-size:18px}.hint{color:#9aa;font-size:12px}</style>'
        '<h1>Max Player — Quick Share</h1>'
        '<p class="hint">${files.length} file(s) — keep the sender screen open until all downloads finish.</p>'
        '$items';
  }

  static String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  Future<void> stop() async {
    await _sub?.cancel();
    await _server.close(force: true);
    CrashLog.crumb('quickshare.server_stopped');
  }
}
