import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'playlist.dart';

const maxShareBytes = 10 * 1024 * 1024 * 1024;
String safeShareName(String raw) {
  var name = raw
      .replaceAll('\\', '/')
      .split('/')
      .last
      .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_')
      .trim();
  name = name.replaceAll(RegExp(r'[. ]+$'), '');
  if (name.isEmpty || name == '.' || name == '..') name = 'media';
  if (RegExp(r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)',
          caseSensitive: false)
      .hasMatch(name)) {
    name = '_$name';
  }
  if (name.length > 160) {
    final dot = name.lastIndexOf('.');
    final ext = dot >= 0 && name.length - dot <= 12 ? name.substring(dot) : '';
    name = '${name.substring(0, 140)}$ext';
  }
  return name;
}

class ShareFile {
  final int index, size;
  final String name;
  const ShareFile(this.index, this.name, this.size);
}

class LocalShareSession {
  final HttpServer _server;
  final List<File> _files;
  final List<FileStat> _stats;
  final List<ShareFile> files;
  final String token;
  Timer? _expiry;
  bool closed = false, _sending = false;
  int completed = 0;
  final void Function()? onChanged;
  LocalShareSession._(this._server, this._files, this._stats, this.files,
      this.token, this.onChanged);
  int get port => _server.port;
  String url(String host) =>
      Uri(scheme: 'http', host: host, port: port, path: '/$token/').toString();
  static Future<LocalShareSession> start(List<String> sources,
      {InternetAddress? bind,
      Duration lifetime = const Duration(minutes: 15),
      void Function()? onChanged}) async {
    if (sources.isEmpty || sources.length > 200) {
      throw const FormatException('Select 1–200 media files.');
    }
    final files = <File>[], stats = <FileStat>[], entries = <ShareFile>[];
    for (final source in sources) {
      if (validStream(source) || !isMediaPath(source)) {
        throw const FormatException('Only selected local media can be shared.');
      }
      final file = File(await File(source).resolveSymbolicLinks());
      final stat = await file.stat();
      if (stat.type != FileSystemEntityType.file || stat.size > maxShareBytes) {
        throw const FormatException('File unavailable or larger than 10 GB.');
      }
      entries.add(ShareFile(
          entries.length, safeShareName(labelFor(source)), stat.size));
      files.add(file);
      stats.add(stat);
    }
    final server = await HttpServer.bind(bind ?? InternetAddress.anyIPv4, 0);
    final random = Random.secure();
    final token = base64UrlEncode(List.generate(24, (_) => random.nextInt(256)))
        .replaceAll('=', '');
    final session = LocalShareSession._(
        server, files, stats, List.unmodifiable(entries), token, onChanged);
    server.listen(session._serve, onError: (Object _) {});
    session._expiry = Timer(lifetime, () => session.stop());
    return session;
  }

  Future<void> _serve(HttpRequest request) async {
    final response = request.response;
    response.headers.set('Cache-Control', 'no-store');
    response.headers.set('Referrer-Policy', 'no-referrer');
    response.headers.set('X-Content-Type-Options', 'nosniff');
    response.headers.set('Content-Security-Policy',
        "default-src 'none'; style-src 'unsafe-inline'; frame-ancestors 'none'");
    try {
      final segments =
          request.uri.pathSegments.where((s) => s.isNotEmpty).toList();
      if (closed || segments.isEmpty || segments.first != token) {
        response.statusCode = 404;
        return;
      }
      if (request.method != 'GET' && request.method != 'HEAD') {
        response.statusCode = 405;
        return;
      }
      final origin = request.headers.value('origin');
      if (origin != null) {
        final uri = Uri.tryParse(origin);
        final target = request.requestedUri;
        if (uri == null ||
            uri.host != target.host ||
            uri.port != target.port ||
            uri.scheme != target.scheme) {
          response.statusCode = 403;
          return;
        }
      }
      if (segments.length == 2 && segments[1] == 'manifest.json') {
        response.headers.contentType = ContentType.json;
        if (request.method == 'GET') {
          response.write(jsonEncode([
            for (final file in files)
              {'i': file.index, 'name': file.name, 'size': file.size}
          ]));
        }
      } else if (segments.length == 2 && segments[1] == 'file') {
        final index = int.tryParse(request.uri.queryParameters['i'] ?? '');
        if (index == null || index < 0 || index >= files.length) {
          response.statusCode = 404;
          return;
        }
        if (_sending) {
          response.statusCode = 429;
          return;
        }
        final current = await _files[index].stat();
        if (current.size != _stats[index].size ||
            current.modified != _stats[index].modified ||
            current.type != FileSystemEntityType.file) {
          response.statusCode = 409;
          return;
        }
        final sendingBody = request.method == 'GET';
        if (sendingBody && _sending) {
          response.statusCode = 429;
          return;
        }
        if (sendingBody) _sending = true;
        try {
          response.headers.contentType = ContentType.binary;
          response.headers.set('Content-Disposition',
              "attachment; filename=\"media\"; filename*=UTF-8''${Uri.encodeComponent(files[index].name)}");
          response.contentLength = current.size;
          if (sendingBody) {
            await response.addStream(_files[index].openRead());
            if (!closed) {
              completed++;
              onChanged?.call();
            }
          }
        } finally {
          if (sendingBody) _sending = false;
        }
      } else if (segments.length == 1) {
        response.headers.contentType = ContentType.html;
        if (request.method == 'GET') {
          response.write(
              '<!doctype html><meta name="viewport" content="width=device-width"><title>Hyper Player Quick Share</title><style>body{background:#14141c;color:white;font:16px sans-serif;max-width:800px;margin:40px auto;padding:20px}a{color:#c4b5fd;display:block;padding:14px;border:1px solid #333;border-radius:12px;margin:8px 0}</style><h1>Quick Share</h1><p>Selected files only. Downloads use your browser. This temporary link is private; do not forward it.</p>${files.map((f) => '<a href="file?i=${f.index}" download>${const HtmlEscape().convert(f.name)} · ${f.size} bytes</a>').join()}<p>Local HTTP is not encrypted. Only use on a trusted network.</p>');
        }
      } else {
        response.statusCode = 404;
      }
    } catch (_) {
      try {
        response.statusCode = 500;
      } catch (_) {}
    } finally {
      try {
        await response.close();
      } catch (_) {}
    }
  }

  Future<void> stop() async {
    if (closed) return;
    closed = true;
    _expiry?.cancel();
    await _server.close(force: true);
    onChanged?.call();
  }
}

Uri normalizeShareAddress(String input) {
  var text = input.trim();
  if (!text.contains('://')) text = 'http://$text';
  final uri = Uri.parse(text);
  if (!['http', 'https'].contains(uri.scheme) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment) {
    throw const FormatException(
        'Use the sender’s HTTP(S) address without login details or query parameters.');
  }
  final port = uri.hasPort
      ? uri.port
      : uri.scheme == 'http' && (uri.path.isEmpty || uri.path == '/')
          ? 4747
          : uri.port;
  final path = uri.path.endsWith('/') ? uri.path : '${uri.path}/';
  return uri.replace(port: port, path: path);
}

class ShareCancelled implements Exception {
  const ShareCancelled();
}

class LocalShareClient {
  HttpClient? _active;
  bool _cancelled = false;
  void cancel() {
    _cancelled = true;
    _active?.close(force: true);
  }

  HttpClient _create() {
    if (_active != null) throw StateError('Transfer already active');
    _cancelled = false;
    return _active = HttpClient()
      ..connectionTimeout = const Duration(seconds: 6)
      ..idleTimeout = const Duration(seconds: 20)
      ..autoUncompress = false;
  }

  Future<HttpClientResponse> _get(HttpClient client, Uri uri) async {
    final request = await client.getUrl(uri);
    request.followRedirects = false;
    final response = await request.close().timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw HttpException('Sender response was not OK');
    }
    return response;
  }

  Future<List<ShareFile>> manifest(Uri base) async {
    final client = _create();
    try {
      final response = await _get(client, base.resolve('manifest.json'));
      final bytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 15))) {
        if (bytes.length + chunk.length > 131072) {
          throw const FormatException('Manifest too large');
        }
        bytes.addAll(chunk);
      }
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! List || decoded.length > 200) {
        throw const FormatException('Invalid manifest');
      }
      final seen = <int>{};
      return [for (final row in decoded) _decode(row, seen)];
    } catch (_) {
      if (_cancelled) throw const ShareCancelled();
      rethrow;
    } finally {
      client.close(force: true);
      _active = null;
    }
  }

  ShareFile _decode(Object? value, Set<int> seen) {
    if (value is! Map ||
        value['i'] is! int ||
        value['name'] is! String ||
        value['size'] is! int) {
      throw const FormatException('Invalid file row');
    }
    final int index = value['i'], size = value['size'];
    final String name = value['name'];
    if (index < 0 ||
        index >= 200 ||
        !seen.add(index) ||
        size < 0 ||
        size > maxShareBytes ||
        name.length > 512 ||
        !isMediaPath(name)) {
      throw const FormatException('Unsupported manifest file');
    }
    return ShareFile(index, safeShareName(name), size);
  }

  Future<File> download(Uri base, ShareFile remote, Directory destination,
      {required void Function(int received, int total) onProgress}) async {
    final client = _create();
    RandomAccessFile? output;
    File? partial;
    try {
      if (remote.size < 0 ||
          remote.size > maxShareBytes ||
          !isMediaPath(remote.name)) {
        throw const FormatException('Invalid media');
      }
      final response = await _get(
          client,
          base
              .resolve('file')
              .replace(queryParameters: {'i': '${remote.index}'}));
      if (response.contentLength >= 0 &&
          response.contentLength != remote.size) {
        throw const FormatException('File changed; reload sender list');
      }
      await destination.create(recursive: true);
      final target = File(
          '${destination.path}/${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(0x7fffffff)}-${safeShareName(remote.name)}');
      partial = File('${target.path}.part');
      output = await partial.open(mode: FileMode.writeOnly);
      var received = 0;
      onProgress(0, remote.size);
      await for (final chunk in response.timeout(const Duration(seconds: 20))) {
        if (_cancelled) throw const ShareCancelled();
        received += chunk.length;
        if (received > remote.size) {
          throw const FormatException('Transfer larger than expected');
        }
        await output.writeFrom(chunk);
        onProgress(received, remote.size);
      }
      if (_cancelled) throw const ShareCancelled();
      if (received != remote.size) {
        throw const FormatException('Incomplete transfer');
      }
      await output.flush();
      await output.close();
      output = null;
      if (_cancelled) throw const ShareCancelled();
      return await partial.rename(target.path);
    } catch (_) {
      if (_cancelled) throw const ShareCancelled();
      rethrow;
    } finally {
      try {
        await output?.close();
      } catch (_) {}
      try {
        if (partial != null && await partial.exists()) await partial.delete();
      } catch (_) {}
      client.close(force: true);
      _active = null;
    }
  }
}
