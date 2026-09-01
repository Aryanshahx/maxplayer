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

  /// v88: set when this item was listed via OAuth sign-in - lets
  /// [streamUrl]/[authHeaders] build an authenticated request for
  /// private files instead of the API-key/public-link fallback.
  final String? oauthAccessToken;

  const GDriveItem({
    required this.id,
    required this.name,
    required this.mimeType,
    this.sizeBytes = 0,
    this.thumbnailLink,
    this.isFolder = false,
    this.oauthAccessToken,
  });

  String get streamUrl => GDriveService.getDirectStreamUrl(
        id,
        accessToken: oauthAccessToken,
      );

  /// Headers to send alongside [streamUrl] when signed in via OAuth -
  /// empty map otherwise (nothing extra needed for public-link URLs).
  Map<String, String> get authHeaders => oauthAccessToken != null
      ? GDriveService.oauthHeaders(oauthAccessToken!)
      : const {};
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
  /// v88: when [accessToken] is provided (OAuth sign-in), the caller must
  /// send it as an `Authorization: Bearer` HEADER (Drive does not accept
  /// OAuth tokens as a URL query param) - see [oauthHeaders]. This method
  /// only builds the URL.
  static String getDirectStreamUrl(String fileId, {String? apiKey, String? accessToken}) {
    if (apiKey != null && apiKey.isNotEmpty) {
      return 'https://www.googleapis.com/drive/v3/files/$fileId?alt=media&key=$apiKey';
    }
    if (accessToken != null && accessToken.isNotEmpty) {
      return 'https://www.googleapis.com/drive/v3/files/$fileId?alt=media';
    }
    return 'https://drive.google.com/uc?export=download&id=$fileId';
  }

  /// v88: HTTP headers to send alongside [getDirectStreamUrl]'s OAuth-mode
  /// URL (pass to media_kit's `Media(httpHeaders: ...)`).
  static Map<String, String> oauthHeaders(String accessToken) =>
      {'Authorization': 'Bearer $accessToken'};

  /// v88: lists video files using a real OAuth access token (from Google
  /// Sign-In) instead of an API key - this is what lets the app see the
  /// signed-in user's own PRIVATE Drive files, which an API key alone
  /// cannot do (API keys only ever see files shared "anyone with the
  /// link"). Same shape as [listDriveFiles], different auth mechanism.
  static Future<List<GDriveItem>> listDriveFilesOAuth({
    required String accessToken,
    String? folderId,
  }) async {
    final token = accessToken.trim();
    if (token.isEmpty) return const [];

    try {
      final q = folderId != null
          ? "'$folderId' in parents and trashed = false"
          : "mimeType contains 'video/' and trashed = false";

      final uri = Uri.https('www.googleapis.com', '/drive/v3/files', {
        'q': q,
        'fields': 'files(id, name, mimeType, size, thumbnailLink)',
        'pageSize': '100',
        'orderBy': 'folder, name',
        'spaces': 'drive',
      });

      final req = await _http.getUrl(uri);
      req.headers.set('Authorization', 'Bearer $token');
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
