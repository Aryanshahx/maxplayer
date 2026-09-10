import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../theme.dart';
import '../utils/crash_log.dart';
import '../widgets/video_grid.dart';

/// File Manager — MediaStore-backed browse of the whole device, grouped by
/// real folder. Videos open in the player, images in a viewer, other files
/// are listed (no raw-file access is granted to scoped-storage apps).
class FileManagerScreen extends StatefulWidget {
  const FileManagerScreen({super.key});

  @override
  State<FileManagerScreen> createState() => _FileManagerScreenState();
}

class _FileManagerScreenState extends State<FileManagerScreen> {
  List<AssetPathEntity>? _paths;
  bool _denied = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final perm = await PhotoManager.requestPermissionExtend();
    if (!mounted) return;
    if (!perm.hasAccess) {
      setState(() => _denied = true);
      return;
    }
    final paths = await PhotoManager.getAssetPathList(
        type: RequestType.common, hasAll: true);
    paths.removeWhere((p) => p.name == 'All');
    paths.sort((a, b) => a.name.compareTo(b.name));
    if (mounted) setState(() => _paths = paths);
  }

  @override
  Widget build(BuildContext context) {
    if (_denied) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'File Manager needs media access to list your folders.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 14),
                FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: AppColors.onAccent),
                  onPressed: () =>
                      PhotoManager.openSetting().then((_) => _load()),
                  child: const Text('Open system settings'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final paths = _paths;
    return Scaffold(
      appBar: AppBar(title: const Text('File Manager')),
      body: paths == null
          ? Center(child: CircularProgressIndicator(color: AppColors.accent))
          : paths.isEmpty
              ? const Center(
                  child: Text('No media folders found on this device.',
                      style: TextStyle(color: AppColors.textSecondary)))
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: paths.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final p = paths[i];
                    return Card(
                      child: FutureBuilder<int>(
                        future: p.assetCountAsync,
                        builder: (context, snap) => ListTile(
                          leading: Icon(Icons.folder_outlined,
                              color: AppColors.accent),
                          title: Text(p.name,
                              style: const TextStyle(
                                  color: AppColors.textPrimary)),
                          subtitle: Text('${snap.data ?? '…'} files',
                              style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12)),
                          trailing: const Icon(
                              Icons.chevron_right_rounded,
                              color: AppColors.textSecondary),
                          onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) =>
                                      _FolderBrowseScreen(path: p))),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

class _FolderBrowseScreen extends StatefulWidget {
  const _FolderBrowseScreen({required this.path});

  final AssetPathEntity path;

  @override
  State<_FolderBrowseScreen> createState() => _FolderBrowseScreenState();
}

class _FolderBrowseScreenState extends State<_FolderBrowseScreen> {
  final List<AssetEntity> _assets = [];
  bool _hasMore = true;
  bool _loading = false;
  int _page = 0;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels >
              _scroll.position.maxScrollExtent - 300 &&
          !_loading &&
          _hasMore) {
        _more();
      }
    });
    _more();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _more() async {
    _loading = true;
    final batch =
        await widget.path.getAssetListPaged(page: _page, size: 60);
    if (!mounted) return;
    setState(() {
      _assets.addAll(batch);
      _hasMore = batch.length == 60;
      _page++;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final videos =
        _assets.where((a) => a.type == AssetType.video).toList();
    return Scaffold(
      appBar: AppBar(title: Text(widget.path.name)),
      body: LayoutBuilder(
        builder: (context, c) {
          final cols = (c.maxWidth / 150).floor().clamp(3, 8);
          return GridView.builder(
            controller: _scroll,
            padding: const EdgeInsets.all(12),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
            ),
            itemCount: _assets.length,
            itemBuilder: (context, i) {
              final a = _assets[i];
              final isVideo = a.type == AssetType.video;
              final isImage = a.type == AssetType.image;
              return Card(
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () {
                    CrashLog.crumb('fileman.open', {'type': '${a.type}'});
                    if (isVideo) {
                      // play within the folder's video queue
                      VideoGrid.openVideo(context, a, queue: videos);
                    } else if (isImage) {
                      _previewImage(a);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(
                              '${a.title ?? 'File'} — this format opens in its own app')));
                    }
                  },
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      FutureBuilder(
                        future: a.thumbnailDataWithSize(
                            const ThumbnailSize(200, 200)),
                        builder: (context, snap) =>
                            snap.hasError || snap.data == null
                                ? ColoredBox(
                                    color: AppColors.surfaceAlt,
                                    child: Center(
                                      child: Icon(
                                        isVideo
                                            ? Icons.videocam_outlined
                                            : isImage
                                                ? Icons.image_outlined
                                                : Icons
                                                    .insert_drive_file_outlined,
                                        color: AppColors.textSecondary,
                                        size: 30,
                                      ),
                                    ),
                                  )
                                : Image.memory(snap.data!,
                                    fit: BoxFit.cover),
                      ),
                      if (isVideo)
                        Positioned(
                          right: 6,
                          bottom: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.7),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${a.duration}s',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 10.5),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _previewImage(AssetEntity a) async {
    final file = await a.file;
    if (!mounted || file == null) return;
    await showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          fit: StackFit.expand,
          children: [
            InteractiveViewer(child: Image.file(file)),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
