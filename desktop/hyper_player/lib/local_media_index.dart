import 'dart:collection';
import 'dart:io';
import 'playlist.dart';

const audioExtensions = {'mp3', 'flac', 'wav', 'ogg', 'm4a', 'aac', 'wma'};
bool isAudioPath(String path) =>
    audioExtensions.contains(path.split('.').last.toLowerCase());

class LocalMediaEntry {
  final String path;
  final DateTime modified;
  final int bytes;
  const LocalMediaEntry(this.path, this.modified, this.bytes);
}

class LocalScan {
  final Map<String, List<LocalMediaEntry>> folders;
  final List<String> unavailable;
  final bool truncated;
  const LocalScan(this.folders, this.unavailable, this.truncated);
}

/// Scans only chosen roots. Recursive mode visits subdirectories individually so
/// an unreadable folder does not abort siblings; links are never traversed.
Future<LocalScan> scanLocalMedia(Iterable<String> paths,
    {int limit = 20000,
    bool recursive = false,
    int directoryLimit = 100000,
    bool Function()? cancelled,
    void Function(int files, int directories)? onProgress}) async {
  if (limit < 1 || directoryLimit < 1) {
    throw ArgumentError('Positive scan limits required.');
  }
  final folders = <String, List<LocalMediaEntry>>{};
  final unavailable = <String>[];
  final pending = Queue<String>.of(paths.toSet());
  final visited = <String>{};
  int count = 0;
  bool truncated = false;
  while (pending.isNotEmpty) {
    if (cancelled?.call() ?? false) {
      truncated = true;
      break;
    }
    final path = pending.removeFirst();
    final canonical = Directory(path).absolute.uri.normalizePath().toString();
    if (!visited
        .add(Platform.isWindows ? canonical.toLowerCase() : canonical)) {
      continue;
    }
    if (visited.length > directoryLimit) {
      truncated = true;
      break;
    }
    final entries = <LocalMediaEntry>[];
    folders[path] = entries;
    try {
      if (await FileSystemEntity.type(path, followLinks: false) !=
          FileSystemEntityType.directory) {
        unavailable.add(path);
        continue;
      }
      await for (final file in Directory(path)
          .list(followLinks: false)
          .timeout(const Duration(seconds: 10))) {
        if (cancelled?.call() ?? false) {
          truncated = true;
          break;
        }
        if (file is Directory) {
          if (recursive) {
            if (pending.length + visited.length >= directoryLimit) {
              truncated = true;
              break;
            }
            pending.add(file.path);
          }
          continue;
        }
        if (file is! File || !isMediaPath(file.path)) continue;
        if (count >= limit) {
          truncated = true;
          break;
        }
        try {
          final stat = await file.stat();
          entries.add(LocalMediaEntry(file.path, stat.modified, stat.size));
          count++;
          if (count % 100 == 0) onProgress?.call(count, visited.length);
        } catch (_) {/* A file may disappear during a scan. */}
      }
      entries.sort((a, b) => labelFor(a.path)
          .toLowerCase()
          .compareTo(labelFor(b.path).toLowerCase()));
    } catch (_) {
      unavailable.add(path);
    }
    if (truncated) break;
    onProgress?.call(count, visited.length);
    await Future<void>.delayed(Duration.zero);
  }
  return LocalScan(folders, unavailable, truncated);
}

String mediaSize(int bytes) => bytes >= 1048576
    ? '${(bytes / 1048576).toStringAsFixed(1)} MB'
    : '${(bytes / 1024).toStringAsFixed(0)} KB';
