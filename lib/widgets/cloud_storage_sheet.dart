import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/gdrive_service.dart';
import '../services/native_bridge.dart';
import '../state/theme_state.dart';
import '../utils/formatters.dart';

/// v84: Dedicated Cloud Storage (Google Drive) sheet for mobile phones.
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

class _CloudStorageSheetState extends State<CloudStorageSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  final TextEditingController _linkCtrl = TextEditingController();
  final TextEditingController _apiKeyCtrl = TextEditingController();

  bool _loading = false;
  List<GDriveItem> _driveItems = [];
  String? _detectedId;

  static const String _kSavedDriveKey = 'gdrive.api_key';

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _linkCtrl.addListener(_onLinkChanged);
    _loadSavedKey();
  }

  Future<void> _loadSavedKey() async {
    final s = await NativeBridge.loadSettings();
    final savedKey = s[_kSavedDriveKey];
    if (savedKey != null && savedKey.isNotEmpty && mounted) {
      _apiKeyCtrl.text = savedKey;
      _loadDriveFiles(savedKey);
    }
  }

  void _onLinkChanged() {
    final id = GDriveService.parseDriveFileId(_linkCtrl.text);
    setState(() => _detectedId = id);
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data != null && data.text != null && data.text!.isNotEmpty) {
      _linkCtrl.text = data.text!.trim();
    }
  }

  Future<void> _loadDriveFiles(String key) async {
    if (key.trim().isEmpty) return;
    setState(() => _loading = true);
    final items = await GDriveService.listDriveFiles(apiKey: key.trim());
    if (mounted) {
      setState(() {
        _driveItems = items;
        _loading = false;
      });
      NativeBridge.saveSetting(_kSavedDriveKey, key.trim());
    }
  }

  void _playLink() {
    final id = _detectedId;
    if (id == null || id.isEmpty) return;
    final streamUrl = GDriveService.getDirectStreamUrl(id);
    Navigator.of(context).pop();
    widget.onPlay(streamUrl, 'Google Drive Video');
  }

  void _playItem(GDriveItem item) {
    Navigator.of(context).pop();
    widget.onPlay(item.streamUrl, item.name);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _linkCtrl.dispose();
    _apiKeyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = themeState.accent;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

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
                    Icon(Icons.cloud_queue, color: accent, size: 22),
                    const SizedBox(width: 10),
                    const Text(
                      'Cloud Storage (Google Drive)',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              TabBar(
                controller: _tabCtrl,
                indicatorColor: accent,
                labelColor: accent,
                unselectedLabelColor: Colors.white54,
                tabs: const [
                  Tab(text: 'Paste Drive Link'),
                  Tab(text: 'Drive API Browser'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabCtrl,
                  children: [
                    // Tab 1: Paste Drive Link
                    ListView(
                      padding: const EdgeInsets.all(20),
                      children: [
                        const Text(
                          'Paste any Google Drive shared video link to stream instantly without downloading:',
                          style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
                        ),
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _detectedId != null
                                  ? accent
                                  : Colors.white12,
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _linkCtrl,
                                  style: const TextStyle(color: Colors.white, fontSize: 14),
                                  decoration: const InputDecoration(
                                    hintText: 'https://drive.google.com/file/d/...',
                                    hintStyle: TextStyle(color: Colors.white38),
                                    border: InputBorder.none,
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.paste, color: Colors.white70, size: 20),
                                tooltip: 'Paste from clipboard',
                                onPressed: _pasteFromClipboard,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (_detectedId != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.check_circle_outline, color: accent, size: 16),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Valid File ID: $_detectedId',
                                    style: TextStyle(color: accent, fontSize: 12, fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 20),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: accent,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: _detectedId != null ? _playLink : null,
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('Stream Video Now', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'Client ID: ${GDriveService.clientId}',
                          style: TextStyle(color: Colors.white24, fontSize: 11),
                        ),
                      ],
                    ),

                    // Tab 2: Drive API Browser
                    Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
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
                                    controller: _apiKeyCtrl,
                                    style: const TextStyle(color: Colors.white, fontSize: 13),
                                    decoration: const InputDecoration(
                                      hintText: 'Enter Google Drive API Key…',
                                      hintStyle: TextStyle(color: Colors.white38),
                                      border: InputBorder.none,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              FilledButton(
                                style: FilledButton.styleFrom(
                                  backgroundColor: accent,
                                  visualDensity: VisualDensity.compact,
                                ),
                                onPressed: () => _loadDriveFiles(_apiKeyCtrl.text),
                                child: const Text('Connect'),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: _loading
                              ? const Center(child: CircularProgressIndicator())
                              : _driveItems.isEmpty
                                  ? const Center(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.video_library_outlined, size: 40, color: Colors.white24),
                                          SizedBox(height: 8),
                                          Text(
                                            'Connect with API key to list cloud videos',
                                            style: TextStyle(color: Colors.white54, fontSize: 13),
                                          ),
                                        ],
                                      ),
                                    )
                                  : ListView.separated(
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                      itemCount: _driveItems.length,
                                      separatorBuilder: (_, __) => const Divider(height: 1, color: Colors.white10),
                                      itemBuilder: (context, i) {
                                        final item = _driveItems[i];
                                        return ListTile(
                                          leading: Icon(
                                            item.isFolder ? Icons.folder : Icons.video_file,
                                            color: accent,
                                          ),
                                          title: Text(
                                            item.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(color: Colors.white, fontSize: 13.5),
                                          ),
                                          subtitle: Text(
                                            formatFileSize(item.sizeBytes),
                                            style: const TextStyle(color: Colors.white38, fontSize: 11),
                                          ),
                                          trailing: const Icon(Icons.play_circle_outline, color: Colors.white70),
                                          onTap: () => _playItem(item),
                                        );
                                      },
                                    ),
                        ),
                      ],
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
