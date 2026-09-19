import 'dart:async';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../theme.dart';
import '../utils/audio_player.dart';
import '../utils/crash_log.dart';
import '../utils/format.dart';
import 'audio_player_screen.dart';

/// v1.0.21 Audio tab — every audio file on the device, with search, sort,
/// a process-lifetime playback engine, a mini player bar, and the full
/// Now Playing screen (AudioPlayerScreen). Replaces the old "File Manager"
/// quick tile.
enum _AudioSort { dateDesc, titleAsc, durationDesc }

class AudioScreen extends StatefulWidget {
  const AudioScreen({super.key});

  @override
  State<AudioScreen> createState() => _AudioScreenState();
}

class _AudioScreenState extends State<AudioScreen> {
  final List<AssetEntity> _songs = [];
  final TextEditingController _searchCtrl = TextEditingController();
  bool _loading = true;
  bool _denied = false;
  String _query = '';
  _AudioSort _sort = _AudioSort.dateDesc;

  @override
  void initState() {
    super.initState();
    AudioPlayerHolder.instance.addListener(_onEngine);
    _scan();
  }

  @override
  void dispose() {
    AudioPlayerHolder.instance.removeListener(_onEngine);
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onEngine() {
    if (mounted) setState(() {});
  }

  Future<void> _scan() async {
    setState(() {
      _loading = true;
      _denied = false;
    });
    try {
      // The DEFAULT request option is RequestType.common = image|video —
      // no AUDIO. On Android 13+ the video permission does NOT cover
      // music, and the scan below would silently return zero songs.
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

  List<AssetEntity> get _visible {
    var list = _songs;
    final q = _query.trim().toLowerCase();
    if (q.isNotEmpty) {
      list =
          list.where((a) => (a.title ?? '').toLowerCase().contains(q)).toList();
    }
    final sorted = List<AssetEntity>.from(list);
    switch (_sort) {
      case _AudioSort.dateDesc:
        sorted.sort((a, b) => b.createDateTime.compareTo(a.createDateTime));
        break;
      case _AudioSort.titleAsc:
        sorted.sort((a, b) =>
            (a.title ?? '').toLowerCase().compareTo((b.title ?? '').toLowerCase()));
        break;
      case _AudioSort.durationDesc:
        sorted.sort((a, b) => b.duration.compareTo(a.duration));
        break;
    }
    return sorted;
  }

  Future<void> _openTrack(List<AssetEntity> visible, int i) async {
    await AudioPlayerHolder.instance.setQueue(visible, i);
    if (!mounted) return;
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const AudioPlayerScreen()));
  }

  void _cycleSort() {
    setState(() {
      _sort = _AudioSort.values[(_sort.index + 1) % _AudioSort.values.length];
    });
  }

  String get _sortLabel => switch (_sort) {
        _AudioSort.dateDesc => 'Newest',
        _AudioSort.titleAsc => 'A–Z',
        _AudioSort.durationDesc => 'Longest',
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(_loading ? 'Audio' : 'Audio (${_visible.length})'),
        actions: [
          if (_songs.isNotEmpty)
            TextButton.icon(
              onPressed: _cycleSort,
              icon: const Icon(Icons.sort_rounded, size: 18),
              label: Text(_sortLabel),
            ),
          IconButton(
            tooltip: 'Rescan',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loading ? null : _scan,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_songs.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _query = v),
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Search songs…',
                  isDense: true,
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close_rounded, size: 18),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _query = '');
                          },
                        ),
                  filled: true,
                  fillColor: AppColors.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
          Expanded(child: _buildBody()),
          _MiniBar(onOpenFull: () {
            Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AudioPlayerScreen()));
          }),
        ],
      ),
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
    final visible = _visible;
    if (visible.isEmpty) {
      return Center(
          child: Text(
              _query.isEmpty
                  ? 'No audio files found on this device'
                  : 'No matches for "$_query"',
              style: const TextStyle(color: AppColors.textSecondary)));
    }
    final holder = AudioPlayerHolder.instance;
    return RefreshIndicator(
      onRefresh: _scan,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: visible.length,
        separatorBuilder: (_, i) => const Divider(height: 1, indent: 72),
        itemBuilder: (context, i) {
          final a = visible[i];
          final isCurrent = holder.hasTrack &&
              holder.current?.id == a.id;
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: AppColors.accent.withValues(alpha: 0.12),
              child: Icon(
                isCurrent && holder.playing
                    ? Icons.graphic_eq_rounded
                    : Icons.music_note,
                color: AppColors.accent,
              ),
            ),
            title: Text(
              a.title ?? 'Audio',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color:
                    isCurrent ? AppColors.accent : AppColors.textPrimary,
                fontWeight:
                    isCurrent ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            subtitle: Text(
              formatDuration(Duration(seconds: a.duration)),
              maxLines: 1,
            ),
            onTap: () => unawaited(_openTrack(visible, i)),
          );
        },
      ),
    );
  }
}

/// Bottom mini bar — visible while the engine has a track, survives this
/// screen being rebuilt/popped; the engine is process-lifetime.
class _MiniBar extends StatelessWidget {
  const _MiniBar({required this.onOpenFull});

  final VoidCallback onOpenFull;

  @override
  Widget build(BuildContext context) {
    final holder = AudioPlayerHolder.instance;
    return AnimatedBuilder(
      animation: holder,
      builder: (context, _) {
        if (!holder.hasTrack) return const SizedBox.shrink();
        return Material(
          color: AppColors.surface,
          child: InkWell(
            onTap: onOpenFull,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
              child: Row(
                children: [
                  Icon(Icons.music_note_rounded, color: AppColors.accent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(holder.currentTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        Text(
                          '${formatDuration(holder.position)} / ${formatDuration(holder.duration)}',
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 11.5),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      holder.playing
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                    ),
                    onPressed: () => unawaited(holder.toggle()),
                  ),
                  IconButton(
                    icon: const Icon(Icons.skip_next_rounded),
                    onPressed: () => unawaited(holder.next()),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
