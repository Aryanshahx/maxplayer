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
      scaffoldBackgroundColor: const Color(0xff060608),
      appBarTheme: const AppBarTheme(backgroundColor: Color(0xff060608), surfaceTintColor: Colors.transparent),
      colorScheme: const ColorScheme.dark(primary: Colors.white, onPrimary: Color(0xff0b0b0e), surface: Color(0xff101013), onSurface: Color(0xfff5f6f8)),
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
  bool viewingPlayer = false;
  bool listMode = false;
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
    setState(() { selected = index; viewingPlayer = true; });
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
  Future<void> unavailable(String title) async {
    await showDialog<void>(context: context, builder: (context) => AlertDialog(
      title: Text(title),
      content: const Text('This Android feature does not have a Windows implementation yet. This update adds the desktop layout and preserves local playback, folder import, streams and the session playlist.'),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
    ));
  }

  Future<void> showQueue() async {
    await showDialog<void>(context: context, builder: (context) => AlertDialog(
      title: Text('Playlists · Current queue (${queue.length})'),
      content: SizedBox(width: 550, height: 360, child: queue.isEmpty
        ? const Center(child: Text('Open files to create a queue.'))
        : ListView.builder(itemCount: queue.length, itemBuilder: (context, i) => ListTile(
          leading: const Icon(Icons.play_arrow), title: Text(labelFor(queue[i])),
          onTap: () { Navigator.pop(context); play(i); },
        ))),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
    ));
  }

  Widget quickTile(IconData icon, String label, VoidCallback onTap, {bool planned = false}) => Tooltip(
    message: planned ? '$label — Windows implementation pending' : label,
    child: Material(color: Colors.transparent, child: InkWell(
      onTap: onTap, borderRadius: BorderRadius.circular(12),
      child: Ink(
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [Colors.white.withValues(alpha: .11), Colors.white.withValues(alpha: .04)]),
          borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white.withValues(alpha: .14)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
        child: Row(children: [Icon(icon, size: 18), const SizedBox(width: 8),
          Expanded(child: Text(label, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
          if (planned) const Icon(Icons.construction_outlined, size: 12, color: Color(0xff9296a0)),
        ]),
      ),
    )),
  );

  Widget brandTitle() => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
    ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) => const LinearGradient(colors: [Color(0xffa78bfa), Color(0xff8b5cf6), Color(0xff22d3ee)]).createShader(bounds),
      child: const Text('Hyper Player', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
    ),
    const Text('Proudly Developed in India 🇮🇳', style: TextStyle(fontSize: 9.5, color: Color(0xff9296a0), letterSpacing: .3)),
  ]);

  Widget library() => LayoutBuilder(builder: (context, size) {
    final columns = size.maxWidth >= 1300 ? 8 : size.maxWidth >= 700 ? 4 : 2;
    final tiles = <Widget>[
      quickTile(Icons.lock_outline_rounded, 'Private Space', () => unavailable('Private Space'), planned: true),
      quickTile(Icons.queue_music_outlined, 'Playlists', showQueue),
      quickTile(Icons.folder_outlined, 'Folders', folder),
      quickTile(Icons.music_note_outlined, 'Audio', files),
      quickTile(Icons.dns_outlined, 'Network Storage', () => unavailable('Network Storage'), planned: true),
      quickTile(Icons.cloud_queue_outlined, 'Cloud Storage', () => unavailable('Cloud Storage'), planned: true),
      quickTile(Icons.link, 'Open Stream(iptv)', stream),
      quickTile(Icons.ios_share, 'Quick Share', () => unavailable('Quick Share'), planned: true),
    ];
    return CustomScrollView(slivers: [SliverPadding(
      padding: const EdgeInsets.all(16), sliver: SliverList(delegate: SliverChildListDelegate([
        InkWell(onTap: () => unavailable('Discover movies'), borderRadius: BorderRadius.circular(14), child: Ink(
          height: 118, padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), gradient: const LinearGradient(colors: [Color(0xff241d3d), Color(0xff16222e)])),
          child: const Row(children: [Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Discover movies', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            SizedBox(height: 6), Text('Windows catalogue integration pending', style: TextStyle(color: Color(0xff9296a0), fontSize: 12)),
          ])), Icon(Icons.arrow_forward)],),
        )),
        const SizedBox(height: 12),
        for (var start = 0; start < tiles.length; start += columns) ...[
          Row(children: [for (var j = 0; j < columns; j++) ...[
            if (j > 0) const SizedBox(width: 8), Expanded(child: tiles[start + j]),
          ]]), const SizedBox(height: 8),
        ],
        const SizedBox(height: 12),
        Row(children: [Text('Media · ${queue.length}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
          const Spacer(), TextButton.icon(onPressed: files, icon: const Icon(Icons.add, size: 18), label: const Text('Open files')),
          IconButton(tooltip: 'Switch grid/list', onPressed: () => setState(() => listMode = !listMode), icon: Icon(listMode ? Icons.grid_view : Icons.view_list)),
        ]),
        if (queue.isEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 90), child: Center(child: Column(children: [
          const Icon(Icons.video_library_outlined, color: Color(0xff9296a0), size: 46), const SizedBox(height: 15),
          const Text('No media yet. Open files or a folder to begin.', style: TextStyle(color: Color(0xff9296a0))),
          const SizedBox(height: 16), FilledButton(onPressed: files, child: const Text('Open files')),
        ]))),
      ])),
    ),
    if (listMode) SliverList(delegate: SliverChildBuilderDelegate((context, i) => ListTile(
      leading: const Icon(Icons.movie_outlined), title: Text(labelFor(queue[i])),
      subtitle: Text(validStream(queue[i]) ? 'Network stream' : 'Local media'), onTap: () => play(i),
    ), childCount: queue.length))
    else SliverPadding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), sliver: SliverGrid(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 300, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 1.55),
      delegate: SliverChildBuilderDelegate((context, i) => Material(
        color: const Color(0xff101013), borderRadius: BorderRadius.circular(16),
        child: InkWell(onTap: () => play(i), borderRadius: BorderRadius.circular(16), child: Container(
          decoration: BoxDecoration(border: Border.all(color: const Color(0xff26262c)), borderRadius: BorderRadius.circular(16)),
          padding: const EdgeInsets.all(15), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Expanded(child: Center(child: Icon(Icons.play_circle_outline, size: 42, color: Color(0xff9296a0)))),
            Text(labelFor(queue[i]), maxLines: 2, overflow: TextOverflow.ellipsis), const SizedBox(height: 5),
            Text(validStream(queue[i]) ? 'Network stream' : 'Local media', style: const TextStyle(fontSize: 11, color: Color(0xff9296a0))),
          ]),
        )),
      ), childCount: queue.length),
    )),
    ]);
  });

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.keyO, control: true): files,
      const SingleActivator(LogicalKeyboardKey.keyL, control: true): stream,
    },
    child: Focus(autofocus: true, child: Scaffold(
      appBar: AppBar(toolbarHeight: 76, title: brandTitle(), actions: [
        if (viewingPlayer) IconButton(tooltip: 'Back to library (playback continues)', onPressed: () => setState(() => viewingPlayer = false), icon: const Icon(Icons.home_outlined)),
        IconButton(tooltip: 'Open files (Ctrl+O)', onPressed: files, icon: const Icon(Icons.video_file_outlined)),
        IconButton(tooltip: 'Current playlist', onPressed: showQueue, icon: const Icon(Icons.queue_music)),
        PopupMenuButton<String>(onSelected: (value) {
          if (value == 'Clear queue') { clearQueue(); }
          else if (value == 'Open folder') { folder(); }
          else { unavailable(value); }
        }, itemBuilder: (context) => ['Language', 'Display settings', 'Watch statistics', 'History', 'User manual', 'AI subtitles', 'Open folder', 'Clear queue'].map((name) => PopupMenuItem(value: name, child: Text(name))).toList()),
        const SizedBox(width: 12),
      ]),
      body: Column(children: [
        if (busy) const LinearProgressIndicator(),
        Expanded(child: viewingPlayer ? Row(children: [
          Expanded(child: Video(controller: controller, controls: AdaptiveVideoControls)),
          SizedBox(width: MediaQuery.sizeOf(context).width < 800 ? 210 : 280, child: ListView.builder(
            itemCount: queue.length, itemBuilder: (context, i) => ListTile(selected: i == selected,
              leading: Icon(i == selected ? Icons.play_arrow : Icons.music_video),
              title: Text(labelFor(queue[i]), maxLines: 2, overflow: TextOverflow.ellipsis), onTap: () => play(i)),
          )),
        ]) : library()),
        if (!viewingPlayer && selected >= 0 && selected < queue.length) Material(color: const Color(0xff101013), child: ListTile(
          leading: IconButton(tooltip: 'Play/pause', onPressed: () => player.playOrPause(), icon: const Icon(Icons.play_pause)),
          title: Text(labelFor(queue[selected]), maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: TextButton(onPressed: () => setState(() => viewingPlayer = true), child: const Text('Open player')),
        )),
        const Padding(padding: EdgeInsets.all(6), child: Text('Windows preview · Construction icon = integration pending · Folder import scans direct children only', style: TextStyle(fontSize: 10, color: Color(0xff9296a0)))),
      ]),
    )),
  );

  Future<void> clearQueue() async {
    await player.stop();
    if (!mounted) { return; }
    setState(() { queue.clear(); selected = -1; viewingPlayer = false; });
    await save();
  }
}
