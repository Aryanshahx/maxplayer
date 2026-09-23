import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/saved_server.dart';
import '../theme.dart';
import '../utils/crash_log.dart';
import '../utils/iptv.dart';
import '../utils/local_store.dart';
import '../utils/m3u.dart';
import 'player_screen.dart';

/// iptv-org public playlists (https://github.com/iptv-org/iptv) — one-tap
/// channel lists near the top of the screen, before the manual URL field.
/// index.m3u is the full ~10k+ channel index; the per-category/country
/// ones are the fast way onto live TV.
const String _iptvOrgBase = 'https://iptv-org.github.io/iptv';
const List<({String label, String url})> _iptvOrgPlaylists = [
  (label: '🌏 All channels (10k+)', url: '$_iptvOrgBase/index.m3u'),
  (label: '🇮🇳 India', url: '$_iptvOrgBase/countries/in.m3u'),
  (label: '🇺🇸 USA', url: '$_iptvOrgBase/countries/us.m3u'),
  (label: '🇬🇧 UK', url: '$_iptvOrgBase/countries/uk.m3u'),
  (label: '📰 News', url: '$_iptvOrgBase/categories/news.m3u'),
  (label: '⚽ Sports', url: '$_iptvOrgBase/categories/sports.m3u'),
  (label: '🎬 Movies', url: '$_iptvOrgBase/categories/movies.m3u'),
  (label: '🎵 Music', url: '$_iptvOrgBase/categories/music.m3u'),
  (label: '👶 Kids', url: '$_iptvOrgBase/categories/kids.m3u'),
  (label: '💻 Tech', url: '$_iptvOrgBase/categories/science.m3u'),
  (label: '😂 Comedy', url: '$_iptvOrgBase/categories/comedy.m3u'),
];

/// Old-app parity: prefetching thousands of rows on first paint kills the
/// screen — page the channel list in chunks of this many tiles.
const int _channelPageSize = 50;

/// Open Stream (IPTV) — old-app parity: protocol chips, clipboard paste,
/// optional title, saved & recent streams, and .m3u/.m3u8 channel lists.
/// v1.0.1+12: one-tap iptv-org playlists, channel search & group filter,
/// and a paged channel list that survives 10k+ channel indexes.
class OpenStreamScreen extends StatefulWidget {
  const OpenStreamScreen({super.key});

  @override
  State<OpenStreamScreen> createState() => _OpenStreamScreenState();
}

class _OpenStreamScreenState extends State<OpenStreamScreen> {
  final _store = LocalStore();
  final _urlCtrl = TextEditingController();
  final _titleCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();

  List<SavedServer> _savedServers = [];
  String? _detectedProto;
  List<IptvChannel>? _channels;
  List<IptvChannel>? _filtered;
  bool _loadingPlaylist = false;
  List<String> _groups = const [];
  String? _selectedGroup;
  int _visible = _channelPageSize;

  @override
  void initState() {
    super.initState();
    _urlCtrl.addListener(_onUrlChanged);
    _searchCtrl.addListener(_applyFilter);
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
      _detectedProto = (uri != null && uri.hasScheme)
          ? uri.scheme.toUpperCase()
          : null;
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

  Future<void> _loadPlaylist(String url) async {
    setState(() => _loadingPlaylist = true);
    CrashLog.crumb('iptv.playlist', {'url': url});
    final channels = await fetchM3uChannels(url);
    if (!mounted) return;
    final groups = <String>{};
    for (final c in channels) {
      final g = c.group;
      if (g != null && g.isNotEmpty) groups.add(g);
    }
    setState(() {
      _loadingPlaylist = false;
      _channels = channels;
      _groups = groups.toList()..sort();
      _selectedGroup = null;
      _searchCtrl.clear();
    });
    _applyFilter();
    if (channels.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No channels found — is that a public M3U link?'),
        ),
      );
    }
  }

  void _applyFilter() {
    List<IptvChannel>? all = _channels;
    if (all == null) {
      if (mounted) setState(() => _filtered = null);
      return;
    }
    final q = _searchCtrl.text.trim().toLowerCase();
    var out = all;
    if (_selectedGroup != null) {
      out = out.where((c) => c.group == _selectedGroup).toList();
    }
    if (q.isNotEmpty) {
      out = out.where((c) => c.name.toLowerCase().contains(q)).toList();
    }
    setState(() {
      _filtered = out;
      _visible = _channelPageSize;
    });
  }

  Future<void> _play(String url, String title) async {
    final cleanUrl = url.trim();
    if (cleanUrl.isEmpty) return;
    final name = title.trim().isNotEmpty
        ? title.trim()
        : _serverNameFor(cleanUrl);

    // Save to servers list (dedupe by url).
    _savedServers = addSavedServer(
      _savedServers,
      SavedServer(name: name, url: cleanUrl),
    );
    await _store.setRawString(kServersSettingKey, serversToJson(_savedServers));
    CrashLog.crumb('stream.open', {'url': cleanUrl});

    if (!mounted) return;
    if (_looksLikePlaylist(cleanUrl) && title.trim().isEmpty) {
      // Treat a raw playlist URL as a channel list, not a single video.
      await _loadPlaylist(cleanUrl);
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerScreen.stream(path: cleanUrl, title: name),
      ),
    );
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
    _searchCtrl.dispose();
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
        title: const Text(
          'Open Stream(iptv)',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // iptv-org quick playlists
          Row(
            children: [
              Icon(Icons.public, color: accent, size: 15),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Free live TV — iptv-org playlists',
                  style: TextStyle(
                    color: accent,
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final p in _iptvOrgPlaylists)
                ActionChip(
                  label: Text(
                    p.label,
                    style: const TextStyle(color: Colors.white, fontSize: 11.5),
                  ),
                  backgroundColor: Colors.white.withValues(alpha: 0.06),
                  side: BorderSide(color: accent.withValues(alpha: 0.35)),
                  onPressed: _loadingPlaylist
                      ? null
                      : () {
                          _urlCtrl.text = p.url;
                          _titleCtrl.clear();
                          _loadPlaylist(p.url);
                        },
                ),
            ],
          ),
          const SizedBox(height: 14),
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
                'WebDAV',
              ])
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
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
                  icon: const Icon(
                    Icons.paste,
                    color: Colors.white70,
                    size: 20,
                  ),
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
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: canPlay
                ? () => _play(_urlCtrl.text, _titleCtrl.text)
                : null,
            icon: const Icon(Icons.play_arrow),
            label: const Text(
              'Play Stream',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'IPTV lives here: paste a channel list (.m3u / .m3u8) - it plays directly.',
            style: TextStyle(color: Colors.white38, fontSize: 11),
          ),
          if (_loadingPlaylist) ...[
            const SizedBox(height: 24),
            Center(child: CircularProgressIndicator(color: accent)),
            const SizedBox(height: 8),
            const Center(
              child: Text(
                'Fetching playlist… big lists take a moment',
                style: TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ),
          ] else if (_channels != null && _filtered != null) ...[
            const SizedBox(height: 16),
            Text(
              '${_filtered!.length} of ${_channels!.length} channels',
              style: TextStyle(
                color: accent,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            // Search bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.search, color: Colors.white38, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: const InputDecoration(
                        hintText: 'Search channels…',
                        hintStyle: TextStyle(
                          color: Colors.white24,
                          fontSize: 12.5,
                        ),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  if (_searchCtrl.text.isNotEmpty)
                    IconButton(
                      icon: const Icon(
                        Icons.clear,
                        color: Colors.white38,
                        size: 18,
                      ),
                      onPressed: _searchCtrl.clear,
                    ),
                ],
              ),
            ),
            // Group chips (group-title= from iptv-org lists)
            if (_groups.isNotEmpty) ...[
              const SizedBox(height: 8),
              SizedBox(
                height: 32,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: const Text(
                          'All',
                          style: TextStyle(fontSize: 11),
                        ),
                        selected: _selectedGroup == null,
                        onSelected: (_) {
                          _selectedGroup = null;
                          _applyFilter();
                        },
                        selectedColor: accent.withValues(alpha: 0.25),
                      ),
                    ),
                    for (final g in _groups)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(g, style: const TextStyle(fontSize: 11)),
                          selected: _selectedGroup == g,
                          onSelected: (v) {
                            _selectedGroup = v ? g : null;
                            _applyFilter();
                          },
                          selectedColor: accent.withValues(alpha: 0.25),
                        ),
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 10),
            // Paged channel tiles — a full 10k list is virtualized, only
            // _visible tiles are materialized at a time.
            for (var i = 0; i < _visible && i < _filtered!.length; i++)
              Builder(
                builder: (context) {
                  final ch = _filtered![i];
                  return Container(
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
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      subtitle: Text(
                        ch.group == null ? ch.url : '${ch.group} · ${ch.url}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 11,
                        ),
                      ),
                      onTap: () => _play(ch.url, ch.name),
                    ),
                  );
                },
              ),
            if (_visible < _filtered!.length)
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 8),
                child: TextButton(
                  onPressed: () => setState(() => _visible += _channelPageSize),
                  child: Text(
                    'Show ${_filtered!.length - _visible > _channelPageSize ? '$_channelPageSize more' : 'all ${_filtered!.length - _visible}'} of ${_filtered!.length - _visible} remaining',
                    style: TextStyle(color: accent, fontSize: 12.5),
                  ),
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
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  subtitle: Text(
                    _savedServers[i].url,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                  trailing: IconButton(
                    icon: const Icon(
                      Icons.delete_outline,
                      color: Colors.white38,
                      size: 18,
                    ),
                    onPressed: () => _deleteServer(i),
                  ),
                  onTap: () =>
                      _play(_savedServers[i].url, _savedServers[i].name),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

