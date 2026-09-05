import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../services/gdrive_service.dart';
import '../services/native_bridge.dart';
import '../state/theme_state.dart';
import '../utils/formatters.dart';

/// v86: Dedicated Cloud Storage (Google Drive) manager with automatic video fetching.
class CloudStorageSheet extends StatefulWidget {
  final Future<void> Function(String url, String title,
      [Map<String, String>? httpHeaders]) onPlay;

  const CloudStorageSheet({super.key, required this.onPlay});

  static Future<void> show(
    BuildContext context, {
    required Future<void> Function(String url, String title,
            [Map<String, String>? httpHeaders])
        onPlay,
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

  bool _isConnected = false;
  bool _loading = false;
  bool _signingIn = false;
  bool _picking = false; // v110: Android system picker round-trip in progress
  String _error = '';
  String _email = '';
  Map<String, String>? _headers;
  List<GDriveItem> _driveVideos = [];
  String _searchFilter = '';

  static const String _kDriveUserKey = 'gdrive.user_email';
  static const String _kDriveVideosCacheKey = 'gdrive.videos_cache';

  @override
  void initState() {
    super.initState();
    _loadStoredSession();
  }

  Future<void> _loadStoredSession() async {
    // Instant UI from the last cached list, then a silent Google session.
    final s = await NativeBridge.loadSettings();
    final email = s[_kDriveUserKey];
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
    // v106-fix2: never prompt on open - silent re-auth runs only when
    // this device signed in before (email saved); otherwise wait for the
    // Sign-In button.
    if (email == null || email.isEmpty) return;
    // v108: reuse this launch's silent session - repeat opens never prompt.
    final memHeaders = GDriveAuth.recall();
    if (memHeaders != null) {
      _email = email;
      _headers = memHeaders;
      if (mounted) setState(() => _isConnected = true);
      _fetchAllVideos();
      return;
    }
    try {
      // v107: stay signed in once signed in - a dead grant just retries
      // silently next open (never prompts); only Disconnect clears it.
      final account = await GDriveAuth.signInSilently();
      if (!mounted || account == null) return;
      final headers = await GDriveAuth.authHeadersOf(account);
      if (!mounted || headers == null) return;
      _email = account.email;
      _headers = headers;
      GDriveAuth.remember(headers);
      setState(() => _isConnected = true);
      _fetchAllVideos();
    } catch (_) {}
  }

  Future<void> _signIn() async {
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
      GDriveAuth.remember(headers);
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
            : 'Sign in failed (${e.code}): ${e.description ?? 'no details'}. '
                'If this persists, the app SHA-1 may not match the Cloud '
                'Console OAuth client.';
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
      GDriveAuth.forget();
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
    });

    final cacheData = jsonEncode(items
        .map((i) => {
              'id': i.id,
              'name': i.name,
              'mimeType': i.mimeType,
              'sizeBytes': i.sizeBytes,
              'thumbnailLink': i.thumbnailLink,
            })
        .toList());
    NativeBridge.saveSetting(_kDriveVideosCacheKey, cacheData);
  }

  Future<void> _disconnect() async {
    await GDriveAuth.signOut();
    GDriveAuth.forget();
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

  // v110 "The Easy Way": Android's built-in file picker lists this device
  // AND the user's installed storage apps (Google Drive included) - no
  // Google sign-in, no OAuth verification. Local files play straight from
  // their path; cloud files arrive as a temporary copy, so the user is
  // offered a permanent "Save to device" copy in Movies/Max Player.
  Future<void> _pickViaAndroidPicker() async {
    if (_picking) return;
    setState(() => _picking = true);
    final picked = await NativeBridge.pickVideoDocument();
    if (!mounted) return;
    setState(() => _picking = false);
    if (picked == null) return; // user canceled the picker
    final messenger = ScaffoldMessenger.maybeOf(context);
    final path = picked['path']?.toString() ?? '';
    final name = picked['name']?.toString() ?? 'video';
    if (path.isEmpty) {
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1b1b24),
          title: const Text("Couldn't open that file",
              style: TextStyle(color: Colors.white, fontSize: 17)),
          content: const Text(
            'The selected video could not be read. Try another file, or '
            'sign in to Google Drive instead.',
            style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }
    if (picked['cached'] != true) {
      // Plain local file: already on the device, nothing to save.
      _playPicked(path, name);
      return;
    }
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1b1b24),
        title: const Text('Play or keep?',
            style: TextStyle(color: Colors.white, fontSize: 17)),
        content: Text(
          '"$name" came from a cloud app and is stored only as a temporary '
          'copy. Keep a permanent copy on this device?',
          style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('play'),
            child: const Text('Play once'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: themeState.accent,
              foregroundColor: themeState.onAccent,
            ),
            onPressed: () => Navigator.of(ctx).pop('save'),
            child: const Text('Save to device'),
          ),
        ],
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'play') {
      _playPicked(path, name);
      return;
    }
    final saved = await NativeBridge.savePickedVideoToDevice(
      sourceUri: picked['sourceUri']?.toString(),
      cachePath: path,
      name: name,
    );
    if (!mounted) return;
    if (saved == null) {
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1b1b24),
          title: const Text("Couldn't save",
              style: TextStyle(color: Colors.white, fontSize: 17)),
          content: const Text(
            'The copy could not be written to Movies/Max Player. Playing '
            'the temporary copy is still possible.',
            style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }
    final savedPath = saved['path']?.toString() ?? '';
    final location = saved['location']?.toString() ?? 'Movies/Max Player';
    _playPicked(savedPath.isNotEmpty ? savedPath : path, name);
    messenger?.showSnackBar(
      SnackBar(
        content: Text('Saved to $location'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _playPicked(String path, String name) {
    Navigator.of(context).pop();
    // Same onPlay pipeline the Drive list uses: libmpv opens local absolute
    // paths exactly like stream URLs.
    widget.onPlay(path, name);
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
                    if (_isConnected)
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
                child: !_isConnected
                    ? Padding(
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
                                'Fetch & Stream Drive Videos',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Sign in to automatically fetch all video files from your Google Drive and stream them directly in Max Player.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.white54, fontSize: 13, height: 1.4),
                              ),
                              const SizedBox(height: 24),
                              if (_error.isNotEmpty) ...[
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
                              ),
                              const SizedBox(height: 14),
                              const Text(
                                'or',
                                style: TextStyle(
                                    color: Colors.white24, fontSize: 12),
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.white,
                                    side:
                                        const BorderSide(color: Colors.white24),
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 13),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(12)),
                                  ),
                                  icon: const Icon(
                                      Icons.folder_open_outlined),
                                  label: Text(
                                    _picking
                                        ? 'Opening picker…'
                                        : 'Select video (no sign-in)',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14),
                                  ),
                                  onPressed:
                                      _picking ? null : _pickViaAndroidPicker,
                                ),
                              ),
                              const SizedBox(height: 10),
                              const Text(
                                "Opens Android's file picker: choose a video "
                                'from this device, your Google Drive app, or '
                                'any storage app. Cloud files are copied '
                                'first, so big ones take a moment - then you '
                                'can keep them with Save to device.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: Colors.white38,
                                    fontSize: 11.5,
                                    height: 1.35),
                              ),
                            ],
                          ),
                        ),
                      )
                    : Column(
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
                            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                            child: SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  side: const BorderSide(
                                      color: Colors.white24),
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 11),
                                  shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(12)),
                                ),
                                icon: const Icon(
                                    Icons.folder_open_outlined,
                                    size: 20),
                                label: Text(
                                  _picking
                                      ? 'Opening picker…'
                                      : 'Select video via Android picker '
                                          '(device / Drive app)',
                                  style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w500),
                                ),
                                onPressed: _picking
                                    ? null
                                    : _pickViaAndroidPicker,
                              ),
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
                                  icon: const Icon(Icons.refresh,
                                      color: Colors.white70),
                                  onPressed: _fetchAllVideos,
                                ),
                              ],
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
                                              style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w500),
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
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
