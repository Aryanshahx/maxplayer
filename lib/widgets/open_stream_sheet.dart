import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/saved_server.dart';
import '../services/native_bridge.dart';
import '../state/theme_state.dart';

/// v84: Dedicated, phone-optimized Open Stream sheet.
class OpenStreamSheet extends StatefulWidget {
  final Future<void> Function(String url, String title) onPlay;

  const OpenStreamSheet({super.key, required this.onPlay});

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
      builder: (_) => OpenStreamSheet(onPlay: onPlay),
    );
  }

  @override
  State<OpenStreamSheet> createState() => _OpenStreamSheetState();
}

class _OpenStreamSheetState extends State<OpenStreamSheet> {
  final _urlCtrl = TextEditingController();
  final _titleCtrl = TextEditingController();

  List<SavedServer> _savedServers = [];
  String? _detectedProto;

  @override
  void initState() {
    super.initState();
    _urlCtrl.addListener(_onUrlChanged);
    _loadServers();
  }

  Future<void> _loadServers() async {
    final s = await NativeBridge.loadSettings();
    final list = parseServersJson(s[kServersSettingKey]);
    if (mounted) setState(() => _savedServers = list);
  }

  void _onUrlChanged() {
    final uri = Uri.tryParse(_urlCtrl.text.trim());
    setState(() {
      _detectedProto = (uri != null && uri.hasScheme) ? uri.scheme.toUpperCase() : null;
    });
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data != null && data.text != null && data.text!.isNotEmpty) {
      _urlCtrl.text = data.text!.trim();
    }
  }

  void _play(String url, String title) {
    final cleanUrl = url.trim();
    if (cleanUrl.isEmpty) return;
    final name = title.trim().isNotEmpty ? title.trim() : _serverNameFor(cleanUrl);

    // Save to servers list
    _savedServers = addSavedServer(_savedServers, SavedServer(name: name, url: cleanUrl));
    NativeBridge.saveSetting(kServersSettingKey, serversToJson(_savedServers));

    Navigator.of(context).pop();
    widget.onPlay(cleanUrl, name);
  }

  void _deleteServer(int index) {
    setState(() => _savedServers.removeAt(index));
    NativeBridge.saveSetting(kServersSettingKey, serversToJson(_savedServers));
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
    _urlCtrl.dispose();
    _titleCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = themeState.accent;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final canPlay = _urlCtrl.text.trim().isNotEmpty;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.75,
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
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                child: Row(
                  children: [
                    Icon(Icons.link, color: accent, size: 22),
                    const SizedBox(width: 10),
                    const Text(
                      'Open Network Stream',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Colors.white12),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    // Protocols Row
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final p in ['HTTP', 'HTTPS', 'HLS/M3U8', 'RTSP', 'RTMP', 'FTP', 'SMB', 'WebDAV'])
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: _detectedProto == p ? accent.withValues(alpha: 0.25) : Colors.white.withValues(alpha: 0.05),
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
                    // Optional Title input
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
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: canPlay ? () => _play(_urlCtrl.text, _titleCtrl.text) : null,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Play Stream', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    if (_savedServers.isNotEmpty) ...[
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
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                            ),
                            subtitle: Text(
                              _savedServers[i].url,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white38, fontSize: 11),
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.white38, size: 18),
                              onPressed: () => _deleteServer(i),
                            ),
                            onTap: () => _play(_savedServers[i].url, _savedServers[i].name),
                          ),
                        ),
                    ],
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
