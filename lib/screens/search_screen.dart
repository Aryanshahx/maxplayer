import 'dart:async';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../theme.dart';
import '../utils/collections.dart';
import '../utils/local_store.dart';
import '../utils/settings.dart';
import '../utils/sort.dart';
import '../widgets/video_grid.dart';

/// Dedicated search screen (opened from the home search icon):
/// live filters EVERY video on the device as you type.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  static const _pageSize = 100;

  final _ctrl = TextEditingController();
  final List<AssetEntity> _all = [];
  Set<String> _priv = {};
  bool _exhausted = false;
  bool _loadingMore = true;
  int _page = 0;
  AssetPathEntity? _path;
  Timer? _debounce;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    _priv = await LocalStore().privateIds();
    final paths = await PhotoManager.getAssetPathList(
        type: RequestType.video, onlyAll: true);
    if (paths.isEmpty) {
      if (mounted) {
        setState(() {
          _exhausted = true;
          _loadingMore = false;
        });
      }
      return;
    }
    _path = paths.first;
    await _drain();
  }

  Future<void> _drain() async {
    final path = _path;
    if (path == null) return;
    while (mounted && !_exhausted) {
      final batch =
          await path.getAssetListPaged(page: _page, size: _pageSize);
      if (batch.length < _pageSize) _exhausted = true;
      _page++;
      final vids = batch.where((a) => a.type == AssetType.video).toList();
      final before = _all.length;
      final merged = appendUnique(_all, vids, (a) => a.id);
      _all
        ..clear()
        ..addAll(merged);
      if (mounted) setState(() {});
      if (_all.length == before && _exhausted) break;
      await Future.delayed(const Duration(milliseconds: 30));
    }
    if (mounted) setState(() => _loadingMore = false);
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () {
      if (mounted) setState(() => _query = v.trim().toLowerCase());
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = AppSettings.instance;
    final results = _all.where((a) {
      if (_priv.contains(a.id)) return false;
      if (s.onlyFavs) {
        // favourites-only applies here too
      }
      if (_query.isEmpty) return false;
      return (a.title ?? '').toLowerCase().contains(_query);
    }).toList()
      ..sort((x, y) => cmpStr(x.title ?? '', y.title ?? '', true));

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _ctrl,
          autofocus: true,
          onChanged: _onChanged,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: 'Search all videos…',
            hintStyle: const TextStyle(color: AppColors.textSecondary),
            border: InputBorder.none,
            suffixIcon: _query.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.close_rounded,
                        color: AppColors.textSecondary),
                    onPressed: () {
                      _ctrl.clear();
                      _onChanged('');
                    },
                  )
                : null,
          ),
        ),
      ),
      body: _query.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.search_rounded,
                      size: 46, color: AppColors.textSecondary),
                  const SizedBox(height: 12),
                  const Text('Type to search every video on this device',
                      style: TextStyle(color: AppColors.textSecondary)),
                  if (_loadingMore) ...[
                    const SizedBox(height: 10),
                    Text('Indexing… ${_all.length} scanned',
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 11)),
                  ],
                ],
              ),
            )
          : results.isEmpty
              ? Center(
                  child: Text(
                    _loadingMore
                        ? 'Searching…'
                        : 'Nothing matches "$_query"',
                    style:
                        const TextStyle(color: AppColors.textSecondary),
                  ),
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text('${results.length} result(s)',
                            style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12)),
                      ),
                    ),
                    Expanded(
                      child: VideoGrid(
                        videos: results,
                        listMode: s.viewMode == ViewMode.list,
                        onChanged: () async {
                          _priv = await LocalStore().privateIds();
                          if (mounted) setState(() {});
                        },
                      ),
                    ),
                  ],
                ),
    );
  }
}
