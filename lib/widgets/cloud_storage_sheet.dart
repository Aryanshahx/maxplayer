import 'dart:convert';
import 'package:flutter/material.dart';

import '../services/gdrive_service.dart';
import '../services/native_bridge.dart';
import '../state/theme_state.dart';
import '../utils/formatters.dart';

/// v86: Dedicated Cloud Storage (Google Drive) manager with automatic video fetching.
class CloudStorageSheet extends StatefulWidget {
  final Future<void> Function(String url, String title) onPlay;

  const CloudStorageSheet({super.key, required this.onPlay});

  static Future<void> show(
    BuildContext context, {
    required Future<void> Function(String url, String title) onPlay,
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
  final TextEditingController _tokenCtrl = TextEditingController();

  bool _isConnected = false;
  bool _loading = false;
  List<GDriveItem> _driveVideos = [];
  String _searchFilter = '';

  static const String _kDriveTokenKey = 'gdrive.access_token';
  static const String _kDriveUserKey = 'gdrive.user_email';
  static const String _kDriveVideosCacheKey = 'gdrive.videos_cache';

  @override
  void initState() {
    super.initState();
    _loadStoredSession();
  }

  Future<void> _loadStoredSession() async {
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
  }

  Future<void> _fetchAllVideos(String token) async {
    setState(() => _loading = true);
    final items = await GDriveService.listDriveFiles(apiKey: token);
    if (!mounted) return;
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

  void _connectWithToken(String token) {
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
                              Container(
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
                              ),
                            ],
                          ),
                        ),
                      )
                    : Column(
                        children: [
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
                                  onPressed: () {
                                    final s = NativeBridge.loadSettings();
                                    s.then((map) {
                                      final t = map[_kDriveTokenKey];
                                      if (t != null) _fetchAllVideos(t);
                                    });
                                  },
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
