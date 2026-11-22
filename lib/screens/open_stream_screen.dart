import '../utils/app_language.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/saved_server.dart';
import '../theme.dart';
import '../utils/crash_log.dart';
import '../utils/iptv.dart';
import '../utils/local_store.dart';
import '../utils/m3u.dart';
import 'iptv_screen.dart';
import 'player_screen.dart';

/// Old-app parity: prefetching thousands of rows on first paint kills the
/// screen — page the channel list in chunks of this many tiles.
final int _channelPageSize = 50;

/// Open Stream (IPTV) — old-app parity: protocol chips, clipboard paste,
/// optional title, saved & recent streams, and .m3u/.m3u8 channel lists.
/// NO channels or playlists ship with the app — the user pastes their own
/// M3U link. v1.0.1+13: channel search & group filter, and a paged
/// channel list that survives 10k+ channel indexes.
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
  int _playlistRequest = 0;
  List<String> _groups = [];
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
      _playlistRequest++;
      _channels = null;
      _filtered = null;
      _loadingPlaylist = false;
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
    final path = Uri.tryParse(url)?.path.toLowerCase() ?? '';
    return path.endsWith('.m3u') || path.endsWith('.m3u8');
  }

  Future<void> _loadPlaylist(String url, String title) async {
    final requestId = ++_playlistRequest;
    setState(() => _loadingPlaylist = true);
    CrashLog.crumb('iptv.playlist', {'host': Uri.tryParse(url)?.host ?? ''});
    final source = await fetchM3uSource(url);
    if (!mounted || requestId != _playlistRequest) return;
    setState(() => _loadingPlaylist = false);
    if (source.isHls) {
      setState(() {
        _channels = null;
        _filtered = null;
      });
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PlayerScreen.stream(path: url, title: title),
        ),
      );
      await _loadServers();
      return;
    }
    if (source.error != null) {
      setState(() {
        _channels = null;
        _filtered = null;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(source.error!)));
      return;
    }
    final channels = source.channels;
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
        SnackBar(
          content: LText('No channels found — is that a public M3U link?'),
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

  Future<void> _play(
    String url,
    String title, {
    bool fromChannel = false,
  }) async {
    if (_loadingPlaylist) return;
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
    if (_looksLikePlaylist(cleanUrl) && !fromChannel) {
      // Inspect contents: HLS plays as one stream; IPTV M3U lists show channels.
      await _loadPlaylist(cleanUrl, name);
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
    Theme.of(context);
    final accent = AppColors.accent;
    final canPlay = _urlCtrl.text.trim().isNotEmpty && !_loadingPlaylist;

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: LText(
          'Open Stream(iptv)',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
        ),
      ),
      body: ListView(
        padding: EdgeInsets.all(20),
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
                'WebDAV',
              ])
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _detectedProto == p
                        ? accent.withValues(alpha: 0.25)
                        : AppColors.textPrimary.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: _detectedProto == p ? accent : AppColors.border,
                    ),
                  ),
                  child: Text(
                    p,
                    style: TextStyle(
                      color: _detectedProto == p
                          ? accent
                          : AppColors.textSecondary,
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          SizedBox(height: 16),
          // Stream URL input
          Container(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.textPrimary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: canPlay ? accent : AppColors.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _urlCtrl,
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13.5,
                    ),
                    decoration: LInputDecoration(
                      hintText: 'https://, http://, rtsp://, ftp://…',
                      hintStyle: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                      border: InputBorder.none,
                    ),
                    onSubmitted: (_) => _play(_urlCtrl.text, _titleCtrl.text),
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.paste,
                    color: AppColors.textSecondary,
                    size: 20,
                  ),
                  tooltip: 'Paste URL',
                  onPressed: _pasteFromClipboard,
                ),
              ],
            ),
          ),
          SizedBox(height: 10),
          // Optional title input
          Container(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.textPrimary.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(10),
            ),
            child: TextField(
              controller: _titleCtrl,
              style: TextStyle(color: AppColors.textPrimary, fontSize: 13),
              decoration: LInputDecoration(
                hintText: 'Stream title (optional)',
                hintStyle: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12.5,
                ),
                border: InputBorder.none,
              ),
            ),
          ),
          SizedBox(height: 16),
          // v1.0.1+62: one-tap LIVE TV — iptv-org's legal free-to-air
          // collection with logos, IN/WORLD switch, group filters.
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: accent.withValues(alpha: 0.16),
                foregroundColor: accent,
                side: BorderSide(color: accent.withValues(alpha: 0.6)),
                padding: EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => IptvScreen())),
              icon: Icon(Icons.live_tv_rounded),
              label: LText(
                'LIVE TV — free channels',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
          SizedBox(height: 20),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: AppColors.onAccent,
              padding: EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: canPlay
                ? () => _play(_urlCtrl.text, _titleCtrl.text)
                : null,
            icon: Icon(Icons.play_arrow),
            label: LText(
              'Play Stream',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          SizedBox(height: 8),
          LText(
            'Paste a direct stream or an IPTV channel list. HLS (.m3u8) plays as one stream; channel lists open below.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
          ),
          if (_loadingPlaylist) ...[
            SizedBox(height: 24),
            Center(child: CircularProgressIndicator(color: accent)),
            SizedBox(height: 8),
            Center(
              child: LText(
                'Fetching playlist… big lists take a moment',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
              ),
            ),
          ] else if (_channels != null && _filtered != null) ...[
            SizedBox(height: 16),
            Text(
              '${_filtered!.length} of ${_channels!.length} channels',
              style: TextStyle(
                color: accent,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 8),
            // Search bar
            Container(
              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.textPrimary.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(Icons.search, color: AppColors.textSecondary, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                      ),
                      decoration: LInputDecoration(
                        hintText: 'Search channels…',
                        hintStyle: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12.5,
                        ),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  if (_searchCtrl.text.isNotEmpty)
                    IconButton(
                      icon: Icon(
                        Icons.clear,
                        color: AppColors.textSecondary,
                        size: 18,
                      ),
                      onPressed: _searchCtrl.clear,
                    ),
                ],
              ),
            ),
            // Group chips (group-title= from iptv-org lists)
            if (_groups.isNotEmpty) ...[
              SizedBox(height: 8),
              SizedBox(
                height: 32,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    Padding(
                      padding: EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: LText('All', style: TextStyle(fontSize: 11)),
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
                        padding: EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(g, style: TextStyle(fontSize: 11)),
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
            SizedBox(height: 10),
            // Paged channel tiles — a full 10k list is virtualized, only
            // _visible tiles are materialized at a time.
            for (var i = 0; i < _visible && i < _filtered!.length; i++)
              Builder(
                builder: (context) {
                  final ch = _filtered![i];
                  return Container(
                    margin: EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: AppColors.textPrimary.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: ListTile(
                      dense: true,
                      leading: Icon(Icons.live_tv, color: accent, size: 20),
                      title: Text(
                        ch.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      subtitle: Text(
                        ch.group == null ? ch.url : '${ch.group} · ${ch.url}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                      onTap: () => _play(ch.url, ch.name, fromChannel: true),
                    ),
                  );
                },
              ),
            if (_visible < _filtered!.length)
              Padding(
                padding: EdgeInsets.only(top: 4, bottom: 8),
                child: TextButton(
                  onPressed: () => setState(() => _visible += _channelPageSize),
                  child: Text(
                    'Show ${_filtered!.length - _visible > _channelPageSize ? '$_channelPageSize more' : 'all ${_filtered!.length - _visible}'} of ${_filtered!.length - _visible} remaining',
                    style: TextStyle(color: accent, fontSize: 12.5),
                  ),
                ),
              ),
          ] else if (_savedServers.isNotEmpty) ...[
            SizedBox(height: 24),
            Row(
              children: [
                Icon(Icons.history, color: accent, size: 16),
                SizedBox(width: 6),
                LText(
                  'Saved & Recent Streams',
                  style: TextStyle(
                    color: accent,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            SizedBox(height: 10),
            for (var i = 0; i < _savedServers.length; i++)
              Container(
                margin: EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: AppColors.textPrimary.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.live_tv, color: accent, size: 20),
                  title: Text(
                    _savedServers[i].name,
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  subtitle: Text(
                    _savedServers[i].url,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                  trailing: IconButton(
                    icon: Icon(
                      Icons.delete_outline,
                      color: AppColors.textSecondary,
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
