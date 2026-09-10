import 'package:flutter/material.dart';

import '../theme.dart';
import '../utils/crash_log.dart';
import '../utils/iptv.dart';
import '../utils/local_store.dart';
import '../utils/m3u.dart';
import 'player_screen.dart';

/// Open Stream (IPTV) — paste a direct stream URL, or load an M3U/M3U8
/// playlist and browse its channels. Streams go straight into the MPV
/// player as network sources (no resume bookkeeping).
class OpenStreamScreen extends StatefulWidget {
  const OpenStreamScreen({super.key});

  @override
  State<OpenStreamScreen> createState() => _OpenStreamScreenState();
}

class _OpenStreamScreenState extends State<OpenStreamScreen> {
  final _store = LocalStore();
  final _urlCtrl = TextEditingController();
  List<SavedLink> _recent = [];
  List<IptvChannel>? _channels; // null = not loaded yet
  bool _loadingPlaylist = false;

  @override
  void initState() {
    super.initState();
    _loadRecents();
  }

  Future<void> _loadRecents() async {
    final r = await _store.recentStreams();
    if (mounted) setState(() => _recent = r);
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  bool _looksLikePlaylist(String url) {
    final u = url.toLowerCase();
    return u.contains('.m3u');
  }

  Future<void> _open(String url, {String? name}) async {
    url = url.trim();
    if (url.isEmpty) return;
    CrashLog.crumb('stream.open', {'url': url});
    await _store.addRecentStream(SavedLink(
        name: name?.trim().isNotEmpty == true
            ? name!.trim()
            : Uri.tryParse(url)?.host ?? 'Stream',
        url: url));
    if (!mounted) return;
    if (_looksLikePlaylist(url) && name == null) {
      // treat raw playlist URL as a channel list, not a single video
      setState(() => _loadingPlaylist = true);
      final channels = await fetchM3uChannels(url);
      if (!mounted) return;
      setState(() {
        _loadingPlaylist = false;
        _channels = channels;
      });
      if (channels.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content:
                Text('No channels found — is that a public M3U link?')));
      }
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PlayerScreen.stream(
          path: url, title: name?.trim().isNotEmpty == true
              ? name!.trim()
              : Uri.tryParse(url)?.host ?? 'Stream'),
    ));
    await _loadRecents();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Open Stream (IPTV)')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _urlCtrl,
                    style: const TextStyle(color: AppColors.textPrimary),
                    decoration: const InputDecoration(
                      hintText:
                          'Stream URL — http(s)://, rtmp://, rtsp://, .m3u8, .ts',
                      hintStyle:
                          TextStyle(color: AppColors.textSecondary),
                    ),
                    onSubmitted: (v) => _open(v),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: AppColors.onAccent,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () => _open(_urlCtrl.text),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Open stream'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Tip: paste an IPTV M3U paste URL to browse all its channels.',
            style:
                TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
          ),
          if (_loadingPlaylist) ...[
            const SizedBox(height: 24),
            Center(
                child: CircularProgressIndicator(color: AppColors.accent)),
          ] else if (_channels != null) ...[
            const SizedBox(height: 16),
            Text('${_channels!.length} channels',
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            for (final ch in _channels!)
              Card(
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.live_tv_rounded,
                      color: AppColors.accent, size: 20),
                  title: Text(ch.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AppColors.textPrimary, fontSize: 13.5)),
                  subtitle: Text(ch.url,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 11)),
                  onTap: () => _open(ch.url, name: ch.name),
                ),
              ),
          ] else ...[
            const SizedBox(height: 16),
            if (_recent.isNotEmpty)
              const Text('Recent streams',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            for (final s in _recent)
              Card(
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.stream_rounded,
                      color: AppColors.accent, size: 20),
                  title: Text(s.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AppColors.textPrimary, fontSize: 13.5)),
                  subtitle: Text(s.url,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 11)),
                  onTap: () => _open(s.url, name: s.name),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
