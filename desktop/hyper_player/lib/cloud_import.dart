import 'dart:io';
import 'dart:math';
import 'playlist.dart';

class ImportCancelled implements Exception {
  const ImportCancelled();
}

class ImportCancellation {
  bool cancelled = false;
  void cancel() => cancelled = true;
  void check() {
    if (cancelled) throw const ImportCancelled();
  }
}

/// Bounded-memory local copy. Cloud hydration/sign-in belongs to the provider /
/// Windows picker; this operation never accepts passwords or uploads media.
Future<File> importVideoFile(File source, Directory library,
    {required ImportCancellation cancellation,
    required void Function(int done, int total) onProgress}) async {
  cancellation.check();
  final stat = await source.stat();
  if (stat.type != FileSystemEntityType.file) {
    throw const FileSystemException('Selected source is not a file.');
  }
  await library.create(recursive: true);
  var name =
      labelFor(source.path).replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_');
  if (name.isEmpty) name = 'video';
  if (name.length > 140) {
    final dot = name.lastIndexOf('.');
    final ext = dot >= 0 && name.length - dot <= 12 ? name.substring(dot) : '';
    name = '${name.substring(0, 120)}$ext';
  }
  final id =
      '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(0x7fffffff)}';
  final target = File('${library.path}/$id-$name');
  final partial = File('${target.path}.part');
  RandomAccessFile? output;
  try {
    cancellation.check();
    output = await partial.open(mode: FileMode.writeOnly);
    var done = 0;
    onProgress(0, stat.size);
    await for (final chunk in source.openRead()) {
      cancellation.check();
      await output.writeFrom(chunk);
      done += chunk.length;
      onProgress(done, stat.size);
    }
    cancellation.check();
    if (done != stat.size) {
      throw const FileSystemException(
          'Source changed during import. Please retry.');
    }
    await output.flush();
    await output.close();
    output = null;
    cancellation.check();
    return await partial.rename(target.path);
  } catch (_) {
    await output?.close();
    if (await partial.exists()) await partial.delete();
    rethrow;
  }
}
