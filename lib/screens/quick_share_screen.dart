import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:share_plus/share_plus.dart';

import '../theme.dart';
import '../utils/badges.dart';
import '../utils/crash_log.dart';
import '../utils/format.dart';

/// Quick Share — pick videos and blast them out through the Android share
/// sheet (Nearby Share, Bluetooth, WhatsApp, Drive — whatever you have).
class QuickShareScreen extends StatefulWidget {
  const QuickShareScreen({super.key});

  @override
  State<QuickShareScreen> createState() => _QuickShareScreenState();
}

class _QuickShareScreenState extends State<QuickShareScreen> {
  List<AssetEntity>? _videos;
  final Set<String> _selected = {};
  bool _sharing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final perm = await PhotoManager.requestPermissionExtend();
    if (!perm.hasAccess || !mounted) return;
    final all = await PhotoManager.getAssetPathList(
        type: RequestType.video, hasAll: true);
    if (all.isEmpty) {
      if (mounted) setState(() => _videos = []);
      return;
    }
    final vids =
        await all.first.getAssetListPaged(page: 0, size: 200);
    if (mounted) setState(() => _videos = vids);
  }

  Future<void> _share() async {
    setState(() => _sharing = true);
    CrashLog.crumb('quickshare.send', {'count': _selected.length});
    try {
      final files = <XFile>[];
      for (final v in _videos!) {
        if (!_selected.contains(v.id)) continue;
        final f = await v.file;
        if (f != null && f.existsSync()) files.add(XFile(f.path));
      }
      if (files.isNotEmpty) {
        await SharePlus.instance.share(ShareParams(
            files: files,
            text: files.length == 1
                ? 'Shared from Max Player'
                : '${files.length} videos from Max Player'));
      }
    } catch (e) {
      CrashLog.error('quickshare.failed', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Share failed')));
      }
    }
    if (mounted) setState(() => _sharing = false);
  }

  @override
  Widget build(BuildContext context) {
    final vids = _videos;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Quick Share'),
        actions: [
          if (_selected.isNotEmpty)
            TextButton.icon(
              onPressed: _sharing ? null : _share,
              icon: Icon(Icons.ios_share_rounded,
                  color: AppColors.accent, size: 18),
              label: Text('Share ${_selected.length}',
                  style: TextStyle(color: AppColors.accent)),
            ),
        ],
      ),
      body: vids == null
          ? Center(child: CircularProgressIndicator(color: AppColors.accent))
          : vids.isEmpty
              ? const Center(
                  child: Text('No videos on this device.',
                      style: TextStyle(color: AppColors.textSecondary)))
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: vids.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder: (context, i) {
                    final v = vids[i];
                    final sel = _selected.contains(v.id);
                    return Card(
                      child: CheckboxListTile(
                        value: sel,
                        activeColor: AppColors.accent,
                        checkColor: AppColors.onAccent,
                        title: Text(v.title ?? 'Video',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 13.5)),
                        subtitle: Text(
                          '${qualityBadge(v.width, v.height)} · '
                          '${formatDuration(Duration(seconds: v.duration))}',
                          style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 11.5),
                        ),
                        onChanged: (_) => setState(() => sel
                            ? _selected.remove(v.id)
                            : _selected.add(v.id)),
                      ),
                    );
                  },
                ),
    );
  }
}
