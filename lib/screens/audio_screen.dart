import 'dart:async';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../theme.dart';
import '../utils/crash_log.dart';
import '../utils/format.dart';
import 'player_screen.dart';

/// v1.0.20 Audio tab — every audio file on the device (MediaStore via
/// photo_manager), playable in the SAME player as videos (mpv renders the
/// waveform-less track over the normal control surface: seek, speed, EQ,
/// boost all apply). Replaces the old "File Manager" quick tile.
class AudioScreen extends StatefulWidget {
  const AudioScreen({super.key});

  @override
  State<AudioScreen> createState() => _AudioScreenState();
}

class _AudioScreenState extends State<AudioScreen> {
  final List<AssetEntity> _songs = [];
  bool _loading = true;
  bool _denied = false;

  @override
  void initState() {
    super.initState();
    _scan();
  }

  Future<void> _scan() async {
    setState(() {
      _loading = true;
      _denied = false;
    });
    try {
      // v1.0.20 forensics: the DEFAULT request option is RequestType
      // .common = image|video — no AUDIO. On Android 13+ that means the
      // video permission the app already holds does NOT cover music, the
      // scan below would query MediaStore.Audio with READ_MEDIA_AUDIO
      // denied and silently return zero songs (the classic "nothing
      // shows up" bug). Ask for the AUDIO type explicitly.
      final ps = await PhotoManager.requestPermissionExtend(
        requestOption: const PermissionRequestOption(
          androidPermission:
              AndroidPermission(type: RequestType.audio, mediaLocation: false),
        ),
      );
      if (!ps.isAuth && !ps.hasAccess) {
        CrashLog.crumb('audio.permission_denied');
        if (mounted) {
          setState(() {
            _loading = false;
            _denied = true;
          });
        }
        return;
      }
      final paths = await PhotoManager.getAssetPathList(
        type: RequestType.audio,
        onlyAll: true,
      );
      final items = <AssetEntity>[];
      if (paths.isNotEmpty) {
        final count = await paths.first.assetCountAsync;
        for (var start = 0; start < count; start += 200) {
          final end = (start + 200) > count ? count : start + 200;
          items.addAll(
              await paths.first.getAssetListRange(start: start, end: end));
        }
      }
      // Newest first, matching the video library's ordering.
      items.sort((a, b) => b.createDateTime.compareTo(a.createDateTime));
      if (!mounted) return;
      setState(() {
        _songs
          ..clear()
          ..addAll(items);
        _loading = false;
      });
      CrashLog.crumb('audio.scanned', {'count': _songs.length});
    } catch (e) {
      CrashLog.error('audio.scan_failed', e);
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Could not scan audio on this device')));
      }
    }
  }

  Future<void> _open(AssetEntity asset) async {
    try {
      final file = await asset.file;
      if (file == null) {
        throw StateError('no backing file for ${asset.id}');
      }
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PlayerScreen(
          path: file.path,
          title: asset.title ?? 'Audio',
          meta: {
            'File': file.path,
            'Duration (MediaStore)':
                formatDuration(Duration(seconds: asset.duration)),
            if (asset.mimeType != null) 'MIME': asset.mimeType!,
          },
        ),
      ));
    } catch (e) {
      CrashLog.error('audio.open_failed', e, {'id': asset.id});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open this audio file')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(_loading
            ? 'Audio'
            : 'Audio (${_songs.length})'),
        actions: [
          IconButton(
            tooltip: 'Rescan',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loading ? null : _scan,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_denied) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.library_music_outlined, size: 56),
              const SizedBox(height: 12),
              const Text(
                'Audio permission is needed to list songs on this device.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _scan,
                child: const Text('Grant & retry'),
              ),
            ],
          ),
        ),
      );
    }
    if (_songs.isEmpty) {
      return const Center(child: Text('No audio files found on this device'));
    }
    return RefreshIndicator(
      onRefresh: _scan,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _songs.length,
        separatorBuilder: (_, i) =>
            const Divider(height: 1, indent: 72),
        itemBuilder: (context, i) {
          final a = _songs[i];
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: AppColors.accent.withValues(alpha: 0.12),
              child: Icon(Icons.music_note, color: AppColors.accent),
            ),
            title: Text(
              a.title ?? 'Audio',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              formatDuration(Duration(seconds: a.duration)),
              maxLines: 1,
            ),
            onTap: () => unawaited(_open(a)),
          );
        },
      ),
    );
  }
}
