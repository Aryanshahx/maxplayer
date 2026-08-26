import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:media_kit/media_kit.dart' hide VideoTrack;
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;

import '../models/history_entry.dart';
import '../models/video_track.dart';
import '../services/native_bridge.dart';
import '../utils/formatters.dart';
import '../utils/srt.dart';
import 'player_settings.dart';

/// v30: merge picked videos into the play queue, skipping entries whose id
/// is already queued. Pure so the playlist "+" logic is unit-testable.
List<VideoTrack> mergeQueueVideos(
  List<VideoTrack> queue,
  List<VideoTrack> added,
) {
  final out = [...queue];
  final have = queue.map((v) => v.id).toSet();
  for (final v in added) {
    if (have.add(v.id)) out.add(v);
  }
  return out;
}

/// Mirrors the web app's useMediaPlayer hook, backed by media_kit's Player.
class MediaPlayerState extends ChangeNotifier {
  final Player player = Player();

  /// ONE video controller for the app's lifetime, created lazily.
  /// PlayerScreen used to construct a new VideoController on every visit and
  /// (with media_kit_video 1.3.x having no public dispose) those stacked up
  /// on the same player - one source of the fullscreen glitches.
  late final VideoController videoController = VideoController(player);

  List<VideoTrack> playlist = [];
  int currentIndex = 0;
  bool isPlaying = false;
  Duration position = Duration.zero;
  Duration duration = Duration.zero;
  double volume = 0.75; // 0..1
  bool isMuted = false;
  double playbackRate = 1.0;
  RepeatMode repeatMode = RepeatMode.none;
  bool isShuffled = false;
  bool isLoading = false;
  List<int> _shuffledOrder = [];

  // Available tracks of the currently loaded media (populated from streams).
  List<AudioTrack> audioTracks = [];
  List<SubtitleTrack> subtitleTracks = [];
  AudioTrack? currentAudioTrack;
  SubtitleTrack? currentSubtitleTrack;

  /// Short user-facing notices ("Resumed 12:34" etc) - the player screen
  /// shows these as a transient overlay indicator.
  final _notices = StreamController<String>.broadcast();
  Stream<String> get notices => _notices.stream;

  /// Periodic bookmark saver ("resume from where you left off").
  Timer? _bookmarkTimer;

  /// Last-used app-local brightness (left-half swipe in the player).
  double brightness = 1.0;
  bool _brightnessSynced = false;

  // --- A-B loop ---
  Duration? loopA;
  Duration? loopB;
  bool get abLoopActive => loopA != null && loopB != null;

  // --- Long-press speed boost ---
  double? _preBoostRate;

  /// True while the long-press speed boost is engaged; the player shows a
  /// persistent "Nx" badge for the whole boost, not just a flash.
  bool get isSpeedBoosting => _preBoostRate != null;

  // --- Equalizer (libmpv lavfi filter chain) ---
  static const List<int> eqFrequencies = [60, 230, 910, 3600, 14000];
  List<double> eqGains = List.filled(eqFrequencies.length, 0);
  bool eqEnabled = false;

  // --- Watch-time stats ---
  int _watchTodaySecs = 0;
  String _todayStatsKey = '';

  /// v27: cumulative watch seconds PER VIDEO (path -> seconds), powering
  /// the Statistics screen's "Most watched" list. Persisted as one small
  /// JSON map, capped at the 60 heaviest entries so it never grows wild.
  Map<String, int> _watchByVideo = const {};
  static const String _kWatchByVideoKey = 'stats.video';
  static const int _kWatchByVideoMax = 60;

  // --- Watch history (drives the home History screen + resume playback) ---
  final List<HistoryEntry> _history = [];
  bool _historyLoaded = false;
  static const String _kHistoryKey = 'history';
  static const int _kHistoryMax = 150;

  List<HistoryEntry> get history => List.unmodifiable(_history);

  VideoTrack? get currentTrack =>
      playlist.isNotEmpty && currentIndex < playlist.length
      ? playlist[currentIndex]
      : null;

  final _rand = Random();
  Timer? _uiTicker;
  late final List<StreamSubscription> _subs;

  MediaPlayerState() {
    // v51: cap mpv's demuxer cache once. Without explicit values some
    // builds fall back to mpv's desktop-oriented defaults, which wastes
    // RAM on 3-4 GB phones for zero benefit on a handset screen.
    final capPlat = player.platform;
    if (capPlat is NativePlayer) {
      for (final e in kMpvCacheCapProps.entries) {
        unawaited(capPlat.setProperty(e.key, e.value));
      }
    }
    _subs = [
      player.stream.playing.listen((v) {
        isPlaying = v;
        notifyListeners();
        // Keep the PiP window's play/pause remote action in sync
        // (native side ignores this when not in PiP).
        NativeBridge.setPipPlaying(v);
        _syncNowPlaying();
      }),
      player.stream.position.listen((v) {
        position = v;
        // Enforce the A-B loop window.
        final a = loopA;
        final b = loopB;
        if (a != null && b != null && b > a && v >= b) {
          player.seek(a);
        }
        _checkSleepAtEnd(v); // "sleep at end of video" timer
        _maybeAutoSkipCredits(v); // v65 smart skip
        _maybeCaptureThumb(v); // 4K/HDR thumbnail fallback (v22)
        notifyListeners();
      }),
      player.stream.duration.listen((v) {
        duration = v;
        notifyListeners();
        // v65: credits detection needs the real duration; subtitles may
        // have attached before the demuxer reported it, so recompute now.
        _recomputeSkipIntro();
        // Kick off scrub-preview thumbnail generation (idempotent - runs
        // once per file, cached on disk afterwards).
        _ensureThumbStrip();
        _syncNowPlaying();
      }),
      player.stream.buffering.listen((v) {
        isLoading = v;
        notifyListeners();
      }),
      player.stream.completed.listen((completed) {
        if (completed) _handleEnded();
      }),
      // Repopulates whenever a new media is opened.
      player.stream.tracks.listen((t) {
        audioTracks = t.audio;
        subtitleTracks = t.subtitle;
        notifyListeners();
      }),
      player.stream.track.listen((t) {
        currentAudioTrack = t.audio;
        currentSubtitleTrack = t.subtitle;
        // Karaoke mode: switching to a real subtitle track flips the
        // overlay on (and mpv's own rendering off) immediately.
        if (karaokeMode) unawaited(_applySubVisibility());
        notifyListeners();
      }),
      // v60 (old-phone pack): any decode/render failure phones home here.
      player.stream.error.listen(_onPlaybackError),
    ];
    // libmpv stays at 100%: loudness is driven by the DEVICE media volume
    // (MX Player / VLC style) so the swipe can always reach the phone's
    // true maximum, no matter where the system volume started.
    player.setVolume(100);
    // Play/pause from the picture-in-picture window's own button.
    NativeBridge.configureCallbacks(onPipAction: togglePlay);
    _init();
    // Persist the resume point + watch time every few seconds.
    _bookmarkTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _saveBookmark();
      _trackWatchTime();
    });
    // v19: guaranteed UI pulse - the mini player / scrub bar / time labels
    // keep ticking even if the position stream coalesces (the home-screen
    // mini player's progress bar looked frozen because of that).
    _uiTicker = Timer.periodic(const Duration(milliseconds: 500), (_) {
      // v22: also pulse while a sleep timer runs so the under-title
      // countdown keeps counting even when playback is paused.
      if (!isPlaying && !sleepTimerActive) return;
      final p = player.state.position;
      if (p != position || sleepTimerActive) {
        position = p;
        _maybeCaptureThumb(p);
        notifyListeners();
      }
    });
    _startLiveSubObserver();
  }

  Future<void> _init() async {
    await _ensureHistoryLoaded();
    final s = await NativeBridge.loadSettings();
    // Restore today's accumulated watch time (+ the v27 per-video totals).
    _todayStatsKey = statsKeyFor(DateTime.now());
    _watchTodaySecs = int.tryParse(s[_todayStatsKey] ?? '') ?? 0;
    try {
      final raw = s[_kWatchByVideoKey] ?? '';
      if (raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          _watchByVideo = {
            for (final e in decoded.entries)
              if (e.value is num) '${e.key}': (e.value as num).toInt(),
          };
        }
      }
    } catch (_) {
      _watchByVideo = const {}; // corrupt payload -> start fresh
    }
    // Restore equalizer.
    eqEnabled = s[_kEqEnabledKey] == 'true';
    final gainsRaw = (s[_kEqGainsKey] ?? '').split(',');
    for (var i = 0; i < eqFrequencies.length && i < gainsRaw.length; i++) {
      eqGains[i] = double.tryParse(gainsRaw[i]) ?? 0;
    }
    if (eqEnabled) _applyEqFilter();
  }

  // ---------------------------------------------------------------------------
  // Watch history
  // ---------------------------------------------------------------------------

  Future<void> _ensureHistoryLoaded() async {
    if (_historyLoaded) return;
    _historyLoaded = true;
    try {
      final s = await NativeBridge.loadSettings();
      final raw = s[_kHistoryKey];
      if (raw == null || raw.isEmpty) return;
      final list = jsonDecode(raw) as List<dynamic>;
      _history
        ..clear()
        ..addAll([
          for (final e in list)
            HistoryEntry.fromJson(Map<String, dynamic>.from(e as Map)),
        ]);
      notifyListeners();
    } catch (_) {
      // Corrupt payload -> start with an empty history.
    }
  }

  void _persistHistory() {
    final capped = _history.length > _kHistoryMax
        ? _history.sublist(0, _kHistoryMax)
        : _history;
    NativeBridge.saveSetting(
      _kHistoryKey,
      jsonEncode([for (final e in capped) e.toJson()]),
    );
  }

  HistoryEntry? _historyEntryFor(String path) {
    for (final e in _history) {
      if (e.path == path) return e;
    }
    return null;
  }

  /// Move the just-opened video to the top of the history, preserving its
  /// previous resume position.
  Future<void> _recordOpen(VideoTrack track) async {
    try {
      await _ensureHistoryLoaded();
      final prevPos = _historyEntryFor(track.path)?.lastPositionSecs ?? 0;
      _history.removeWhere((e) => e.path == track.path);
      _history.insert(
        0,
        HistoryEntry(
          path: track.path,
          title: track.title,
          thumbnailPath: track.thumbnailPath,
          durationSecs: track.duration?.inSeconds ?? 0,
          lastPositionSecs: prevPos,
          playedAtMs: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      _persistHistory();
      notifyListeners();
    } catch (_) {}
  }

  void clearHistory() {
    _history.clear();
    _persistHistory();
    notifyListeners();
  }

  void removeHistoryEntry(String path) {
    _history.removeWhere((e) => e.path == path);
    _persistHistory();
    notifyListeners();
  }

  /// Play a single video straight from a history row.
  Future<void> playHistoryEntry(HistoryEntry entry) async {
    final track = VideoTrack(
      id: entry.path,
      title: entry.title,
      path: entry.path,
      thumbnailPath: entry.thumbnailPath,
      duration: entry.durationSecs > 0
          ? Duration(seconds: entry.durationSecs)
          : null,
    );
    await setPlaylistAndPlay([track], 0);
  }

  /// Play a network stream URL (http/https/rtsp/rtmp). Handled directly by
  /// libmpv - the local-file metadata pipeline is skipped upstream.
  Future<void> playStream(String url, String title) async {
    final track = VideoTrack(id: url, title: title, path: url);
    await setPlaylistAndPlay([track], 0);
  }

  List<int> _generateShuffledOrder(int length, int currentIdx) {
    final indices = List.generate(length, (i) => i)..remove(currentIdx);
    indices.shuffle(_rand);
    return [currentIdx, ...indices];
  }

  int _getNextIndex({required bool forward}) {
    if (playlist.isEmpty) return 0;
    if (isShuffled && _shuffledOrder.isNotEmpty) {
      final pos = _shuffledOrder.indexOf(currentIndex);
      final len = _shuffledOrder.length;
      return forward
          ? _shuffledOrder[(pos + 1) % len]
          : _shuffledOrder[(pos - 1 + len) % len];
    }
    final len = playlist.length;
    return forward ? (currentIndex + 1) % len : (currentIndex - 1 + len) % len;
  }

  /// Replace the whole queue and start playing at [startIndex].
  Future<void> setPlaylistAndPlay(
    List<VideoTrack> videos, [
    int startIndex = 0,
  ]) async {
    playlist = videos;
    currentIndex = startIndex.clamp(0, videos.isEmpty ? 0 : videos.length - 1);
    notifyListeners();
    await _loadCurrent(autoplay: true);
  }

  /// v30: "+" in the playlist sheet - appends the picked videos to the
  /// current queue without changing what is playing. Duplicates are
  /// skipped. The player keeps showing only the playlist: previous/next
  /// never leave these entries.
  void addToPlaylist(List<VideoTrack> videos) {
    final merged = mergeQueueVideos(playlist, videos);
    if (merged.length == playlist.length) return;
    playlist = merged;
    // The shuffle order is keyed to queue positions - rebuild it so the
    // new entries become reachable in shuffle mode too.
    if (isShuffled) {
      _shuffledOrder = _generateShuffledOrder(playlist.length, currentIndex);
    }
    notifyListeners();
  }

  Future<void> playTrack(int index) async {
    if (index < 0 || index >= playlist.length) return;
    currentIndex = index;
    notifyListeners();
    await _loadCurrent(autoplay: true);
  }

  /// v60 (old-phone pack): path of the file that already FAILED once on
  /// the hardware decoder and was moved to software. Reset per new file
  /// by usage in _loadCurrent; the audio-only fallback insight: many
  /// cheap SoCs (buggy HEVC) just can not do hardware decode.
  String? _hwFallbackForPath;

  /// Fires on mpv decode/render errors. Cheap-SoC hardware decoders
  /// (H.265 especially) die here - so we flip the SAME file to SOFTWARE
  /// decoding once and continue right where playback stopped, instead
  /// of the dead black screen users reported.
  void _onPlaybackError(Object e) {
    final track = currentTrack;
    if (track == null) return;
    if (_hwFallbackForPath == track.path) return; // already retried once
    _hwFallbackForPath = track.path;
    final plat = player.platform;
    if (plat is NativePlayer) {
      unawaited(plat.setProperty('hwdec', 'no')); // software from now on
    }
    final resume = player.state.position;
    unawaited(player.open(Media(track.path), play: true).then((_) {
      if (resume > Duration.zero && resume < player.state.duration) {
        player.seek(resume);
      }
    }).catchError((_) {}));
    notifyListeners();
  }

  Future<void> _loadCurrent({required bool autoplay}) async {
    final track = currentTrack;
    if (track == null) return;
    // A new file invalidates any A-B loop points from the previous one.
    loopA = null;
    loopB = null;
    final plat = player.platform;
    if (plat is NativePlayer) {
      // v60: this exact file failed on the hardware decoder before ->
      // start it in SOFTWARE straight away.
      if (_hwFallbackForPath == track.path) {
        unawaited(plat.setProperty('hwdec', 'no'));
      }
      // Head-room for the 200% volume boost + re-apply the current gain /
      // leveling filter for the new file.
      unawaited(plat.setProperty('volume-max', '200'));
      // v38: keep the Enhance pipeline asserted for every new file.
      if (_enhanceApplied && _enhanceShaderPath != null) {
        unawaited(plat.setProperty('glsl-shaders', _enhanceShaderPath!));
        unawaited(plat.setProperty('hwdec', MediaPlayerState.kEnhanceHwdec));
      }
      // Force the sub-visibility to be re-pushed for the new file (mpv may
      // reset it at open, while our cache would think it's still applied).
      _appliedSubVisibility = null;
    }
    await player.open(Media(track.path), play: autoplay);
    await player.setRate(playbackRate);
    await _applyMpvVolume();
    await _applyAudioFilters(); // equalizer + leveling survive file changes
    await _attachSidecarSubtitles(track.path);
    await _recordOpen(track);
    await _restoreBookmark(track);
    // v25: re-verify karaoke's subtitle hiding after the demuxer settles -
    // the track listener can fire before the subtitle selection is known.
    if (karaokeMode) {
      Future<void>.delayed(const Duration(milliseconds: 800), () {
        _appliedSubVisibility = null; // force a fresh push (engine may reset)
        _applySubVisibility();
      });
    }
    // v22: if this file has no cached thumbnail AND Android's metadata
    // engine could not make one, remember it - after ~1.5 s of playback a
    // frame is captured through mpv instead (see _maybeCaptureThumb).
    _pendingThumbFor =
        (track.thumbnailPath == null && !track.path.contains('://'))
        ? track.path
        : null;
  }

  /// Re-attaches previously generated AI subtitles ("<video>.maxai.srt"
  /// next to the video) so they survive closing/reopening the app - they
  /// are written to disk, only the player session forgot them.
  /// v21: cues of the AI sidecar currently attached (null when none or the
  /// file is a stream). Feeds the karaoke word-highlight overlay.
  List<SrtCue>? aiCues;

  /// v22: cues parsed from the video's OWN same-name subtitle file
  /// ("movie.srt", "movie.en.srt" - the files mpv auto-loads). Used when
  /// there is no AI sidecar, so karaoke + skip-intro work on ordinary
  /// subtitled videos too.
  List<SrtCue>? sidecarCues;

  /// v21/v65 smart skip: where the dialogue actually starts (intro) and
  /// where the end-credits roll begins, when subtitles (AI sidecar or
  /// same-name .srt) let us detect them. Both are auto-skippable with an
  /// on-screen "Undo" chip; there is no longer a settings toggle for this.
  Duration? skipIntroAt;
  Duration? skipCreditsAt;

  /// True once the current video's credits have already been auto-skipped,
  /// so the position stream doesn't fire the skip repeatedly.
  bool _didSkipCredits = false;

  Future<void> _attachSidecarSubtitles(String videoPath) async {
    aiCues = null;
    sidecarCues = null;
    skipIntroAt = null;
    skipCreditsAt = null;
    _didSkipCredits = false;
    liveSubCue = null;
    if (videoPath.contains('://')) return; // no sidecars for streams
    final platform = player.platform;
    if (platform is! NativePlayer) return;
    try {
      final srt = srtPathForVideo(videoPath);
      if (File(srt).existsSync()) {
        // "select" makes it the active track right away.
        await platform.command(['sub-add', srt, 'select']);
        await refreshAiCues(videoPath);
      }
    } catch (_) {
      // Missing/unreadable sidecar is not fatal.
    }
    // v22: no AI captions -> look for the video's own subtitle file and
    // use it as the skip-intro + karaoke source instead.
    if (aiCues == null) {
      try {
        final cues = await _loadSidecarCues(videoPath);
        if (cues != null && cues.isNotEmpty) sidecarCues = cues;
      } catch (_) {
        // An unreadable sibling file must never break playback.
      }
    }
    _recomputeSkipIntro();
    await _applySubVisibility();
    notifyListeners();
  }

  /// Parses the best same-name .srt sitting next to [videoPath], if any.
  Future<List<SrtCue>?> _loadSidecarCues(String videoPath) async {
    final dir = Directory(p.dirname(videoPath));
    if (!dir.existsSync()) return null;
    final names = <String>[];
    await for (final e in dir.list(followLinks: false)) {
      if (e is File) names.add(p.basename(e.path));
    }
    final candidates = sidecarSrtCandidates(names, videoPath);
    if (candidates.isEmpty) return null;
    final cues = parseSrt(
      await File(p.join(dir.path, candidates.first)).readAsString(),
    );
    return cues.isEmpty ? null : cues;
  }

  void _recomputeSkipIntro() {
    // AI captions win (word-accurate); same-name .srt is the fallback.
    final cues = aiCues ?? sidecarCues;
    skipIntroAt = cues == null ? null : computeSkipIntro(cues);
    skipCreditsAt = cues == null
        ? null
        : computeSkipCredits(cues, durationMs: duration.inMilliseconds);
  }

  /// (Re)parses the AI sidecar for karaoke + skip-intro. Called when a track
  /// attaches its sidecar, and by the AI runner right after it finishes
  /// writing new subtitles.
  Future<void> refreshAiCues(String videoPath) async {
    aiCues = null;
    if (videoPath.contains('://')) return;
    try {
      final srt = File(srtPathForVideo(videoPath));
      if (!srt.existsSync()) return;
      final cues = parseSrt(await srt.readAsString());
      if (cues.isEmpty) return;
      aiCues = cues;
    } catch (_) {
      // A corrupt sidecar must never break playback.
    }
    _recomputeSkipIntro();
    await _applySubVisibility();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Karaoke mode + live subtitle reading (v22)
  // ---------------------------------------------------------------------------

  /// Whether karaoke rendering is enabled (mirrors the player setting).
  bool karaokeMode = false;

  /// The subtitle line mpv is showing RIGHT NOW (from its `sub-text` /
  /// `sub-start` / `sub-end` properties), with real cue timing. This makes
  /// karaoke work with ANY subtitle - embedded mkv tracks included - not
  /// just ones we can parse as files.
  SrtCue? liveSubCue;

  /// Last sub-visibility value we pushed to mpv (avoids redundant sets).
  String? _appliedSubVisibility;

  Future<void> _startLiveSubObserver() async {
    final platform = player.platform;
    if (platform is! NativePlayer) return;
    try {
      await platform.observeProperty('sub-text', (text) async {
        final plat = player.platform;
        if (text.trim().isEmpty || plat is! NativePlayer) {
          if (liveSubCue != null) {
            liveSubCue = null;
            notifyListeners();
          }
          return;
        }
        var startMs = 0;
        var endMs = 0;
        try {
          startMs =
              ((double.tryParse(await plat.getProperty('sub-start')) ?? 0) *
                      1000)
                  .round();
          endMs =
              ((double.tryParse(await plat.getProperty('sub-end')) ?? 0) * 1000)
                  .round();
        } catch (_) {}
        if (endMs <= startMs) endMs = startMs + 2000; // sane fallback
        final clean = text.replaceAll(RegExp(r'\s+'), ' ').trim();
        liveSubCue = isMusicOnlyText(clean)
            ? null
            : SrtCue(startMs, endMs, clean);
        notifyListeners();
      });
    } catch (_) {
      // Older engine - karaoke simply falls back to parsed cue files.
    }
  }

  /// Player-settings-driven: turn karaoke mode on/off. Hides mpv's own
  /// subtitle rendering (our overlay takes over) whenever a usable
  /// subtitle source exists.
  Future<void> setKaraokeMode(bool on) async {
    karaokeMode = on;
    await _applySubVisibility();
  }

  Future<void> _applySubVisibility() async {
    final platform = player.platform;
    if (platform is! NativePlayer) return;
    final hide =
        karaokeMode &&
        (subtitlesActive || aiCues != null || sidecarCues != null);
    final want = hide ? 'no' : 'yes';
    if (want == _appliedSubVisibility) return;
    _appliedSubVisibility = want;
    // v25 hardening (user report: the normal subtitle line stayed visible
    // next to karaoke): verify the property actually flipped; on engines
    // where setProperty silently no-ops, issue the raw mpv command too.
    try {
      await platform.setProperty('sub-visibility', want);
      final applied = await platform.getProperty('sub-visibility');
      if (applied != want) {
        await platform.command(['set', 'sub-visibility', want]);
      }
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // 4K/HDR thumbnail fallback (v22)
  //
  // Android's MediaMetadataRetriever gives up on some 4K/HDR (10-bit HEVC,
  // certain mkv) files, so their library tiles stayed placeholder-grey.
  // mpv plays those same files fine - so once such a video has been playing
  // for ~1.5 s we ask mpv for a frame and write it to the exact cache file
  // the native scanner uses, then shrink it to the standard 320px width.
  // ---------------------------------------------------------------------------

  /// Video awaiting a playback-captured thumbnail.
  String? _pendingThumbFor;

  /// Wired by main.dart: (videoPath, thumbPath) -> live-updates the
  /// library tile so the image appears without a rescan.
  void Function(String videoPath, String thumbPath)? onThumbnailCaptured;

  void _maybeCaptureThumb(Duration pos) {
    final path = _pendingThumbFor;
    if (path == null || pos < const Duration(milliseconds: 1500)) return;
    _pendingThumbFor = null;
    unawaited(_captureThumbWithMpv(path));
  }

  Future<void> _captureThumbWithMpv(String videoPath) async {
    try {
      final platform = player.platform;
      if (platform is! NativePlayer) return;
      final target = await NativeBridge.thumbnailPathFor(videoPath);
      if (target == null) return;
      final thumb = File(target);
      if (thumb.existsSync()) return; // scanner beat us to it meanwhile
      final tmp = File('$target.capture');
      if (tmp.existsSync()) await tmp.delete();
      await platform.setProperty('screenshot-format', 'jpg');
      await platform.setProperty('screenshot-jpeg-quality', '82');
      await platform.command(['screenshot-to-file', tmp.path, 'video']);
      // mpv encodes the shot asynchronously - wait briefly for the file.
      for (var i = 0; i < 25; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        if (tmp.existsSync() && tmp.lengthSync() > 0) break;
      }
      if (!tmp.existsSync() || tmp.lengthSync() == 0) return;
      // A 4K screenshot decodes to a ~33 MB bitmap; shrink to the same
      // 320px width the native scanner writes, so scrolling the library
      // never decodes a giant image.
      final data = await tmp.readAsBytes();
      final codec = await ui.instantiateImageCodec(data, targetWidth: 320);
      final frame = await codec.getNextFrame();
      final png = await frame.image.toByteData(format: ui.ImageByteFormat.png);
      frame.image.dispose();
      codec.dispose();
      if (png == null) return;
      await thumb.writeAsBytes(png.buffer.asUint8List(), flush: true);
      await tmp.delete();
      onThumbnailCaptured?.call(videoPath, target);
    } catch (_) {
      // Worst case: the tile keeps its movie-icon placeholder.
    }
  }

  // ---------------------------------------------------------------------------
  // Sleep timer (v21)
  // ---------------------------------------------------------------------------

  Timer? _sleepTimer;
  DateTime? _sleepFireAt;
  bool _sleepAtEndOfVideo = false;

  bool get sleepTimerActive => _sleepFireAt != null || _sleepAtEndOfVideo;

  /// Short label for menus ("12 min" / "end of video"); null when inactive.
  String? get sleepTimerLabel {
    if (_sleepAtEndOfVideo) return 'end of video';
    final at = _sleepFireAt;
    if (at == null) return null;
    final left = at.difference(DateTime.now()).inSeconds;
    if (left <= 0) return null;
    return '${(left + 30) ~/ 60} min'; // rounded while counting down
  }

  /// v22: precise live countdown for the player top bar ("23:41" or
  /// "end of video"); null when no timer runs. The state pulses every
  /// 500 ms while a timer is active, so this ticks visibly.
  String? get sleepTimerCountdown {
    if (_sleepAtEndOfVideo) return 'end of video';
    final at = _sleepFireAt;
    if (at == null) return null;
    final left = at.difference(DateTime.now());
    return left.inSeconds <= 0 ? null : formatCountdown(left.inSeconds);
  }

  void setSleepTimer({Duration? forDuration, bool atEndOfVideo = false}) {
    cancelSleepTimer();
    if (atEndOfVideo) {
      _sleepAtEndOfVideo = true;
    } else if (forDuration != null) {
      _sleepFireAt = DateTime.now().add(forDuration);
      _sleepTimer = Timer(forDuration, _fireSleepTimer);
    }
    notifyListeners();
  }

  void cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepFireAt = null;
    _sleepAtEndOfVideo = false;
    notifyListeners();
  }

  Future<void> _fireSleepTimer() async {
    cancelSleepTimer();
    _notices.add('Sleep timer paused playback');
    await pause();
  }

  void _checkSleepAtEnd(Duration pos) {
    if (!_sleepAtEndOfVideo || duration <= Duration.zero) return;
    if (duration - pos <= const Duration(milliseconds: 1500)) {
      cancelSleepTimer();
      _notices.add('Sleep timer: stopped at end of video');
      pause();
    }
  }

  /// Jump to where the user left off last time this file was open. The saved
  /// position lives in the watch history; honours the "Resume playback"
  /// player setting.
  Future<void> _restoreBookmark(VideoTrack track) async {
    try {
      final settings = await NativeBridge.loadSettings();
      if (settings[PlayerSettings.kResumePlayback] == 'false') return;
      final secs = _historyEntryFor(track.path)?.lastPositionSecs ?? 0;
      if (secs < 10) return; // ignore tiny offsets

      var d = duration;
      if (d == Duration.zero) {
        // Wait briefly for the demuxer to report the length.
        d = await player.stream.duration
            .firstWhere((v) => v > Duration.zero)
            .timeout(
              const Duration(seconds: 3),
              onTimeout: () => Duration.zero,
            );
      }
      if (d == Duration.zero) return;
      // Almost-finished videos start from the beginning again.
      if (secs >= d.inSeconds - 15) {
        final e = _historyEntryFor(track.path);
        if (e != null) {
          e.lastPositionSecs = 0;
          _persistHistory();
        }
        return;
      }
      // User may have switched tracks while we waited.
      if (currentTrack?.path != track.path) return;
      await player.seek(Duration(seconds: secs));
      _notices.add('Resumed ${formatDuration(Duration(seconds: secs))}');
    } catch (_) {
      // Resume is best-effort.
    }
  }

  /// v65 Smart skip: when playback reaches the detected end-credits point,
  /// jump to just before the end (so the player naturally finishes). Fires
  /// once per video; the PlayerScreen shows an "Undo" chip via [notice].
  void _maybeAutoSkipCredits(Duration pos) {
    final at = skipCreditsAt;
    if (at == null || _didSkipCredits) return;
    if (pos < at) return;
    _didSkipCredits = true;
    // If there is a next video (series episode), going to the end triggers
    // nextTrack via _handleEnded; for a single video this just fast-forwards
    // the credits. Remember where we jumped from so the Undo chip can revert.
    final from = pos;
    if (duration > Duration.zero) {
      final target = duration - const Duration(seconds: 2);
      if (target > from) {
        player.seek(target);
        _notices.add('Skipped credits');
      }
    }
  }

  /// PlayerScreen calls this when the user taps "Undo" on a credits skip.
  Future<void> undoSkipCredits() async {
    final at = skipCreditsAt;
    if (at == null) return;
    _didSkipCredits = false;
    await player.seek(at - const Duration(milliseconds: 500));
  }

  /// v65 A2: the full transcript cues available for the current video
  /// (AI sidecar preferred, then the same-name .srt), or null. Feeds the
  /// "Ask anything about this video" chat.
  List<SrtCue>? get transcriptCues => aiCues ?? sidecarCues;

  void _saveBookmark() {
    final track = currentTrack;
    if (track == null || !isPlaying) return;
    final secs = position.inSeconds;
    if (secs <= 0) return;
    final entry = _historyEntryFor(track.path);
    if (entry != null && entry.lastPositionSecs != secs) {
      entry.lastPositionSecs = secs;
      _persistHistory();
    }
  }

  // ---------------------------------------------------------------------------
  // Brightness (left-half swipe in the player)
  // ---------------------------------------------------------------------------

  /// Reads the current override once so the first drag starts from the real
  /// screen brightness instead of a guess.
  Future<double> currentBrightness() async {
    if (!_brightnessSynced) {
      brightness = await NativeBridge.getBrightness();
      _brightnessSynced = true;
      notifyListeners();
    }
    return brightness;
  }

  Future<void> setBrightness(double v) async {
    brightness = v.clamp(0.0, 1.0);
    notifyListeners();
    await NativeBridge.setBrightness(brightness);
  }

  Future<void> resetBrightness() async {
    brightness = 1.0;
    _brightnessSynced = false;
    notifyListeners();
    await NativeBridge.resetBrightness();
  }

  Future<void> togglePlay() async {
    // v19: optimistic UI - flip the icon instantly; the playing stream
    // confirms (or corrects) a moment later. Kills the visible tap->icon
    // lag that made the play/pause button feel delayed.
    final wantPlay = !isPlaying;
    isPlaying = wantPlay;
    notifyListeners();
    if (wantPlay) {
      await player.play();
    } else {
      await pause();
    }
  }

  /// Unconditional resume (used when handing playback back from a TV cast
  /// session - togglePlay would pause if the user already resumed).
  Future<void> resumePlayback() => player.play();

  /// Saves the CURRENT video frame exactly as shown (subtitles included)
  /// as a PNG into /storage/emulated/0/Pictures/Max Player and registers it
  /// with the media scanner so gallery apps see it immediately.
  ///
  /// Returns the saved path, or null when there is nothing to capture
  /// (no video, or a network stream) or the capture failed.
  Future<String?> captureScreenshot() async {
    final track = currentTrack;
    if (track == null) return null;
    if (track.path.startsWith('http')) return null; // stream: nothing on disk
    final platform = player.platform;
    if (platform is! NativePlayer) return null;
    try {
      final dir = Directory('/storage/emulated/0/Pictures/Max Player');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final out =
          '${dir.path}/MaxPlayer_${DateTime.now().millisecondsSinceEpoch}.png';
      // libmpv command; plain (non-async) screenshot-to-file blocks mpv's
      // core until the PNG is written, then we verify from Dart.
      await platform.command(['screenshot-to-file', out]);
      final f = File(out);
      for (var i = 0; i < 20; i++) {
        if (f.existsSync() && f.lengthSync() > 0) {
          await NativeBridge.scanFile(out);
          return out;
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> pause() async {
    // v20: pause FIRST so the video freezes instantly. The previous order
    // (boost cleanup + bookmark disk write BEFORE pausing) added a visible
    // delay between tapping pause and the video actually stopping.
    await player.pause();
    // Pausing always ends an active long-press boost (and its badge).
    await stopSpeedBoost();
    _saveBookmark();
  }

  Future<void> seek(Duration to) => player.seek(to);

  /// Relative seek (e.g. ±10s), clamped to the media bounds.
  Future<void> seekBy(int seconds) async {
    if (currentTrack == null) return;
    var target = position + Duration(seconds: seconds);
    if (target < Duration.zero) target = Duration.zero;
    if (duration > Duration.zero && target > duration) target = duration;
    await player.seek(target);
  }

  // ---------------------------------------------------------------------------
  // Volume (device MEDIA volume, MX Player / VLC style)
  // ---------------------------------------------------------------------------

  bool _volumeSynced = false;
  double _preMuteVolume = 0.5;

  /// Reads the real device media volume once so the player swipe starts
  /// from the true level (mirrors [currentBrightness]).
  Future<double> currentVolume() async {
    if (!_volumeSynced) {
      volume = await NativeBridge.getMediaVolume();
      isMuted = volume <= 0;
      _volumeSynced = true;
      notifyListeners();
    }
    return volume;
  }

  /// When the setting is on, the volume range becomes 0..200%.
  /// The device volume covers 0..100%; mpv's decoder gain (volume-max=200
  /// is set when a track opens) covers the 100..200% boost region.
  bool volumeBoost200 = false;

  /// Current volume upper limit for the swipe gesture / slider math.
  double get volumeCap => volumeBoost200 ? 2.0 : 1.0;

  Future<void> setVolume(double v) async {
    volume = v.clamp(0.0, volumeCap);
    if (volume > 0) {
      isMuted = false;
      _preMuteVolume = volume;
    }
    await NativeBridge.setMediaVolume(isMuted ? 0 : volume.clamp(0.0, 1.0));
    await _applyMpvVolume();
    notifyListeners();
  }

  Future<void> _applyMpvVolume() async {
    final platform = player.platform;
    if (platform is! NativePlayer) return;
    final pct = volume <= 1 ? 100.0 : volume * 100.0;
    try {
      await platform.setProperty('volume', pct.toStringAsFixed(0));
    } catch (_) {}
  }

  /// Settings toggle: enable/disable the 200% boost region. Turning it off
  /// while boosted pulls the volume back to 100%.
  Future<void> setVolumeBoost200(bool on) async {
    volumeBoost200 = on;
    if (!on && volume > 1.0) await setVolume(1.0);
    if (!on) await _applyMpvVolume();
    notifyListeners();
  }

  /// v67 B1/B2/v70: syncs Now Playing notification, media session, thumbnail & duration.
  void _syncNowPlaying() {
    final track = currentTrack;
    if (track == null) {
      unawaited(NativeBridge.cancelNowPlaying());
      unawaited(NativeBridge.setWakeLock(false));
      return;
    }
    if (backgroundAudio) {
      unawaited(NativeBridge.showNowPlaying(
        title: track.title,
        subtitle: isPlaying ? 'Playing' : 'Paused',
        isPlaying: isPlaying,
        path: track.path,
        thumbnailPath: track.thumbnailPath,
        positionMs: position.inMilliseconds,
        durationMs: duration.inMilliseconds,
      ));
      unawaited(NativeBridge.setWakeLock(isPlaying));
    } else {
      unawaited(NativeBridge.cancelNowPlaying());
      unawaited(NativeBridge.setWakeLock(false));
    }
  }

  /// v67 B2: background audio setting.
  bool backgroundAudio = true;

  void setBackgroundAudio(bool on) {
    backgroundAudio = on;
    _syncNowPlaying();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Volume leveling (v21) - mpv dynaudnorm: quiet dialogue and loud
  // explosions come out at a steady level.
  // v22: merged with the equalizer into ONE mpv `af` chain (both used to
  // overwrite the whole property, silently cancelling each other), the
  // window was widened so the effect is actually audible, and the applied
  // chain is read back once - if this engine build lacks dynaudnorm the
  // user is told instead of the toggle doing nothing.
  // ---------------------------------------------------------------------------

  static const String kLevelingFilter = 'dynaudnorm=f=150:g=15:m=5:p=0.95';
  bool _levelingOn = false;
  bool get volumeLeveling => _levelingOn;

  Future<void> setVolumeLeveling(bool on) async {
    _levelingOn = on;
    notifyListeners();
    await _applyAudioFilters();
  }

  /// v32: mpv tone-mapping curve for HDR sources ("How does an HDR10 or
  /// Dolby Vision file render on this screen"). Values validated in
  /// PlayerSettings - anything unknown becomes 'auto' upstream.
  Future<void> setToneMapping(String mode) async {
    final plat = player.platform;
    if (plat is! NativePlayer) return;
    try {
      await plat.setProperty('tone-mapping', mode);
    } catch (_) {}
  }

  /// v32/v38: real-time picture enhancement. The shader is a tiny one-pass
  /// sharpen+contrast+vibrance GLSL hook (assets/shaders/mx_enhance.glsl)
  /// written to a cache file and given to mpv via glsl-shaders. Off simply
  /// clears the list. Any failure (missing shader, old output driver) is
  /// silent - playback continues untouched.
  ///
  /// v38 reality check ("video enhance is not effective"): with hardware
  /// DIRECT rendering the decoder pushes frames straight to the screen and
  /// user shaders are skipped completely - the toggle did nothing visible.
  /// Switching to copy-back decode routes every frame through the shader
  /// pipeline, so the effect is real. mpv itself falls back to software
  /// decode when a codec cannot copy back, so nothing breaks.
  static const String kEnhanceHwdec = 'mediacodec-copy';

  /// Pure so tests can pin the decode-mode switch.
  static String enhanceHwdecFor(bool on) => on ? kEnhanceHwdec : 'auto';

  /// v51: one-time mpv cache caps applied in the constructor. 32 MiB of
  /// forward buffer still smooths 4K remux files; an 8 MiB back buffer
  /// keeps instant seek-back; cache-secs bounds network-stream caching by
  /// time so live http links cannot pile up RAM. (The 800 MB storage
  /// bloat was on-disk seek strips - fixed natively in MainActivity.)
  static const Map<String, String> kMpvCacheCapProps = {
    'demuxer-max-bytes': '32MiB',
    'demuxer-max-back-bytes': '8MiB',
    'cache-secs': '10',
  };

  bool _enhanceApplied = false;
  String? _enhanceShaderPath;

  Future<void> setEnhanceVideo(bool on) async {
    final plat = player.platform;
    if (plat is! NativePlayer) return;
    try {
      final f = File('${Directory.systemTemp.path}/mx_enhance.glsl');
      if (on) {
        const asset = 'assets/shaders/mx_enhance.glsl';
        final src = await rootBundle.loadString(asset);
        if (!f.existsSync() || await f.readAsString() != src) {
          await f.writeAsString(src, flush: true);
        }
        _enhanceShaderPath = f.path;
      }
      await plat.setProperty('glsl-shaders', on ? (_enhanceShaderPath ?? '') : '');
      await plat.setProperty('hwdec', enhanceHwdecFor(on));
    } catch (_) {
      return;
    }
    if (on == _enhanceApplied) return;
    _enhanceApplied = on;
    // v38: the decode mode only changes for the NEXT opened file - reload
    // the current video in place (position + play/pause kept) so toggling
    // Enhance is visible immediately, not just on the next video.
    if (playlist.isEmpty || currentTrack == null) return;
    final pos = player.state.position;
    final wasPlaying = player.state.playing;
    await _loadCurrent(autoplay: wasPlaying);
    if (pos > Duration.zero) {
      // mpv finishes opening asynchronously; pin the position shortly after.
      Future<void>.delayed(const Duration(milliseconds: 350), () {
        player.seek(pos);
      });
    }
  }

  /// The single writer of mpv's `af` property: equalizer bands + leveling
  /// combined inside a single unified lavfi filter chain.
  Future<void> _applyAudioFilters() async {
    final platform = player.platform;
    if (platform is! NativePlayer) return;
    final lavfiParts = <String>[
      if (eqEnabled) ...equalizerFilterParts(eqGains),
      if (_levelingOn) kLevelingFilter,
    ];
    final af = lavfiParts.isEmpty ? '' : 'lavfi=[${lavfiParts.join(',')}]';
    try {
      await platform.setProperty('af', af);
    } catch (_) {}
  }

  Future<void> toggleMute() async {
    if (isMuted) {
      isMuted = false;
      if (volume <= 0) volume = _preMuteVolume;
      await NativeBridge.setMediaVolume(volume);
    } else {
      if (volume > 0) _preMuteVolume = volume;
      isMuted = true;
      await NativeBridge.setMediaVolume(0);
    }
    notifyListeners();
  }

  Future<void> setPlaybackRate(double rate) async {
    playbackRate = rate;
    await player.setRate(rate);
    notifyListeners();
  }

  /// Switch to a different audio track (e.g. Hindi / English in dual-audio
  /// files). Pass an entry of [audioTracks].
  void selectAudioTrack(AudioTrack track) => player.setAudioTrack(track);

  /// Switch subtitle track; pass SubtitleTrack.no() to turn subtitles off.
  void selectSubtitleTrack(SubtitleTrack track) =>
      player.setSubtitleTrack(track);

  /// True when a real subtitle track (not "no"/off) is currently active.
  bool get subtitlesActive =>
      currentSubtitleTrack != null && currentSubtitleTrack!.id != 'no';

  // ---------------------------------------------------------------------------
  // A-B loop
  // ---------------------------------------------------------------------------

  /// Button callback: 1st tap sets A, 2nd sets B (loop starts), 3rd clears.
  /// Returns a short message for the on-screen indicator.
  String tapLoopPoint() {
    if (loopA == null) {
      loopA = position;
      notifyListeners();
      return 'A set ${formatDuration(position)}';
    }
    if (loopB == null) {
      // Ignore a B that's not after A (user double-tapped by accident).
      if (position <= loopA! + const Duration(seconds: 1)) {
        loopA = position;
        notifyListeners();
        return 'A set ${formatDuration(position)}';
      }
      loopB = position;
      notifyListeners();
      return 'Looping ${formatDuration(loopA!)} → ${formatDuration(loopB!)}';
    }
    loopA = null;
    loopB = null;
    notifyListeners();
    return 'A-B loop cleared';
  }

  // ---------------------------------------------------------------------------
  // Long-press speed boost (customizable multiplier)
  // ---------------------------------------------------------------------------

  Future<void> startSpeedBoost(double multiplier) async {
    if (_preBoostRate != null) return; // already boosting
    if (!isPlaying) return; // no boost/badge while paused
    _preBoostRate = playbackRate;
    playbackRate = multiplier;
    await player.setRate(multiplier);
    notifyListeners();
  }

  Future<void> stopSpeedBoost() async {
    final restore = _preBoostRate;
    if (restore == null) return;
    _preBoostRate = null;
    playbackRate = restore;
    await player.setRate(restore);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Equalizer (libmpv `af` lavfi chain)
  // ---------------------------------------------------------------------------

  static const String _kEqEnabledKey = 'eq.enabled';
  static const String _kEqGainsKey = 'eq.gains';

  /// Generates the individual lavfi equalizer filter parts.
  static List<String> equalizerFilterParts(List<double> gains) {
    final parts = <String>[];
    for (var i = 0; i < eqFrequencies.length && i < gains.length; i++) {
      if (gains[i] == 0) continue;
      parts.add(
        'equalizer=f=${eqFrequencies[i]}:t=q:w=1.0:g=${gains[i].toStringAsFixed(1)}',
      );
    }
    return parts;
  }

  /// Builds the lavfi audio-filter chain, skipping bands at 0 dB.
  /// Pure + testable.
  static String buildEqualizerFilter(List<double> gains) {
    final parts = equalizerFilterParts(gains);
    return parts.isEmpty ? '' : 'lavfi=[${parts.join(',')}]';
  }

  Future<void> applyEqualizer(List<double> gains, bool enabled) async {
    eqGains = List.of(gains);
    eqEnabled = enabled;
    NativeBridge.saveSetting(_kEqEnabledKey, '$enabled');
    NativeBridge.saveSetting(
      _kEqGainsKey,
      gains.map((g) => g.toStringAsFixed(1)).join(','),
    );
    notifyListeners();
    await _applyEqFilter();
  }

  Future<void> _applyEqFilter() => _applyAudioFilters(); // v22: shared chain

  // ---------------------------------------------------------------------------
  // Watch-time stats
  // ---------------------------------------------------------------------------

  /// Persisted key for a day bucket, e.g. stats.20260811. Pure + testable.
  static String statsKeyFor(DateTime d) =>
      'stats.${d.year * 10000 + d.month * 100 + d.day}';

  void _trackWatchTime() {
    if (!isPlaying) return;
    final key = statsKeyFor(DateTime.now());
    if (key != _todayStatsKey) {
      // Day rolled over while playing.
      _todayStatsKey = key;
      _watchTodaySecs = 0;
    }
    _watchTodaySecs += 5;
    NativeBridge.saveSetting(key, '$_watchTodaySecs');
    // v27: per-video totals for the "Most watched" list (same 5s tick,
    // trimmed to the heaviest entries so the stored blob stays tiny).
    final path = currentTrack?.path;
    if (path != null) {
      final map = Map<String, int>.of(_watchByVideo);
      map[path] = (map[path] ?? 0) + 5;
      if (map.length > _kWatchByVideoMax) {
        final sorted = map.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        map
          ..clear()
          ..addEntries(sorted.take(_kWatchByVideoMax));
      }
      _watchByVideo = map;
      NativeBridge.saveSetting(_kWatchByVideoKey, jsonEncode(map));
    }
  }

  /// Last 7 days of watch time (index 0 = 6 days ago, last = today).
  Future<List<WatchDay>> getWeekStats() async {
    final s = await NativeBridge.loadSettings();
    final now = DateTime.now();
    final todayKey = statsKeyFor(now);
    final days = <WatchDay>[];
    for (var i = 6; i >= 0; i--) {
      final d = now.subtract(Duration(days: i));
      final key = statsKeyFor(d);
      var secs = int.tryParse(s[key] ?? '') ?? 0;
      if (key == todayKey && _watchTodaySecs > secs) secs = _watchTodaySecs;
      days.add(WatchDay(d, secs));
    }
    return days;
  }

  /// v27 advanced stats: total watch seconds over the last [days] days
  /// (including today's in-progress count).
  Future<int> getWatchSecondsForLastDays(int days) async {
    final s = await NativeBridge.loadSettings();
    final now = DateTime.now();
    final todayKey = statsKeyFor(now);
    var total = 0;
    for (var i = days - 1; i >= 0; i--) {
      final key = statsKeyFor(now.subtract(Duration(days: i)));
      var secs = int.tryParse(s[key] ?? '') ?? 0;
      if (key == todayKey && _watchTodaySecs > secs) secs = _watchTodaySecs;
      total += secs;
    }
    return total;
  }

  /// v27: how many days IN A ROW something was watched (today counts when
  /// already non-zero; the chain may start yesterday and still count).
  Future<int> getWatchStreakDays() async {
    final s = await NativeBridge.loadSettings();
    final now = DateTime.now();
    final todayKey = statsKeyFor(now);
    final todaySecs = _watchTodaySecs > (int.tryParse(s[todayKey] ?? '') ?? 0)
        ? _watchTodaySecs
        : (int.tryParse(s[todayKey] ?? '') ?? 0);
    var streak = 0;
    var offset = todaySecs > 0
        ? 0
        : 1; // no watching today yet -> start yesterday
    while (true) {
      final key = statsKeyFor(now.subtract(Duration(days: offset)));
      final secs = int.tryParse(s[key] ?? '') ?? 0;
      if (secs <= 0) break;
      streak++;
      offset++;
      if (offset > 3650) break; // paranoia guard
    }
    return streak;
  }

  /// v27: the [limit] most-watched videos (path -> total seconds),
  /// heaviest first. Uses the in-memory map restored in [_init].
  List<MapEntry<String, int>> getTopWatchedVideos({int limit = 5}) {
    final entries = _watchByVideo.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.take(limit).toList();
  }

  /// Display title for a path: the history entry's title when known,
  /// else the file name.
  String titleForPath(String path) {
    for (final e in _history) {
      if (e.path == path) return e.title;
    }
    return path.split('/').last;
  }

  // ---------------------------------------------------------------------------
  // Scrub preview thumbnail strip (v19)
  // ---------------------------------------------------------------------------

  /// Frames generated per video - must match the native generator
  /// (MainActivity.thumbStripEnsureSync).
  static const int thumbStripCount = 72;

  String? _thumbStripFor;
  String? _thumbStripDir;

  void _ensureThumbStrip() {
    final track = currentTrack;
    if (track == null) return;
    final path = track.path;
    if (path.startsWith('http')) return; // streams: nothing on disk to scan
    if (_thumbStripFor == path) return; // already requested for this file
    _thumbStripFor = path;
    _thumbStripDir = null;
    NativeBridge.thumbStripEnsure(path).then((dir) {
      if (dir != null && _thumbStripFor == path) {
        _thumbStripDir = dir;
        notifyListeners();
      }
    });
  }

  /// Thumbnail file for the preview bubble at [fraction] (0..1 of the
  /// video), or null while that frame hasn't been generated yet (the
  /// bubble then shows the timestamp only).
  String? scrubThumbPath(double fraction) {
    final dir = _thumbStripDir;
    if (dir == null) return null;
    final i = (fraction.clamp(0.0, 1.0) * (thumbStripCount - 1)).round();
    final f = File('$dir/f_${i.toString().padLeft(3, '0')}.jpg');
    return f.existsSync() ? f.path : null;
  }

  // ---------------------------------------------------------------------------
  // Mini player
  // ---------------------------------------------------------------------------

  /// Dismisses the mini player: clears the queue and stops playback.
  Future<void> stopMini() async {
    playlist = [];
    currentIndex = 0;
    _syncNowPlaying();
    notifyListeners();
    await player.stop();
  }

  Future<void> nextTrack() async {
    if (playlist.length <= 1) return;
    await playTrack(_getNextIndex(forward: true));
  }

  Future<void> prevTrack() async {
    if (position.inSeconds > 3) {
      await seek(Duration.zero);
      return;
    }
    if (playlist.length <= 1) return;
    await playTrack(_getNextIndex(forward: false));
  }

  /// Alias for [prevTrack] used by media session / notifications.
  Future<void> previousTrack() => prevTrack();

  void toggleRepeat() {
    repeatMode = switch (repeatMode) {
      RepeatMode.none => RepeatMode.all,
      RepeatMode.all => RepeatMode.one,
      RepeatMode.one => RepeatMode.none,
    };
    notifyListeners();
  }

  void toggleShuffle() {
    isShuffled = !isShuffled;
    if (isShuffled) {
      _shuffledOrder = _generateShuffledOrder(playlist.length, currentIndex);
    }
    notifyListeners();
  }

  Future<void> removeFromPlaylist(int index) async {
    final wasCurrent = index == currentIndex;
    playlist = [...playlist]..removeAt(index);
    if (playlist.isEmpty) {
      currentIndex = 0;
      await player.stop();
    } else if (wasCurrent) {
      currentIndex = currentIndex.clamp(0, playlist.length - 1);
      await _loadCurrent(autoplay: false);
    } else if (index < currentIndex) {
      currentIndex -= 1;
    }
    notifyListeners();
  }

  Future<void> _handleEnded() async {
    // Completed video: reset its saved position so it replays from the start.
    final track = currentTrack;
    if (track != null) {
      final e = _historyEntryFor(track.path);
      if (e != null) {
        e.lastPositionSecs = 0;
        _persistHistory();
      }
    }
    if (repeatMode == RepeatMode.one) {
      await player.seek(Duration.zero);
      await player.play();
    } else if (repeatMode == RepeatMode.all ||
        currentIndex < playlist.length - 1) {
      await nextTrack();
    }
  }

  @override
  void dispose() {
    _uiTicker?.cancel();
    _bookmarkTimer?.cancel();
    _notices.close();
    for (final s in _subs) {
      s.cancel();
    }
    player.dispose();
    super.dispose();
  }
}

/// One day of watch time for the stats screen.
class WatchDay {
  final DateTime day;
  final int seconds;
  const WatchDay(this.day, this.seconds);
}
