import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'playlist.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const HyperPlayer());
}
class HyperPlayer extends StatelessWidget {
  const HyperPlayer({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Hyper Player - All Formats',
    debugShowCheckedModeBanner: false,
    theme: ThemeData.dark(useMaterial3: true).copyWith(
      scaffoldBackgroundColor: const Color(0xff101114),
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.lightBlue, brightness: Brightness.dark),
    ),
    home: const DesktopPlayer(),
  );
}
class DesktopPlayer extends StatefulWidget {
  const DesktopPlayer({super.key});
  @override
  State<DesktopPlayer> createState() => _DesktopPlayerState();
}
class _DesktopPlayerState extends State<DesktopPlayer> {
  final player = Player();
  late final VideoController controller = VideoController(player);
  final queue = <String>[];
  StreamSubscription<String>? errors;
  StreamSubscription<bool>? completion;
  int selected = -1;
  bool busy = false;
  bool sidebar = true;
  @override
  void initState() {
    super.initState();
    errors = player.stream.error.listen((message) => notify('Playback error: $message'));
    completion = player.stream.completed.listen((done) {
      if (done && selected + 1 < queue.length) { play(selected + 1); }
    });
    restore();
  }
  Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) { return; }
    setState(() => queue.addAll(decodeQueue(prefs.getString('hyper.queue.v1'))));
  }
  Future<void> save() async {
    final snapshot = jsonEncode(queue);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('hyper.queue.v1', snapshot);
  }
  void notify(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }
  Future<void> play(int index) async {
    if (index < 0 || index >= queue.length) { return; }
    setState(() => selected = index);
    try {
      final source = queue[index];
      if (!validStream(source) && !await File(source).exists()) {
        notify('File is no longer available. Open it again from its current location.');
        return;
      }
      await player.open(Media(source));
    } catch (e) { notify('Cannot open media: $e'); }
  }
  Future<void> add(List<String> paths) async {
    if (!mounted || paths.isEmpty) { return; }
    final start = queue.length;
    setState(() => queue.addAll(paths));
    await save();
    if (selected == -1) { await play(start); }
  }
  Future<void> files() async {
    try {
      final result = await openFiles(acceptedTypeGroups: [XTypeGroup(label: 'Media', extensions: mediaExtensions.toList())]);
      await add(result.map((e) => e.path).toList());
    } catch (e) { notify('File picker failed: $e'); }
  }
  Future<void> folder() async {
    if (busy) { return; }
    try {
      final path = await getDirectoryPath();
      if (path == null || !mounted) { return; }
      setState(() => busy = true);
      final paths = <String>[];
      // Non-recursive by design: do not silently scan entire drives.
      await for (final entity in Directory(path).list(followLinks: false)) {
        if (entity is File && isMediaPath(entity.path)) {
          paths.add(entity.path);
        }
      }
      paths.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      await add(paths);
      if (paths.isEmpty) { notify('No supported media found directly inside this folder.'); }
    } catch (e) { notify('Could not read folder: $e'); }
    finally { if (mounted) { setState(() => busy = false); } }
  }
  Future<void> stream() async {
    final input = TextEditingController();
    final value = await showDialog<String>(context: context, builder: (context) => AlertDialog(
      title: const Text('Open stream'),
      content: SizedBox(width: 480, child: TextField(controller: input, autofocus: true,
        decoration: const InputDecoration(labelText: 'HTTP or HTTPS media URL'),
        onSubmitted: (value) => Navigator.pop(context, value.trim()))),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, input.text.trim()), child: const Text('Add'))],
    ));
    // The dialog route may still be animating out; no controller reuse is needed.
    if (value == null) { return; }
    if (!validStream(value)) { notify('Enter a valid HTTP or HTTPS URL.'); return; }
    await add([value]);
  }
  @override
  void dispose() {
    errors?.cancel(); completion?.cancel(); player.dispose(); super.dispose();
  }
  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.keyO, control: true): files,
      const SingleActivator(LogicalKeyboardKey.keyL, control: true): stream,
    },
    child: Focus(autofocus: true, child: Scaffold(
      appBar: AppBar(title: const Text('Hyper Player - All Formats'), actions: [
        IconButton(tooltip: 'Open files (Ctrl+O)', onPressed: files, icon: const Icon(Icons.video_file_outlined)),
        IconButton(tooltip: 'Open folder', onPressed: busy ? null : folder, icon: const Icon(Icons.folder_open)),
        IconButton(tooltip: 'Open stream (Ctrl+L)', onPressed: stream, icon: const Icon(Icons.link)),
        IconButton(tooltip: 'Toggle playlist', onPressed: () => setState(() => sidebar = !sidebar), icon: const Icon(Icons.queue_music)),
      ]),
      body: Column(children: [
        if (busy) const LinearProgressIndicator(),
        Expanded(child: Row(children: [
          Expanded(child: ColoredBox(color: Colors.black, child: selected < 0
            ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.play_circle_outline, size: 80), const SizedBox(height: 18),
                const Text('Your media. Your player.', style: TextStyle(fontSize: 24)),
                const SizedBox(height: 16), FilledButton.icon(onPressed: files, icon: const Icon(Icons.folder_open), label: const Text('Open media')),
                const SizedBox(height: 12), const Text('Desktop preview • Local files and online streams'),
              ]))
            : Video(controller: controller, controls: AdaptiveVideoControls))),
          if (sidebar) SizedBox(width: MediaQuery.sizeOf(context).width < 700 ? 210 : 300,
            child: Column(children: [
              ListTile(title: Text('Playlist (${queue.length})'), trailing: IconButton(
                tooltip: 'Clear playlist', icon: const Icon(Icons.delete_sweep_outlined), onPressed: () async {
                  await player.stop();
                  if (!mounted) { return; }
                  setState(() { queue.clear(); selected = -1; });
                  await save();
                })),
              const Divider(height: 1),
              Expanded(child: ListView.builder(itemCount: queue.length, itemBuilder: (context, index) => ListTile(
                selected: index == selected,
                leading: Icon(index == selected ? Icons.play_arrow : Icons.music_video),
                title: Text(labelFor(queue[index]), maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text(queue[index], maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () => play(index),
              ))),
            ])),
        ])),
        const Padding(padding: EdgeInsets.all(6), child: Text('Windows preview • Playback depends on the source and supported codecs.')),
      ]),
    )),
  );
}
