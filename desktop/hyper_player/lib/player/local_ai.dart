import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class SpeechModel {
  final String name, digest;
  final int bytes;
  const SpeechModel(this.name, this.bytes, this.digest);
}

const speechModels = [
  SpeechModel('base', 147951465,
      '60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe'),
  SpeechModel('small', 487601967,
      '1be3a9b2063867b937e64e2ec7483364a79917e157fa98c5d94b5c1fffea987b'),
  SpeechModel('medium', 1533763059,
      '6c14d5adee5f86394037b4e4e8b59f1673b6cee10e3cf0b11bbdbee79c156208'),
];
bool safeArchiveEntry(String name) =>
    !p.posix.isAbsolute(name) &&
    !name.contains('\\') &&
    !name.split('/').contains('..') &&
    !name.contains(':');

void extractSpeechTool(String archivePath, String destination) {
  final input = InputFileStream(archivePath);
  try {
    final zip = ZipDecoder().decodeStream(input);
    var expanded = 0;
    if (zip.length > 20000) throw StateError('Too many archive entries');
    for (final entry in zip) {
      if (!safeArchiveEntry(entry.name) || entry.isSymbolicLink) {
        throw StateError('Unsafe archive entry');
      }
      expanded += entry.size;
      if (expanded > 1024 * 1024 * 1024) {
        throw StateError('Tool archive too large');
      }
      if (!entry.isFile) continue;
      final file = File(p.join(destination, entry.name));
      file.parent.createSync(recursive: true);
      final output = OutputFileStream(file.path);
      try {
        entry.writeContent(output);
      } finally {
        output.closeSync();
      }
    }
  } finally {
    input.closeSync();
  }
}

/// Entirely opt-in local processing. Models/tools are never shipped in installer.
/// All executable archives and models require SHA-256 verification before use.
class LocalSpeechJob extends ChangeNotifier {
  bool busy = false, cancelled = false;
  String status = 'Ready';
  Process? _process;
  HttpClient? _http;
  void report(String text) {
    status = text;
    notifyListeners();
  }

  void cancel() {
    cancelled = true;
    _http?.close(force: true);
    _process?.kill();
  }

  void check() {
    if (cancelled) throw StateError('Cancelled');
  }

  Future<Directory> get root async => Directory(
      p.join((await getApplicationSupportDirectory()).path, 'local-ai-v1'))
    ..createSync(recursive: true);

  @visibleForTesting
  Future<File> downloadVerified(String url, File target, String expected,
      {int? size}) async {
    if (await target.exists()) {
      report('Checking cached ${p.basename(target.path)}');
      if ((await sha256.bind(target.openRead()).first).toString() == expected) {
        return target;
      }
      await target.delete();
    }
    check();
    final temp = File('${target.path}.partial');
    final client =
        _http = HttpClient()..connectionTimeout = const Duration(seconds: 30);
    IOSink? sink;
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      if (response.statusCode != 200) {
        throw HttpException('Download returned ${response.statusCode}');
      }
      sink = temp.openWrite();
      var received = 0, last = 0;
      await for (final chunk in response.timeout(const Duration(seconds: 60))) {
        check();
        received += chunk.length;
        if (size != null && received > size) {
          throw StateError('Unexpected download size');
        }
        sink.add(chunk);
        if (received - last > 1024 * 1024) {
          last = received;
          report(
              'Downloading ${p.basename(target.path)}: ${(received / 1048576).toStringAsFixed(0)} MB');
        }
      }
      await sink.close();
      sink = null;
      check();
      if (size != null && received != size) {
        throw StateError('Incomplete download');
      }
      if ((await sha256.bind(temp.openRead()).first).toString() != expected) {
        throw StateError('SHA-256 mismatch. File will not be used.');
      }
      return await temp.rename(target.path);
    } finally {
      await sink?.close();
      client.close(force: true);
      _http = null;
      if (await temp.exists()) await temp.delete();
    }
  }

  Future<File> _tool(Directory dir, String name, String url, String digest,
      String executable) async {
    final archive = await downloadVerified(
        url, File(p.join(dir.path, '$name.zip')), digest);
    final target = Directory(p.join(dir.path, name));
    // Re-extract from a verified archive each job. Never trust an old executable.
    if (await target.exists()) await target.delete(recursive: true);
    await target.create(recursive: true);
    report('Preparing $name');
    check();
    final zipPath = archive.path, targetPath = target.path;
    await Isolate.run(() => extractSpeechTool(zipPath, targetPath));
    check();
    final matches = await target
        .list(recursive: true, followLinks: false)
        .where(
            (e) => e is File && p.basename(e.path).toLowerCase() == executable)
        .toList();
    if (matches.length != 1) {
      throw StateError('Expected $executable was not in tool archive');
    }
    return File(matches.single.path);
  }

  Future<void> _run(File executable, List<String> args) async {
    check();
    final process = _process = await Process.start(executable.path, args,
        workingDirectory: executable.parent.path);
    if (cancelled) process.kill();
    final logs = <String>[];
    void log(String line) {
      if (logs.length >= 12) logs.removeAt(0);
      logs.add(line);
    }

    final out = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(log);
    final err = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(log);
    try {
      final code = await process.exitCode;
      check();
      if (code != 0) {
        throw StateError('Local tool failed ($code): ${logs.join('\n')}');
      }
    } finally {
      await out.cancel();
      await err.cancel();
      _process = null;
    }
  }

  Future<String> transcribe(String source, SpeechModel model,
      {bool translate = false}) async {
    if (busy) throw StateError('An AI job is already running');
    if (!Platform.isWindows) {
      throw UnsupportedError('Windows x64 local AI tools required');
    }
    if (Uri.tryParse(source)?.hasScheme == true &&
        !RegExp(r'^[A-Za-z]:[\\/]').hasMatch(source)) {
      throw StateError('Open a local media file first');
    }
    if (!await File(source).exists()) {
      throw StateError('Local media is unavailable');
    }
    busy = true;
    cancelled = false;
    report('Preparing optional local AI');
    Directory? work;
    try {
      final dir = await root;
      final whisper = await _tool(
          dir,
          'whisper-1.8.3',
          'https://github.com/ggml-org/whisper.cpp/releases/download/v1.8.3/whisper-bin-x64.zip',
          'd824b1e37599f882b396e73f1ee0bfd5d0529f700314c48311dcbd00b803321d',
          'whisper-cli.exe');
      final ffmpeg = await _tool(
          dir,
          'ffmpeg-7.1.1',
          'https://github.com/GyanD/codexffmpeg/releases/download/7.1.1/ffmpeg-7.1.1-essentials_build.zip',
          '04861d3339c5ebe38b56c19a15cf2c0cc97f5de4fa8910e4d47e5e6404e4a2d4',
          'ffmpeg.exe');
      final weights = await downloadVerified(
          'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-${model.name}.bin',
          File(p.join(dir.path, 'ggml-${model.name}.bin')),
          model.digest,
          size: model.bytes);
      work = await Directory(p.join(dir.path, 'jobs'))
          .create(recursive: true)
          .then((d) => d.createTemp('speech-'));
      final wav = p.join(work!.path, 'audio.wav');
      report('Extracting local audio. Cancel is available.');
      await _run(ffmpeg, [
        '-nostdin',
        '-hide_banner',
        '-loglevel',
        'error',
        '-i',
        source,
        '-vn',
        '-ac',
        '1',
        '-ar',
        '16000',
        '-c:a',
        'pcm_s16le',
        wav
      ]);
      report(
          'Transcribing with ${model.name}. Larger models can take much longer than playback on CPU.');
      final output = p.join(work.path, 'subtitles');
      await _run(whisper, [
        '-m',
        weights.path,
        '-f',
        wav,
        '-l',
        'auto',
        '-osrt',
        '-of',
        output,
        if (translate) '-tr'
      ]);
      final generated = File('$output.srt');
      if (!await generated.exists() || await generated.length() == 0) {
        throw StateError('No subtitle output was generated');
      }
      final saved = await Directory(p.join(dir.path, 'subtitles'))
          .create(recursive: true);
      final destination =
          p.join(saved.path, '${DateTime.now().microsecondsSinceEpoch}.srt');
      await generated.copy(destination);
      report('Subtitles generated locally');
      return destination;
    } finally {
      busy = false;
      if (work != null && await work.exists()) {
        await work.delete(recursive: true);
      }
      notifyListeners();
    }
  }
}
