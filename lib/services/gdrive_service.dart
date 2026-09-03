import 'dart:convert';
import 'dart:io';

/// Google Drive item representation.
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

class GDriveException implements Exception {
  final String message;
  const GDriveException(this.message);

  @override
  String toString() => message;
}

/// Service for Google Drive API interaction and streaming link resolution.
class GDriveService {
  static const String clientId =
      '998035561765-4tlp75rcp5549fej391bc8pbj8q3htc0.apps.googleusercontent.com';
  static const String projectId = 'max-player-507121';
  static const String driveReadonlyScope =
      'https://www.googleapis.com/auth/drive.readonly';

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

    // If string is already a standalone ID (20+ URL-safe chars)
    if (RegExp(r'^[a-zA-Z0-9_-]{20,}$').hasMatch(clean)) {
      return clean;
    }

    return null;
  }

  /// Builds the authenticated Google Drive media endpoint for a file id.
  /// The caller supplies OAuth headers when opening it in the player.
  static String getDirectStreamUrl(String fileId) =>
      'https://www.googleapis.com/drive/v3/files/$fileId?alt=media';

  /// Lists ALL accessible video files from Google Drive using OAuth.
  ///
  /// v98: paginates through the whole Drive result set instead of stopping
  /// at the first 50 files, and uses OAuth authorization headers so private
  /// videos work - the old API-key/token text field could not reliably list
  /// or play a user's full personal library.
  static Future<List<GDriveItem>> listDriveFiles({
    required Map<String, String> headers,
  }) async {
    if (headers.isEmpty) {
      throw const GDriveException('Google Drive sign-in is required.');
    }

    final out = <GDriveItem>[];
    final seenIds = <String>{};
    String? pageToken;

    do {
      final uri = Uri.https('www.googleapis.com', '/drive/v3/files', {
        'q': "mimeType contains 'video/' and trashed = false",
        'fields': 'nextPageToken,files(id,name,mimeType,size,thumbnailLink)',
        'pageSize': '1000',
        'orderBy': 'name_natural',
        'spaces': 'drive',
        'includeItemsFromAllDrives': 'true',
        'supportsAllDrives': 'true',
        if (pageToken != null && pageToken.isNotEmpty) 'pageToken': pageToken,
      });

      final req = await _http.getUrl(uri);
      headers.forEach((k, v) => req.headers.set(k, v));
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');

      final res = await req.close().timeout(const Duration(seconds: 20));
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode == 401 || res.statusCode == 403) {
        throw const GDriveException(
          'Google Drive access expired. Please sign in again.',
        );
      }
      if (res.statusCode != 200) {
        throw GDriveException(
          'Google Drive request failed (HTTP ${res.statusCode}).',
        );
      }

      final decoded = jsonDecode(body);
      if (decoded is! Map) {
        throw const GDriveException('Google Drive returned an invalid response.');
      }
      final files = decoded['files'];
      if (files is List) {
        for (final f in files) {
          if (f is! Map) continue;
          final id = '${f['id'] ?? ''}'.trim();
          final name = '${f['name'] ?? ''}'.trim();
          final mime = '${f['mimeType'] ?? ''}'.trim();
          final size = int.tryParse('${f['size'] ?? ''}') ?? 0;
          final thumb = f['thumbnailLink']?.toString();
          if (id.isEmpty || name.isEmpty || !seenIds.add(id)) continue;
          out.add(
            GDriveItem(
              id: id,
              name: name,
              mimeType: mime,
              sizeBytes: size,
              thumbnailLink: thumb,
            ),
          );
        }
      }

      pageToken = decoded['nextPageToken']?.toString();
    } while (pageToken != null && pageToken.isNotEmpty);

    return out;
  }
}
