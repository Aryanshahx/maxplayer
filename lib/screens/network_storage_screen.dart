import '../utils/app_language.dart';

import 'package:flutter/material.dart';

import '../models/network_location.dart';
import '../theme.dart';
import '../utils/crash_log.dart';
import '../utils/local_store.dart';
import 'player_screen.dart';

/// Network Storage (NAS / Share) — old-app parity: saved SMB / FTP / WebDAV
/// connections built from name + host + port + path + credentials, each
/// resolving to a stream URL that MPV opens directly.
class NetworkStorageScreen extends StatefulWidget {
  const NetworkStorageScreen({super.key});

  @override
  State<NetworkStorageScreen> createState() => _NetworkStorageScreenState();
}

class _NetworkStorageScreenState extends State<NetworkStorageScreen> {
  final _store = LocalStore();
  final _nameCtrl = TextEditingController();
  final _hostCtrl = TextEditingController();
  final _portCtrl = TextEditingController();
  final _pathCtrl = TextEditingController();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  String _protocol = 'smb';
  List<NetworkLocation> _savedLocations = [];
  bool _showAddForm = false;
  bool _loading = true;

  static final String _kNetworkLocsKey = 'network.locations_v2';

  @override
  void initState() {
    super.initState();
    _loadLocations();
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

  Future<void> _loadLocations() async {
    final raw = await _store.rawString(_kNetworkLocsKey);
    final list = parseNetworkLocationsJson(raw);
    if (mounted) {
      setState(() {
        _savedLocations = list;
        _loading = false;
      });
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
      _savedLocations = [loc, ..._savedLocations];
      _showAddForm = false;
      _nameCtrl.clear();
      _hostCtrl.clear();
      _portCtrl.clear();
      _pathCtrl.clear();
      _userCtrl.clear();
      _passCtrl.clear();
    });
    await _store.setRawString(
      _kNetworkLocsKey,
      networkLocationsToJson(_savedLocations),
    );
  }

  Future<void> _deleteLocation(int index) async {
    setState(() => _savedLocations.removeAt(index));
    await _store.setRawString(
      _kNetworkLocsKey,
      networkLocationsToJson(_savedLocations),
    );
  }

  void _connectAndPlay(NetworkLocation loc) async {
    CrashLog.crumb('network.play', {'url': loc.streamUrl});
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            PlayerScreen.stream(path: loc.streamUrl, title: loc.name),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final accent = AppColors.accent;
    final btnTextColor = AppColors.onAccent;
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: LText(
          'Network Storage (NAS / Share)',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
        ),
        actions: [
          if (!_showAddForm && !_loading)
            IconButton(
              icon: Icon(Icons.add_circle_outline, color: accent),
              tooltip: 'Add Connection',
              onPressed: () => setState(() => _showAddForm = true),
            ),
        ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator())
          : _showAddForm
          ? _buildAddForm(accent, btnTextColor)
          : _savedLocations.isEmpty
          ? _buildEmpty(accent, btnTextColor)
          : ListView.separated(
              padding: EdgeInsets.all(14),
              itemCount: _savedLocations.length,
              separatorBuilder: (_, _) => SizedBox(height: 8),
              itemBuilder: (context, i) {
                final loc = _savedLocations[i];
                return Container(
                  decoration: BoxDecoration(
                    color: AppColors.textPrimary.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: ListTile(
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 2,
                    ),
                    leading: CircleAvatar(
                      backgroundColor: accent.withValues(alpha: 0.2),
                      child: Icon(
                        loc.protocol == 'smb'
                            ? Icons.folder_shared
                            : (loc.protocol == 'ftp'
                                  ? Icons.cloud_download
                                  : Icons.storage),
                        color: accent,
                        size: 18,
                      ),
                    ),
                    title: Text(
                      loc.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    subtitle: Text(
                      '${loc.protocol.toUpperCase()}  ·  ${loc.host}${loc.path}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11.5,
                      ),
                    ),
                    trailing: IconButton(
                      icon: Icon(
                        Icons.delete_outline,
                        color: AppColors.textSecondary,
                        size: 20,
                      ),
                      onPressed: () => _deleteLocation(i),
                    ),
                    onTap: () => _connectAndPlay(loc),
                  ),
                );
              },
            ),
    );
  }

  Widget _buildEmpty(Color accent, Color btnTextColor) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.dns_outlined, size: 48, color: AppColors.border),
            SizedBox(height: 12),
            LText(
              'No saved network storage connections',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
            ),
            SizedBox(height: 16),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: btnTextColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () => setState(() => _showAddForm = true),
              icon: Icon(Icons.add),
              label: LText(
                'Add Network Storage',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddForm(Color accent, Color btnTextColor) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(18),
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
          SizedBox(height: 14),
          _inputField(_nameCtrl, 'Connection Name (e.g. Living Room NAS)'),
          SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: _inputField(_hostCtrl, 'Host / IP (e.g. 192.168.1.100)'),
              ),
              SizedBox(width: 8),
              Expanded(
                flex: 1,
                child: _inputField(
                  _portCtrl,
                  _protocol == 'smb'
                      ? '445'
                      : (_protocol == 'ftp' ? '21' : '80'),
                ),
              ),
            ],
          ),
          SizedBox(height: 10),
          _inputField(
            _pathCtrl,
            'Share / Folder path (e.g. /Movies/video.mp4)',
          ),
          SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _inputField(_userCtrl, 'Username (optional)')),
              SizedBox(width: 8),
              Expanded(
                child: _inputField(_passCtrl, 'Password', obscure: true),
              ),
            ],
          ),
          SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    side: BorderSide(color: AppColors.border),
                    padding: EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () => setState(() => _showAddForm = false),
                  child: LText('Cancel'),
                ),
              ),
              SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: btnTextColor,
                    padding: EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: _saveLocation,
                  child: LText(
                    'Save & Connect',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _protoChip(String proto, String label, Color accent) {
    final selected = _protocol == proto;
    final chipTextColor = selected
        ? (accent.computeLuminance() > 0.55
              ? AppColors.surface
              : AppColors.textPrimary)
        : AppColors.textSecondary;
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

  Widget _inputField(
    TextEditingController ctrl,
    String hint, {
    bool obscure = false,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.textPrimary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
      ),
      child: TextField(
        controller: ctrl,
        obscureText: obscure,
        style: TextStyle(color: AppColors.textPrimary, fontSize: 13.5),
        decoration: LInputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
          border: InputBorder.none,
          isDense: true,
        ),
      ),
    );
  }
}
