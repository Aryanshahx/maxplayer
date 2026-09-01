import 'dart:convert';
import 'package:flutter/material.dart';

import '../services/native_bridge.dart';
import '../state/theme_state.dart';

class NetworkLocation {
  final String name;
  final String protocol;
  final String host;
  final int port;
  final String path;
  final String username;
  final String password;

  const NetworkLocation({
    required this.name,
    required this.protocol,
    required this.host,
    this.port = 0,
    this.path = '',
    this.username = '',
    this.password = '',
  });

  String get streamUrl {
    final auth = username.isNotEmpty
        ? (password.isNotEmpty ? '$username:$password@' : '$username@')
        : '';
    final portStr = port > 0 ? ':$port' : '';
    final cleanPath = path.startsWith('/') ? path : '/$path';
    return '$protocol://$auth$host$portStr$cleanPath';
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'protocol': protocol,
        'host': host,
        'port': port,
        'path': path,
        'username': username,
        'password': password,
      };

  factory NetworkLocation.fromJson(Map<String, dynamic> j) => NetworkLocation(
        name: '${j['name'] ?? ''}',
        protocol: '${j['protocol'] ?? 'smb'}',
        host: '${j['host'] ?? ''}',
        port: int.tryParse('${j['port'] ?? 0}') ?? 0,
        path: '${j['path'] ?? ''}',
        username: '${j['username'] ?? ''}',
        password: '${j['password'] ?? ''}',
      );
}

/// v91: Phone & Tablet responsive Network Storage sheet (SMB, FTP, WebDAV) with dynamic contrast.
class NetworkStorageSheet extends StatefulWidget {
  final Future<void> Function(String url, String title) onPlay;

  const NetworkStorageSheet({super.key, required this.onPlay});

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
      builder: (_) => NetworkStorageSheet(onPlay: onPlay),
    );
  }

  @override
  State<NetworkStorageSheet> createState() => _NetworkStorageSheetState();
}

class _NetworkStorageSheetState extends State<NetworkStorageSheet> {
  final _nameCtrl = TextEditingController();
  final _hostCtrl = TextEditingController();
  final _portCtrl = TextEditingController();
  final _pathCtrl = TextEditingController();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  String _protocol = 'smb';
  List<NetworkLocation> _savedLocations = [];
  bool _showAddForm = false;

  static const String _kNetworkLocsKey = 'network.locations_v2';

  @override
  void initState() {
    super.initState();
    _loadLocations();
  }

  Future<void> _loadLocations() async {
    final s = await NativeBridge.loadSettings();
    final raw = s[_kNetworkLocsKey];
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List;
        setState(() {
          _savedLocations = list
              .map((e) => NetworkLocation.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList();
        });
      } catch (_) {}
    }
  }

  Future<void> _saveLocation() async {
    final name = _nameCtrl.text.trim();
    final host = _hostCtrl.text.trim();
    if (host.isEmpty) return;

    final loc = NetworkLocation(
      name: name.isNotEmpty ? name : '$_protocol://$host',
      protocol: _protocol,
      host: host,
      port: int.tryParse(_portCtrl.text.trim()) ?? 0,
      path: _pathCtrl.text.trim(),
      username: _userCtrl.text.trim(),
      password: _passCtrl.text.trim(),
    );

    setState(() {
      _savedLocations.add(loc);
      _showAddForm = false;
    });

    final jsonStr = jsonEncode(_savedLocations.map((e) => e.toJson()).toList());
    await NativeBridge.saveSetting(_kNetworkLocsKey, jsonStr);
  }

  Future<void> _deleteLocation(int index) async {
    setState(() => _savedLocations.removeAt(index));
    final jsonStr = jsonEncode(_savedLocations.map((e) => e.toJson()).toList());
    await NativeBridge.saveSetting(_kNetworkLocsKey, jsonStr);
  }

  void _connectAndPlay(NetworkLocation loc) {
    Navigator.of(context).pop();
    widget.onPlay(loc.streamUrl, loc.name);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _pathCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = themeState.accent;
    final btnTextColor = accent.computeLuminance() > 0.55 ? const Color(0xFF14141c) : Colors.white;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final screenH = MediaQuery.of(context).size.height;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: SizedBox(
          height: screenH * 0.8,
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
                    Icon(Icons.dns, color: accent, size: 22),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Network Storage (NAS / Share)',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (!_showAddForm)
                      IconButton(
                        icon: Icon(Icons.add_circle_outline, color: accent),
                        tooltip: 'Add Connection',
                        onPressed: () => setState(() => _showAddForm = true),
                      ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Colors.white12),
              Expanded(
                child: _showAddForm
                    ? SingleChildScrollView(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: [
                                _protoChip('smb', 'SMB (Windows/Samba)', accent),
                                _protoChip('ftp', 'FTP / FTPS', accent),
                                _protoChip('http', 'WebDAV', accent),
                              ],
                            ),
                            const SizedBox(height: 14),
                            _inputField(_nameCtrl, 'Connection Name (e.g. Living Room NAS)'),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: _inputField(_hostCtrl, 'Host / IP (e.g. 192.168.1.100)'),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  flex: 1,
                                  child: _inputField(
                                    _portCtrl,
                                    _protocol == 'smb' ? '445' : (_protocol == 'ftp' ? '21' : '80'),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            _inputField(_pathCtrl, 'Share / Folder path (e.g. /Movies/video.mp4)'),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(child: _inputField(_userCtrl, 'Username (optional)')),
                                const SizedBox(width: 8),
                                Expanded(child: _inputField(_passCtrl, 'Password', obscure: true)),
                              ],
                            ),
                            const SizedBox(height: 18),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.white70,
                                      side: const BorderSide(color: Colors.white24),
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                    onPressed: () => setState(() => _showAddForm = false),
                                    child: const Text('Cancel'),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: FilledButton(
                                    style: FilledButton.styleFrom(
                                      backgroundColor: accent,
                                      foregroundColor: btnTextColor,
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                    onPressed: _saveLocation,
                                    child: const Text('Save & Connect', style: TextStyle(fontWeight: FontWeight.bold)),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      )
                    : _savedLocations.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.dns_outlined, size: 48, color: Colors.white24),
                                  const SizedBox(height: 12),
                                  const Text(
                                    'No saved network storage connections',
                                    style: TextStyle(color: Colors.white54, fontSize: 14),
                                  ),
                                  const SizedBox(height: 16),
                                  FilledButton.icon(
                                    style: FilledButton.styleFrom(
                                      backgroundColor: accent,
                                      foregroundColor: btnTextColor,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                    onPressed: () => setState(() => _showAddForm = true),
                                    icon: const Icon(Icons.add),
                                    label: const Text('Add Network Storage', style: TextStyle(fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.all(14),
                            itemCount: _savedLocations.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (context, i) {
                              final loc = _savedLocations[i];
                              return Container(
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.05),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.white12),
                                ),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                                  leading: CircleAvatar(
                                    backgroundColor: accent.withValues(alpha: 0.2),
                                    child: Icon(
                                      loc.protocol == 'smb'
                                          ? Icons.folder_shared
                                          : (loc.protocol == 'ftp' ? Icons.cloud_download : Icons.storage),
                                      color: accent,
                                      size: 18,
                                    ),
                                  ),
                                  title: Text(
                                    loc.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                                  ),
                                  subtitle: Text(
                                    '${loc.protocol.toUpperCase()}  ·  ${loc.host}${loc.path}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: Colors.white38, fontSize: 11.5),
                                  ),
                                  trailing: IconButton(
                                    icon: const Icon(Icons.delete_outline, color: Colors.white38, size: 20),
                                    onPressed: () => _deleteLocation(i),
                                  ),
                                  onTap: () => _connectAndPlay(loc),
                                ),
                              );
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _protoChip(String proto, String label, Color accent) {
    final selected = _protocol == proto;
    final chipTextColor = selected
        ? (accent.computeLuminance() > 0.55 ? const Color(0xFF14141c) : Colors.white)
        : Colors.white70;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      selectedColor: accent,
      labelStyle: TextStyle(
        color: chipTextColor,
        fontSize: 12,
        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
      ),
      onSelected: (_) => setState(() => _protocol = proto),
    );
  }

  Widget _inputField(TextEditingController ctrl, String hint, {bool obscure = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
      ),
      child: TextField(
        controller: ctrl,
        obscureText: obscure,
        style: const TextStyle(color: Colors.white, fontSize: 13.5),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Colors.white38, fontSize: 12.5),
          border: InputBorder.none,
          isDense: true,
        ),
      ),
    );
  }
}
