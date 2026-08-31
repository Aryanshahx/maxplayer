import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../models/video_track.dart';
import '../state/media_player_state.dart';
import '../state/private_vault.dart';
import '../state/theme_state.dart';
import '../state/video_library_state.dart';
import '../utils/formatters.dart';
import 'player_screen.dart';

/// v86: Advance File Manager for local & SD-card storage.
class FileManagerScreen extends StatefulWidget {
  final VideoLibraryState library;
  final MediaPlayerState player;

  const FileManagerScreen({super.key, required this.library, required this.player});

  @override
  State<FileManagerScreen> createState() => _FileManagerScreenState();
}

class _FileManagerScreenState extends State<FileManagerScreen> {
  String _currentPath = '/storage/emulated/0';
  List<FileSystemEntity> _entries = [];
  bool _loading = true;
  String _searchQuery = '';
  String _sortBy = 'name'; // 'name', 'date', 'size'
  bool _sortAsc = true;
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadDirectory(_currentPath);
  }

  Future<void> _loadDirectory(String path) async {
    setState(() {
      _loading = true;
      _currentPath = path;
    });

    final dir = Directory(path);
    if (!dir.existsSync()) {
      setState(() {
        _entries = [];
        _loading = false;
      });
      return;
    }

    try {
      final list = await dir.list(followLinks: false).toList();
      // Filter hidden/system files starting with .
      final visible = list.where((e) {
        final name = p.basename(e.path);
        return !name.startsWith('.') || name == '.thumbnails';
      }).toList();

      _sortEntries(visible);

      if (mounted) {
        setState(() {
          _entries = visible;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _entries = [];
          _loading = false;
        });
      }
    }
  }

  void _sortEntries(List<FileSystemEntity> list) {
    list.sort((a, b) {
      final aIsDir = a is Directory;
      final bIsDir = b is Directory;
      if (aIsDir && !bIsDir) return -1;
      if (!aIsDir && bIsDir) return 1;

      int cmp = 0;
      if (_sortBy == 'name') {
        cmp = p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase());
      } else if (_sortBy == 'date') {
        try {
          final aStat = a.statSync();
          final bStat = b.statSync();
          cmp = aStat.modified.compareTo(bStat.modified);
        } catch (_) {
          cmp = 0;
        }
      } else if (_sortBy == 'size') {
        try {
          final aSize = a is File ? a.lengthSync() : 0;
          final bSize = b is File ? b.lengthSync() : 0;
          cmp = aSize.compareTo(bSize);
        } catch (_) {
          cmp = 0;
        }
      }
      return _sortAsc ? cmp : -cmp;
    });
  }

  void _navigateUp() {
    if (_currentPath == '/storage/emulated/0' || _currentPath == '/' || _currentPath.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    final parent = p.dirname(_currentPath);
    _loadDirectory(parent);
  }

  void _onEntityTap(FileSystemEntity entity) {
    if (entity is Directory) {
      _loadDirectory(entity.path);
    } else if (entity is File) {
      final path = entity.path;
      if (isVideoFile(path)) {
        final track = widget.library.findByPath(path) ??
            VideoTrack(
              id: path,
              title: p.basenameWithoutExtension(path),
              path: path,
            );
        widget.player.setPlaylistAndPlay([track], 0);
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => PlayerScreen(player: widget.player)),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(p.basename(path)),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _showFileOptions(FileSystemEntity entity) {
    final name = p.basename(entity.path);
    final isVideo = entity is File && isVideoFile(entity.path);
    final accent = themeState.accent;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1a1a24),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    entity is Directory ? Icons.folder : (isVideo ? Icons.movie_outlined : Icons.insert_drive_file_outlined),
                    color: accent,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Colors.white12),
            if (isVideo)
              ListTile(
                leading: Icon(Icons.play_arrow, color: accent),
                title: const Text('Play Video', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _onEntityTap(entity);
                },
              ),
            if (isVideo)
              ListTile(
                leading: const Icon(Icons.lock_outline, color: Colors.white70),
                title: const Text('Move to Private Space', style: TextStyle(color: Colors.white)),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  try {
                    await PrivateVault().hide(entity.path);
                    widget.library.removeVideo(entity.path);
                    _loadDirectory(_currentPath);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Moved to Private Space')),
                      );
                    }
                  } catch (_) {}
                },
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
              title: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
              onTap: () async {
                Navigator.of(sheetContext).pop();
                final yes = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: const Color(0xFF1a1a24),
                    title: const Text('Delete File?', style: TextStyle(color: Colors.white)),
                    content: Text('Delete "$name"? This cannot be undone.', style: const TextStyle(color: Colors.white70)),
                    actions: [
                      TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
                      FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
                        onPressed: () => Navigator.of(ctx).pop(true),
                        child: const Text('Delete'),
                      ),
                    ],
                  ),
                );
                if (yes == true) {
                  try {
                    if (entity is File) {
                      entity.deleteSync();
                    } else if (entity is Directory) {
                      entity.deleteSync(recursive: true);
                    }
                    _loadDirectory(_currentPath);
                  } catch (_) {}
                }
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = themeState.accent;
    final visibleEntries = _entries.where((e) {
      if (_searchQuery.isEmpty) return true;
      return p.basename(e.path).toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    return PopScope(
      canPop: _currentPath == '/storage/emulated/0' || _currentPath == '/' || _currentPath.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _navigateUp();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0e0e16),
        appBar: AppBar(
          backgroundColor: const Color(0xFF14141c),
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _navigateUp,
          ),
          title: Text(
            p.basename(_currentPath).isEmpty ? 'Storage' : p.basename(_currentPath),
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17),
          ),
          actions: [
            PopupMenuButton<String>(
              icon: const Icon(Icons.sort, color: Colors.white70),
              tooltip: 'Sort by',
              onSelected: (v) {
                setState(() {
                  if (_sortBy == v) {
                    _sortAsc = !_sortAsc;
                  } else {
                    _sortBy = v;
                    _sortAsc = true;
                  }
                  _sortEntries(_entries);
                });
              },
              itemBuilder: (ctx) => [
                const PopupMenuItem(value: 'name', child: Text('Name')),
                const PopupMenuItem(value: 'date', child: Text('Date Modified')),
                const PopupMenuItem(value: 'size', child: Text('File Size')),
              ],
            ),
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white70),
              onPressed: () => _loadDirectory(_currentPath),
            ),
          ],
        ),
        body: Column(
          children: [
            // Breadcrumbs path
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.white.withValues(alpha: 0.03),
              child: Text(
                _currentPath.replaceAll('/storage/emulated/0', 'Internal Storage'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: accent, fontSize: 12, fontWeight: FontWeight.w500),
              ),
            ),
            // Search in folder
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: TextField(
                  controller: _searchCtrl,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  onChanged: (v) => setState(() => _searchQuery = v),
                  decoration: InputDecoration(
                    hintText: 'Search files in this folder…',
                    hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                    icon: const Icon(Icons.search, size: 18, color: Colors.white38),
                    border: InputBorder.none,
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 16, color: Colors.white38),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                  ),
                ),
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : visibleEntries.isEmpty
                      ? const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.folder_open, size: 48, color: Colors.white24),
                              SizedBox(height: 10),
                              Text('Empty folder', style: TextStyle(color: Colors.white54)),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          itemCount: visibleEntries.length,
                          separatorBuilder: (_, __) => const Divider(height: 1, color: Colors.white10),
                          itemBuilder: (context, i) {
                            final entity = visibleEntries[i];
                            final name = p.basename(entity.path);
                            final isDir = entity is Directory;
                            final isVid = !isDir && isVideoFile(entity.path);

                            String subtitle = '';
                            if (!isDir && entity is File) {
                              try {
                                final len = entity.lengthSync();
                                subtitle = formatFileSize(len);
                              } catch (_) {}
                            }

                            return ListTile(
                              dense: true,
                              leading: CircleAvatar(
                                radius: 18,
                                backgroundColor: isDir
                                    ? accent.withValues(alpha: 0.18)
                                    : (isVid ? Colors.purple.withValues(alpha: 0.2) : Colors.white10),
                                child: Icon(
                                  isDir
                                      ? Icons.folder
                                      : (isVid ? Icons.videocam : Icons.insert_drive_file),
                                  color: isDir ? accent : (isVid ? Colors.purpleAccent : Colors.white70),
                                  size: 18,
                                ),
                              ),
                              title: Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 13.5,
                                  fontWeight: isDir ? FontWeight.w600 : FontWeight.normal,
                                ),
                              ),
                              subtitle: subtitle.isNotEmpty
                                  ? Text(subtitle, style: const TextStyle(color: Colors.white38, fontSize: 11))
                                  : null,
                              trailing: IconButton(
                                icon: const Icon(Icons.more_vert, size: 18, color: Colors.white38),
                                onPressed: () => _showFileOptions(entity),
                              ),
                              onTap: () => _onEntityTap(entity),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
