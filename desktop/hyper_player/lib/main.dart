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
import 'desktop_store.dart';
import 'discover/discover_screen.dart';
import 'screens/language_screen.dart';
import 'utils/app_language.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await AppLanguage.instance.load();
  runApp(const HyperPlayer());
}

class HyperPlayer extends StatelessWidget {
  const HyperPlayer({super.key});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: AppLanguage.instance,
      builder: (context, child) => MaterialApp(
            locale: AppLanguage.instance.locale,
            supportedLocales:
                uiLanguages.map((language) => Locale(language.code)).toList(),
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate
            ],
            title: 'Hyper Player - All Formats',
            debugShowCheckedModeBanner: false,
            theme: ThemeData.dark(useMaterial3: true).copyWith(
              scaffoldBackgroundColor: const Color(0xff060608),
              appBarTheme: const AppBarTheme(
                  backgroundColor: Color(0xff060608),
                  surfaceTintColor: Colors.transparent),
              colorScheme: const ColorScheme.dark(
                  primary: Colors.white,
                  onPrimary: Color(0xff0b0b0e),
                  surface: Color(0xff101013),
                  onSurface: Color(0xfff5f6f8)),
            ),
            home: const DesktopPlayer(),
          ));
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
  final collections = DesktopStore();
  final scanFolders = <String>{};
  StreamSubscription<String>? errors;
  StreamSubscription<bool>? completion;
  int selected = -1;
  bool busy = false;
  bool viewingPlayer = false;
  bool listMode = false;
  BoxFit videoFit = BoxFit.contain;
  Timer? sleep;
  Timer? ticker;
  DateTime? sleepDeadline;
  Duration? repeatA;
  Duration? repeatB;
  bool repeatSeeking = false;
  int watchSeconds = 0;
  int playStarts = 0;
  @override
  void initState() {
    super.initState();
    errors = player.stream.error
        .listen((message) => notify('Playback error: $message'));
    completion = player.stream.completed.listen((done) {
      if (done && selected + 1 < queue.length) {
        play(selected + 1);
      }
    });
    restore();
    ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (player.state.playing && !player.state.buffering) {
        watchSeconds++;
        if (watchSeconds % 15 == 0) {
          unawaited(saveStats());
        }
      }
      final a = repeatA;
      final b = repeatB;
      if (a != null &&
          b != null &&
          player.state.playing &&
          player.state.position >= b &&
          !repeatSeeking) {
        repeatSeeking = true;
        player.seek(a).whenComplete(() => repeatSeeking = false);
      }
    });
  }

  Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
    await collections.load();
    scanFolders.addAll(prefs.getStringList('hyper.scan.folders.v1') ?? []);
    listMode = prefs.getBool('hyper.list.mode.v1') ?? false;
    watchSeconds += prefs.getInt('hyper.watch.seconds.v1') ?? 0;
    playStarts += prefs.getInt('hyper.play.starts.v1') ?? 0;
    if (!mounted) {
      return;
    }
    setState(
        () => queue.addAll(decodeQueue(prefs.getString('hyper.queue.v1'))));
  }

  Future<void> save() async {
    final snapshot = jsonEncode(queue);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('hyper.queue.v1', snapshot);
  }

  void notify(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> play(int index) async {
    if (index < 0 || index >= queue.length) {
      return;
    }
    setState(() {
      selected = index;
      viewingPlayer = true;
    });
    try {
      final source = queue[index];
      if (!validStream(source) && !await File(source).exists()) {
        notify(
            'File is no longer available. Open it again from its current location.');
        return;
      }
      repeatA = null;
      repeatB = null;
      await player.open(Media(source));
      playStarts++;
      await saveStats();
      await collections.record(source);
    } catch (e) {
      notify('Cannot open media: $e');
    }
  }

  Future<void> add(List<String> paths) async {
    if (!mounted || paths.isEmpty) {
      return;
    }
    final start = queue.length;
    setState(() => queue.addAll(paths));
    await save();
    if (selected == -1) {
      await play(start);
    }
  }

  Future<void> files() async {
    try {
      final result = await openFiles(acceptedTypeGroups: [
        XTypeGroup(label: 'Media', extensions: mediaExtensions.toList())
      ]);
      await add(result.map((e) => e.path).toList());
    } catch (e) {
      notify('File picker failed: $e');
    }
  }

  Future<void> folder() async {
    if (busy) {
      return;
    }
    try {
      final path = await getDirectoryPath();
      if (path == null || !mounted) {
        return;
      }
      scanFolders.add(path);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('hyper.scan.folders.v1', scanFolders.toList());
      if (!mounted) {
        return;
      }
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
      if (paths.isEmpty) {
        notify('No supported media found directly inside this folder.');
      }
    } catch (e) {
      notify('Could not read folder: $e');
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Future<void> stream() async {
    final input = TextEditingController();
    final value = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
              title: const LText('Open stream'),
              content: SizedBox(
                  width: 480,
                  child: TextField(
                      controller: input,
                      autofocus: true,
                      decoration: const InputDecoration(
                          labelText: 'HTTP or HTTPS media URL'),
                      onSubmitted: (value) =>
                          Navigator.pop(context, value.trim()))),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const LText('Cancel')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, input.text.trim()),
                    child: const LText('Add'))
              ],
            ));
    // The dialog route may still be animating out; no controller reuse is needed.
    if (value == null) {
      return;
    }
    if (!validStream(value)) {
      notify('Enter a valid HTTP or HTTPS URL.');
      return;
    }
    await add([value]);
  }

  @override
  void dispose() {
    sleep?.cancel();
    ticker?.cancel();
    unawaited(saveStats());
    errors?.cancel();
    completion?.cancel();
    player.dispose();
    super.dispose();
  }

  Future<String?> askText(String title, {String hint = ''}) async {
    String value = '';
    return showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
              title: Text(title),
              content: SizedBox(
                  width: 480,
                  child: TextField(
                    autofocus: true,
                    decoration: InputDecoration(hintText: hint),
                    onChanged: (text) => value = text,
                    onSubmitted: (text) => Navigator.pop(context, text.trim()),
                  )),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const LText('Cancel')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, value.trim()),
                    child: const LText('Continue'))
              ],
            ));
  }

  Future<void> sourceList(String title, List<String> sources) async {
    final snapshot = List<String>.of(sources);
    if (!mounted) {
      return;
    }
    await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
              title: Text('$title · ${snapshot.length}'),
              content: SizedBox(
                  width: 650,
                  height: 400,
                  child: snapshot.isEmpty
                      ? const Center(child: LText('No entries yet.'))
                      : ListView.builder(
                          itemCount: snapshot.length,
                          itemBuilder: (context, i) => ListTile(
                                title: Text(labelFor(snapshot[i])),
                                subtitle: Text(
                                    validStream(snapshot[i])
                                        ? 'Network media'
                                        : 'Local file',
                                    maxLines: 1),
                                onTap: () async {
                                  Navigator.pop(context);
                                  var index = queue.indexOf(snapshot[i]);
                                  if (index < 0) {
                                    setState(() => queue.add(snapshot[i]));
                                    await save();
                                    index = queue.length - 1;
                                  }
                                  if (mounted) {
                                    await play(index);
                                  }
                                },
                              ))),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const LText('Close'))
              ],
            ));
  }

  Future<void> namedPlaylists() async {
    final action = await showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
              title: const LText('Playlists'),
              children: [
                SimpleDialogOption(
                    onPressed: () => Navigator.pop(context, 'current'),
                    child: const LText('Current queue')),
                SimpleDialogOption(
                    onPressed: () => Navigator.pop(context, 'save'),
                    child:
                        const LText('Save current queue as a named playlist')),
                SimpleDialogOption(
                    onPressed: () => Navigator.pop(context, 'delete'),
                    child: const LText('Delete a named playlist')),
                for (final name in collections.playlists.keys)
                  SimpleDialogOption(
                      onPressed: () => Navigator.pop(context, 'open:$name'),
                      child: Text(name)),
              ],
            ));
    if (!mounted || action == null) {
      return;
    }
    if (action == 'current') {
      await showQueue();
    } else if (action == 'save') {
      if (queue.isEmpty) {
        notify('Add media first.');
        return;
      }
      final name = await askText('Playlist name');
      if (name == null || name.isEmpty || !mounted) {
        return;
      }
      if (collections.playlists.containsKey(name)) {
        notify('That name already exists. Choose a different name.');
        return;
      }
      collections.playlists[name] = List.of(queue);
      await collections.save();
      notify('Playlist saved.');
    } else if (action == 'delete') {
      final name = await askText('Exact playlist name to delete');
      if (name == null || !mounted) {
        return;
      }
      final removed = collections.playlists.remove(name);
      await collections.save();
      notify(removed == null
          ? 'Playlist not found.'
          : 'Playlist deleted; files were not deleted.');
    } else if (action.startsWith('open:')) {
      final name = action.substring(5);
      await sourceList(name, collections.playlists[name] ?? []);
    }
  }

  Future<void> toggleFavourite() async {
    if (selected < 0 || selected >= queue.length) {
      notify('Play media first.');
      return;
    }
    final source = queue[selected];
    if (!collections.favourites.remove(source)) {
      collections.favourites.add(source);
    }
    await collections.save();
    notify(collections.favourites.contains(source)
        ? 'Added to favourites.'
        : 'Removed from favourites.');
  }

  Future<void> searchMedia() async {
    final text = await askText('Search media',
        hint: 'Search filenames in queue and history');
    if (text == null || !mounted) {
      return;
    }
    final all = {...queue, ...collections.history, ...collections.favourites};
    await sourceList(
        'Search results',
        all
            .where(
                (s) => labelFor(s).toLowerCase().contains(text.toLowerCase()))
            .toList());
  }

  Future<void> importIptv() async {
    try {
      final kind = await showDialog<String>(
          context: context,
          builder: (context) => SimpleDialog(
                title: const LText('Import M3U playlist'),
                children: [
                  SimpleDialogOption(
                      onPressed: () => Navigator.pop(context, 'file'),
                      child: const LText('From a local M3U file')),
                  SimpleDialogOption(
                      onPressed: () => Navigator.pop(context, 'url'),
                      child: const LText('From an HTTP/HTTPS URL')),
                ],
              ));
      if (kind == null || !mounted) {
        return;
      }
      String text;
      Uri base;
      if (kind == 'file') {
        final file = await openFile(acceptedTypeGroups: [
          const XTypeGroup(label: 'M3U playlist', extensions: ['m3u', 'm3u8'])
        ]);
        if (file == null) {
          return;
        }
        if (await file.length() > 2 * 1024 * 1024) {
          throw const FormatException('Playlist exceeds 2 MB.');
        }
        text = await file.readAsString();
        base = Uri.file(file.path, windows: true);
      } else {
        final value = await askText('Playlist URL');
        if (value == null || !mounted) {
          return;
        }
        if (!validStream(value)) {
          throw const FormatException('Enter an HTTP/HTTPS URL.');
        }
        base = Uri.parse(value);
        final client = HttpClient()
          ..connectionTimeout = const Duration(seconds: 15);
        try {
          final request =
              await client.getUrl(base).timeout(const Duration(seconds: 20));
          final response =
              await request.close().timeout(const Duration(seconds: 20));
          if (response.statusCode != 200) {
            throw HttpException('HTTP ${response.statusCode}');
          }
          for (final redirect in response.redirects) {
            base = base.resolveUri(redirect.location);
          }
          final bytes = <int>[];
          await for (final chunk
              in response.timeout(const Duration(seconds: 20))) {
            bytes.addAll(chunk);
            if (bytes.length > 2 * 1024 * 1024) {
              throw const FormatException('Playlist exceeds 2 MB.');
            }
          }
          text = utf8.decode(bytes);
        } finally {
          client.close(force: true);
        }
      }
      final entries = parseM3u(text, base);
      if (entries.isEmpty) {
        notify('No supported playlist entries found.');
        return;
      }
      await add(entries);
      notify(
          'Imported ${entries.length} entries. No EPG or channel logos in this version.');
    } catch (e) {
      notify('Playlist import failed: $e');
    }
  }

  Future<void> externalSubtitles() async {
    if (selected < 0) {
      notify('Play a video first.');
      return;
    }
    try {
      final file = await openFile(acceptedTypeGroups: [
        const XTypeGroup(
            label: 'Subtitles', extensions: ['srt', 'ass', 'ssa', 'vtt'])
      ]);
      if (file == null) {
        return;
      }
      await player.setSubtitleTrack(SubtitleTrack.uri(file.path));
      notify('Subtitle track loaded.');
    } catch (e) {
      notify('Could not load subtitles: $e');
    }
  }

  Future<void> playbackOptions() async {
    await showDialog<void>(
        context: context,
        builder: (context) => SimpleDialog(
              title: const LText('Playback speed'),
              children: [
                for (final rate in [.5, .75, 1.0, 1.25, 1.5, 2.0, 3.0, 4.0])
                  SimpleDialogOption(
                      onPressed: () {
                        player.setRate(rate);
                        Navigator.pop(context);
                      },
                      child: Text('$rate×')),
              ],
            ));
  }

  Future<void> sleepTimer() async {
    final minutes = await showDialog<int>(
        context: context,
        builder: (context) => SimpleDialog(
              title: const LText('Sleep timer'),
              children: [
                SimpleDialogOption(
                    onPressed: () => Navigator.pop(context, 0),
                    child: const LText('Cancel timer')),
                for (final value in [15, 30, 45, 60, 90, 120])
                  SimpleDialogOption(
                      onPressed: () => Navigator.pop(context, value),
                      child: Text('$value minutes')),
              ],
            ));
    if (minutes == null || !mounted) {
      return;
    }
    sleep?.cancel();
    sleepDeadline =
        minutes == 0 ? null : DateTime.now().add(Duration(minutes: minutes));
    if (minutes > 0) {
      sleep = Timer(Duration(minutes: minutes), () {
        player.pause();
        sleepDeadline = null;
        notify('Sleep timer: playback paused.');
      });
    }
    notify(minutes == 0
        ? 'Sleep timer cancelled.'
        : 'Playback will pause in $minutes minutes.');
  }

  Future<void> repeatControls() async {
    await showDialog<void>(
        context: context,
        builder: (context) => SimpleDialog(
              title: const LText('A–B repeat'),
              children: [
                SimpleDialogOption(
                    onPressed: () {
                      if (selected < 0) {
                        notify('Play media first.');
                        return;
                      }
                      repeatA = player.state.position;
                      repeatB = null;
                      Navigator.pop(context);
                      notify('Start point A set. Seek forward, then set B.');
                    },
                    child: const LText('Set A at current position')),
                SimpleDialogOption(
                    onPressed: () {
                      final a = repeatA;
                      if (a == null ||
                          player.state.position <=
                              a + const Duration(seconds: 1)) {
                        notify(
                            'Set A first, then set B at least one second later.');
                        return;
                      }
                      repeatB = player.state.position;
                      Navigator.pop(context);
                      notify('A–B repeat enabled.');
                    },
                    child: const LText('Set B at current position')),
                SimpleDialogOption(
                    onPressed: () {
                      repeatA = null;
                      repeatB = null;
                      Navigator.pop(context);
                      notify('A–B repeat disabled.');
                    },
                    child: const LText('Disable repeat')),
              ],
            ));
  }

  Future<void> fitOptions() async {
    final choice = await showDialog<BoxFit>(
        context: context,
        builder: (context) => SimpleDialog(
              title: const LText('Video fit'),
              children: [
                for (final entry in {
                  'Fit': BoxFit.contain,
                  'Crop': BoxFit.cover,
                  'Stretch': BoxFit.fill
                }.entries)
                  SimpleDialogOption(
                      onPressed: () => Navigator.pop(context, entry.value),
                      child: Text(entry.key)),
              ],
            ));
    if (choice != null && mounted) {
      setState(() => videoFit = choice);
    }
  }

  Future<void> subtitleDelay() async {
    final input = await askText('Subtitle delay in milliseconds',
        hint: 'Example: 500 or -500; 0 resets');
    if (input == null || !mounted) {
      return;
    }
    final ms = int.tryParse(input);
    if (ms == null || ms.abs() > 60000) {
      notify('Enter a whole number between -60000 and 60000.');
      return;
    }
    try {
      await (player.platform as NativePlayer)
          .setProperty('sub-delay', (ms / 1000).toString());
      notify('Subtitle delay set to $ms ms.');
    } catch (e) {
      notify('Subtitle delay unavailable: $e');
    }
  }

  Future<void> watchStatistics() async {
    await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
              title: const LText('Watch statistics'),
              content: Text(
                  'Playback starts: $playStarts\nApproximate playback time: ${watchSeconds ~/ 60} minutes ${watchSeconds % 60} seconds\nFavourites: ${collections.favourites.length}\nNamed playlists: ${collections.playlists.length}\n\n${sleepDeadline == null ? "No sleep timer active." : "Sleep timer ends at ${sleepDeadline!.toLocal()}."}\n\nStored on this laptop only. Time is sampled while playing (not buffering); not a measure of attention. Saved every 15 seconds; abrupt exit can lose the last interval.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const LText('Close'))
              ],
            ));
  }

  Future<void> saveStats() async {
    final seconds = watchSeconds;
    final starts = playStarts;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('hyper.watch.seconds.v1', seconds);
    await prefs.setInt('hyper.play.starts.v1', starts);
  }

  Future<void> rescan() async {
    if (busy) {
      return;
    }
    if (scanFolders.isEmpty) {
      await folder();
      return;
    }
    setState(() => busy = true);
    final found = <String>{};
    int failures = 0;
    for (final path in scanFolders) {
      try {
        await for (final entry in Directory(path).list(followLinks: false)) {
          if (entry is File && isMediaPath(entry.path)) {
            found.add(entry.path);
          }
        }
      } catch (_) {
        failures++;
      }
    }
    if (!mounted) {
      return;
    }
    final additions = found.where((path) => !queue.contains(path)).toList()
      ..sort();
    setState(() {
      queue.addAll(additions);
      busy = false;
    });
    await save();
    notify(
        'Rescan: ${additions.length} new files. $failures folders unavailable. Existing entries retained.');
  }

  Future<void> infoDialog(String title, String body) async {
    await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
              title: LText(title),
              content: SizedBox(
                  width: 620,
                  child: SingleChildScrollView(child: SelectableText(body))),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const LText('Close'))
              ],
            ));
  }

  Future<void> displaySettings() async {
    final result = await showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
              title: const LText('Display settings'),
              children: [
                SimpleDialogOption(
                    onPressed: () => Navigator.pop(context, 'grid'),
                    child: const LText('Grid view')),
                SimpleDialogOption(
                    onPressed: () => Navigator.pop(context, 'list'),
                    child: const LText('List view')),
                SimpleDialogOption(
                    onPressed: () => Navigator.pop(context, 'sort'),
                    child: const LText('Sort current queue by name')),
              ],
            ));
    if (result == null || !mounted) {
      return;
    }
    setState(() {
      if (result == 'sort') {
        final playing =
            selected >= 0 && selected < queue.length ? queue[selected] : null;
        queue.sort((a, b) =>
            labelFor(a).toLowerCase().compareTo(labelFor(b).toLowerCase()));
        selected = playing == null ? -1 : queue.indexOf(playing);
      } else {
        listMode = result == 'list';
      }
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hyper.list.mode.v1', listMode);
    await save();
  }

  Future<void> homeMenu(String value) async {
    switch (value) {
      case 'Language':
        await Navigator.push<void>(
            context, MaterialPageRoute(builder: (_) => const LanguageScreen()));
      case 'Display settings':
        await displaySettings();
      case 'User manual':
        await infoDialog(value,
            'Open files (Ctrl+O) or import a folder. Rescan checks saved folders for new direct-child media; it does not search your whole disk or remove missing entries. Search finds entries in queue/history/favourites.\n\nPlaylists saves the queue under a name. Use the extra tools menu entries for IPTV import, subtitles, speed, A–B repeat and sleep timer.\n\nDiscover uses TMDB metadata and opens trailers on YouTube in your browser. It does not supply full movies. Construction-marked tiles remain unimplemented.');
      case 'About Hyper Player':
        await infoDialog(value,
            'Hyper Player - All Formats\nWindows preview 0.2.0\nHyper Tech Labs\n\nAndroid-inspired native desktop application.\n\n$tmdbNotice');
      case 'Privacy policy':
        await infoDialog(value,
            'Windows preview privacy\n\nLocal media is not uploaded. Queue, folder paths, history, favourites, playlists, language and approximate playback statistics are stored locally, without encryption. URLs can contain credentials; do not share local application data.\n\nDiscover connects to TMDB API and image hosts. Search terms and requested title IDs are sent to TMDB. Metadata is cached locally. Hosts receive network connection information including IP address. Where-to-watch information is for India.\n\nTrailers and external links open your browser or email application and follow those providers’ policies. Network streams contact their source hosts.\n\nThis Windows build does not integrate Android Firebase analytics, AdMob or FCM push.\n\nContact: techlabs.hyper@gmail.com. This is a preview disclosure; review the final public Windows privacy policy before Store submission.');
      case 'Report a problem':
        await openDiscoverLink(
            context,
            Uri(
                scheme: 'mailto',
                path: 'techlabs.hyper@gmail.com',
                query:
                    'subject=${Uri.encodeComponent("Hyper Player Windows — report & feedback")}'));
      case 'Follow on Instagram':
        await openDiscoverLink(context,
            Uri.parse('https://www.instagram.com/maxplayer_official/'));
    }
  }

  Future<void> unavailable(String title) async {
    await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
              title: Text(title),
              content: const LText(
                  'This Android feature does not have a Windows implementation yet. This update adds the desktop layout and preserves local playback, folder import, streams and the session playlist.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const LText('Close'))
              ],
            ));
  }

  Future<void> showQueue() async {
    await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
              title: Text('Playlists · Current queue (${queue.length})'),
              content: SizedBox(
                  width: 550,
                  height: 360,
                  child: queue.isEmpty
                      ? const Center(
                          child: LText('Open files to create a queue.'))
                      : ListView.builder(
                          itemCount: queue.length,
                          itemBuilder: (context, i) => ListTile(
                                leading: const Icon(Icons.play_arrow),
                                title: Text(labelFor(queue[i])),
                                onTap: () {
                                  Navigator.pop(context);
                                  play(i);
                                },
                              ))),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const LText('Close'))
              ],
            ));
  }

  Widget quickTile(IconData icon, String label, VoidCallback onTap,
          {bool planned = false}) =>
      Tooltip(
        message: planned ? '$label — Windows implementation pending' : label,
        child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(12),
              child: Ink(
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [
                    Colors.white.withValues(alpha: .11),
                    Colors.white.withValues(alpha: .04)
                  ]),
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: .14)),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
                child: Row(children: [
                  Icon(icon, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                      child: LText(label,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w500))),
                  if (planned)
                    const Icon(Icons.construction_outlined,
                        size: 12, color: Color(0xff9296a0)),
                ]),
              ),
            )),
      );

  Widget brandTitle() => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ShaderMask(
              blendMode: BlendMode.srcIn,
              shaderCallback: (bounds) => const LinearGradient(colors: [
                Color(0xffa78bfa),
                Color(0xff8b5cf6),
                Color(0xff22d3ee)
              ]).createShader(bounds),
              child: const LText('Hyper Player',
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white)),
            ),
            const LText('Proudly Developed in India 🇮🇳',
                style: TextStyle(
                    fontSize: 9.5,
                    color: Color(0xff9296a0),
                    letterSpacing: .3)),
          ]);

  Widget library() => LayoutBuilder(builder: (context, size) {
        final columns = size.maxWidth >= 1300
            ? 8
            : size.maxWidth >= 700
                ? 4
                : 2;
        final tiles = <Widget>[
          quickTile(Icons.lock_outline_rounded, 'Private Space',
              () => unavailable('Private Space'),
              planned: true),
          quickTile(Icons.queue_music_outlined, 'Playlists', namedPlaylists),
          quickTile(Icons.folder_outlined, 'Folders', folder),
          quickTile(Icons.music_note_outlined, 'Audio', files),
          quickTile(Icons.dns_outlined, 'Network Storage',
              () => unavailable('Network Storage'),
              planned: true),
          quickTile(Icons.cloud_queue_outlined, 'Cloud Storage',
              () => unavailable('Cloud Storage'),
              planned: true),
          quickTile(Icons.link, 'Open Stream(iptv)', stream),
          quickTile(
              Icons.ios_share, 'Quick Share', () => unavailable('Quick Share'),
              planned: true),
        ];
        return CustomScrollView(slivers: [
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList(
                delegate: SliverChildListDelegate([
              const DiscoverHomeBanner(),
              const SizedBox(height: 12),
              for (var start = 0; start < tiles.length; start += columns) ...[
                Row(children: [
                  for (var j = 0; j < columns; j++) ...[
                    if (j > 0) const SizedBox(width: 8),
                    Expanded(child: tiles[start + j]),
                  ]
                ]),
                const SizedBox(height: 8),
              ],
              const SizedBox(height: 12),
              Row(children: [
                Text('Media · ${queue.length}',
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w600)),
                const Spacer(),
                TextButton.icon(
                    onPressed: files,
                    icon: const Icon(Icons.add, size: 18),
                    label: const LText('Open files')),
                IconButton(
                    tooltip: 'Switch grid/list',
                    onPressed: () => setState(() => listMode = !listMode),
                    icon: Icon(listMode ? Icons.grid_view : Icons.view_list)),
              ]),
              if (queue.isEmpty)
                Padding(
                    padding: const EdgeInsets.symmetric(vertical: 90),
                    child: Center(
                        child: Column(children: [
                      const Icon(Icons.video_library_outlined,
                          color: Color(0xff9296a0), size: 46),
                      const SizedBox(height: 15),
                      const LText(
                          'No media yet. Open files or a folder to begin.',
                          style: TextStyle(color: Color(0xff9296a0))),
                      const SizedBox(height: 16),
                      FilledButton(
                          onPressed: files, child: const LText('Open files')),
                    ]))),
            ])),
          ),
          if (listMode)
            SliverList(
                delegate: SliverChildBuilderDelegate(
                    (context, i) => ListTile(
                          leading: const Icon(Icons.movie_outlined),
                          title: Text(labelFor(queue[i])),
                          subtitle: Text(validStream(queue[i])
                              ? 'Network stream'
                              : 'Local media'),
                          onTap: () => play(i),
                        ),
                    childCount: queue.length))
          else
            SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 300,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 1.55),
                  delegate: SliverChildBuilderDelegate(
                      (context, i) => Material(
                            color: const Color(0xff101013),
                            borderRadius: BorderRadius.circular(16),
                            child: InkWell(
                                onTap: () => play(i),
                                borderRadius: BorderRadius.circular(16),
                                child: Container(
                                  decoration: BoxDecoration(
                                      border: Border.all(
                                          color: const Color(0xff26262c)),
                                      borderRadius: BorderRadius.circular(16)),
                                  padding: const EdgeInsets.all(15),
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Expanded(
                                            child: Center(
                                                child: Icon(
                                                    Icons.play_circle_outline,
                                                    size: 42,
                                                    color: Color(0xff9296a0)))),
                                        Text(labelFor(queue[i]),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis),
                                        const SizedBox(height: 5),
                                        Text(
                                            validStream(queue[i])
                                                ? 'Network stream'
                                                : 'Local media',
                                            style: const TextStyle(
                                                fontSize: 11,
                                                color: Color(0xff9296a0))),
                                      ]),
                                )),
                          ),
                      childCount: queue.length),
                )),
        ]);
      });

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyO, control: true): files,
          const SingleActivator(LogicalKeyboardKey.keyL, control: true): stream,
        },
        child: Focus(
            autofocus: true,
            child: Scaffold(
              appBar: AppBar(toolbarHeight: 76, title: brandTitle(), actions: [
                IconButton(
                    tooltip: 'Search media',
                    onPressed: searchMedia,
                    icon: const Icon(Icons.search)),
                IconButton(
                    tooltip: 'Rescan saved folders',
                    onPressed: busy ? null : rescan,
                    icon: const Icon(Icons.sync)),
                if (viewingPlayer)
                  IconButton(
                      tooltip: 'Back to library (playback continues)',
                      onPressed: () => setState(() => viewingPlayer = false),
                      icon: const Icon(Icons.home_outlined)),
                PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'Clear queue') {
                        clearQueue();
                      } else if (value == 'Open folder') {
                        folder();
                      } else if (value == 'History') {
                        sourceList('History', collections.history);
                      } else if (value == 'Favourites') {
                        sourceList('Favourites', collections.favourites);
                      } else if (value == 'Toggle favourite') {
                        toggleFavourite();
                      } else if (value == 'Named playlists') {
                        namedPlaylists();
                      } else if (value == 'Import IPTV playlist') {
                        importIptv();
                      } else if (value == 'Load subtitle file') {
                        externalSubtitles();
                      } else if (value == 'Playback speed') {
                        playbackOptions();
                      } else if (value == 'Watch statistics') {
                        watchStatistics();
                      } else if (value == 'Sleep timer') {
                        sleepTimer();
                      } else if (value == 'A–B repeat') {
                        repeatControls();
                      } else if (value == 'Video fit') {
                        fitOptions();
                      } else if (value == 'Subtitle delay') {
                        subtitleDelay();
                      } else if ([
                        'Language',
                        'Display settings',
                        'User manual',
                        'About Hyper Player',
                        'Privacy policy',
                        'Report a problem',
                        'Follow on Instagram'
                      ].contains(value)) {
                        homeMenu(value);
                      } else {
                        unavailable(value);
                      }
                    },
                    icon: const Icon(Icons.more_vert),
                    color: const Color(0xff1a1a24),
                    itemBuilder: (context) => [
                          for (final entry in <String, IconData>{
                            'Language': Icons.language,
                            'Display settings': Icons.tune_rounded,
                            'Watch statistics': Icons.bar_chart_rounded,
                            'History': Icons.history,
                            'User manual': Icons.menu_book_outlined,
                            'About Hyper Player': Icons.info_outline_rounded,
                            'Privacy policy': Icons.privacy_tip_outlined,
                            'Report a problem': Icons.flag_outlined,
                            'Follow on Instagram': Icons.camera_alt_outlined,
                          }.entries)
                            PopupMenuItem(
                                value: entry.key,
                                child: Row(children: [
                                  Icon(entry.value, size: 20),
                                  const SizedBox(width: 12),
                                  LText(entry.key)
                                ])),
                          const PopupMenuDivider(),
                          for (final name in [
                            'Sleep timer',
                            'A–B repeat',
                            'Video fit',
                            'Subtitle delay',
                            'Favourites',
                            'Toggle favourite',
                            'Named playlists',
                            'Import IPTV playlist',
                            'Load subtitle file',
                            'Playback speed',
                            'AI subtitles',
                            'Open folder',
                            'Clear queue'
                          ])
                            PopupMenuItem(value: name, child: LText(name)),
                          const PopupMenuDivider(),
                          const PopupMenuItem<String>(
                              enabled: false,
                              child: LText('Windows preview 0.2.0',
                                  style: TextStyle(
                                      fontSize: 11, color: Colors.grey))),
                        ]),
                const SizedBox(width: 12),
              ]),
              body: Column(children: [
                if (busy) const LinearProgressIndicator(),
                Expanded(
                    child: viewingPlayer
                        ? Row(children: [
                            Expanded(
                                child: Video(
                                    controller: controller,
                                    fit: videoFit,
                                    controls: AdaptiveVideoControls)),
                            SizedBox(
                                width: MediaQuery.sizeOf(context).width < 800
                                    ? 210
                                    : 280,
                                child: ListView.builder(
                                  itemCount: queue.length,
                                  itemBuilder: (context, i) => ListTile(
                                      selected: i == selected,
                                      leading: Icon(i == selected
                                          ? Icons.play_arrow
                                          : Icons.music_video),
                                      title: Text(labelFor(queue[i]),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis),
                                      onTap: () => play(i)),
                                )),
                          ])
                        : library()),
                if (!viewingPlayer && selected >= 0 && selected < queue.length)
                  Material(
                      color: const Color(0xff101013),
                      child: ListTile(
                        leading: IconButton(
                            tooltip: 'Play/pause',
                            onPressed: () => player.playOrPause(),
                            icon: const Icon(Icons.play_arrow)),
                        title: Text(labelFor(queue[selected]),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: TextButton(
                            onPressed: () =>
                                setState(() => viewingPlayer = true),
                            child: const LText('Open player')),
                      )),
                const Padding(
                    padding: EdgeInsets.all(6),
                    child: LText(
                        'Windows preview · Construction icon = integration pending · Folder import scans direct children only',
                        style:
                            TextStyle(fontSize: 10, color: Color(0xff9296a0)))),
              ]),
            )),
      );

  Future<void> clearQueue() async {
    repeatA = null;
    repeatB = null;
    await player.stop();
    if (!mounted) {
      return;
    }
    setState(() {
      queue.clear();
      selected = -1;
      viewingPlayer = false;
    });
    await save();
  }
}
