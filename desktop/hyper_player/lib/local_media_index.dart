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

/// Only explicitly chosen directories; non-recursive and no symlink traversal.
Future<LocalScan> scanLocalMedia(Iterable<String> paths,
    {int limit = 20000}) async {
  final folders = <String, List<LocalMediaEntry>>{};
  final unavailable = <String>[];
  int count = 0;
  bool truncated = false;
  for (final path in paths.toSet()) {
    final entries = <LocalMediaEntry>[];
    folders[path] = entries;
    try {
      await for (final file in Directory(path).list(followLinks: false)) {
        if (file is! File || !isMediaPath(file.path)) {
          continue;
        }
        if (count >= limit) {
          truncated = true;
          break;
        }
        try {
          final stat = await file.stat();
          entries.add(LocalMediaEntry(file.path, stat.modified, stat.size));
          count++;
        } catch (_) {/* A file may disappear during a scan. */}
      }
      entries.sort((a, b) => labelFor(a.path)
          .toLowerCase()
          .compareTo(labelFor(b.path).toLowerCase()));
    } catch (_) {
      unavailable.add(path);
    }
    if (truncated) {
      break;
    }
  }
  return LocalScan(folders, unavailable, truncated);
}

String mediaSize(int bytes) => bytes >= 1048576
    ? '${(bytes / 1048576).toStringAsFixed(1)} MB'
    : '${(bytes / 1024).toStringAsFixed(0)} KB';
