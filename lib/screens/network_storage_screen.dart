import 'package:flutter/material.dart';

import '../theme.dart';
import '../utils/crash_log.dart';
import '../utils/local_store.dart';
import 'player_screen.dart';

/// Network Storage — saved LAN/direct media links (HTTP, FTP, RTSP, SMB-
/// style URLs that MPV/ffmpeg can open). Save a server/share once, tap to
/// stream it later.
class NetworkStorageScreen extends StatefulWidget {
  const NetworkStorageScreen({super.key});

  @override
  State<NetworkStorageScreen> createState() => _NetworkStorageScreenState();
}

class _NetworkStorageScreenState extends State<NetworkStorageScreen> {
  final _store = LocalStore();
  List<SavedLink> _links = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final links = await _store.networkLinks();
    if (mounted) {
      setState(() {
        _links = links;
        _loading = false;
      });
    }
  }

  Future<void> _add() async {
    final link = await _askLink(context);
    if (link == null) return;
    await _store.saveNetworkLink(link);
    CrashLog.crumb('network.link_saved', {'url': link.url});
    await _load();
  }

  Future<void> _play(SavedLink link) async {
    CrashLog.crumb('network.play', {'url': link.url});
    await _store.addRecentStream(link);
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) =>
          PlayerScreen.stream(path: link.url, title: link.name),
    ));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Network Storage')),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.accent,
        foregroundColor: AppColors.onAccent,
        onPressed: _add,
        child: const Icon(Icons.add_rounded),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: AppColors.accent))
          : _links.isEmpty
              ? const _NetworkEmpty()
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: _links.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final link = _links[i];
                    return Card(
                      child: ListTile(
                        leading: Icon(Icons.dns_outlined,
                            color: AppColors.accent),
                        title: Text(link.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: AppColors.textPrimary)),
                        subtitle: Text(link.url,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12)),
                        trailing: IconButton(
                          tooltip: 'Remove',
                          icon: const Icon(Icons.delete_outline_rounded,
                              color: AppColors.textSecondary, size: 20),
                          onPressed: () async {
                            await _store.deleteNetworkLink(link.url);
                            await _load();
                          },
                        ),
                        onTap: () => _play(link),
                      ),
                    );
                  },
                ),
    );
  }
}

/// Shared name+url dialog used by Network & Cloud storage screens.
Future<SavedLink?> askSavedLinkDialog(BuildContext context,
    {String nameHint = 'Server share', String urlHint = 'http://… / smb://…'}) {
  return _askLink(context, nameHint: nameHint, urlHint: urlHint);
}

Future<SavedLink?> _askLink(BuildContext context,
    {String nameHint = 'Server share', String urlHint = 'http://… / smb://…'}) {
  final name = TextEditingController();
  final url = TextEditingController();
  return showDialog<SavedLink>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border),
      ),
      title: const Text('Add a network link',
          style: TextStyle(color: AppColors.textPrimary, fontSize: 17)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: name,
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: const InputDecoration(
              hintText: 'Name (e.g. Family videos)',
              hintStyle: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: url,
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: InputDecoration(
              hintText: urlHint,
              hintStyle: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel',
              style: TextStyle(color: AppColors.textSecondary)),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.accent,
            foregroundColor: AppColors.onAccent,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: () {
            final u = url.text.trim();
            if (u.isEmpty) return;
            Navigator.of(context).pop(SavedLink(
                name: name.text.trim().isEmpty ? nameHint : name.text.trim(),
                url: u));
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
}

class _NetworkEmpty extends StatelessWidget {
  const _NetworkEmpty();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.dns_outlined,
                size: 46, color: AppColors.accent),
            const SizedBox(height: 12),
            const Text(
              'Add a server link to stream from your PC or NAS.\n'
              'MPV understands http://, ftp://, rtsp:// and most smb:// URLs.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}
