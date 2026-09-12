import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/saved_server.dart';
import '../theme.dart';
import '../utils/crash_log.dart';
import '../utils/iptv.dart';
import '../utils/local_store.dart';
import '../utils/m3u.dart';
import 'player_screen.dart';

/// Open Stream (IPTV) — old-app parity: protocol chips, clipboard paste,
/// optional title, saved & recent streams, and .m3u/.m3u8 channel lists.
class OpenStreamScreen extends StatefulWidget {
  const OpenStreamScreen({super.key});

  @override
  State<OpenStreamScreen> createState() => _OpenStreamScreenState();
}

class _OpenStreamScreenState extends State<OpenStreamScreen> {
  final _store = LocalStore();
  final _urlCtrl = TextEditingController();
  final _titleCtrl = TextEditingController();

  List<SavedServer> _savedServers = [];
  String? _detectedProto;
  List<IptvChannel>? _channels;
  bool _loadingPlaylist = false;

  @override
  void initState() {
    super.initState();
    _urlCtrl.addListener(_onUrlChanged);
    _loadServers();
  }

  Future<void> _loadServers() async {
    final raw = await _store.rawString(kServersSettingKey);
    final list = parseServersJson(raw);
    if (mounted) setState(() => _savedServers = list);
  }

  void _onUrlChanged() {
    final uri = Uri.tryParse(_urlCtrl.text.trim());
    setState(() {
      _detectedProto =
          (uri != null && uri.hasScheme) ? uri.scheme.toUpperCase() : null;
    });
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data != null && data.text != null && data.text!.isNotEmpty) {
      _urlCtrl.text = data.text!.trim();
    }
  }

  bool _looksLikePlaylist(String url) {
    final u = url.toLowerCase();
    return u.contains('.m3u');
  }

  Future<void> _play(String url, String title) async {
    final cleanUrl = url.trim();
    if (cleanUrl.isEmpty) return;
    final name = title.trim().isNotEmpty ? title.trim() : _serverNameFor(cleanUrl);

    // Save to servers list (dedupe by url).
    _savedServers =
        addSavedServer(_savedServers, SavedServer(name: name, url: cleanUrl));
    await _store.setRawString(kServersSettingKey, serversToJson(_savedServers));
    CrashLog.crumb('stream.open', {'url': cleanUrl});

    if (!mounted) return;
    if (_looksLikePlaylist(cleanUrl) && title.trim().isEmpty) {
      // Treat a raw playlist URL as a channel list, not a single video.
      setState(() => _loadingPlaylist = true);
      final channels = await fetchM3uChannels(cleanUrl);
      if (!mounted) return;
      setState(() {
        _loadingPlaylist = false;
        _channels = channels;
      });
      if (channels.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('No channels found — is that a public M3U link?')));
      }
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PlayerScreen.stream(path: cleanUrl, title: name),
    ));
    await _loadServers();
  }

  Future<void> _deleteServer(int index) async {
    setState(() => _savedServers.removeAt(index));
    await _store.setRawString(kServersSettingKey, serversToJson(_savedServers));
  }

  String _serverNameFor(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return 'Stream';
    if (uri.hasPort && uri.port != 80 && uri.port != 443) {
      return '${uri.host}:${uri.port}';
    }
    return uri.host.isNotEmpty ? uri.host : 'Network Stream';
  }

  @override
  void dispose() {
    _urlCtrl.removeListener(_onUrlChanged);
    _urlCtrl.dispose();
    _titleCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.accent;
    final canPlay = _urlCtrl.text.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFF14141c),
      appBar: AppBar(
        backgroundColor: const Color(0xFF14141c),
        title: const Text('Open Stream(iptv)',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Protocols row
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final p in [
                'HTTP',
                'HTTPS',
                'HLS/M3U8',
                'RTSP',
                'RTMP',
                'FTP',
                'SMB',
                'WebDAV'
              ])
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _detectedProto == p
                        ? accent.withValues(alpha: 0.25)
                        : Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: _detectedProto == p ? accent : Colors.white10,
                    ),
                  ),
                  child: Text(
                    p,
                    style: TextStyle(
                      color: _detectedProto == p ? accent : Colors.white54,
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          // Stream URL input
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: canPlay ? accent : Colors.white12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _urlCtrl,
                    style: const TextStyle(color: Colors.white, fontSize: 13.5),
                    decoration: const InputDecoration(
                      hintText: 'https://, http://, rtsp://, ftp://…',
                      hintStyle: TextStyle(color: Colors.white38, fontSize: 13),
                      border: InputBorder.none,
                    ),
                    onSubmitted: (_) => _play(_urlCtrl.text, _titleCtrl.text),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.paste, color: Colors.white70, size: 20),
                  tooltip: 'Paste URL',
                  onPressed: _pasteFromClipboard,
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // Optional title input
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(10),
            ),
            child: TextField(
              controller: _titleCtrl,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: const InputDecoration(
                hintText: 'Stream title (optional)',
                hintStyle: TextStyle(color: Colors.white24, fontSize: 12.5),
                border: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: AppColors.onAccent,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: canPlay
                ? () => _play(_urlCtrl.text, _titleCtrl.text)
                : null,
            icon: const Icon(Icons.play_arrow),
            label: const Text('Play Stream',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 8),
          const Text(
            'IPTV lives here: paste a channel list (.m3u / .m3u8) - it plays directly.',
            style: TextStyle(color: Colors.white38, fontSize: 11),
          ),
          if (_loadingPlaylist) ...[
            const SizedBox(height: 24),
            Center(child: CircularProgressIndicator(color: accent)),
          ] else if (_channels != null) ...[
            const SizedBox(height: 16),
            Text('${_channels!.length} channels',
                style: TextStyle(
                    color: accent, fontSize: 13, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            for (final ch in _channels!)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.live_tv, color: accent, size: 20),
                  title: Text(
                    ch.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w500),
                  ),
                  subtitle: Text(
                    ch.url,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                  onTap: () => _play(ch.url, ch.name),
                ),
              ),
          ] else if (_savedServers.isNotEmpty) ...[
            const SizedBox(height: 24),
            Row(
              children: [
                Icon(Icons.history, color: accent, size: 16),
                const SizedBox(width: 6),
                Text(
                  'Saved & Recent Streams',
                  style: TextStyle(
                    color: accent,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            for (var i = 0; i < _savedServers.length; i++)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.live_tv, color: accent, size: 20),
                  title: Text(
                    _savedServers[i].name,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w500),
                  ),
                  subtitle: Text(
                    _savedServers[i].url,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline,
                        color: Colors.white38, size: 18),
                    onPressed: () => _deleteServer(i),
                  ),
                  onTap: () => _play(_savedServers[i].url, _savedServers[i].name),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
