import 'dart:async';
import 'dart:io';
import 'playlist.dart';

class NetworkBrowseResult {
  final List<String> folders, files;
  final bool truncated;
  const NetworkBrowseResult(this.folders, this.files, this.truncated);
}

/// Enumerates just the directory requested by the user. No recursive scan,
/// symlink following, port scan or credential probing. Windows handles share auth.
Future<NetworkBrowseResult> browseNetworkDirectory(String path,
    {int limit = 5000,
    Duration inactivityTimeout = const Duration(seconds: 12)}) async {
  if (limit < 1 || limit > 20000) throw ArgumentError.value(limit, 'limit');
  final folders = <String>[], files = <String>[];
  var count = 0;
  bool truncated = false;
  await for (final entry
      in Directory(path).list(followLinks: false).timeout(inactivityTimeout)) {
    if (count >= limit) {
      truncated = true;
      break;
    }
    count++;
    if (entry is Directory) folders.add(entry.path);
    if (entry is File && isMediaPath(entry.path)) files.add(entry.path);
  }
  int compare(String a, String b) =>
      labelFor(a).toLowerCase().compareTo(labelFor(b).toLowerCase());
  folders.sort(compare);
  files.sort(compare);
  return NetworkBrowseResult(folders, files, truncated);
}
