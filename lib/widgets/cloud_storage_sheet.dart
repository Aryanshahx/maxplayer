import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../services/gdrive_service.dart';
import '../services/native_bridge.dart';
import '../state/theme_state.dart';
import '../utils/formatters.dart';

typedef CloudStoragePlayCallback = Future<void> Function(
  String url,
  String title, {
  Map<String, String>? httpHeaders,
});

/// v86/v98: Dedicated Cloud Storage (Google Drive) manager.
///
/// v98 replaces the fake token text field with real Google Sign-In + Drive
/// OAuth, fetches all video pages from the user's Drive, and passes the
/// authorization headers through to media_kit so private files can stream.
class CloudStorageSheet extends StatefulWidget {
  final CloudStoragePlayCallback onPlay;

  const CloudStorageSheet({super.key, required this.onPlay});

  static Future<void> show(
    BuildContext context, {
    required CloudStoragePlayCallback onPlay,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF14141c),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => CloudStorageSheet(onPlay: onPlay),
    );
  }

  @override
  State<CloudStorageSheet> createState() => _CloudStorageSheetState();
}

class _CloudStorageSheetState extends State<CloudStorageSheet> {
  final TextEditingController _searchCtrl = TextEditingController();

  List<GDriveItem> _driveVideos = [];
  bool _loading = false;
  bool _ready = false;
  String _searchFilter = '';
  String? _error;
  String? _userEmail;
  GoogleSignInAccount? _account;
  Map<String, String>? _authHeaders;

  static const String _kDriveUserKey = 'gdrive.user_email';
  static const String _kDriveVideosCacheKey = 'gdrive.videos_cache';
  static Future<void>? _googleInit;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  static Future<void> _ensureGoogleReady() {
    return _googleInit ??= GoogleSignIn.instance.initialize();
  }

  Future<void> _bootstrap() async {
    await _loadCachedState();
    try {
      await _ensureGoogleReady();
      if (!mounted) return;
      setState(() => _ready = true);
      final authAttempt =
          GoogleSignIn.instance.attemptLightweightAuthentication();
      final user = authAttempt == null ? null : await authAttempt;
      if (user == null || !mounted) return;
      final headers = await _authorizationHeaders(
        user,
        promptIfNecessary: false,
      );
      if (!mounted) return;
      setState(() {
        _account = user;
        _userEmail = user.email;
        _authHeaders = headers;
      });
      if (headers != null) {
        await _fetchAllVideos(headers);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _ready = true;
        _error = '$e';
      });
    }
  }

  Future<void> _loadCachedState() async {
    final s = await NativeBridge.loadSettings();
    final cachedUser = s[_kDriveUserKey]?.trim();
    final cachedJson = s[_kDriveVideosCacheKey];
    final cachedVideos = _decodeCachedVideos(cachedJson);
    if (!mounted) return;
    setState(() {
      _userEmail = cachedUser?.isEmpty == true ? null : cachedUser;
      _driveVideos = cachedVideos;
    });
  }

  List<GDriveItem> _decodeCachedVideos(String? jsonText) {
    if (jsonText == null || jsonText.isEmpty) return const [];
    try {
      final list = jsonDecode(jsonText);
      if (list is! List) return const [];
      return [
        for (final e in list)
          if (e is Map)
            GDriveItem(
              id: '${e['id'] ?? ''}',
              name: '${e['name'] ?? ''}',
              mimeType: '${e['mimeType'] ?? ''}',
              sizeBytes: int.tryParse('${e['sizeBytes'] ?? ''}') ?? 0,
              thumbnailLink: e['thumbnailLink']?.toString(),
            ),
      ].where((e) => e.id.isNotEmpty && e.name.isNotEmpty).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<Map<String, String>?> _authorizationHeaders(
    GoogleSignInAccount user, {
    required bool promptIfNecessary,
  }) async {
    try {
      return await user.authorizationClient.authorizationHeaders(
        <String>[GDriveService.driveReadonlyScope],
        promptIfNecessary: promptIfNecessary,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _connectGoogle() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _ensureGoogleReady();
      final signIn = GoogleSignIn.instance;
      if (!signIn.supportsAuthenticate()) {
        throw const GDriveException(
          'This device does not support Google Sign-In here.',
        );
      }
      final user = await signIn.authenticate(
        scopeHint: const <String>[GDriveService.driveReadonlyScope],
      );
      final headers = await _authorizationHeaders(
        user,
        promptIfNecessary: true,
      );
      if (headers == null || headers.isEmpty) {
        throw const GDriveException(
          'Drive permission was not granted. Please try again.',
        );
      }
      if (!mounted) return;
      setState(() {
        _account = user;
        _userEmail = user.email;
        _authHeaders = headers;
      });
      await NativeBridge.saveSetting(_kDriveUserKey, user.email);
      await _fetchAllVideos(headers);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<void> _fetchAllVideos(Map<String, String> headers) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await GDriveService.listDriveFiles(headers: headers);
      if (!mounted) return;
      setState(() {
        _driveVideos = items;
        _authHeaders = headers;
        _loading = false;
      });
      await NativeBridge.saveSetting(
        _kDriveVideosCacheKey,
        jsonEncode(
          items
              .map(
                (i) => {
                  'id': i.id,
                  'name': i.name,
                  'mimeType': i.mimeType,
                  'sizeBytes': i.sizeBytes,
                  'thumbnailLink': i.thumbnailLink,
                },
              )
              .toList(),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<void> _refresh() async {
    final user = _account;
    if (user == null) {
      await _connectGoogle();
      return;
    }
    final headers = await _authorizationHeaders(user, promptIfNecessary: true);
    if (headers == null || headers.isEmpty) {
      if (!mounted) return;
      setState(() {
        _error = 'Drive permission was not granted. Please try again.';
      });
      return;
    }
    await _fetchAllVideos(headers);
  }

  Future<void> _disconnect() async {
    try {
      await GoogleSignIn.instance.disconnect();
    } catch (_) {
      try {
        await GoogleSignIn.instance.signOut();
      } catch (_) {}
    }
    await NativeBridge.saveSetting(_kDriveUserKey, '');
    await NativeBridge.saveSetting(_kDriveVideosCacheKey, '');
    if (!mounted) return;
    setState(() {
      _account = null;
      _authHeaders = null;
      _userEmail = null;
      _driveVideos = [];
      _searchFilter = '';
      _searchCtrl.clear();
      _error = null;
      _loading = false;
    });
  }

  Future<void> _playVideo(GDriveItem item) async {
    final user = _account;
    if (user == null) {
      await _connectGoogle();
      return;
    }
    setState(() => _loading = true);
    try {
      final headers = await _authorizationHeaders(user, promptIfNecessary: true);
      if (headers == null || headers.isEmpty) {
        throw const GDriveException(
          'Google Drive access expired. Please sign in again.',
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      await widget.onPlay(
        item.streamUrl,
        item.name,
        httpHeaders: headers,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = themeState.accent;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final visibleVideos = _driveVideos.where((v) {
      if (_searchFilter.isEmpty) return true;
      return v.name.toLowerCase().contains(_searchFilter.toLowerCase());
    }).toList();
    final signedIn = _account != null && _authHeaders != null;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.8,
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                child: Row(
                  children: [
                    Icon(Icons.cloud_queue, color: accent, size: 24),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Google Drive Cloud Storage',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (signedIn)
                      IconButton(
                        icon: const Icon(Icons.logout, color: Colors.white54, size: 20),
                        tooltip: 'Disconnect Account',
                        onPressed: _disconnect,
                      ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Colors.white12),
              Expanded(
                child: !_ready
                    ? const Center(child: CircularProgressIndicator())
                    : !signedIn
                        ? _buildSignInState(accent)
                        : _buildVideosState(accent, visibleVideos),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSignInState(Color accent) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.05),
              ),
              child: Icon(Icons.cloud_sync, size: 38, color: accent),
            ),
            const SizedBox(height: 16),
            const Text(
              'Sign in to Google Drive',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Max Player will ask for read-only Drive access, fetch all video files from your Google Drive, and stream private videos securely.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54, fontSize: 13, height: 1.4),
            ),
            if (_userEmail != null) ...[
              const SizedBox(height: 10),
              Text(
                'Last used: $_userEmail',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white38, fontSize: 11.5),
              ),
            ],
            if (_driveVideos.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                '${_driveVideos.length} cached video entries are ready and will refresh after sign-in.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white38, fontSize: 11.5),
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: themeState.onAccent,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.login),
                label: Text(
                  _loading ? 'Connecting…' : 'Sign in with Google',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14.5,
                  ),
                ),
                onPressed: _loading ? null : _connectGoogle,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.redAccent, fontSize: 12.5),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildVideosState(Color accent, List<GDriveItem> visibleVideos) {
    return Column(
      children: [
        if (_userEmail != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                Icon(Icons.verified_user, color: accent, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _userEmail!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                  ),
                ),
                Text(
                  '${_driveVideos.length} videos',
                  style: const TextStyle(color: Colors.white38, fontSize: 11.5),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: TextField(
                    controller: _searchCtrl,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    onChanged: (v) => setState(() => _searchFilter = v),
                    decoration: const InputDecoration(
                      hintText: 'Search Drive videos…',
                      hintStyle: TextStyle(color: Colors.white38, fontSize: 13),
                      icon: Icon(Icons.search, size: 18, color: Colors.white38),
                      border: InputBorder.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.refresh, color: Colors.white70),
                onPressed: _loading ? null : _refresh,
              ),
            ],
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.redAccent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
              ),
              child: Text(
                _error!,
                style: const TextStyle(color: Colors.redAccent, fontSize: 12.2),
              ),
            ),
          ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : visibleVideos.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.video_library_outlined, size: 48, color: Colors.white24),
                          SizedBox(height: 10),
                          Text(
                            'No videos found on your Google Drive',
                            style: TextStyle(color: Colors.white54, fontSize: 14),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount: visibleVideos.length,
                      separatorBuilder: (_, __) => const Divider(height: 1, color: Colors.white10),
                      itemBuilder: (context, i) {
                        final vid = visibleVideos[i];
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(vertical: 4),
                          leading: CircleAvatar(
                            backgroundColor: accent.withValues(alpha: 0.18),
                            child: Icon(Icons.movie, color: accent, size: 20),
                          ),
                          title: Text(
                            vid.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          subtitle: Text(
                            formatFileSize(vid.sizeBytes),
                            style: const TextStyle(color: Colors.white38, fontSize: 11.5),
                          ),
                          trailing: IconButton(
                            icon: Icon(Icons.play_circle_fill, color: accent, size: 28),
                            onPressed: () => _playVideo(vid),
                          ),
                          onTap: () => _playVideo(vid),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}
