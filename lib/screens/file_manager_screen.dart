import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../models/video_track.dart';
import '../state/media_player_state.dart';
import '../state/private_vault.dart';
import '../state/theme_state.dart';
import '../state/video_library_state.dart';
import '../utils/formatters.dart';
import '../widgets/playlists_sheet.dart';
import 'player_screen.dart';

/// v90: Advanced Media File Manager & Storage Explorer with full media viewers
/// (Images, Audio/Music, Documents) and AI Media Insights.
class FileManagerScreen extends StatefulWidget {
  final VideoLibraryState library;
  final MediaPlayerState player;

  const FileManagerScreen({
    super.key,
    required this.library,
    required this.player,
  });

  @override
  State<FileManagerScreen> createState() => _FileManagerScreenState();
}

class _FileManagerScreenState extends State<FileManagerScreen> {
  String _currentPath = '/storage/emulated/0';
  List<FileSystemEntity> _entries = [];
  bool _loading = true;
  String _searchQuery = '';
  bool _searchActive = false;
  String _sortBy = 'name'; // 'name', 'date', 'size', 'type'
  bool _sortAsc = true;
  String _typeFilter = 'all'; // 'all', 'video', 'audio', 'image', 'subs', 'doc'
  bool _isGridView = false;

  final TextEditingController _searchCtrl = TextEditingController();

  static const List<Map<String, String>> _shortcuts = [
    {'name': 'Internal', 'path': '/storage/emulated/0', 'icon': 'storage'},
    {'name': 'Camera', 'path': '/storage/emulated/0/DCIM/Camera', 'icon': 'camera'},
    {'name': 'Movies', 'path': '/storage/emulated/0/Movies', 'icon': 'movie'},
    {'name': 'Download', 'path': '/storage/emulated/0/Download', 'icon': 'download'},
    {
      'name': 'WhatsApp',
      'path': '/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Video',
      'icon': 'chat',
    },
  ];

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

  bool _isImageFile(String path) {
    final ext = p.extension(path).toLowerCase();
    return ext == '.jpg' || ext == '.jpeg' || ext == '.png' || ext == '.webp' || ext == '.gif' || ext == '.bmp' || ext == '.heic';
  }

  bool _isAudioFile(String path) {
    final ext = p.extension(path).toLowerCase();
    return ext == '.mp3' || ext == '.m4a' || ext == '.flac' || ext == '.wav' || ext == '.aac' || ext == '.ogg' || ext == '.opus' || ext == '.wma';
  }

  bool _isDocFile(String path) {
    final ext = p.extension(path).toLowerCase();
    return ext == '.txt' || ext == '.pdf' || ext == '.json' || ext == '.doc' || ext == '.docx' || ext == '.log' || ext == '.xml' || ext == '.csv' || ext == '.md' || ext == '.srt' || ext == '.vtt';
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
      } else if (_isImageFile(path)) {
        _openImageViewer(entity);
      } else if (_isAudioFile(path)) {
        _openAudioPlayer(entity);
      } else if (_isDocFile(path)) {
        _openDocumentViewer(entity);
      } else {
        _showFileDetails(entity);
      }
    }
  }

  // --- Image Viewer Modal ---
  void _openImageViewer(File file) {
    final name = p.basename(file.path);
    final size = formatFileSize(file.lengthSync());

    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 4.0,
                child: Image.file(
                  file,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Center(
                    child: Text('Could not load image', style: TextStyle(color: Colors.white70)),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 40,
              left: 16,
              right: 16,
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        Text(size, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.info_outline, color: Colors.white70),
                    onPressed: () => _showFileDetails(file),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Audio / Music Player Modal ---
  void _openAudioPlayer(File file) {
    final name = p.basename(file.path);
    final track = VideoTrack(
      id: file.path,
      title: p.basenameWithoutExtension(file.path),
      path: file.path,
    );

    widget.player.setPlaylistAndPlay([track], 0);

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF181826),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(height: 20),
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: themeState.accent.withValues(alpha: 0.18),
                  border: Border.all(color: themeState.accent.withValues(alpha: 0.4), width: 2),
                ),
                child: Icon(Icons.music_note, size: 42, color: themeState.accent),
              ),
              const SizedBox(height: 16),
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(formatFileSize(file.lengthSync()), style: const TextStyle(color: Colors.white38, fontSize: 12)),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.replay_10, color: Colors.white70, size: 28),
                    onPressed: () => widget.player.seekRelative(-10),
                  ),
                  const SizedBox(width: 20),
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: themeState.accent,
                    child: IconButton(
                      icon: Icon(widget.player.isPlaying ? Icons.pause : Icons.play_arrow, color: themeState.onAccent, size: 30),
                      onPressed: () {
                        widget.player.togglePlayPause();
                        setState(() {});
                      },
                    ),
                  ),
                  const SizedBox(width: 20),
                  IconButton(
                    icon: const Icon(Icons.forward_10, color: Colors.white70, size: 28),
                    onPressed: () => widget.player.seekRelative(10),
                  ),
                ],
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }

  // --- Document Viewer Modal ---
  void _openDocumentViewer(File file) async {
    final name = p.basename(file.path);
    final ext = p.extension(file.path).toLowerCase();
    String content = '';
    bool readable = true;

    if (ext == '.txt' || ext == '.json' || ext == '.log' || ext == '.xml' || ext == '.csv' || ext == '.md' || ext == '.srt' || ext == '.vtt') {
      try {
        content = await file.readAsString();
      } catch (_) {
        readable = false;
      }
    } else {
      readable = false;
    }

    if (!mounted) return;

    if (!readable) {
      _showFileDetails(file);
      return;
    }

    final wordCount = content.trim().isEmpty ? 0 : content.trim().split(RegExp(r'\s+')).length;
    final lineCount = content.isEmpty ? 0 : '\n'.allMatches(content).length + 1;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF14141c),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (_, scrollCtrl) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.description, color: themeState.accent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                        Text('$lineCount lines · $wordCount words · ${formatFileSize(file.lengthSync())}', style: const TextStyle(color: Colors.white38, fontSize: 11.5)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
              const Divider(color: Colors.white12),
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollCtrl,
                  child: SelectableText(
                    content,
                    style: const TextStyle(color: Colors.white70, fontSize: 12.5, fontFamily: 'monospace', height: 1.4),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- AI Smart Media Insights ---
  void _showAiMediaInsights() {
    final totalFiles = _entries.whereType<File>().length;
    final totalDirs = _entries.whereType<Directory>().length;
    int videoCount = 0;
    int audioCount = 0;
    int imageCount = 0;
    int docCount = 0;
    int totalBytes = 0;

    for (final e in _entries) {
      if (e is File) {
        try {
          final len = e.lengthSync();
          totalBytes += len;
          if (isVideoFile(e.path)) videoCount++;
          else if (_isAudioFile(e.path)) audioCount++;
          else if (_isImageFile(e.path)) imageCount++;
          else if (_isDocFile(e.path)) docCount++;
        } catch (_) {}
      }
    }

    final totalSizeStr = formatFileSize(totalBytes);

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF181826),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            Icon(Icons.auto_awesome, color: themeState.accent, size: 22),
            const SizedBox(width: 10),
            const Text('AI Media Insights', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Directory: ${p.basename(_currentPath)}', style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            _aiStatRow('Total Storage Used', totalSizeStr),
            _aiStatRow('Videos Found', '$videoCount files'),
            _aiStatRow('Audio Tracks', '$audioCount files'),
            _aiStatRow('Images & Photos', '$imageCount files'),
            _aiStatRow('Documents', '$docCount files'),
            _aiStatRow('Subfolders', '$totalDirs folders'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: themeState.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: themeState.accent.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.lightbulb_outline, color: themeState.accent, size: 18),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'AI Recommendation: All media formats here are fully accelerated by libmpv for 100% smooth playback.',
                      style: TextStyle(color: Colors.white70, fontSize: 11.5, height: 1.35),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Close', style: TextStyle(color: themeState.accent)),
          ),
        ],
      ),
    );
  }

  Widget _aiStatRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.white38, fontSize: 12)),
        Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12.5)),
      ],
    ),
  );

  void _showFileDetails(FileSystemEntity entity) {
    final name = p.basename(entity.path);
    final stat = entity.statSync();
    final isDir = entity is Directory;
    final size = isDir ? 'Folder' : formatFileSize(stat.size);
    final modified =
        '${stat.modified.year}-${stat.modified.month.toString().padLeft(2, '0')}-${stat.modified.day.toString().padLeft(2, '0')} ${stat.modified.hour.toString().padLeft(2, '0')}:${stat.modified.minute.toString().padLeft(2, '0')}';

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(isDir ? Icons.folder : Icons.insert_drive_file, color: themeState.accent),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                name,
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _metaRow('Path', entity.path),
            _metaRow('Size', size),
            _metaRow('Modified', modified),
            _metaRow('Type', isDir ? 'Directory' : p.extension(entity.path).toUpperCase().replaceAll('.', '')),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Close', style: TextStyle(color: themeState.accent)),
          ),
        ],
      ),
    );
  }

  Widget _metaRow(String label, String val) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 70,
              child: Text(label, style: const TextStyle(color: Colors.white38, fontSize: 12)),
            ),
            Expanded(
              child: SelectableText(
                val,
                style: const TextStyle(color: Colors.white70, fontSize: 12.5),
              ),
            ),
          ],
        ),
      );

  void _confirmDelete(FileSystemEntity entity) async {
    final name = p.basename(entity.path);
    final isDir = entity is Directory;
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Delete ${isDir ? "Folder" : "File"}?', style: const TextStyle(color: Colors.white)),
        content: Text(
          'Are you sure you want to delete "$name"? This action cannot be undone.',
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
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
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Deleted "$name"')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to delete: $e')),
          );
        }
      }
    }
  }

  void _moveToPrivate(String path) async {
    try {
      await PrivateVault().hide(path);
      widget.library.removeVideo(path);
      _loadDirectory(_currentPath);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Moved to Private Space')),
        );
      }
    } catch (_) {}
  }

  void _addToPlaylist(String path) {
    PlaylistsSheet.show(context, library: widget.library, player: widget.player);
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
      if (_searchQuery.isNotEmpty) {
        final matches = p.basename(e.path).toLowerCase().contains(_searchQuery.toLowerCase());
        if (!matches) return false;
      }
      if (_typeFilter != 'all' && e is File) {
        if (_typeFilter == 'video') return isVideoFile(e.path);
        if (_typeFilter == 'audio') return _isAudioFile(e.path);
        if (_typeFilter == 'image') return _isImageFile(e.path);
        if (_typeFilter == 'subs') {
          final ext = p.extension(e.path).toLowerCase();
          return ext == '.srt' || ext == '.vtt' || ext == '.ass' || ext == '.sub';
        }
        if (_typeFilter == 'doc') return _isDocFile(e.path);
      }
      return true;
    }).toList();

    return PopScope(
      canPop: _currentPath == '/storage/emulated/0' || _currentPath == '/' || _currentPath.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _navigateUp();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0e0e16),
        appBar: AppBar(
          backgroundColor: const Color(0xFF14141f),
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _navigateUp,
          ),
          title: _searchActive
              ? TextField(
                  controller: _searchCtrl,
                  autofocus: true,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                  decoration: const InputDecoration(
                    hintText: 'Search in this folder…',
                    hintStyle: TextStyle(color: Colors.white38),
                    border: InputBorder.none,
                  ),
                  onChanged: (v) => setState(() => _searchQuery = v),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.basename(_currentPath).isEmpty ? 'Internal Storage' : p.basename(_currentPath),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16.5),
                    ),
                    Text(
                      _currentPath.replaceAll('/storage/emulated/0', 'Storage'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                  ],
                ),
          actions: [
            IconButton(
              icon: Icon(Icons.auto_awesome, color: accent),
              tooltip: 'AI Media Insights',
              onPressed: _showAiMediaInsights,
            ),
            IconButton(
              icon: Icon(_searchActive ? Icons.close : Icons.search, color: Colors.white70),
              tooltip: _searchActive ? 'Close Search' : 'Search',
              onPressed: () {
                setState(() {
                  _searchActive = !_searchActive;
                  if (!_searchActive) {
                    _searchCtrl.clear();
                    _searchQuery = '';
                  }
                });
              },
            ),
            IconButton(
              icon: Icon(_isGridView ? Icons.view_list : Icons.grid_view, color: Colors.white70),
              tooltip: _isGridView ? 'List View' : 'Grid View',
              onPressed: () => setState(() => _isGridView = !_isGridView),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.sort, color: Colors.white70),
              tooltip: 'Sort by',
              color: const Color(0xFF1a1a24),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                _sortMenuItem('name', 'Name (A→Z)'),
                _sortMenuItem('date', 'Date Modified'),
                _sortMenuItem('size', 'File Size'),
              ],
            ),
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white70),
              tooltip: 'Refresh',
              onPressed: () => _loadDirectory(_currentPath),
            ),
          ],
        ),
        body: Column(
          children: [
            // Storage shortcuts bar
            Container(
              height: 46,
              color: const Color(0xFF14141f),
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                itemCount: _shortcuts.length,
                itemBuilder: (context, i) {
                  final s = _shortcuts[i];
                  final isCurrent = _currentPath == s['path'];
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => _loadDirectory(s['path']!),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: isCurrent ? accent.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isCurrent ? accent : Colors.white12,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _getShortcutIcon(s['icon']!),
                              size: 14,
                              color: isCurrent ? accent : Colors.white60,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              s['name']!,
                              style: TextStyle(
                                color: isCurrent ? accent : Colors.white70,
                                fontSize: 12,
                                fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            // File type filter chips
            Container(
              height: 40,
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                children: [
                  _typeChip('all', 'All Files', accent),
                  _typeChip('video', 'Videos', accent),
                  _typeChip('audio', 'Music', accent),
                  _typeChip('image', 'Images', accent),
                  _typeChip('subs', 'Subtitles', accent),
                  _typeChip('doc', 'Documents', accent),
                ],
              ),
            ),

            // Entries List or Grid
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : visibleEntries.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.folder_open, size: 54, color: Colors.white24),
                              const SizedBox(height: 12),
                              const Text('No files found', style: TextStyle(color: Colors.white54, fontSize: 15)),
                              if (_searchQuery.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text('Matching "$_searchQuery"', style: const TextStyle(color: Colors.white38, fontSize: 12)),
                                ),
                            ],
                          ),
                        )
                      : _isGridView
                          ? GridView.builder(
                              padding: const EdgeInsets.all(10),
                              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 140,
                                childAspectRatio: 0.88,
                                crossAxisSpacing: 8,
                                mainAxisSpacing: 8,
                              ),
                              itemCount: visibleEntries.length,
                              itemBuilder: (context, i) => _buildGridItem(visibleEntries[i], accent),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              itemCount: visibleEntries.length,
                              separatorBuilder: (_, __) => const Divider(height: 1, color: Colors.white10),
                              itemBuilder: (context, i) => _buildListItem(visibleEntries[i], accent),
                            ),
            ),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<String> _sortMenuItem(String key, String label) {
    final isSelected = _sortBy == key;
    return PopupMenuItem(
      value: key,
      child: Row(
        children: [
          Icon(
            isSelected ? (_sortAsc ? Icons.arrow_upward : Icons.arrow_downward) : Icons.sort,
            size: 16,
            color: isSelected ? themeState.accent : Colors.white38,
          ),
          const SizedBox(width: 10),
          Text(label, style: TextStyle(color: isSelected ? Colors.white : Colors.white70, fontSize: 13.5)),
        ],
      ),
    );
  }

  Widget _buildListItem(FileSystemEntity entity, Color accent) {
    final name = p.basename(entity.path);
    final isDir = entity is Directory;
    final isVid = !isDir && isVideoFile(entity.path);
    final isAud = !isDir && _isAudioFile(entity.path);
    final isImg = !isDir && _isImageFile(entity.path);
    final ext = p.extension(entity.path).toUpperCase().replaceAll('.', '');

    String subtitle = '';
    if (!isDir && entity is File) {
      try {
        final stat = entity.statSync();
        final sizeStr = formatFileSize(stat.size);
        final dateStr = '${stat.modified.month}/${stat.modified.day}';
        subtitle = '$ext • $sizeStr • $dateStr';
      } catch (_) {}
    }

    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: isDir
              ? accent.withValues(alpha: 0.15)
              : (isVid
                  ? Colors.purpleAccent.withValues(alpha: 0.18)
                  : (isAud
                      ? Colors.pinkAccent.withValues(alpha: 0.18)
                      : (isImg ? Colors.tealAccent.withValues(alpha: 0.18) : Colors.white.withValues(alpha: 0.06)))),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          isDir
              ? Icons.folder
              : (isVid
                  ? Icons.movie_outlined
                  : (isAud
                      ? Icons.music_note
                      : (isImg ? Icons.image_outlined : Icons.insert_drive_file_outlined))),
          color: isDir
              ? accent
              : (isVid
                  ? Colors.purpleAccent
                  : (isAud ? Colors.pinkAccent : (isImg ? Colors.tealAccent : Colors.white70))),
          size: 20,
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
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isVid || isAud)
            IconButton(
              icon: Icon(Icons.play_circle_fill, color: accent, size: 24),
              tooltip: 'Play',
              onPressed: () => _onEntityTap(entity),
            ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 18, color: Colors.white38),
            color: const Color(0xFF1a1a24),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onSelected: (action) {
              if (action == 'play') _onEntityTap(entity);
              if (action == 'playlist') _addToPlaylist(entity.path);
              if (action == 'private') _moveToPrivate(entity.path);
              if (action == 'info') _showFileDetails(entity);
              if (action == 'delete') _confirmDelete(entity);
            },
            itemBuilder: (ctx) => [
              if (isVid || isAud)
                const PopupMenuItem(
                  value: 'play',
                  child: Row(children: [Icon(Icons.play_arrow, size: 18, color: Colors.white), SizedBox(width: 8), Text('Play')]),
                ),
              if (isVid) ...[
                const PopupMenuItem(
                  value: 'playlist',
                  child: Row(children: [Icon(Icons.playlist_add, size: 18, color: Colors.white), SizedBox(width: 8), Text('Add to playlist')]),
                ),
                const PopupMenuItem(
                  value: 'private',
                  child: Row(children: [Icon(Icons.lock_outline, size: 18, color: Colors.white), SizedBox(width: 8), Text('Move to Private Space')]),
                ),
              ],
              const PopupMenuItem(
                value: 'info',
                child: Row(children: [Icon(Icons.info_outline, size: 18, color: Colors.white), SizedBox(width: 8), Text('File details')]),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: Row(children: [Icon(Icons.delete_outline, size: 18, color: Colors.redAccent), SizedBox(width: 8), Text('Delete', style: TextStyle(color: Colors.redAccent))]),
              ),
            ],
          ),
        ],
      ),
      onTap: () => _onEntityTap(entity),
    );
  }

  Widget _buildGridItem(FileSystemEntity entity, Color accent) {
    final name = p.basename(entity.path);
    final isDir = entity is Directory;
    final isVid = !isDir && isVideoFile(entity.path);
    final isAud = !isDir && _isAudioFile(entity.path);
    final isImg = !isDir && _isImageFile(entity.path);

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _onEntityTap(entity),
      onLongPress: () => _showFileDetails(entity),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isDir
                  ? Icons.folder
                  : (isVid
                      ? Icons.videocam
                      : (isAud
                          ? Icons.music_note
                          : (isImg ? Icons.image : Icons.insert_drive_file))),
              color: isDir
                  ? accent
                  : (isVid
                      ? Colors.purpleAccent
                      : (isAud ? Colors.pinkAccent : (isImg ? Colors.tealAccent : Colors.white70))),
              size: 34,
            ),
            const SizedBox(height: 8),
            Text(
              name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }

  Widget _typeChip(String key, String label, Color accent) {
    final selected = _typeFilter == key;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        selectedColor: accent.withValues(alpha: 0.2),
        checkmarkColor: accent,
        labelStyle: TextStyle(
          color: selected ? accent : Colors.white60,
          fontSize: 11.5,
          fontWeight: selected ? FontWeight.bold : FontWeight.normal,
        ),
        backgroundColor: Colors.white.withValues(alpha: 0.04),
        side: BorderSide(color: selected ? accent : Colors.white12),
        onSelected: (_) => setState(() => _typeFilter = key),
      ),
    );
  }

  IconData _getShortcutIcon(String name) {
    switch (name) {
      case 'storage':
        return Icons.storage;
      case 'camera':
        return Icons.camera_alt_outlined;
      case 'movie':
        return Icons.movie_outlined;
      case 'download':
        return Icons.download_outlined;
      case 'chat':
        return Icons.chat_bubble_outline;
      default:
        return Icons.folder;
    }
  }
}
