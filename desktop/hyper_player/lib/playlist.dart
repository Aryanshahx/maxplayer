import 'dart:convert';

const mediaExtensions = <String>{
  'mp4',
  'mkv',
  'avi',
  'mov',
  'webm',
  'm4v',
  'ts',
  'mp3',
  'flac',
  'wav',
  'ogg',
  'm4a',
  'aac',
  'wma',
  'wmv',
  'm3u8',
};
bool isMediaPath(String path) =>
    mediaExtensions.contains(path.split('.').last.toLowerCase());
String labelFor(String source) {
  final uri = Uri.tryParse(source);
  if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
    return uri.pathSegments.isEmpty ? uri.host : uri.pathSegments.last;
  }
  return source.replaceAll('\\', '/').split('/').last;
}

bool validStream(String value) {
  final uri = Uri.tryParse(value);
  return uri != null &&
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      uri.host.isNotEmpty;
}

List<String> decodeQueue(String? value) {
  try {
    final decoded = jsonDecode(value ?? '[]');
    if (decoded is! List) return [];
    return decoded.whereType<String>().where((e) => e.isNotEmpty).toList();
  } catch (_) {
    return [];
  }
}
