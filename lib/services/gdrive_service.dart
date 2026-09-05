import 'dart:convert';
import 'dart:io';

import 'package:google_sign_in/google_sign_in.dart';

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

  String get streamUrl => GDriveService.authStreamUrl(id);
}

/// v106: native Google Sign-In (google_sign_in v7). No google-services.json -
/// Play Services resolves the SHA-1-registered Android OAuth client at
/// runtime; the web client only travels as serverClientId. Nothing secret is
/// shipped in the app (OAuth client IDs are public identifiers; there is no
/// API key anywhere - Drive calls carry the user's Bearer token).
class GDriveAuth {
  // Web-application OAuth client (Cloud Console -> Credentials).
  static const String webClientId =
      '998035561765-idopfuk6vbo5bkavajiug911s4ceerro.apps.googleusercontent.com';
  static const String driveReadonlyScope =
      'https://www.googleapis.com/auth/drive.readonly';
  static const List<String> scopes = [driveReadonlyScope];

  static bool _ready = false;

  static Future<void> ensureInitialized() async {
    if (_ready) return;
    await GoogleSignIn.instance.initialize(serverClientId: webClientId);
    _ready = true;
  }

  /// Silent re-sign-in after a restart. Null when the user never signed in
  /// (or revoked) - the sheet then shows the Sign-In button.
  static Future<GoogleSignInAccount?> signInSilently() async {
    await ensureInitialized();
    return GoogleSignIn.instance.attemptLightweightAuthentication();
  }

  /// Interactive sign-in + Drive scope grant. Throws on cancel/failure -
  /// the sheet turns that into a readable message.
  static Future<GoogleSignInAccount> signIn() async {
    await ensureInitialized();
    final account = await GoogleSignIn.instance.authenticate();
    await account.authorizationClient.authorizeScopes(scopes);
    return account;
  }

  /// Fresh `Authorization: Bearer ...` headers for Drive REST calls.
  /// Null when the grant is gone - the sheet asks for sign-in again.
  static Future<Map<String, String>?> authHeadersOf(
      GoogleSignInAccount account) async {
    try {
      return await account.authorizationClient.authorizationHeaders(scopes);
    } catch (_) {
      return null;
    }
  }

  /// Revokes the grant and signs out (matches the sheet's Disconnect button).
  static Future<void> signOut() async {
    try {
      await ensureInitialized();
      await GoogleSignIn.instance.disconnect();
    } catch (_) {}
  }
}

/// Service for Google Drive API interaction and streaming link resolution.
class GDriveService {
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

  /// Authenticated streaming URL (the Bearer token travels in the player's
  /// HTTP headers, never in the URL).
  static String authStreamUrl(String fileId) =>
      'https://www.googleapis.com/drive/v3/files/$fileId?alt=media';

  /// Lists video files & folders from Google Drive API v3 using the user's
  /// OAuth headers. Returns null on 401/403 (grant expired - sign in again),
  /// empty list on any other failure.
  static Future<List<GDriveItem>?> listDriveFiles({
    Map<String, String>? headers,
    String? folderId,
  }) async {
    if (headers == null || headers.isEmpty) return const [];

    try {
      final q = folderId != null
          ? "'$folderId' in parents and trashed = false"
          : "mimeType contains 'video/' and trashed = false";

      final uri = Uri.https('www.googleapis.com', '/drive/v3/files', {
        'q': q,
        'fields': 'files(id, name, mimeType, size, thumbnailLink)',
        'pageSize': '50',
        'orderBy': 'folder, name',
      });

      final req = await _http.getUrl(uri);
      headers.forEach((k, v) => req.headers.set(k, v));
      final res = await req.close().timeout(const Duration(seconds: 15));
      if (res.statusCode == 401 || res.statusCode == 403) {
        await res.drain<void>();
        return null;
      }
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
