import 'dart:async';
import 'dart:typed_data';
import 'dart:io';


/// Tiny embedded HTTP server that hands the CURRENT video file to the TV.
///
/// DLNA renderers do not receive the video over the control channel - they
/// PULL it from an URL. While casting, the phone runs this server and the
/// TV fetches `http://<phone-ip>:<port>/video.mp4` (plus an optional SRT).
///
/// Range (byte-range) support is mandatory: TVs probe the file, seek with
/// Range headers and open several parallel connections. This server handles
/// one range per request, HEAD probes and keep-alive, all with dart:io so
/// no plugin dependency is added.
class CastFileServer {
  HttpServer? _server;
  String? _videoPath;
  String? _videoMime;
  String? _subsPath;

  bool get isRunning => _server != null;

  /// Base URL once started, e.g. "http://192.168.1.23:45678". Null before.
  String? baseUrl;

  /// Picks the IPv4 address of the interface that can reach the TV network
  /// (prefers Wi-Fi/en*, falls back to the first non-loopback address).
  static Future<String?> localIpV4() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      String? fallback;
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          final ip = addr.address;
          if (ip.startsWith('127.')) continue;
          // Wi-Fi / ethernet-ish interface names first.
          final n = iface.name.toLowerCase();
          final preferred =
              n.startsWith('wlan') || n.startsWith('en') || n.startsWith('eth');
          if (preferred) return ip;
          fallback ??= ip;
        }
      }
      return fallback;
    } catch (_) {
      return null;
    }
  }

  /// Starts serving [videoPath] (and optionally [subsPath]) on a random
  /// port on all interfaces. Returns false when it could not start.
  Future<bool> start({
    required String videoPath,
    required String videoMime,
    String? subsPath,
  }) async {
    await stop();
    try {
      final ip = await localIpV4();
      if (ip == null) return false;
      final server = await HttpServer.bind(
        InternetAddress.anyIPv4,
        0,
        shared: true,
      );
      _server = server;
      _videoPath = videoPath;
      _videoMime = videoMime;
      _subsPath = subsPath;
      baseUrl = 'http://$ip:${server.port}';
      server.listen(_handle, onError: (_) {});
      return true;
    } catch (_) {
      await stop();
      return false;
    }
  }

  String? get videoUrl =>
      _server == null ? null : '$baseUrl/video.mp4';
  String? get subsUrl =>
      _server == null || _subsPath == null ? null : '$baseUrl/subs.srt';

  Future<void> stop() async {
    final s = _server;
    _server = null;
    _videoPath = null;
    _subsPath = null;
    baseUrl = null;
    if (s != null) {
      try {
        await s.close(force: true);
      } catch (_) {}
    }
  }

  Future<void> _handle(HttpRequest req) async {
    try {
      switch (req.uri.path) {
        case '/video.mp4':
          await _serveFile(req, _videoPath!, _videoMime!);
          return;
        case '/subs.srt':
          final p = _subsPath;
          if (p != null) {
            await _serveFile(req, p, 'text/plain; charset=utf-8');
            return;
          }
          break;
      }
      req.response.statusCode = HttpStatus.notFound;
      await req.response.close();
    } catch (_) {
      try {
        await req.response.close();
      } catch (_) {}
    }
  }

  /// Serves [path] honouring a single byte Range. Streams via a buffered
  /// RandomAccessFile so back-to-back 4K reads don't spike memory.
  Future<void> _serveFile(HttpRequest req, String path, String mime) async {
    final file = File(path);
    if (!file.existsSync()) {
      req.response.statusCode = HttpStatus.notFound;
      await req.response.close();
      return;
    }
    final size = await file.length();
    final res = req.response;

    int start = 0;
    int end = size - 1; // inclusive
    var partial = false;

    final rangeHeader = req.headers.value('range');
    if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
      final spec = rangeHeader.substring(6).split(',').first.trim();
      final dash = spec.indexOf('-');
      if (dash >= 0) {
        final fromRaw = spec.substring(0, dash);
        final toRaw = spec.substring(dash + 1);
        if (fromRaw.isEmpty) {
          // "bytes=-N": the last N bytes.
          final n = int.tryParse(toRaw) ?? 0;
          if (n > 0) {
            start = size - n;
            if (start < 0) start = 0;
            partial = true;
          }
        } else {
          final from = int.tryParse(fromRaw);
          if (from != null && from < size) {
            start = from;
            final to = int.tryParse(toRaw);
            if (to != null && to < end) end = to;
            partial = true;
          }
        }
      }
    }

    final length = end - start + 1;
    res.statusCode = partial ? HttpStatus.partialContent : HttpStatus.ok;
    res.headers.set(HttpHeaders.contentTypeHeader, mime);
    res.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    // DLNA flags: OP=01 (range supported). Helps TVs buffer properly.
    res.headers.set(
      'contentFeatures.dlna.org',
      'DLNA.ORG_OP=01;DLNA.ORG_CI=0;DLNA.ORG_FLAGS=01700000000000000000000000000000',
    );
    res.headers.set('transferMode.dlna.org', 'Streaming');
    if (partial) {
      res.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $start-$end/$size',
      );
    }
    res.contentLength = length;

    if (req.method == 'HEAD') {
      await res.close();
      return;
    }

    final raf = await file.open();
    try {
      await raf.setPosition(start);
      const chunk = 256 * 1024;
      var remaining = length;
      while (remaining > 0) {
        final toRead = remaining < chunk ? remaining : chunk;
        // Fresh buffer per chunk: res.add() writes asynchronously, so a
        // reused buffer could be mutated before its flush completed.
        final buf = Uint8List(toRead);
        final got = await raf.readInto(buf, 0, toRead);
        if (got <= 0) break;
        res.add(got == toRead ? buf : buf.sublist(0, got));
        remaining -= got;
        // Let the event loop breathe so the SOAP control channel stays
        // responsive on long pulls.
        await res.flush();
      }
      await res.close();
    } finally {
      try {
        await raf.close();
      } catch (_) {}
    }
  }
}
