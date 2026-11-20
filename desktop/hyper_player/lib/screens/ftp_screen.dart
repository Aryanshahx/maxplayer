import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../playlist.dart';

String curlConfigValue(String value) {
  if (RegExp(r'[\r\n\x00]').hasMatch(value)) {
    throw const FormatException('Newlines are not permitted');
  }
  return value.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
}

/// Session-only credentials, passed to curl via stdin (not command line/logs).
/// FTPS uses Windows trusted certificates; never permits insecure TLS bypass.
class FtpScreen extends StatefulWidget {
  const FtpScreen({super.key});
  @override
  State<FtpScreen> createState() => _FtpScreenState();
}

class _FtpScreenState extends State<FtpScreen> {
  final host = TextEditingController(),
      port = TextEditingController(text: '21'),
      path = TextEditingController(text: '/'),
      user = TextEditingController(),
      password = TextEditingController();
  bool secure = true, busy = false;
  String? error;
  List<String> entries = [];
  Process? process;
  @override
  void dispose() {
    process?.kill();
    for (final c in [host, port, path, user, password]) {
      c.dispose();
    }
    super.dispose();
  }

  Uri uriFor(String remote) {
    final h = host.text.trim();
    final number = int.tryParse(port.text);
    if (h.isEmpty ||
        RegExp(r'[\s/@\\?#]').hasMatch(h) ||
        number == null ||
        number < 1 ||
        number > 65535) {
      throw const FormatException('Enter a server host and valid port');
    }
    return Uri(
        scheme: 'ftp',
        host: h,
        port: number,
        path: remote.startsWith('/') ? remote : '/$remote');
  }

  Future<String> run(String remote, {File? output}) async {
    if (!Platform.isWindows) throw UnsupportedError('Windows curl is required');
    final uri = uriFor(remote);
    final config = StringBuffer('url = "${curlConfigValue(uri.toString())}"\n');
    config.writeln(
        'user = "${curlConfigValue('${user.text.isEmpty ? 'anonymous' : user.text}:${password.text}')}"');
    final args = [
      '--config',
      '-',
      '--fail',
      '--silent',
      '--show-error',
      '--ftp-pasv',
      '--connect-timeout',
      '15',
      if (secure) '--ssl-reqd',
      if (output == null) '--list-only',
      if (output != null) ...[
        '--max-filesize',
        '5368709120',
        '--output',
        output.path
      ]
    ];
    final child = process = await Process.start('curl.exe', args);
    child.stdin.write(config.toString());
    await child.stdin.close();
    Object? outputError;
    Future<String> readOutput() async {
      final bytes = <int>[];
      await for (final part in child.stdout) {
        if (bytes.length + part.length > 4 * 1024 * 1024) {
          throw StateError(
              'Directory listing is too large; choose a smaller folder');
        }
        bytes.addAll(part);
      }
      return utf8.decode(bytes, allowMalformed: true);
    }

    final out = readOutput().catchError((Object e) {
      outputError = e;
      child.kill();
      return '';
    });
    final err = child.stderr.drain<void>();
    final code = await child.exitCode
        .timeout(Duration(minutes: output == null ? 1 : 120), onTimeout: () {
      child.kill();
      return -1;
    });
    final text = await out;
    await err;
    process = null;
    if (outputError != null) {
      throw StateError('Directory listing exceeded safety limit');
    }
    if (code != 0) {
      throw StateError(
          'FTP/FTPS failed ($code). Check host, credentials, path, firewall and trusted certificates.');
    }
    return text;
  }

  Future<void> list([String? folder]) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final remote = folder ?? path.text;
      final text = await run(remote.endsWith('/') ? remote : '$remote/');
      if (mounted) {
        setState(() {
          path.text = remote;
          entries = const LineSplitter()
              .convert(text)
              .where((e) => e.isNotEmpty && !['.', '..'].contains(e))
              .take(5000)
              .toList();
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> download(String remote) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    File? partial;
    try {
      final dir = await Directory(
              '${(await getTemporaryDirectory()).path}/hyper_network_media')
          .create(recursive: true);
      final name =
          remote.split('/').last.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      partial = File(
          '${dir.path}/${DateTime.now().microsecondsSinceEpoch}-$name.partial');
      await run(remote, output: partial);
      final file = await partial
          .rename(partial.path.replaceFirst(RegExp(r'\.partial$'), ''));
      if (mounted) Navigator.pop(context, file.path);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (partial != null && await partial.exists()) await partial.delete();
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('FTP / FTPS')),
      body: ListView(padding: const EdgeInsets.all(24), children: [
        const Text(
            'FTPS is explicit TLS on port 21 by default (not SFTP). Credentials stay in this page only. Files download locally before playback; allow sufficient disk space. Ordinary FTP is unencrypted. Downloads are limited to 5 GB. Temporary media remains in the app cache until Windows/app cache is cleared.'),
        for (final field in [
          (host, 'Server host'),
          (port, 'Port'),
          (path, 'Folder / remote path'),
          (user, 'Username'),
          (password, 'Password')
        ])
          TextField(
              controller: field.$1,
              enabled: !busy,
              obscureText: field.$1 == password,
              autocorrect: false,
              decoration: InputDecoration(labelText: field.$2)),
        SwitchListTile(
            title: const Text('Require TLS (FTPS)'),
            value: secure,
            onChanged: busy ? null : (v) => setState(() => secure = v)),
        FilledButton(
            onPressed: busy ? null : list,
            child: const Text('Connect / list folder')),
        if (busy) ...[
          const LinearProgressIndicator(),
          TextButton(
              onPressed: () => process?.kill(), child: const Text('Cancel'))
        ],
        if (error != null)
          Text(error!, style: const TextStyle(color: Colors.orange)),
        if (!busy)
          TextButton(
              onPressed: () {
                final parts = path.text.split('/')
                  ..removeWhere((e) => e.isEmpty);
                if (parts.isNotEmpty) parts.removeLast();
                list('/${parts.join('/')}');
              },
              child: const Text('Parent folder')),
        for (final name in entries)
          ListTile(
              leading:
                  Icon(isMediaPath(name) ? Icons.video_file : Icons.folder),
              title: Text(name),
              onTap: busy
                  ? null
                  : () {
                      final remote =
                          '${path.text.replaceFirst(RegExp(r'/+$'), '')}/$name';
                      if (isMediaPath(name)) {
                        download(remote);
                      } else {
                        list(remote);
                      }
                    }),
      ]));
}
