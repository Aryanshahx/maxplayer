import 'package:url_launcher/url_launcher.dart';
import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../cloud_import.dart';
import '../local_thumbnail.dart';
import '../playlist.dart';
import '../local_media_index.dart';

const cloudVideoExtensions = [
  'mp4',
  'mkv',
  'avi',
  'mov',
  'webm',
  'm4v',
  'ts',
  'wmv'
];

/// Actual Android import screen composition with Windows picker/copy semantics.
/// Provider account operations remain in the operating-system file picker.
class DesktopCloudStorageScreen extends StatefulWidget {
  const DesktopCloudStorageScreen({super.key});
  @override
  State<DesktopCloudStorageScreen> createState() =>
      _DesktopCloudStorageScreenState();
}

class _DesktopCloudStorageScreenState extends State<DesktopCloudStorageScreen> {
  bool importing = false;
  bool loading = true;
  bool saving = false;
  String? error;
  int done = 0, total = 0;
  final imported = <String>[];
  ImportCancellation? cancellation;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList('hyper.cloud.imports.v1') ?? [];
      if (mounted) {
        setState(() {
          imported.addAll(saved);
          loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          loading = false;
          error =
              'Could not read the import list. Existing imported files are not deleted.';
        });
      }
    }
  }

  Future<void> choose() async {
    if (importing) return;
    setState(() {
      importing = true;
      error = null;
      done = 0;
      total = 0;
    });
    try {
      final selection = await openFile(acceptedTypeGroups: [
        const XTypeGroup(label: 'Video', extensions: cloudVideoExtensions)
      ]);
      if (selection == null || !mounted) return;
      final extension = selection.path.split('.').last.toLowerCase();
      if (!cloudVideoExtensions.contains(extension)) {
        throw const FormatException('Choose a supported video file.');
      }
      final token = ImportCancellation();
      cancellation = token;
      final support = await getApplicationSupportDirectory();
      final result = await importVideoFile(
          File(selection.path), Directory('${support.path}/imported_media'),
          cancellation: token, onProgress: (copied, size) {
        if (mounted) {
          setState(() {
            done = copied;
            total = size;
          });
        }
      });
      if (mounted) setState(() => imported.insert(0, result.path));
      try {
        final prefs = await SharedPreferences.getInstance();
        final saved = [
          result.path,
          ...?prefs.getStringList('hyper.cloud.imports.v1')
        ];
        if (!await prefs.setStringList('hyper.cloud.imports.v1', saved)) {
          throw StateError('Could not save import index');
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content:
                  Text('Video imported locally. Select it below to play.')));
        }
      } catch (_) {
        if (mounted) {
          setState(() => error =
              'Video copied, but its list entry could not be saved. Use Save copy as before closing this screen. The imported file has not been deleted.');
        }
      }
    } on ImportCancelled {
      if (mounted) {
        setState(() => error = 'Import cancelled. Incomplete copy removed.');
      }
    } catch (_) {
      if (mounted) {
        setState(() => error =
            'Could not import the video. Check available disk space and that the provider file is downloaded and accessible.');
      }
    } finally {
      cancellation = null;
      if (mounted) setState(() => importing = false);
    }
  }

  Future<void> saveCopy(String source) async {
    if (saving) return;
    setState(() => saving = true);
    try {
      final selected = await getSaveLocation(
          suggestedName:
              labelFor(source).replaceFirst(RegExp(r'^\d+-\d+-'), ''),
          acceptedTypeGroups: [
            const XTypeGroup(label: 'Video', extensions: cloudVideoExtensions)
          ]);
      if (selected == null) return;
      if (File(source).absolute.path.toLowerCase() ==
          File(selected.path).absolute.path.toLowerCase()) {
        return;
      }
      await File(source).copy(selected.path);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Copy saved. Original import kept.')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Could not save a copy. Check destination permissions and available space.')));
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> open(String path) async {
    if (!await File(path).exists()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Imported file is no longer available. Import it again.')));
      }
      return;
    }
    if (mounted) Navigator.pop(context, path);
  }

  @override
  void dispose() {
    cancellation?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      backgroundColor: const Color(0xff14141c),
      appBar: AppBar(
          backgroundColor: const Color(0xff14141c),
          title: const Text('Import from cloud storage',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold))),
      body: Center(
          child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: ListView(padding: const EdgeInsets.all(24), children: [
                Card(
                    child: ListTile(
                        leading: const Icon(Icons.cloud_circle, size: 40),
                        title:
                            const Text('pCloud · more space for your videos'),
                        subtitle: const Text(
                            'Partner link · Free plan and paid upgrades. We may earn a commission.'),
                        trailing: const Icon(Icons.open_in_new),
                        onTap: () => launchUrl(
                            Uri.parse('https://partner.pcloud.com/r/157632'),
                            mode: LaunchMode.externalApplication))),
                const SizedBox(height: 16),
                Center(
                    child: Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: .05)),
                        child: const Icon(Icons.drive_folder_upload_outlined,
                            size: 38, color: Colors.white))),
                const SizedBox(height: 16),
                const Text('Import a video',
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text(
                    'Windows’ file picker opens local folders and files made available by your installed or synced storage providers. Select a video to copy into Hyper Player’s local library.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Colors.white54, fontSize: 13, height: 1.4)),
                const SizedBox(height: 24),
                FilledButton.icon(
                    onPressed: importing ? null : choose,
                    style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12))),
                    icon: const Icon(Icons.file_open_outlined),
                    label: Text(
                        importing ? 'Importing…' : 'Choose a video to import',
                        style: const TextStyle(
                            fontSize: 14.5, fontWeight: FontWeight.bold))),
                const SizedBox(height: 12),
                const Text(
                    'Hyper Player does not request cloud passwords. Provider sign-in and on-demand downloads are handled by Windows or that provider. Google Drive/Dropbox/OneDrive appear only if available in your picker.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Colors.white38, fontSize: 11.5, height: 1.35)),
                if (importing && cancellation != null) ...[
                  const SizedBox(height: 18),
                  LinearProgressIndicator(
                      value: total > 0 ? (done / total).clamp(0, 1) : null,
                      minHeight: 6,
                      color: Colors.white),
                  const SizedBox(height: 8),
                  Text('${mediaSize(done)} of ${mediaSize(total)} copied',
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 12.5)),
                  TextButton(
                      onPressed: () => cancellation?.cancel(),
                      child: const Text('Cancel copy'))
                ],
                if (error != null)
                  Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(error!,
                          style: const TextStyle(
                              color: Colors.orangeAccent, fontSize: 12.5))),
                const SizedBox(height: 24),
                const Text('IMPORTED VIDEOS',
                    style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        letterSpacing: 1.1,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                if (loading)
                  const LinearProgressIndicator(minHeight: 2)
                else if (imported.isEmpty)
                  const Padding(
                      padding: EdgeInsets.symmetric(vertical: 18),
                      child: Text('No videos imported yet.',
                          style:
                              TextStyle(color: Colors.white38, fontSize: 13))),
                for (final path in imported)
                  Card(
                      color: const Color(0xff1b1b24),
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                          leading: SizedBox(
                              width: 80,
                              height: 45,
                              child: LocalThumbnail(path)),
                          title: Text(
                              labelFor(path)
                                  .replaceFirst(RegExp(r'^\d+-\d+-'), ''),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13)),
                          subtitle: const Text('Local imported copy',
                              style: TextStyle(
                                  color: Colors.white38, fontSize: 11.5)),
                          onTap: importing ? null : () => open(path),
                          trailing: IconButton(
                              tooltip: 'Save copy as…',
                              onPressed:
                                  importing ? null : () => saveCopy(path),
                              icon: const Icon(Icons.save_alt_rounded,
                                  size: 20)))),
                const SizedBox(height: 14),
                const Text(
                    'Imports are stored in this application’s support folder, not a cloud backup. Save a copy to a folder you control before uninstalling or clearing app data. Cancel stops the local copy between chunks; provider download dialogs are controlled by Windows.',
                    style: TextStyle(
                        color: Colors.white38, fontSize: 11.5, height: 1.5)),
              ]))));
}
