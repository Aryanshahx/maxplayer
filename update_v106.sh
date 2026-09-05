#!/bin/bash
# v106: native Google Sign-In for Cloud Storage (Drive), replacing the
# manual access-token paste. Flat video list + search + authed streaming stay.
# No google-services.json needed: Play Services resolves the SHA-1-registered
# OAuth client at runtime; the web client ID is passed as serverClientId.
# CONSOLE CHECKLIST (one time, Cloud Console project max-player-507121):
#   - Drive API enabled; OAuth consent screen has the
#     .../auth/drive.readonly scope (Drive shows an "unverified app" warning
#     until Google verifies it - normal for personal/side-loaded builds).
#   - Android OAuth clients exist for the debug key + Play signing key.
set -eu
cd "$(dirname "$0")"

python3 <<'PYEOF'
import sys

def rep(path, old, new, count=1):
    with open(path, 'r', encoding='utf-8') as f:
        src = f.read()
    n = src.count(old)
    if n != count:
        print(f'PATCH FAILED: {path}: expected {count}x, found {n}x')
        print('--- wanted old text (first 400 chars) ---')
        print(old[:400])
        sys.exit(1)
    with open(path, 'w', encoding='utf-8') as f:
        f.write(src.replace(old, new))
    print(f'patched ({n}x): {path}')

# ------------------------------------------------- version + deps
rep('pubspec.yaml', 'version: 1.0.0+105', 'version: 1.0.0+106')
rep('pubspec.yaml',
    "  permission_handler: ^11.3.1\n",
    """  permission_handler: ^11.3.1

  # v106: native Google Sign-In for Drive (no google-services.json - the
  # SHA-1-registered OAuth client resolves via Play Services at runtime).
  google_sign_in: ^7.2.0
""")
# v106: google_sign_in (Credential Manager) needs minSdk 24+ (Android 7.0).
rep('android/app/build.gradle.kts',
    "        minSdk = flutter.minSdkVersion",
    "        minSdk = 24 // v106: google_sign_in needs 24+")

# ------------------------------------------------- VideoTrack carries auth headers
rep('lib/models/video_track.dart',
    """  final int? width; // pixels, from native metadata
  final int? height;
""",
    """  final int? width; // pixels, from native metadata
  final int? height;
  /// v106: HTTP headers for authed streams (Google Drive Bearer token).
  /// Null for local files and open streams.
  final Map<String, String>? httpHeaders;
""")
rep('lib/models/video_track.dart',
    """    this.width,
    this.height,
  });""",
    """    this.width,
    this.height,
    this.httpHeaders,
  });""")
rep('lib/models/video_track.dart',
    """    String? thumbnailPath,
    Duration? duration,
""",
    """    String? thumbnailPath,
    Duration? duration,
    Map<String, String>? httpHeaders,
""")
rep('lib/models/video_track.dart',
    """      width: width,
      height: height,
    );""",
    """      width: width,
      height: height,
      httpHeaders: httpHeaders ?? this.httpHeaders,
    );""")

# ------------------------------------------------- player honors the headers
rep('lib/state/media_player_state.dart',
    "    unawaited(player.open(Media(track.path), play: true).then((_) {",
    "    unawaited(player.open(Media(track.path, httpHeaders: track.httpHeaders), play: true).then((_) {")
rep('lib/state/media_player_state.dart',
    "    await player.open(Media(track.path), play: autoplay);",
    "    await player.open(Media(track.path, httpHeaders: track.httpHeaders), play: autoplay);")
rep('lib/state/media_player_state.dart',
    """  Future<void> playStream(String url, String title) async {
    final track = VideoTrack(id: url, title: title, path: url);""",
    """  Future<void> playStream(String url, String title,
      {Map<String, String>? httpHeaders}) async {
    final track =
        VideoTrack(id: url, title: title, path: url, httpHeaders: httpHeaders);""")

# ------------------------------------------------- library forwards Drive headers
rep('lib/screens/library_screen.dart',
    """  Future<void> _playNetworkOrStream(String url, String title) async {
    await widget.player.playStream(url, title);""",
    """  Future<void> _playNetworkOrStream(String url, String title,
      [Map<String, String>? httpHeaders]) async {
    await widget.player.playStream(url, title, httpHeaders: httpHeaders);""")
PYEOF

# ------------------------------------------------- Drive service rewrite (OAuth)
python3 <<'PYEOF'
old = open('lib/services/gdrive_service.dart').read()
assert 'GDriveService.getDirectStreamUrl' in old, 'service baseline changed'
assert 'parseDriveFileId' in old, 'service baseline changed'
new = '''import 'dart:convert';
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
'''
open('lib/services/gdrive_service.dart', 'w').write(new)
print('rewrote (1x): lib/services/gdrive_service.dart')
PYEOF

python3 <<'PYEOF'
import sys

def rep(path, old, new, count=1):
    with open(path, 'r', encoding='utf-8') as f:
        src = f.read()
    n = src.count(old)
    if n != count:
        print(f'PATCH FAILED: {path}: expected {count}x, found {n}x')
        print('--- wanted old text (first 400 chars) ---')
        print(old[:400])
        sys.exit(1)
    with open(path, 'w', encoding='utf-8') as f:
        f.write(src.replace(old, new))
    print(f'patched ({n}x): {path}')

# ------------------------------------------------- cloud sheet: sign-in swap
rep('lib/widgets/cloud_storage_sheet.dart',
    """import 'dart:convert';
import 'package:flutter/material.dart';
""",
    """import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
""")
rep('lib/widgets/cloud_storage_sheet.dart',
    "  final Future<void> Function(String url, String title) onPlay;",
    """  final Future<void> Function(String url, String title,
      [Map<String, String>? httpHeaders]) onPlay;""")
rep('lib/widgets/cloud_storage_sheet.dart',
    "    required Future<void> Function(String url, String title) onPlay,",
    """    required Future<void> Function(String url, String title,
            [Map<String, String>? httpHeaders])
        onPlay,""")
rep('lib/widgets/cloud_storage_sheet.dart',
    """  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _tokenCtrl = TextEditingController();

  bool _isConnected = false;
  bool _loading = false;
  List<GDriveItem> _driveVideos = [];
  String _searchFilter = '';

  static const String _kDriveTokenKey = 'gdrive.access_token';
  static const String _kDriveUserKey = 'gdrive.user_email';
  static const String _kDriveVideosCacheKey = 'gdrive.videos_cache';""",
    """  final TextEditingController _searchCtrl = TextEditingController();

  bool _isConnected = false;
  bool _loading = false;
  bool _signingIn = false;
  String _error = '';
  String _email = '';
  Map<String, String>? _headers;
  List<GDriveItem> _driveVideos = [];
  String _searchFilter = '';

  static const String _kDriveUserKey = 'gdrive.user_email';
  static const String _kDriveVideosCacheKey = 'gdrive.videos_cache';""")
rep('lib/widgets/cloud_storage_sheet.dart',
    """  Future<void> _loadStoredSession() async {
    final s = await NativeBridge.loadSettings();
    final token = s[_kDriveTokenKey];
    final cachedJson = s[_kDriveVideosCacheKey];

    if (token != null && token.isNotEmpty) {
      setState(() {
        _isConnected = true;
      });
      if (cachedJson != null && cachedJson.isNotEmpty) {
        try {
          final list = jsonDecode(cachedJson) as List;
          setState(() {
            _driveVideos = list
                .map((e) => GDriveItem(
                      id: '${e['id']}',
                      name: '${e['name']}',
                      mimeType: '${e['mimeType']}',
                      sizeBytes: int.tryParse('${e['sizeBytes']}') ?? 0,
                      thumbnailLink: e['thumbnailLink']?.toString(),
                    ))
                .toList();
          });
        } catch (_) {}
      }
      _fetchAllVideos(token);
    }
  }""",
    """  Future<void> _loadStoredSession() async {
    // Instant UI from the last cached list, then a silent Google session.
    final s = await NativeBridge.loadSettings();
    final cachedJson = s[_kDriveVideosCacheKey];
    if (cachedJson != null && cachedJson.isNotEmpty) {
      try {
        final list = jsonDecode(cachedJson) as List;
        if (mounted) {
          setState(() {
            _driveVideos = list
                .map((e) => GDriveItem(
                      id: '${e['id']}',
                      name: '${e['name']}',
                      mimeType: '${e['mimeType']}',
                      sizeBytes: int.tryParse('${e['sizeBytes']}') ?? 0,
                      thumbnailLink: e['thumbnailLink']?.toString(),
                    ))
                .toList();
          });
        }
      } catch (_) {}
    }
    try {
      final account = await GDriveAuth.signInSilently();
      if (!mounted || account == null) return;
      final headers = await GDriveAuth.authHeadersOf(account);
      if (!mounted || headers == null) return;
      _email = account.email;
      _headers = headers;
      setState(() => _isConnected = true);
      _fetchAllVideos();
    } catch (_) {}
  }""")
rep('lib/widgets/cloud_storage_sheet.dart',
    """  Future<void> _fetchAllVideos(String token) async {
    setState(() => _loading = true);
    final items = await GDriveService.listDriveFiles(apiKey: token);
    if (!mounted) return;
    setState(() {
      _driveVideos = items;
      _loading = false;
      _isConnected = true;
    });""",
    """  Future<void> _signIn() async {
    setState(() {
      _signingIn = true;
      _error = '';
    });
    try {
      final account = await GDriveAuth.signIn();
      final headers = await GDriveAuth.authHeadersOf(account);
      if (!mounted) return;
      if (headers == null) {
        setState(() {
          _signingIn = false;
          _error = 'Drive permission was not granted.';
        });
        return;
      }
      _email = account.email;
      NativeBridge.saveSetting(_kDriveUserKey, _email);
      _headers = headers;
      setState(() {
        _signingIn = false;
        _isConnected = true;
      });
      _fetchAllVideos();
    } on GoogleSignInException catch (e) {
      if (!mounted) return;
      setState(() {
        _signingIn = false;
        _error = e.code == GoogleSignInExceptionCode.canceled
            ? 'Sign in canceled.'
            : 'Sign in failed (${e.code}). If this persists, the app '
                'SHA-1 may not match the Cloud Console OAuth client.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _signingIn = false;
        _error = 'Sign in failed: $e';
      });
    }
  }

  Future<void> _fetchAllVideos() async {
    final headers = _headers;
    if (headers == null) return;
    setState(() {
      _loading = true;
      _error = '';
    });
    final items = await GDriveService.listDriveFiles(headers: headers);
    if (!mounted) return;
    if (items == null) {
      // 401/403: the grant expired or was revoked - ask for sign-in again.
      setState(() {
        _loading = false;
        _isConnected = false;
        _error = 'Session expired - please sign in again.';
      });
      return;
    }
    setState(() {
      _driveVideos = items;
      _loading = false;
      _isConnected = true;
    });""")
rep('lib/widgets/cloud_storage_sheet.dart',
    """  void _connectWithToken(String token) {
    final clean = token.trim();
    if (clean.isEmpty) return;
    NativeBridge.saveSetting(_kDriveTokenKey, clean);
    NativeBridge.saveSetting(_kDriveUserKey, 'Connected Account');
    setState(() {
      _isConnected = true;
    });
    _fetchAllVideos(clean);
  }

  void _disconnect() {
    NativeBridge.saveSetting(_kDriveTokenKey, '');
    NativeBridge.saveSetting(_kDriveUserKey, '');
    NativeBridge.saveSetting(_kDriveVideosCacheKey, '');
    setState(() {
      _isConnected = false;
      _driveVideos = [];
    });
  }

  void _playVideo(GDriveItem item) {
    Navigator.of(context).pop();
    widget.onPlay(item.streamUrl, item.name);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _tokenCtrl.dispose();
    super.dispose();
  }""",
    """  Future<void> _disconnect() async {
    await GDriveAuth.signOut();
    NativeBridge.saveSetting(_kDriveUserKey, '');
    NativeBridge.saveSetting(_kDriveVideosCacheKey, '');
    if (!mounted) return;
    setState(() {
      _isConnected = false;
      _driveVideos = [];
      _headers = null;
      _email = '';
      _error = '';
    });
  }

  void _playVideo(GDriveItem item) {
    Navigator.of(context).pop();
    widget.onPlay(item.streamUrl, item.name, _headers);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }""")
# v106: token paste box + client-ID footer become the Sign-In button.
rep('lib/widgets/cloud_storage_sheet.dart',
    """                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.06),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.white12),
                                ),
                                child: TextField(
                                  controller: _tokenCtrl,
                                  style: const TextStyle(color: Colors.white, fontSize: 13.5),
                                  decoration: const InputDecoration(
                                    hintText: 'Enter Google Drive Access Key / Token…',
                                    hintStyle: TextStyle(color: Colors.white38, fontSize: 13),
                                    border: InputBorder.none,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton.icon(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: accent,
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                  icon: const Icon(Icons.login),
                                  label: const Text(
                                    'Connect & Fetch Videos',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
                                  ),
                                  onPressed: () => _connectWithToken(_tokenCtrl.text),
                                ),
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'Client ID: ${GDriveService.clientId}',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.white24, fontSize: 10.5),
                              ),""",
    """                              if (_error.isNotEmpty) ...[
                                Text(
                                  _error,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                      color: Colors.redAccent,
                                      fontSize: 12.5,
                                      height: 1.4),
                                ),
                                const SizedBox(height: 12),
                              ],
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton.icon(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: accent,
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                  icon: const Icon(Icons.login),
                                  label: Text(
                                    _signingIn
                                        ? 'Signing in…'
                                        : 'Sign in with Google',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14.5),
                                  ),
                                  onPressed: _signingIn ? null : _signIn,
                                ),
                              ),""")
# v106: show which account is connected.
rep('lib/widgets/cloud_storage_sheet.dart',
    """                    : Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),""",
    """                    : Column(
                        children: [
                          if (_email.isNotEmpty)
                            Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 10, 16, 0),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  _email,
                                  style: const TextStyle(
                                      color: Colors.white38, fontSize: 11.5),
                                ),
                              ),
                            ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),""")
# v106: refresh just re-lists (a 401 drops back to sign-in by itself).
rep('lib/widgets/cloud_storage_sheet.dart',
    """                                IconButton(
                                  icon: const Icon(Icons.refresh, color: Colors.white70),
                                  onPressed: () {
                                    final s = NativeBridge.loadSettings();
                                    s.then((map) {
                                      final t = map[_kDriveTokenKey];
                                      if (t != null) _fetchAllVideos(t);
                                    });
                                  },
                                ),""",
    """                                IconButton(
                                  icon: const Icon(Icons.refresh,
                                      color: Colors.white70),
                                  onPressed: _fetchAllVideos,
                                ),""")
PYEOF

# ------------------------------------------------- tests
python3 <<'PYEOF'
path = 'test/widget_test.dart'
src = open(path).read()
tail = '    });\n  });\n}\n'
assert src.endswith(tail), 'test file tail changed'
new_test = '''    test('v106 Google Sign-In powers Drive', () {
      final pub = File('pubspec.yaml').readAsStringSync();
      expect(pub, contains('google_sign_in'));
      final gradle =
          File('android/app/build.gradle.kts').readAsStringSync();
      expect(gradle, contains('minSdk = 24'));
      final svc =
          File('lib/services/gdrive_service.dart').readAsStringSync();
      for (final k in [
        'GoogleSignIn.instance.initialize',
        'serverClientId',
        'drive.readonly',
        'authorizationHeaders',
        'attemptLightweightAuthentication',
        'authenticate()',
        'disconnect()',
        'alt=media',
      ]) {
        expect(svc, contains(k));
      }
      // No pasted tokens, no shipped API key.
      expect(svc.contains('AIza'), isFalse);
      final sheet =
          File('lib/widgets/cloud_storage_sheet.dart').readAsStringSync();
      expect(sheet, contains('Sign in with Google'));
      expect(sheet.contains('Access Key'), isFalse);
      expect(sheet.contains('gdrive.access_token'), isFalse);
      // Authed playback path: headers ride the track into mpv.
      final track =
          File('lib/models/video_track.dart').readAsStringSync();
      expect(track, contains('httpHeaders'));
      final state =
          File('lib/state/media_player_state.dart').readAsStringSync();
      expect('httpHeaders: track.httpHeaders'.allMatches(state).length, 2);
      expect(state, contains('playStream(String url, String title'));
      expect(state, contains('httpHeaders: httpHeaders'));
    });

'''
open(path, 'w').write(src[:-len(tail)] + new_test + tail)
print('patched (1x): test/widget_test.dart')
PYEOF

echo "ALL v106 PATCHES APPLIED"
echo "--- diff stat ---"
git diff --stat
