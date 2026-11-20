import 'screens/local_ai_screen.dart';
import 'screens/user_manual_android.dart';
import 'screens/library_layouts.dart';
import 'screens/onboarding_flow.dart';
import 'utils/onboarding.dart';
import 'player/native_properties.dart';
import 'windows_drives.dart';
import 'player/karaoke_overlay.dart';
import 'player/srt.dart';
import 'app_design.dart';
import 'utils/player_settings.dart';
import 'screens/player_settings_android.dart';
import 'dart:math' as math;
import 'package:url_launcher/url_launcher.dart';
import 'player/frame_preview_decoder.dart';
import 'player/mini_player.dart';
import 'package:window_manager/window_manager.dart';
import 'library_projection.dart';
import 'screens/private_space_screen.dart';
import 'screens/quick_share_screen.dart';
import 'screens/network_storage_screen.dart';
import 'screens/cloud_storage_screen.dart';
import 'local_media_index.dart' show isAudioPath, scanLocalMedia;
import 'player/audio_now_playing.dart';
import 'player/android_controls.dart';
import 'player/fit.dart';
import 'player/queue_order.dart';
import 'player/player_sheets.dart';
import 'player/mpv_filters.dart';
import 'screens/about_android.dart';
import 'local_thumbnail.dart';
import 'screens/video_adjustment_sheets.dart';
import 'screens/media_info_sheet.dart';
import 'screens/track_sheet.dart';
import 'screens/playback_sheets.dart';
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
import 'screens/collection_screens.dart';
import 'screens/stream_screen.dart';
import 'screens/library_screens.dart';
import 'screens/desktop_display_screen.dart';
import 'screens/info_sheets.dart';
import 'screens/search_screen.dart';
import 'screens/statistics_screen.dart';
import 'watch_days.dart';
import 'utils/app_language.dart';

import 'package:flutter_localizations/flutter_localizations.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  if (Platform.isWindows) await windowManager.ensureInitialized();
  await AppLanguage.instance.load();
  await AppDesign.instance.load();
  runApp(const HyperPlayer());
}

class HyperPlayer extends StatelessWidget {
  const HyperPlayer({super.key});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: Listenable.merge([AppLanguage.instance, AppDesign.instance]),
        builder: (context, child) => MaterialApp(
          locale: AppLanguage.instance.locale,
          supportedLocales:
              uiLanguages.map((language) => Locale(language.code)).toList(),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          title: 'Hyper Player - All Formats',
          debugShowCheckedModeBanner: false,
          theme: AppDesign.instance
              .theme(ThemeData.dark(useMaterial3: true).copyWith(
            cardTheme: CardThemeData(
              color: const Color(0xff101013),
              elevation: 0,
              margin: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: Color(0xff26262c)),
              ),
            ),
            dividerTheme: const DividerThemeData(
              color: Color(0xff26262c),
              thickness: 1,
            ),
            scaffoldBackgroundColor: const Color(0xff060608),
            appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xff060608),
              surfaceTintColor: Colors.transparent,
              titleTextStyle: TextStyle(
                color: Color(0xfff5f6f8),
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: .2,
              ),
            ),
            colorScheme: const ColorScheme.dark(
              primary: Colors.white,
              onPrimary: Color(0xff0b0b0e),
              surface: Color(0xff101013),
              onSurface: Color(0xfff5f6f8),
            ),
          )),
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(MediaQuery.textScalerOf(context)
                      .scale(AppDesign.instance.textScale))),
              child: child!),
          home: const DesktopPlayer(),
        ),
      );
}

class DesktopPlayer extends StatefulWidget {
  const DesktopPlayer({super.key});
  @override
  State<DesktopPlayer> createState() => _DesktopPlayerState();
}

class _DesktopPlayerState extends State<DesktopPlayer> {
  final inputSettings = PlayerSettings.instance;
  final framePreview = FramePreviewDecoder();
  final miniWindow = MiniPlayerWindow(WindowsMiniWindowPort());
  bool miniTransition = false;
  final player = Player();
  final mediaSizes = <String, int>{};
  final mediaLengths = <String, int>{};
  late final VideoController controller = VideoController(player);
  final queue = <String>[];
  final collections = DesktopStore();
  final scanFolders = <String>{};
  StreamSubscription<String>? errors;
  StreamSubscription<bool>? completion;
  int selected = -1;
  bool busy = false;
  bool scanCancelled = false;
  int scanFilesSeen = 0, scanDirectoriesSeen = 0;
  bool viewingPlayer = false;
  bool listMode = false;
  bool queueAll = true;
  bool onlyFavourites = false;
  bool groupByFolder = false;
  String librarySort = 'queue';
  FitMode fitMode = FitMode.fit;
  final order = QueueOrder();
  final playbackView = ValueNotifier(const PlaybackSnapshot());
  final List<StreamSubscription<dynamic>> playbackSubscriptions = [];
  bool sleepUntilEnd = false;
  bool autoHide = true;
  bool resumeEnabled = true;
  final resumePositions = <String, int>{};
  List<double> equalizerBands = [0, 0, 0, 0, 0];
  bool dialogueBoost = false;
  bool karaokeEnabled = false, enhanceEnabled = false, effectsBusy = false;
  String toneMapping = 'auto';
  int karaokeEpoch = 0;
  final karaokeCue = ValueNotifier<SrtCue?>(null);
  Map<String, String>? beforeEnhance;
  int playRequest = 0;
  bool openingMedia = false;
  Timer? sleep;
  Timer? ticker;
  DateTime? sleepDeadline;
  Duration? repeatA;
  Duration? repeatB;
  bool repeatSeeking = false;
  final dailyWatch = WatchDays();
  int watchSeconds = 0;
  int playStarts = 0;
  @override
  void initState() {
    super.initState();
    errors = player.stream.error.listen(
      (message) => notify('Playback error: $message'),
    );
    void updateView(dynamic _) {
      if (!mounted) return;
      final state = player.state;
      if (selected >= 0 &&
          selected < queue.length &&
          state.duration > Duration.zero) {
        mediaLengths[queue[selected]] = state.duration.inMilliseconds;
      }
      playbackView.value = PlaybackSnapshot(
          position: state.position,
          duration: state.duration,
          playing: state.playing,
          buffering: state.buffering,
          volume: state.volume,
          rate: state.rate);
    }

    playbackSubscriptions.addAll([
      player.stream.position.listen(updateView),
      player.stream.duration.listen(updateView),
      player.stream.playing.listen(updateView),
      player.stream.buffering.listen(updateView),
      player.stream.volume.listen(updateView),
      player.stream.rate.listen(updateView),
      player.stream.subtitle.listen(updateKaraoke),
    ]);
    completion = player.stream.completed.listen((done) {
      if (!done || openingMedia) return;
      if (selected >= 0 && selected < queue.length) {
        resumePositions.remove(queue[selected]);
      }
      if (sleepUntilEnd) {
        setState(() => sleepUntilEnd = false);
        player.pause();
        notify('Sleep timer — playback paused at end.');
        return;
      }
      if (!queueAll) return;
      final next = order.next(selected, queue.length, completed: true);
      if (next != null) play(next);
    });
    inputSettings.addListener(inputSettingsChanged);
    restore();
    ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (player.state.playing && !player.state.buffering) {
        watchSeconds++;
        if (selected >= 0 && selected < queue.length) {
          dailyWatch.record(DateTime.now(), labelFor(queue[selected]));
        }
        if (watchSeconds % 15 == 0) {
          unawaited(saveStats());
          rememberPosition();
          unawaited(savePlayerPreferences());
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
    await inputSettings.load();
    if (mounted) {
      autoHide = inputSettings.autoHide;
      resumeEnabled = inputSettings.resume;
    }
    await dailyWatch.load();
    scanFolders.addAll(prefs.getStringList('hyper.scan.folders.v1') ?? []);
    listMode = prefs.getBool('hyper.list.mode.v1') ?? false;
    queueAll = prefs.getBool('hyper.playback.queueAll.v1') ?? true;
    onlyFavourites = prefs.getBool('hyper.library.onlyFavourites.v1') ?? false;
    groupByFolder = prefs.getBool('hyper.library.groupFolder.v1') ?? false;
    final savedSort = prefs.getString('hyper.library.sort.v1');
    if ([
      'queue',
      'nameAsc',
      'nameDesc',
      'dateAsc',
      'dateDesc',
      'sizeAsc',
      'sizeDesc',
      'lengthAsc',
      'lengthDesc'
    ].contains(savedSort)) {
      librarySort = savedSort!;
    }
    autoHide = inputSettings.autoHide;
    resumeEnabled = inputSettings.resume;
    final fitIndex = prefs.getInt('hyper.player.fit.v1') ?? 0;
    fitMode = FitMode.values[fitIndex.clamp(0, FitMode.values.length - 1)];
    order.shuffle = prefs.getBool('hyper.player.shuffle.v1') ?? false;
    order.repeat = QueueRepeat
        .values[(prefs.getInt('hyper.player.repeat.v1') ?? 0).clamp(0, 2)];
    try {
      final decoded =
          jsonDecode(prefs.getString('hyper.player.positions.v1') ?? '{}');
      if (decoded is Map) {
        for (final entry in decoded.entries.take(500)) {
          if (entry.key is String && entry.value is int && entry.value > 0) {
            resumePositions[entry.key] = entry.value;
          }
        }
      }
    } catch (_) {/* Corrupt position cache never blocks the library. */}
    watchSeconds += prefs.getInt('hyper.watch.seconds.v1') ?? 0;
    playStarts += prefs.getInt('hyper.play.starts.v1') ?? 0;
    if (!mounted) {
      return;
    }
    setState(
      () => queue.addAll(decodeQueue(prefs.getString('hyper.queue.v1'))),
    );
    if (!await Onboarding.hasSeen() && mounted) {
      await Navigator.push<void>(
          context, MaterialPageRoute(builder: (_) => const OnboardingFlow()));
    }
    if (Platform.isWindows &&
        queue.isEmpty &&
        !(prefs.getBool('hyper.scan.intro.v1') ?? false)) {
      await prefs.setBool('hyper.scan.intro.v1', true);
      if (mounted) await scanLibraryOptions();
    }
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
    final request = ++playRequest;
    final source = queue[index];
    try {
      if (!validStream(source) && !await File(source).exists()) {
        notify(
            'File is no longer available. Open it again from its current location.');
        return;
      }
      if (!mounted ||
          request != playRequest ||
          index >= queue.length ||
          queue[index] != source) {
        return;
      }
      rememberPosition();
      karaokeEpoch++;
      karaokeCue.value = null;
      setState(() {
        selected = index;
        fitMode = FitMode.values[inputSettings.defaultFit];
        viewingPlayer = true;
        openingMedia = true;
      });
      repeatA = null;
      repeatB = null;
      order.select(index, queue.length);
      final start = resumeEnabled && !validStream(source)
          ? resumePositions[source] ?? 0
          : 0;
      // Let the windowed Video attach before opening its decoder. Playback
      // starts explicitly; stats/preference IO is not on the start path.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || request != playRequest) return;
      await player.open(Media(source, start: Duration(milliseconds: start)),
          play: true);
      if (!mounted || request != playRequest) return;
      await player.setRate((await SharedPreferences.getInstance())
              .getDouble('hyper.player.rate.v1') ??
          1);
      await applyInputProfile();
      playStarts++;
      await saveStats();
      await collections.record(source);
    } catch (e) {
      notify('Cannot open media: $e');
    } finally {
      if (mounted && request == playRequest) {
        setState(() => openingMedia = false);
      }
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
      final result = await openFiles(
        acceptedTypeGroups: [
          XTypeGroup(label: 'Media', extensions: mediaExtensions.toList()),
        ],
      );
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
      setState(() {
        busy = true;
        scanCancelled = false;
        scanFilesSeen = 0;
        scanDirectoriesSeen = 0;
      });
      final result = await scanLocalMedia([path],
          recursive: true,
          cancelled: () => !mounted || scanCancelled,
          onProgress: updateScanProgress);
      if (!mounted) return;
      final paths = result.folders.values
          .expand((items) => items.map((entry) => entry.path))
          .toList();
      if (result.truncated || result.unavailable.isNotEmpty) {
        notify(
            'Scan partial: ${result.unavailable.length} folders unavailable; limit/cancellation: ${result.truncated}.');
      }
      paths.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      await add(paths);
      if (paths.isEmpty) {
        notify(
            'No supported media found in this folder or its accessible subfolders.');
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
    final value = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            DesktopStreamScreen(recent: List.of(collections.history)),
      ),
    );
    if (value == null || !mounted) {
      return;
    }
    if (value == '__IMPORT_M3U__') {
      await importIptv();
      return;
    }
    await playSource(value);
  }

  @override
  void dispose() {
    inputSettings.removeListener(inputSettingsChanged);
    rememberPosition();
    unawaited(savePlayerPreferences());
    sleep?.cancel();
    ticker?.cancel();
    for (final sub in playbackSubscriptions) {
      sub.cancel();
    }
    karaokeEpoch++;
    karaokeCue.dispose();
    playbackView.dispose();
    unawaited(saveStats());
    errors?.cancel();
    completion?.cancel();
    unawaited(framePreview.dispose());
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
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const LText('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, value.trim()),
            child: const LText('Continue'),
          ),
        ],
      ),
    );
  }

  Future<void> playSource(String source) async {
    var index = queue.indexOf(source);
    if (index < 0) {
      setState(() => queue.add(source));
      await save();
      index = queue.length - 1;
    }
    if (mounted) {
      await play(index);
    }
  }

  Future<void> sourceList(String title, List<String> sources) async {
    if (!mounted) {
      return;
    }
    final editable = identical(sources, collections.history) ||
        identical(sources, collections.favourites);
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => SourceCollectionScreen(
          title: title,
          sources: sources,
          onSave: editable ? collections.save : null,
        ),
      ),
    );
    if (result != null && mounted) {
      await playSource(result);
    }
  }

  Future<void> namedPlaylists() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => DesktopPlaylistsScreen(
          store: collections,
          currentQueue: List.of(queue),
        ),
      ),
    );
    if (result != null && mounted) {
      await playSource(result);
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
    notify(
      collections.favourites.contains(source)
          ? 'Added to favourites.'
          : 'Removed from favourites.',
    );
  }

  Future<void> searchMedia() async {
    final all = {
      ...queue,
      ...collections.history,
      ...collections.favourites,
      for (final list in collections.playlists.values) ...list
    };
    final source = await Navigator.push<String>(
        context,
        MaterialPageRoute(
            builder: (_) => DesktopSearchScreen(
                sources: all.toList(), listMode: listMode)));
    if (source != null && mounted) {
      await playSource(source);
    }
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
              child: const LText('From a local M3U file'),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, 'url'),
              child: const LText('From an HTTP/HTTPS URL'),
            ),
          ],
        ),
      );
      if (kind == null || !mounted) {
        return;
      }
      String text;
      Uri base;
      if (kind == 'file') {
        final file = await openFile(
          acceptedTypeGroups: [
            const XTypeGroup(
              label: 'M3U playlist',
              extensions: ['m3u', 'm3u8'],
            ),
          ],
        );
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
          final response = await request.close().timeout(
                const Duration(seconds: 20),
              );
          if (response.statusCode != 200) {
            throw HttpException('HTTP ${response.statusCode}');
          }
          for (final redirect in response.redirects) {
            base = base.resolveUri(redirect.location);
          }
          final bytes = <int>[];
          await for (final chunk in response.timeout(
            const Duration(seconds: 20),
          )) {
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
        'Imported ${entries.length} entries. No EPG or channel logos in this version.',
      );
    } catch (e) {
      notify('Playlist import failed: $e');
    }
  }

  Future<void> trackPicker({required bool subtitle}) async {
    final tracks = player.state.tracks;
    await showPlaybackSheet<void>(
        context,
        Builder(
            builder: (sheetContext) => DesktopTrackSheet(
                  subtitle: subtitle,
                  selected: subtitle
                      ? player.state.track.subtitle.id
                      : player.state.track.audio.id,
                  tracks: subtitle
                      ? [
                          for (final t in tracks.subtitle)
                            if (t.id != 'no' && t.id != 'auto')
                              DesktopTrackChoice(
                                  t.id,
                                  desktopTrackLabel(
                                      id: t.id,
                                      title: t.title,
                                      language: t.language,
                                      codec: t.codec))
                        ]
                      : [
                          for (final t in tracks.audio)
                            if (t.id != 'no' && t.id != 'auto')
                              DesktopTrackChoice(
                                  t.id,
                                  desktopTrackLabel(
                                      id: t.id,
                                      title: t.title,
                                      language: t.language,
                                      codec: t.codec))
                        ],
                  onSelect: (id) async {
                    if (subtitle) {
                      await player.setSubtitleTrack(id == 'no'
                          ? SubtitleTrack.no()
                          : tracks.subtitle.firstWhere((t) => t.id == id));
                    } else {
                      await player.setAudioTrack(
                          tracks.audio.firstWhere((t) => t.id == id));
                    }
                  },
                  onExternal: () {
                    Navigator.pop(sheetContext);
                    externalSubtitles();
                  },
                )));
  }

  Future<void> externalSubtitles() async {
    if (selected < 0) {
      notify('Play a video first.');
      return;
    }
    try {
      final file = await openFile(
        acceptedTypeGroups: [
          const XTypeGroup(
            label: 'Subtitles',
            extensions: ['srt', 'ass', 'ssa', 'vtt'],
          ),
        ],
      );
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
    await showPlaybackSheet<void>(
        context,
        PlaybackSpeedSheet(
            rate: player.state.rate,
            onRate: (value) async {
              await player.setRate(value);
              final prefs = await SharedPreferences.getInstance();
              await prefs.setDouble('hyper.player.rate.v1', value);
            }),
        color: const Color(0xff1a1a24));
  }

  Future<void> sleepTimer() async {
    final minutes = await showPlaybackSheet<int>(
        context,
        Builder(
            builder: (sheetContext) => SleepTimerSheet(
                deadline: sleepDeadline,
                onEnd: () => Navigator.pop(sheetContext, -1),
                untilEnd: sleepUntilEnd,
                onMinutes: (minutes) => Navigator.pop(sheetContext, minutes))));
    if (minutes == null || !mounted) {
      return;
    }
    sleep?.cancel();
    sleepUntilEnd = minutes == -1;
    sleepDeadline =
        minutes <= 0 ? null : DateTime.now().add(Duration(minutes: minutes));
    if (minutes > 0) {
      sleep = Timer(Duration(minutes: minutes), () {
        player.pause();
        if (mounted) setState(() => sleepDeadline = null);
        notify('Sleep timer: playback paused.');
      });
    }
    setState(() {});
    notify(
      minutes == -1
          ? 'Playback will pause at the end of this item.'
          : minutes == 0
              ? 'Sleep timer cancelled.'
              : 'Playback will pause in $minutes minutes.',
    );
  }

  void rememberPosition() {
    if (!resumeEnabled ||
        selected < 0 ||
        selected >= queue.length ||
        validStream(queue[selected])) {
      return;
    }
    final state = player.state;
    final source = queue[selected];
    if (state.position.inSeconds > 5 &&
        state.duration - state.position > const Duration(seconds: 10)) {
      resumePositions.remove(source);
      resumePositions[source] = state.position.inMilliseconds;
      while (resumePositions.length > 500) {
        resumePositions.remove(resumePositions.keys.first);
      }
    } else if (state.duration > Duration.zero &&
        state.duration - state.position <= const Duration(seconds: 10)) {
      resumePositions.remove(source);
    }
  }

  Future<void> savePlayerPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hyper.player.autohide.v1', autoHide);
    await prefs.setBool('hyper.player.resume.v1', resumeEnabled);
    await prefs.setBool('hyper.player.shuffle.v1', order.shuffle);
    await prefs.setInt('hyper.player.repeat.v1', order.repeat.index);
    await prefs.setInt('hyper.player.fit.v1', fitMode.index);
    await prefs.setString(
        'hyper.player.positions.v1', jsonEncode(resumePositions));
  }

  Future<void> skipPlayer({bool previous = false}) async {
    final next = previous
        ? order.previous(selected, queue.length)
        : order.next(selected, queue.length);
    if (next != null) await play(next);
  }

  Future<void> changeAudioFilters(List<double> bands, bool boost) async {
    await (player.platform as NativePlayer)
        .setProperty('af', combineAudioFilters(bands, dialogueBoost: boost));
    equalizerBands = [...bands];
    dialogueBoost = boost;
  }

  Future<void> equalizer() => showPlaybackSheet<void>(
      context,
      EqualizerSheet(
          initial: equalizerBands,
          dialogue: dialogueBoost,
          onApply: changeAudioFilters));

  Future<void> setPlayerVolume(double requested) async {
    final value =
        requested.clamp(0.0, inputSettings.volumeBoost ? 200.0 : 100.0);
    try {
      final native = player.platform;
      if (native is NativePlayer && value > 0) {
        await setCheckedProperty(native, 'mute', 'no');
      }
      await player.setVolume(value);
      if (native is NativePlayer &&
          !propertyMatches(
              'volume', '$value', await native.getProperty('volume'))) {
        throw StateError('Volume readback failed');
      }
    } catch (_) {
      notify('Could not change media volume. Check the Windows output device.');
    }
  }

  Future<void> screenshot() async {
    try {
      final bytes = await player.screenshot(format: 'image/png');
      if (bytes == null || bytes.isEmpty) {
        notify('No video frame available for screenshot.');
        return;
      }
      final target = await getSaveLocation(
          suggestedName:
              'HyperPlayer-${DateTime.now().millisecondsSinceEpoch}.png',
          acceptedTypeGroups: [
            const XTypeGroup(label: 'PNG image', extensions: ['png'])
          ]);
      if (target == null) return;
      await File(target.path).writeAsBytes(bytes, flush: true);
      notify('Screenshot saved.');
    } catch (_) {
      notify('Could not save screenshot.');
    }
  }

  void inputSettingsChanged() {
    if (!mounted) return;
    setState(() {
      autoHide = inputSettings.autoHide;
      resumeEnabled = inputSettings.resume;
    });
    if (selected >= 0) unawaited(applyInputProfile());
  }

  Future<void> applyInputProfile() async {
    final native = player.platform;
    if (native is! NativePlayer) return;
    try {
      await native.setProperty(
          'volume-max', inputSettings.volumeBoost ? '200' : '100');
      if (!inputSettings.volumeBoost && player.state.volume > 100) {
        await player.setVolume(100);
      }
      await native.setProperty(
          'framedrop', inputSettings.performanceMode == 'on' ? 'vo' : 'no');
    } catch (_) {
      notify('Some native sound/performance settings could not be applied.');
    }
  }

  Future<void> playerSettings() async {
    await showPlaybackSheet<void>(context, const PlayerSettingsSheet());
  }

  Future<void> updateKaraoke(List<String> parts) async {
    if (!karaokeEnabled) return;
    final epoch = ++karaokeEpoch;
    final text = parts.isEmpty ? '' : parts.first.trim();
    if (text.isEmpty) {
      karaokeCue.value = null;
      return;
    }
    if (text.length > 8192 || isMusicOnlyText(text)) {
      karaokeCue.value = null;
      return;
    }
    final native = player.platform;
    if (native is! NativePlayer) return;
    try {
      final start = double.tryParse(await native.getProperty('sub-start'));
      final end = double.tryParse(await native.getProperty('sub-end'));
      if (!mounted || epoch != karaokeEpoch || !karaokeEnabled) return;
      if (start == null ||
          end == null ||
          !start.isFinite ||
          !end.isFinite ||
          end <= start) {
        karaokeCue.value = null;
        return;
      }
      karaokeCue.value = SrtCue((start * 1000).round(), (end * 1000).round(),
          text.replaceAll(RegExp(r'<[^>]*>|\{[^}]*\}'), ''));
    } catch (_) {
      if (mounted && epoch == karaokeEpoch) karaokeCue.value = null;
    }
  }

  Future<void> setKaraoke(bool value) async {
    if (value && ['no', 'auto', ''].contains(player.state.track.subtitle.id)) {
      final tracks = player.state.tracks.subtitle
          .where((track) => track.id != 'no' && track.id != 'auto')
          .toList();
      if (tracks.isEmpty) {
        notify(
            'Select or load text subtitles first; karaoke does not generate captions.');
        return;
      }
      try {
        await player.setSubtitleTrack(tracks.first);
      } catch (_) {
        notify('Could not select a subtitle track.');
        return;
      }
    }
    if (!mounted) return;
    setState(() => karaokeEnabled = value);
    karaokeEpoch++;
    karaokeCue.value = null;
    if (value) {
      await updateKaraoke(player.state.subtitle);
      notify(
          'Karaoke on: word timing is estimated inside each timed text cue. Bitmap subtitles may not supply text.');
    }
  }

  Future<void> setEnhance(bool value) async {
    final native = player.platform;
    if (native is! NativePlayer) {
      notify('Native video filtering is unavailable.');
      return;
    }
    final current = <String, String>{};
    try {
      for (final key in ['vf', 'contrast', 'saturation', 'gamma']) {
        current[key] = await native.getProperty(key);
      }
      final desired = value
          ? {
              'vf': buildEnhanceFilter(),
              'contrast': '14',
              'saturation': '12',
              'gamma': '2'
            }
          : (beforeEnhance ??
              {'vf': '', 'contrast': '0', 'saturation': '0', 'gamma': '0'});
      for (final entry in desired.entries) {
        await setCheckedProperty(native, entry.key, entry.value);
      }
      if (value) beforeEnhance = current;
      if (mounted) setState(() => enhanceEnabled = value);
    } catch (_) {
      for (final entry in current.entries) {
        try {
          await native.setProperty(entry.key, entry.value);
        } catch (_) {}
      }
      notify(
          'Video enhancement could not be applied; previous filter values restored where possible.');
    }
  }

  Future<void> setToneMapping(String value) async {
    if (!['auto', 'clip', 'mobius', 'reinhard', 'hable', 'bt.2390']
        .contains(value)) {
      return;
    }
    final native = player.platform;
    if (native is! NativePlayer) return;
    final previous = toneMapping;
    try {
      await setCheckedProperty(native, 'tone-mapping', value);
      if (mounted) setState(() => toneMapping = value);
      notify(
          'Tone-mapping mode set. It affects HDR sources on supported renderers, not ordinary SDR video.');
    } catch (_) {
      try {
        await native.setProperty('tone-mapping', previous);
      } catch (_) {}
      notify('This renderer did not accept the tone-mapping mode.');
    }
  }

  Future<void> extras() async {
    await showPlaybackSheet<void>(
        context,
        StatefulBuilder(
            builder: (sheetContext, update) =>
                Column(mainAxisSize: MainAxisSize.min, children: [
                  const PlaybackSheetHandle(),
                  ListTile(
                      leading: const Icon(Icons.auto_awesome),
                      title: const Text('AI subtitles · generate locally'),
                      subtitle: const Text(
                          'Download tools/model once; no video upload'),
                      onTap: () {
                        Navigator.pop(sheetContext);
                        generateAiSubtitles();
                      }),
                  ListTile(
                      leading: const Icon(Icons.subtitles_rounded),
                      title: const Text('Subtitles'),
                      onTap: () {
                        Navigator.pop(sheetContext);
                        trackPicker(subtitle: true);
                      }),
                  ListTile(
                      leading: const Icon(Icons.music_note_rounded),
                      title: const Text('Audio track'),
                      onTap: () {
                        Navigator.pop(sheetContext);
                        trackPicker(subtitle: false);
                      }),
                  ListTile(
                      leading: const Icon(Icons.repeat_one_rounded),
                      title: const Text('A-B loop'),
                      subtitle: Text(repeatA == null
                          ? 'Off'
                          : repeatB == null
                              ? 'A set · set B after seeking'
                              : 'Loop active'),
                      onTap: () {
                        Navigator.pop(sheetContext);
                        repeatControls();
                      }),
                  ListTile(
                      leading: const Icon(Icons.subtitles_outlined),
                      title: const Text('Subtitle delay'),
                      onTap: () {
                        Navigator.pop(sheetContext);
                        subtitleDelay();
                      }),
                  ListTile(
                      leading: const Icon(Icons.graphic_eq),
                      title: const Text('Equalizer & Audio FX'),
                      onTap: () {
                        Navigator.pop(sheetContext);
                        equalizer();
                      }),
                  SwitchListTile(
                      secondary: const Icon(Icons.closed_caption_outlined),
                      title: const Text('Karaoke subtitles'),
                      subtitle: const Text(
                          'Timed text required; word timing is estimated like Android.'),
                      value: karaokeEnabled,
                      onChanged: effectsBusy
                          ? null
                          : (value) async {
                              update(() => effectsBusy = true);
                              await setKaraoke(value);
                              if (sheetContext.mounted) {
                                update(() => effectsBusy = false);
                              }
                            }),
                  SwitchListTile(
                      secondary: const Icon(Icons.auto_fix_high),
                      title: const Text('Enhance video'),
                      subtitle: const Text(
                          'Native sharpen/contrast filter; codec/renderer support required.'),
                      value: enhanceEnabled,
                      onChanged: effectsBusy
                          ? null
                          : (value) async {
                              update(() => effectsBusy = true);
                              await setEnhance(value);
                              if (sheetContext.mounted) {
                                update(() => effectsBusy = false);
                              }
                            }),
                  ListTile(
                      leading: const Icon(Icons.hdr_on),
                      title: const Text('HDR tone-mapping'),
                      subtitle: const Text(
                          'Only affects HDR video on supported renderers.'),
                      trailing: DropdownButton<String>(
                          value: toneMapping,
                          items: [
                            for (final mode in [
                              'auto',
                              'clip',
                              'mobius',
                              'reinhard',
                              'hable',
                              'bt.2390'
                            ])
                              DropdownMenuItem(value: mode, child: Text(mode))
                          ],
                          onChanged: effectsBusy
                              ? null
                              : (value) async {
                                  if (value == null) return;
                                  update(() => effectsBusy = true);
                                  await setToneMapping(value);
                                  if (sheetContext.mounted) {
                                    update(() => effectsBusy = false);
                                  }
                                })),
                  const SizedBox(height: 18),
                ])));
  }

  Future<void> castToTv() async {
    if (!Platform.isWindows) {
      notify('Wireless display is available on Windows.');
      return;
    }
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
              title: const Text('Cast to TV · Windows wireless display'),
              content: const Text(
                  'Open the Windows wireless-display chooser to select a compatible Miracast TV or adapter. This mirrors the screen, including other visible apps. Your PC and TV must support wireless display. This is not Chromecast, DLNA or private media-only casting. Stop projection from Windows when finished.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: const Text('Open Windows Cast')),
              ],
            ));
    if (confirmed != true || !mounted) return;
    try {
      if (!await launchUrl(
          Uri.parse('ms-settings-connectabledevices:devicediscovery'),
          mode: LaunchMode.externalApplication)) {
        throw StateError('Wireless display chooser unavailable.');
      }
    } catch (_) {
      notify(
          'Could not open Windows Cast. Press Windows+K and check wireless-display support.');
    }
  }

  Future<void> toggleMiniPlayer() async {
    if (!Platform.isWindows || miniTransition) return;
    setState(() => miniTransition = true);
    try {
      if (miniWindow.active) {
        await miniWindow.restore();
      } else {
        await miniWindow.enter();
      }
    } catch (_) {
      notify(
          'Windows mini-player could not change window state. Use Return to full player to retry restoration.');
    } finally {
      if (mounted) setState(() => miniTransition = false);
    }
  }

  void playerMenu(String action) {
    switch (action) {
      case 'AI subtitles':
        generateAiSubtitles();
      case 'Playback queue':
        showQueue();
      case 'Cast to TV':
        castToTv();
      case 'Picture-in-Picture':
        toggleMiniPlayer();
      case 'Video info':
        videoInfo();
      case 'Equalizer & Audio FX':
        equalizer();
      case 'Screenshot':
        screenshot();
      case 'Sleep timer':
        sleepTimer();
    }
  }

  Widget buildVideoPlayer() {
    final currentSource =
        selected >= 0 && selected < queue.length ? queue[selected] : null;
    if (selected >= 0 &&
        selected < queue.length &&
        isAudioPath(queue[selected]) &&
        !miniWindow.active) {
      return AudioNowPlaying(
          playback: playbackView,
          title: labelFor(queue[selected]),
          index: selected,
          count: queue.length,
          shuffle: order.shuffle,
          repeat: order.repeat,
          canPrevious: order.hasPrevious(selected, queue.length),
          canNext: order.hasNext(selected, queue.length),
          onBack: () {
            player.pause();
            setState(() => viewingPlayer = false);
          },
          onQueue: namedPlaylists,
          onSettings: playerSettings,
          onPlayPause: () => player.playOrPause(),
          onPrevious: () => skipPlayer(previous: true),
          onNext: () => skipPlayer(),
          onShuffle: () {
            setState(() => order.setShuffle(!order.shuffle,
                current: selected, length: queue.length));
            unawaited(savePlayerPreferences());
          },
          onRepeat: () {
            setState(() => order.repeat =
                QueueRepeat.values[(order.repeat.index + 1) % 3]);
            unawaited(savePlayerPreferences());
          },
          onSpeed: playbackOptions,
          onSeek: (value) => player.seek(value),
          onVolume: setPlayerVolume);
    }

    Widget output = Video(
        controller: controller,
        fit: miniWindow.active ? BoxFit.contain : fitMode.boxFit,
        subtitleViewConfiguration:
            SubtitleViewConfiguration(visible: !karaokeEnabled),
        controls: (videoState) => miniWindow.active
            ? ValueListenableBuilder<PlaybackSnapshot>(
                valueListenable: playbackView,
                builder: (_, state, __) => MiniPlayerControls(
                    title: selected >= 0 && selected < queue.length
                        ? labelFor(queue[selected])
                        : 'Hyper Player',
                    playing: state.playing,
                    onPlayPause: () => player.playOrPause(),
                    onRestore: toggleMiniPlayer))
            : AndroidPlayerControls(
                playback: playbackView,
                karaokeOverlay: karaokeEnabled
                    ? KaraokeOverlay(playback: playbackView, cue: karaokeCue)
                    : null,
                onTransform: (zoom, pan) async {
                  final native = player.platform;
                  if (native is NativePlayer) {
                    try {
                      await native.setProperty(
                          'video-zoom', '${math.log(zoom) / math.ln2}');
                      await native.setProperty('video-pan-x', '${pan.dx}');
                      await native.setProperty('video-pan-y', '${pan.dy}');
                    } catch (_) {
                      notify(
                          'Video zoom/pan is unavailable for this renderer.');
                    }
                  }
                },
                onTemporaryRate: (rate) async {
                  try {
                    await player.setRate(rate);
                  } catch (_) {}
                },
                onSelectFit: (fit) {
                  setState(() => fitMode = fit);
                  unawaited(savePlayerPreferences());
                },
                previewSourceKey: currentSource ?? '',
                previewLoader: currentSource != null &&
                        !validStream(currentSource) &&
                        !isAudioPath(currentSource)
                    ? (position) => framePreview.frame(currentSource, position)
                    : null,
                title: selected >= 0 && selected < queue.length
                    ? labelFor(queue[selected])
                    : 'Hyper Player',
                shuffle: order.shuffle,
                repeat: order.repeat,
                fit: fitMode,
                autoHide: autoHide,
                sleepDeadline: sleepDeadline,
                sleepUntilEnd: sleepUntilEnd,
                canPrevious: order.hasPrevious(selected, queue.length),
                canNext: order.hasNext(selected, queue.length),
                onBack: () {
                  if (videoState.isFullscreen()) {
                    videoState.exitFullscreen();
                  } else {
                    setState(() => viewingPlayer = false);
                  }
                },
                onPlayPause: () => player.playOrPause(),
                onPrevious: () => skipPlayer(previous: true),
                onNext: () => skipPlayer(),
                onShuffle: () {
                  setState(() => order.setShuffle(!order.shuffle,
                      current: selected, length: queue.length));
                  unawaited(savePlayerPreferences());
                },
                onRepeat: () {
                  setState(() => order.repeat =
                      QueueRepeat.values[(order.repeat.index + 1) % 3]);
                  unawaited(savePlayerPreferences());
                },
                onFit: () {
                  setState(() => fitMode = nextFitMode(fitMode));
                  unawaited(savePlayerPreferences());
                },
                onSpeed: playbackOptions,
                onExtras: extras,
                onQueue: namedPlaylists,
                onSettings: playerSettings,
                onFullscreen: () => videoState.isFullscreen()
                    ? videoState.exitFullscreen()
                    : videoState.enterFullscreen(),
                onMenu: (action) async {
                  if ((action == 'Picture-in-Picture' ||
                          action == 'Cast to TV') &&
                      videoState.isFullscreen()) {
                    await videoState.exitFullscreen();
                  }
                  playerMenu(action);
                },
                onSeek: (value) => player.seek(value),
                onVolume: setPlayerVolume,
              ));
    final ratio = miniWindow.active ? null : fitMode.aspectRatio;
    if (ratio != null) {
      output = Center(child: AspectRatio(aspectRatio: ratio, child: output));
    }
    return ColoredBox(color: Colors.black, child: output);
  }

  Future<void> videoInfo() async {
    final state = player.state;
    final source =
        selected >= 0 && selected < queue.length ? queue[selected] : null;
    await MediaInfoSheet.show(
        context,
        MediaInfoSheet(
          title: source == null ? 'No media selected' : labelFor(source),
          rows: [
            if (source != null) MapEntry('Source', source),
            MapEntry('Position',
                '${mediaClock(state.position)} / ${mediaClock(state.duration)}'),
            MapEntry('Remaining', mediaClock(state.duration - state.position)),
            MapEntry('Playback speed', '${state.rate}x'),
            if (state.videoParams.w != null && state.videoParams.h != null)
              MapEntry('Resolution',
                  '${state.videoParams.w} × ${state.videoParams.h}'),
            if (state.audioBitrate != null)
              MapEntry('Audio bitrate', '${state.audioBitrate} bit/s'),
          ],
          tracks: {
            'Video tracks': [
              for (final t in state.tracks.video)
                if (t.id != 'no' && t.id != 'auto')
                  desktopTrackLabel(
                      id: t.id,
                      title: t.title,
                      language: t.language,
                      codec: t.codec)
            ],
            'Audio tracks': [
              for (final t in state.tracks.audio)
                if (t.id != 'no' && t.id != 'auto')
                  desktopTrackLabel(
                      id: t.id,
                      title: t.title,
                      language: t.language,
                      codec: t.codec)
            ],
            'Subtitles': [
              for (final t in state.tracks.subtitle)
                if (t.id != 'no' && t.id != 'auto')
                  desktopTrackLabel(
                      id: t.id,
                      title: t.title,
                      language: t.language,
                      codec: t.codec)
            ],
          },
        ));
  }

  Future<void> repeatControls() async {
    await showPlaybackSheet<void>(
        context,
        Builder(
            builder: (sheetContext) => RepeatControlSheet(
                a: repeatA,
                b: repeatB,
                onAction: (action) {
                  if (action == 'a') {
                    if (selected < 0) {
                      notify('Play media first.');
                      return;
                    }
                    repeatA = player.state.position;
                    repeatB = null;
                    notify('Start point A set. Seek forward, then set B.');
                  } else if (action == 'b') {
                    final a = repeatA;
                    if (a == null ||
                        player.state.position <=
                            a + const Duration(seconds: 1)) {
                      notify(
                          'Set A first, then set B at least one second later.');
                      return;
                    }
                    repeatB = player.state.position;
                    notify('A–B repeat enabled.');
                  } else {
                    repeatA = null;
                    repeatB = null;
                    notify('A–B repeat disabled.');
                  }
                  Navigator.pop(sheetContext);
                })));
  }

  Future<void> fitOptions() async {
    final choice = await showPlaybackSheet<FitMode>(
        context,
        Builder(
            builder: (sheetContext) => SixModeFitSheet(
                selected: fitMode,
                onSelect: (value) => Navigator.pop(sheetContext, value))));
    if (choice != null && mounted) {
      setState(() => fitMode = choice);
      await savePlayerPreferences();
    }
  }

  Future<void> subtitleDelay() async {
    await showPlaybackSheet<void>(context,
        SubtitleDelaySheet(onApply: (ms) async {
      await (player.platform as NativePlayer)
          .setProperty('sub-delay', (ms / 1000).toString());
      notify('Subtitle delay set to $ms ms.');
    }));
  }

  Future<void> watchStatistics() async {
    await Navigator.push<void>(
        context,
        MaterialPageRoute(
            builder: (_) => DesktopStatisticsScreen(
                stats: dailyWatch,
                lifetimeSeconds: watchSeconds,
                starts: playStarts)));
  }

  Future<void> saveStats() async {
    final seconds = watchSeconds;
    final starts = playStarts;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('hyper.watch.seconds.v1', seconds);
    await prefs.setInt('hyper.play.starts.v1', starts);
    await dailyWatch.save();
  }

  void updateScanProgress(int files, int directories) {
    if (mounted) {
      setState(() {
        scanFilesSeen = files;
        scanDirectoriesSeen = directories;
      });
    }
  }

  Future<void> scanLibraryOptions() async {
    if (busy) return;
    final choice = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
              title: const Text('Scan videos and audio'),
              content: const Text(
                  'Scan all local fixed drives to discover media across this PC, or choose specific folders/drives. Scanning includes subfolders. For manual scanning, choose a root such as C:\u005c or D:\u005c, then add other drives the same way. Only accessible locations are read; protected folders and links are skipped. Each scan is bounded to 20,000 media files and 100,000 directories and reports partial results. You can cancel without deleting existing library entries.'),
              actions: [
                if (Platform.isWindows)
                  FilledButton.icon(
                      icon: const Icon(Icons.computer),
                      onPressed: () => Navigator.pop(dialogContext, 'all'),
                      label: const Text('Scan all local drives')),
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('Cancel')),
                if (scanFolders.isNotEmpty)
                  TextButton(
                      onPressed: () => Navigator.pop(dialogContext, 'saved'),
                      child: const Text('Rescan saved roots')),
                FilledButton(
                    onPressed: () => Navigator.pop(dialogContext, 'choose'),
                    child: const Text('Choose folder / drive')),
              ],
            ));
    if (!mounted) return;
    if (choice == 'all') {
      try {
        final roots = windowsFixedDriveRoots();
        if (roots.isEmpty) {
          notify(
              'No local fixed drives found. Choose a folder or drive manually.');
          return;
        }
        scanFolders.addAll(roots);
        final prefs = await SharedPreferences.getInstance();
        if (!await prefs.setStringList(
            'hyper.scan.folders.v1', scanFolders.toList())) {
          throw StateError('Could not save scan roots.');
        }
        if (mounted) await rescan();
      } catch (_) {
        notify(
            'Could not enumerate or save local drives. Choose a folder manually.');
      }
    }
    if (choice == 'choose') await folder();
    if (choice == 'saved') await rescan();
  }

  Future<void> rescan() async {
    if (busy) {
      return;
    }
    if (scanFolders.isEmpty) {
      await folder();
      return;
    }
    setState(() {
      busy = true;
      scanCancelled = false;
      scanFilesSeen = 0;
      scanDirectoriesSeen = 0;
    });
    final result = await scanLocalMedia(scanFolders,
        recursive: true,
        cancelled: () => !mounted || scanCancelled,
        onProgress: updateScanProgress);
    final found = result.folders.values
        .expand((items) => items.map((entry) => entry.path))
        .toSet();
    final failures = result.unavailable.length;
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
      'Rescan: ${additions.length} new files. $failures folders unavailable. ${result.truncated ? 'Partial scan: limit or cancellation. ' : ''}Existing entries retained.',
    );
  }

  Future<void> infoDialog(String title, String body) async {
    await showAndroidInfoSheet(context, title, body);
  }

  Future<void> browseFolders() async {
    final source = await Navigator.push<String>(
        context,
        MaterialPageRoute(
            builder: (_) => DesktopFoldersScreen(onScanSystem: () async {
                  Navigator.pop(context);
                  await scanLibraryOptions();
                })));
    final prefs = await SharedPreferences.getInstance();
    scanFolders
      ..clear()
      ..addAll(prefs.getStringList('hyper.scan.folders.v1') ?? []);
    if (source != null && mounted) {
      await playSource(source);
    }
  }

  Future<void> browsePrivateSpace() async {
    await player.pause();
    if (!mounted) return;
    await Navigator.push<void>(context,
        MaterialPageRoute(builder: (_) => const DesktopPrivateSpaceScreen()));
  }

  Future<void> browseQuickShare() async {
    final received = await Navigator.push<List<String>>(
        context,
        MaterialPageRoute(
            builder: (_) => DesktopQuickShareScreen(
                    knownSources: {
                  ...queue,
                  ...collections.history,
                  ...collections.favourites,
                  ...collections.playlists.values.expand((items) => items)
                }.toList())));
    if (mounted && received != null) await add(received);
  }

  Future<void> browseNetwork() async {
    final source = await Navigator.push<String>(context,
        MaterialPageRoute(builder: (_) => const DesktopNetworkStorageScreen()));
    if (mounted && source != null) await playSource(source);
  }

  Future<void> browseCloud() async {
    final path = await Navigator.push<String>(context,
        MaterialPageRoute(builder: (_) => const DesktopCloudStorageScreen()));
    if (mounted && path != null) await playSource(path);
  }

  Future<void> browseAudio() async {
    final source = await Navigator.push<String>(
        context,
        MaterialPageRoute(
            builder: (_) => DesktopAudioScreen(
                knownSources: {...queue, ...collections.history}.toList())));
    if (source != null && mounted) {
      await playSource(source);
    }
  }

  Future<void> toggleLibraryLayout() async {
    final next = !listMode;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setBool('hyper.list.mode.v1', next)) {
        throw StateError('Display preference was not saved.');
      }
      if (mounted) setState(() => listMode = next);
    } catch (_) {
      notify('Could not save display settings.');
    }
  }

  Future<void> refreshMediaMetadata() async {
    for (final source in queue.toList()) {
      if (!mounted) return;
      if (validStream(source)) continue;
      try {
        final stat = await File(source).stat();
        if (stat.type == FileSystemEntityType.file) {
          mediaSizes[source] = stat.size;
        }
      } catch (_) {/* Unavailable metadata remains unknown, sorted last. */}
    }
    if (mounted) setState(() {});
  }

  Future<void> displaySettings() async {
    unawaited(refreshMediaMetadata());
    await Navigator.push<void>(
        context,
        MaterialPageRoute(
            builder: (_) => DesktopDisplayScreen(
                listMode: listMode,
                groupByFolder: groupByFolder,
                onGroupByFolder: (value) async {
                  final prefs = await SharedPreferences.getInstance();
                  if (!await prefs.setBool(
                      'hyper.library.groupFolder.v1', value)) {
                    throw StateError('Folder grouping was not saved.');
                  }
                  if (mounted) setState(() => groupByFolder = value);
                },
                initialSort: librarySort,
                onlyFavourites: onlyFavourites,
                onOnlyFavourites: (value) async {
                  final prefs = await SharedPreferences.getInstance();
                  if (!await prefs.setBool(
                      'hyper.library.onlyFavourites.v1', value)) {
                    throw StateError('Favourite filter was not saved.');
                  }
                  if (mounted) setState(() => onlyFavourites = value);
                },
                queueAll: queueAll,
                onQueueAll: (value) async {
                  final prefs = await SharedPreferences.getInstance();
                  if (!await prefs.setBool(
                      'hyper.playback.queueAll.v1', value)) {
                    throw StateError('Playback action was not saved.');
                  }
                  if (mounted) setState(() => queueAll = value);
                },
                onChange: (value, order) async {
                  if (!mounted) {
                    return;
                  }
                  final prefs = await SharedPreferences.getInstance();
                  final saved = order == null
                      ? await prefs.setBool('hyper.list.mode.v1', value)
                      : await prefs.setString('hyper.library.sort.v1', order);
                  if (!saved) {
                    throw StateError('Display preference was not saved.');
                  }
                  if (!mounted) return;
                  setState(() {
                    listMode = value;
                    if (order != null) librarySort = order;
                  });
                })));
  }

  Future<void> generateAiSubtitles() async {
    if (selected < 0 || selected >= queue.length) {
      notify('Open a local video first.');
      return;
    }
    final source = queue[selected];
    final path = await Navigator.push<String>(context,
        MaterialPageRoute(builder: (_) => LocalAiScreen(source: source)));
    if (path != null && mounted && selected >= 0 && queue[selected] == source) {
      await player.setSubtitleTrack(SubtitleTrack.uri(path));
      notify('Generated subtitles loaded.');
    }
  }

  Future<void> homeMenu(String value) async {
    switch (value) {
      case 'Language':
        await Navigator.push<void>(
          context,
          MaterialPageRoute(builder: (_) => const LanguageScreen()),
        );
      case 'Display settings':
        await displaySettings();
      case 'User manual':
        await UserManualSheet.show(context);
        break;
      case 'About Hyper Player':
        await AboutSheet.show(context);
        break;
      case 'Privacy policy':
        showWindowsPrivacy(context);
        break;
      case 'Report a problem':
        await openDiscoverLink(
          context,
          Uri(
            scheme: 'mailto',
            path: 'techlabs.hyper@gmail.com',
            query:
                'subject=${Uri.encodeComponent("Hyper Player Windows — report & feedback")}',
          ),
        );
      case 'Follow on Instagram':
        await openDiscoverLink(
          context,
          Uri.parse('https://www.instagram.com/maxplayer_official/'),
        );
    }
  }

  Future<void> unavailable(String title) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: const LText(
          'This Android feature does not have a Windows implementation yet. This update adds the desktop layout and preserves local playback, folder import, streams and the session playlist.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const LText('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> showQueue() async {
    final choice = await showPlaybackSheet<int>(
        context,
        Builder(
            builder: (sheetContext) => SizedBox(
                height: MediaQuery.sizeOf(sheetContext).height * .7,
                child: Column(children: [
                  const PlaybackSheetHandle(),
                  Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(children: [
                        Expanded(
                            child: Text('Playback queue (${queue.length})',
                                style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700))),
                        TextButton(
                            onPressed: () {
                              Navigator.pop(sheetContext);
                              namedPlaylists();
                            },
                            child: const Text('All playlists'))
                      ])),
                  Expanded(
                      child: queue.isEmpty
                          ? const Center(
                              child: Text('Open files to create a queue.'))
                          : ListView.builder(
                              itemCount: queue.length,
                              itemBuilder: (context, i) => ListTile(
                                  selected: i == selected,
                                  leading: SizedBox(
                                      width: 80,
                                      height: 45,
                                      child: LocalThumbnail(queue[i])),
                                  title: Text(labelFor(queue[i]),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                  trailing: i == selected
                                      ? const Icon(Icons.equalizer_rounded)
                                      : null,
                                  onTap: () =>
                                      Navigator.pop(sheetContext, i)))),
                ]))));
    if (choice != null && mounted) await play(choice);
  }

  Widget quickTile(
    IconData icon,
    String label,
    VoidCallback onTap, {
    bool planned = false,
  }) =>
      Tooltip(
        message: planned ? '$label — Windows implementation pending' : label,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Ink(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.white.withValues(alpha: .11),
                    Colors.white.withValues(alpha: .04),
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: .14)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
              child: Row(
                children: [
                  Icon(icon, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: LText(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  if (planned)
                    const Icon(
                      Icons.construction_outlined,
                      size: 12,
                      color: Color(0xff9296a0),
                    ),
                ],
              ),
            ),
          ),
        ),
      );

  Widget brandTitle() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (bounds) => const LinearGradient(
              colors: [Color(0xffa78bfa), Color(0xff8b5cf6), Color(0xff22d3ee)],
            ).createShader(bounds),
            child: const LText(
              'Hyper Player',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
          const LText(
            'Proudly Developed in India 🇮🇳',
            style: TextStyle(
              fontSize: 9.5,
              color: Color(0xff9296a0),
              letterSpacing: .3,
            ),
          ),
        ],
      );

  Widget library() => LibraryLayouts(
        mode: AppDesign.instance.mode,
        androidLibrary: androidLibrary(
            workspace: AppDesign.instance.mode == AppDesignMode.compact),
        videos: visibleLibraryIndices(queue,
                onlyFavourites: onlyFavourites,
                favourites: collections.favourites,
                sort: librarySort,
                labelOf: labelFor,
                sizes: mediaSizes,
                lengths: mediaLengths)
            .where((i) => !isAudioPath(queue[i]))
            .map((i) => queue[i])
            .toList(),
        play: playSource,
        destinations: [
          LibraryDestination(
              'Discover',
              Icons.explore_outlined,
              () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => DiscoverScreen(
                          localSources: queue.toList(),
                          onPlayLocal: playSource)))),
          LibraryDestination('Open File', Icons.video_file_outlined, files),
          LibraryDestination('Folders', Icons.folder_outlined, browseFolders),
          LibraryDestination('Audio', Icons.music_note, browseAudio),
          LibraryDestination('Playlists', Icons.queue_music, namedPlaylists),
          LibraryDestination('Network', Icons.dns_outlined, browseNetwork),
          LibraryDestination('Cloud', Icons.cloud_outlined, browseCloud),
          LibraryDestination(
              'Display Settings', Icons.dashboard_customize, displaySettings),
          LibraryDestination(
              'Welcome guide',
              Icons.help_outline,
              () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const OnboardingFlow()))),
        ],
      );

  Widget androidLibrary({bool workspace = false}) => LayoutBuilder(
        builder: (context, size) {
          final visible = visibleLibraryIndices(queue,
                  onlyFavourites: onlyFavourites,
                  favourites: collections.favourites,
                  sort: librarySort,
                  labelOf: labelFor,
                  sizes: mediaSizes,
                  lengths: mediaLengths)
              .where((index) => !isAudioPath(queue[index]))
              .toList();
          final groups =
              groupLibraryIndices(queue, visible, byFolder: groupByFolder);
          final columns = size.maxWidth >= 1300
              ? 8
              : size.maxWidth >= 700
                  ? 4
                  : 2;
          final tiles = <Widget>[
            quickTile(
              Icons.lock_outline_rounded,
              'Private Space',
              browsePrivateSpace,
            ),
            quickTile(Icons.queue_music_outlined, 'Playlists', namedPlaylists),
            quickTile(Icons.folder_outlined, 'Folders', browseFolders),
            quickTile(Icons.music_note_outlined, 'Audio', browseAudio),
            quickTile(
              Icons.dns_outlined,
              'Network Storage',
              browseNetwork,
            ),
            quickTile(
              Icons.cloud_queue_outlined,
              'Cloud Storage',
              browseCloud,
            ),
            quickTile(Icons.link, 'Open Stream(iptv)', stream),
            quickTile(
              Icons.ios_share,
              'Quick Share',
              browseQuickShare,
            ),
          ];
          return CustomScrollView(
            slivers: [
              if (!workspace)
                SliverToBoxAdapter(
                    child: Padding(
                        padding: const EdgeInsets.fromLTRB(6, 12, 6, 0),
                        child: DiscoverHomeBanner(
                            localSources: {
                              ...queue,
                              ...collections.history,
                              ...collections.favourites,
                              ...collections.playlists.values
                                  .expand((items) => items)
                            }.toList(),
                            onPlayLocal: (source) {
                              Navigator.of(context)
                                  .popUntil((route) => route.isFirst);
                              playSource(source);
                            }))),
              SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    const SizedBox(height: 12),
                    for (var start = 0;
                        !workspace && start < tiles.length;
                        start += columns) ...[
                      Row(
                        children: [
                          for (var j = 0; j < columns; j++) ...[
                            if (j > 0) const SizedBox(width: 8),
                            Expanded(child: tiles[start + j]),
                          ],
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Text(
                          '${onlyFavourites ? 'Favourites' : 'Media'} · ${visible.length}',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          tooltip: 'Switch grid/list',
                          onPressed: toggleLibraryLayout,
                          icon: Icon(
                              listMode ? Icons.grid_view : Icons.view_list),
                        ),
                      ],
                    ),
                    if (visible.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 90),
                        child: Center(
                          child: Column(
                            children: [
                              const Icon(
                                Icons.video_library_outlined,
                                color: Color(0xff9296a0),
                                size: 46,
                              ),
                              const SizedBox(height: 15),
                              LText(
                                onlyFavourites
                                    ? 'No favourites in this library. Change the filter in Display Settings.'
                                    : 'No media yet. Open files or a folder to begin.',
                                style: TextStyle(color: Color(0xff9296a0)),
                              ),
                              const SizedBox(height: 16),
                              FilledButton(
                                onPressed: files,
                                child: const LText('Open files'),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ]),
                ),
              ),
              for (final group in groups) ...[
                if (groupByFolder)
                  SliverToBoxAdapter(
                      child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                    child: Text('${group.label} · ${group.indices.length}',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  )),
                if (listMode)
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, i) => ListTile(
                        leading: SizedBox(
                            width: 96,
                            height: 54,
                            child: LocalThumbnail(queue[group.indices[i]])),
                        title: Text(labelFor(queue[group.indices[i]])),
                        subtitle: Text(
                          validStream(queue[group.indices[i]])
                              ? 'Network stream'
                              : 'Local media',
                        ),
                        onTap: () => play(group.indices[i]),
                      ),
                      childCount: group.indices.length,
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    sliver: SliverGrid(
                      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: AppDesign.instance.mediaExtent,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: 1.55,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, i) => Material(
                          color: const Color(0xff101013),
                          borderRadius: BorderRadius.circular(16),
                          child: InkWell(
                            onTap: () => play(group.indices[i]),
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              decoration: BoxDecoration(
                                border:
                                    Border.all(color: const Color(0xff26262c)),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              padding: const EdgeInsets.all(15),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                      child: SizedBox(
                                          width: double.infinity,
                                          child: LocalThumbnail(
                                              queue[group.indices[i]]))),
                                  const SizedBox(height: 5),
                                  Text(
                                    validStream(queue[group.indices[i]])
                                        ? 'Network stream'
                                        : 'Local media',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Color(0xff9296a0),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        childCount: group.indices.length,
                      ),
                    ),
                  ),
              ],
            ],
          );
        },
      );

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyO, control: true): files,
          const SingleActivator(LogicalKeyboardKey.keyL, control: true): stream,
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            appBar: viewingPlayer
                ? null
                : AppBar(
                    toolbarHeight: 76,
                    title: brandTitle(),
                    actions: [
                      IconButton(
                        tooltip: 'Search media',
                        onPressed: searchMedia,
                        icon: const Icon(Icons.search),
                      ),
                      IconButton(
                        tooltip: 'Open File (Ctrl+O)',
                        onPressed: files,
                        icon: const Icon(Icons.video_file_outlined),
                      ),
                      if (viewingPlayer)
                        IconButton(
                          tooltip: 'Back to library (playback continues)',
                          onPressed: () =>
                              setState(() => viewingPlayer = false),
                          icon: const Icon(Icons.home_outlined),
                        ),
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
                          } else if (value == 'Audio track') {
                            trackPicker(subtitle: false);
                          } else if (value == 'Subtitles') {
                            trackPicker(subtitle: true);
                          } else if (value == 'Load subtitle file') {
                            externalSubtitles();
                          } else if (value == 'AI subtitles') {
                            generateAiSubtitles();
                          } else if (value == 'Playback speed') {
                            playbackOptions();
                          } else if (value == 'Watch statistics') {
                            watchStatistics();
                          } else if (value == 'Sleep timer') {
                            sleepTimer();
                          } else if (value == 'Video info') {
                            videoInfo();
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
                            'Follow on Instagram',
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
                            'User manual': Icons.menu_book_outlined,
                            'About Hyper Player': Icons.info_outline_rounded,
                            'Privacy policy': Icons.privacy_tip_outlined,
                            'Report a problem': Icons.flag_outlined,
                            'Follow on Instagram': Icons.camera_alt_outlined,
                          }.entries)
                            PopupMenuItem(
                              value: entry.key,
                              child: Row(
                                children: [
                                  Icon(entry.value, size: 20),
                                  const SizedBox(width: 12),
                                  LText(entry.key),
                                ],
                              ),
                            ),
                          if (viewingPlayer) const PopupMenuDivider(),
                          if (viewingPlayer)
                            for (final name in [
                              'Sleep timer',
                              'Video info',
                              'A–B repeat',
                              'Video fit',
                              'Subtitle delay',
                              'Favourites',
                              'Toggle favourite',
                              'Named playlists',
                              'Import IPTV playlist',
                              'Audio track',
                              'Subtitles',
                              'Load subtitle file',
                              'Playback speed',
                              'AI subtitles',
                              'Open folder',
                              'Clear queue',
                            ])
                              PopupMenuItem(value: name, child: LText(name)),
                          const PopupMenuDivider(),
                          const PopupMenuItem<String>(
                            enabled: false,
                            child: LText(
                              'Windows preview 0.2.0',
                              style:
                                  TextStyle(fontSize: 11, color: Colors.grey),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 12),
                    ],
                  ),
            body: Column(
              children: [
                if (busy) ...[
                  const LinearProgressIndicator(),
                  Row(children: [
                    const SizedBox(width: 16),
                    Expanded(
                        child: Text(
                            'Scanning: $scanFilesSeen media · $scanDirectoriesSeen folders${scanCancelled ? ' · stopping…' : ''}')),
                    TextButton(
                        onPressed: scanCancelled
                            ? null
                            : () => setState(() => scanCancelled = true),
                        child: const Text('Cancel scan'))
                  ]),
                ],
                Expanded(
                  child: viewingPlayer ? buildVideoPlayer() : library(),
                ),
                if (!viewingPlayer && selected >= 0 && selected < queue.length)
                  Material(
                    color: const Color(0xff101013),
                    child: ValueListenableBuilder<PlaybackSnapshot>(
                        valueListenable: playbackView,
                        builder: (context, state, _) => ListTile(
                              leading: SizedBox(
                                  width: 72,
                                  height: 48,
                                  child: LocalThumbnail(queue[selected])),
                              onTap: () => setState(() => viewingPlayer = true),
                              title: Text(
                                labelFor(queue[selected]),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                        tooltip:
                                            state.playing ? 'Pause' : 'Play',
                                        onPressed: () async {
                                          if (player.state.completed) {
                                            await player.seek(Duration.zero);
                                            await player.play();
                                          } else {
                                            await player.playOrPause();
                                          }
                                        },
                                        icon: Icon(state.playing
                                            ? Icons.pause
                                            : Icons.play_arrow)),
                                    TextButton(
                                        onPressed: () => setState(
                                            () => viewingPlayer = true),
                                        child: const LText('Open player')),
                                  ]),
                            )),
                  ),
                if (!viewingPlayer)
                  const Padding(
                    padding: EdgeInsets.all(6),
                    child: LText(
                      'Windows preview · Scan accessible local drives from Folders · AI tools download separately',
                      style: TextStyle(fontSize: 10, color: Color(0xff9296a0)),
                    ),
                  ),
              ],
            ),
          ),
        ),
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
