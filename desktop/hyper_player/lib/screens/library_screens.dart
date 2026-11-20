import '../app_design.dart';
import '../local_thumbnail.dart';
import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../local_media_index.dart';
import '../playlist.dart';
import '../utils/app_language.dart';
import 'collection_screens.dart';

class DesktopFoldersScreen extends StatefulWidget {
  final Future<void> Function()? onScanSystem;
  const DesktopFoldersScreen({super.key, this.onScanSystem});
  @override
  State<DesktopFoldersScreen> createState() => _DesktopFoldersScreenState();
}

class _DesktopFoldersScreenState extends State<DesktopFoldersScreen> {
  final paths = <String>[];
  LocalScan? scan;
  bool loading = true;
  String? error;
  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList('hyper.scan.folders.v1') ?? [];
      final result = await scanLocalMedia(saved,
          recursive: true, cancelled: () => !mounted);
      if (mounted) {
        setState(() {
          paths
            ..clear()
            ..addAll(result.folders.entries
                .where((e) => e.value.isNotEmpty || saved.contains(e.key))
                .map((e) => e.key));
          scan = result;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() =>
            error = 'Could not read saved folders. Retry or choose a folder.');
      }
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  Future<void> addFolder() async {
    try {
      final path = await getDirectoryPath();
      if (path == null || !mounted) {
        return;
      }
      final prefs = await SharedPreferences.getInstance();
      final all = {...?prefs.getStringList('hyper.scan.folders.v1'), path};
      await prefs.setStringList('hyper.scan.folders.v1', all.toList());
      if (mounted) {
        await reload();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open the folder picker.')));
      }
    }
  }

  Future<void> open(String path) async {
    final result = await Navigator.push<String>(
        context,
        MaterialPageRoute(
            builder: (_) => FolderMediaScreen(
                path: path, entries: scan?.folders[path] ?? [])));
    if (mounted && result != null) {
      Navigator.pop(context, result);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const LText('Folders'), actions: [
          if (widget.onScanSystem != null)
            IconButton(
                tooltip: 'Scan system / folders',
                onPressed: widget.onScanSystem,
                icon: const Icon(Icons.computer)),
          IconButton(
              tooltip: 'Rescan',
              onPressed: loading ? null : reload,
              icon: const Icon(Icons.refresh_rounded))
        ]),
        floatingActionButton: FloatingActionButton.extended(
            onPressed: loading ? null : addFolder,
            icon: const Icon(Icons.create_new_folder_outlined),
            label: const Text('Add folder')),
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : Column(children: [
                Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Text(
                        error ??
                            'Chosen roots and subfolders · ${scan?.truncated == true ? "Partial scan: file/directory limit or cancellation" : "no whole-PC scan"}',
                        style:
                            const TextStyle(color: secondary, fontSize: 11))),
                Expanded(
                    child: paths.isEmpty
                        ? collectionEmpty(Icons.folder_outlined,
                            'No folders yet.\nChoose a folder to browse your media.')
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                            itemCount: paths.length,
                            separatorBuilder: (context, i) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, i) {
                              final path = paths[i];
                              final missing =
                                  scan?.unavailable.contains(path) ?? false;
                              return Card(
                                  child: ListTile(
                                      leading: const Icon(Icons.folder_rounded,
                                          size: 30),
                                      title: Text(
                                          labelFor(path).isEmpty
                                              ? path
                                              : labelFor(path),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis),
                                      subtitle: Text(
                                          missing
                                              ? 'Folder unavailable'
                                              : '${scan?.folders[path]?.length ?? 0} media items',
                                          style: const TextStyle(
                                              color: secondary, fontSize: 12)),
                                      trailing: const Icon(
                                          Icons.chevron_right_rounded,
                                          color: secondary),
                                      onTap:
                                          missing ? null : () => open(path)));
                            },
                          )),
              ]),
      );
}

class FolderMediaScreen extends StatelessWidget {
  final String path;
  final List<LocalMediaEntry> entries;
  const FolderMediaScreen(
      {super.key, required this.path, required this.entries});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar:
            AppBar(title: Text(labelFor(path).isEmpty ? path : labelFor(path))),
        body: entries.isEmpty
            ? collectionEmpty(Icons.folder_open, 'Empty folder')
            : GridView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: entries.length,
                gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: AppDesign.instance.mediaExtent,
                    childAspectRatio: 1.55,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12),
                itemBuilder: (context, i) {
                  final entry = entries[i];
                  return Card(
                      child: InkWell(
                          onTap: () => Navigator.pop(context, entry.path),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                      child: SizedBox(
                                          width: double.infinity,
                                          child: LocalThumbnail(entry.path))),
                                  Text(labelFor(entry.path),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                  const SizedBox(height: 5),
                                  Text(mediaSize(entry.bytes),
                                      style: const TextStyle(
                                          color: secondary, fontSize: 11)),
                                ]),
                          )));
                },
              ),
      );
}

class DesktopAudioScreen extends StatefulWidget {
  final List<String> knownSources;
  const DesktopAudioScreen({super.key, required this.knownSources});
  @override
  State<DesktopAudioScreen> createState() => _DesktopAudioScreenState();
}

class _DesktopAudioScreenState extends State<DesktopAudioScreen> {
  final search = TextEditingController();
  List<LocalMediaEntry> songs = [];
  String sort = 'Newest';
  bool loading = true;
  String? warning;
  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    setState(() {
      loading = true;
      warning = null;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      final result = await scanLocalMedia(
          prefs.getStringList('hyper.scan.folders.v1') ?? []);
      final all = <String, LocalMediaEntry>{
        for (final entries in result.folders.values)
          for (final entry in entries)
            if (isAudioPath(entry.path)) entry.path: entry
      };
      for (final item in await scanAudioPaths(
          prefs.getStringList('hyper.audio.files.v1') ?? [])) {
        all[item.path] = item;
      }
      for (final source in widget.knownSources
          .where((s) => !validStream(s) && isAudioPath(s))) {
        try {
          final stat = await File(source).stat();
          if (stat.type == FileSystemEntityType.file) {
            all[source] = LocalMediaEntry(source, stat.modified, stat.size);
          }
        } catch (_) {/* Missing files omitted. */}
      }
      if (mounted) {
        setState(() {
          songs = all.values.toList();
          warning = result.truncated
              ? 'Partial scan: file/directory limit or cancellation.'
              : result.unavailable.isNotEmpty
                  ? '${result.unavailable.length} folders unavailable.'
                  : null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
            () => warning = 'Could not scan audio. Retry or open audio files.');
      }
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  Future<void> openAudio() async {
    try {
      final files = await openFiles(acceptedTypeGroups: [
        XTypeGroup(label: 'Audio', extensions: audioExtensions.toList())
      ]);
      final prefs = await SharedPreferences.getInstance();
      final all = {
        ...?prefs.getStringList('hyper.audio.files.v1'),
        ...files.map((f) => f.path)
      };
      await prefs.setStringList('hyper.audio.files.v1', all.toList());
      if (mounted) {
        final result = await scanAudioPaths(all);
        if (!mounted) {
          return;
        }
        setState(() {
          final merged = {
            for (final item in songs) item.path: item,
            for (final item in result) item.path: item
          };
          songs = merged.values.toList();
        });
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open audio files.')));
      }
    }
  }

  Future<List<LocalMediaEntry>> scanAudioPaths(Iterable<String> paths) async {
    final entries = <LocalMediaEntry>[];
    for (final path in paths.where(isAudioPath)) {
      try {
        final stat = await File(path).stat();
        if (stat.type == FileSystemEntityType.file) {
          entries.add(LocalMediaEntry(path, stat.modified, stat.size));
        }
      } catch (_) {/* File unavailable. */}
    }
    return entries;
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visible = songs
        .where((s) => labelFor(s.path)
            .toLowerCase()
            .contains(search.text.trim().toLowerCase()))
        .toList();
    visible.sort((a, b) => sort == 'A–Z'
        ? labelFor(a.path)
            .toLowerCase()
            .compareTo(labelFor(b.path).toLowerCase())
        : b.modified.compareTo(a.modified));
    return Scaffold(
        appBar: AppBar(
            title: Text(loading ? 'Audio' : 'Audio (${visible.length})'),
            actions: [
              if (songs.isNotEmpty)
                TextButton.icon(
                    onPressed: () => setState(
                        () => sort = sort == 'Newest' ? 'A–Z' : 'Newest'),
                    icon: const Icon(Icons.sort_rounded, size: 18),
                    label: Text(sort)),
              IconButton(
                  tooltip: 'Rescan',
                  onPressed: loading ? null : reload,
                  icon: const Icon(Icons.refresh_rounded)),
              IconButton(
                  tooltip: 'Open audio files',
                  onPressed: openAudio,
                  icon: const Icon(Icons.add)),
            ]),
        body: Column(children: [
          Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: TextField(
                  controller: search,
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(fontSize: 14),
                  decoration: LInputDecoration(
                      hintText: 'Search songs…',
                      isDense: true,
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      suffixIcon: search.text.isEmpty
                          ? null
                          : IconButton(
                              onPressed: () => setState(() => search.clear()),
                              icon: const Icon(Icons.close_rounded, size: 18)),
                      filled: true,
                      fillColor: const Color(0xff101013),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none)))),
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                  warning ??
                      'Chosen folders and audio files only · Newest = file modified time',
                  style: const TextStyle(color: secondary, fontSize: 11))),
          Expanded(
              child: loading
                  ? const Center(child: CircularProgressIndicator())
                  : visible.isEmpty
                      ? collectionEmpty(Icons.library_music_outlined,
                          'No songs found.\nChoose audio files or add folders from Home.')
                      : ListView.separated(
                          itemCount: visible.length,
                          separatorBuilder: (context, i) =>
                              const Divider(height: 1, indent: 72),
                          itemBuilder: (context, i) {
                            final item = visible[i];
                            return ListTile(
                                leading: CircleAvatar(
                                    backgroundColor:
                                        Colors.white.withValues(alpha: .12),
                                    child: const Icon(Icons.music_note,
                                        color: Colors.white)),
                                title: Text(labelFor(item.path),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                                subtitle:
                                    Text(mediaSize(item.bytes), maxLines: 1),
                                onTap: () => Navigator.pop(context, item.path));
                          })),
        ]));
  }
}
