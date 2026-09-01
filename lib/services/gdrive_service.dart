import 'dart:convert';
import 'dart:io';

/// Google Drive item representation (file or folder).
class GDriveItem {
  final String id;
  final String name;
  final String mimeType;
  final int sizeBytes;
  final String? thumbnailLink;
  final bool isFolder;

  const GDriveItem({
    required this.id,
    required this.name,
    required this.mimeType,
    this.sizeBytes = 0,
    this.thumbnailLink,
    this.isFolder = false,
  });

  String get streamUrl => GDriveService.getDirectStreamUrl(id);
}

/// Service for Google Drive API interaction and streaming link resolution.
class GDriveService {
  static const String clientId =
      '998035561765-4tlp75rcp5549fej391bc8pbj8q3htc0.apps.googleusercontent.com';
  static const String projectId = 'max-player-507121';

  static final HttpClient _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 12)
    ..idleTimeout = const Duration(seconds: 10);

  /// Extracts Google Drive File ID from standard Drive web URLs.
  static String? parseDriveFileId(String url) {
    final clean = url.trim();
    if (clean.isEmpty) return null;

    // Pattern 1: /file/d/<id>/...
    final fileMatch = RegExp(r'/file/d/([a-zA-Z0-9_-]+)').firstMatch(clean);
    if (fileMatch != null) return fileMatch.group(1);

    // Pattern 2: id=<id>
    final idMatch = RegExp(r'[?&]id=([a-zA-Z0-9_-]+)').firstMatch(clean);
    if (idMatch != null) return idMatch.group(1);

    // Pattern 3: /d/<id>
    final dMatch = RegExp(r'/d/([a-zA-Z0-9_-]+)').firstMatch(clean);
    if (dMatch != null) return dMatch.group(1);

    // If string is already a standalone ID (25-45 alphanumeric chars)
    if (RegExp(r'^[a-zA-Z0-9_-]{20,}$').hasMatch(clean)) {
      return clean;
    }

    return null;
  }

  /// Builds a direct streaming/download URL for a Google Drive file ID.
  static String getDirectStreamUrl(String fileId, {String? apiKey, String? accessToken}) {
    if (apiKey != null && apiKey.isNotEmpty) {
      return 'https://www.googleapis.com/drive/v3/files/$fileId?alt=media&key=$apiKey';
    }
    return 'https://drive.google.com/uc?export=download&id=$fileId';
  }

  /// Lists video files & folders from Google Drive API v3.
  static Future<List<GDriveItem>> listDriveFiles({
    required String apiKey,
    String? folderId,
  }) async {
    final key = apiKey.trim();
    if (key.isEmpty) return const [];

    try {
      final q = folderId != null
          ? "'$folderId' in parents and trashed = false"
          : "mimeType contains 'video/' and trashed = false";

      final uri = Uri.https('www.googleapis.com', '/drive/v3/files', {
        'key': key,
        'q': q,
        'fields': 'files(id, name, mimeType, size, thumbnailLink)',
        'pageSize': '50',
        'orderBy': 'folder, name',
      });

      final req = await _http.getUrl(uri);
      final res = await req.close().timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) {
        await res.drain<void>();
        return const [];
      }

      final body = await res.transform(utf8.decoder).join();
      final decoded = jsonDecode(body);
      if (decoded is! Map) return const [];
      final files = decoded['files'];
      if (files is! List) return const [];

      final out = <GDriveItem>[];
      for (final f in files) {
        if (f is! Map) continue;
        final id = '${f['id'] ?? ''}'.trim();
        final name = '${f['name'] ?? ''}'.trim();
        final mime = '${f['mimeType'] ?? ''}'.trim();
        final size = int.tryParse('${f['size'] ?? ''}') ?? 0;
        final thumb = f['thumbnailLink']?.toString();
        final isFold = mime == 'application/vnd.google-apps.folder';

        if (id.isNotEmpty && name.isNotEmpty) {
          out.add(GDriveItem(
            id: id,
            name: name,
            mimeType: mime,
            sizeBytes: size,
            thumbnailLink: thumb,
            isFolder: isFold,
          ));
        }
      }
      return out;
    } catch (_) {
      return const [];
    }
  }
}
