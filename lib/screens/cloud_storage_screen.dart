import 'package:flutter/material.dart';

import '../theme.dart';
import '../utils/crash_log.dart';
import '../utils/local_store.dart';
import 'network_storage_screen.dart' show askSavedLinkDialog;
import 'player_screen.dart';

/// Cloud Storage — saved direct-download links (Google Drive/Dropbox/
/// OneDrive "direct link") played as streams. OAuth sign-in to cloud
/// providers is a later phase; direct links work today via MPV.
class CloudStorageScreen extends StatefulWidget {
  const CloudStorageScreen({super.key});

  @override
  State<CloudStorageScreen> createState() => _CloudStorageScreenState();
}

class _CloudStorageScreenState extends State<CloudStorageScreen> {
  final _store = LocalStore();
  List<SavedLink> _links = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final links = await _store.cloudLinks();
    if (mounted) {
      setState(() {
        _links = links;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cloud Storage')),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.accent,
        foregroundColor: AppColors.onAccent,
        onPressed: () async {
          final link = await askSavedLinkDialog(context,
              nameHint: 'Cloud video',
              urlHint: 'Direct video URL (Drive / Dropbox / OneDrive)');
          if (link != null) {
            await _store.saveCloudLink(link);
            CrashLog.crumb('cloud.link_saved');
            await _load();
          }
        },
        child: const Icon(Icons.add_rounded),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: AppColors.accent))
          : _links.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'Paste a DIRECT download link to a video in your cloud.\n\n'
                      'Drive: Share → “Anyone with the link” → use the direct-download URL.\n'
                      'Dropbox: change dl=0 to dl=1 in the share link.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: AppColors.textSecondary, height: 1.5),
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: _links.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final link = _links[i];
                    return Card(
                      child: ListTile(
                        leading: Icon(Icons.cloud_outlined,
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
                            await _store.deleteCloudLink(link.url);
                            await _load();
                          },
                        ),
                        onTap: () async {
                          CrashLog.crumb('cloud.play', {'url': link.url});
                          await _store.addRecentStream(link);
                          if (!context.mounted) return;
                          await Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => PlayerScreen.stream(
                                path: link.url, title: link.name),
                          ));
                        },
                      ),
                    );
                  },
                ),
    );
  }
}
