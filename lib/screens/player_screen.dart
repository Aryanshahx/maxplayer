import 'dart:async';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

import '../utils/ab_loop.dart';
import '../utils/mpv_filters.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:volume_controller/volume_controller.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../theme.dart';
import '../utils/crash_log.dart';
import '../utils/format.dart';
import '../utils/resume.dart';

/// Single-engine player: MPV (libmpv + FFmpeg) via media_kit.
///
/// Gesture suite:
///   • single tap            → show/hide controls
///   • double tap L/R        → seek ±10s (flash pill)
///   • long press hold       → 2× speed, release restores
///   • vertical drag RIGHT   → volume
///   • vertical drag LEFT    → screen brightness (restored on exit)
///   • horizontal drag       → scrub seek with preview pill
///   • two-finger pinch      → zoom 1×–4× (anchored center)
///
/// Also: wakelock while playing, resume prompt (survives kill), and
/// "Queue All" auto-advance to the next video on completion.
/// Any open failure is crumbed, persisted, surfaced, and pops — never silent.
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    super.key,
    required this.path,
    required this.title,
    this.queueIds = const [],
    this.queueStart = 0,
    this.isStream = false,
    this.meta = const {},
  });

  /// Network source (IPTV / cloud / LAN) — no queue, no resume.
  const PlayerScreen.stream({
    super.key,
    required this.path,
    required this.title,
  })  : queueIds = const [],
        queueStart = 0,
        isStream = true,
        meta = const {};

  final String path;
  final String title;
  final List<String> queueIds;
  final int queueStart;
  final bool isStream;

  /// Deep-details metadata handed in from the library (size, width...).
  final Map<String, String> meta;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

enum _DragMode { none, brightness, volume, seek, zoom }

enum _PlayerMenuAction { info, eq, screenshot, cast, pip, sleep }

class _PlayerScreenState extends State<PlayerScreen>
    with WidgetsBindingObserver {
  static const _seekStepSecs = 10;
  static const _boostRate = 2.0;
  static const _saveInterval = Duration(seconds: 5);

  late final Player _player;
  late final VideoController _controller;
  final ResumeStore _resume = ResumeStore();
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<bool>? _completedSub;

  late String _title;
  String _currentPath = '';
  int _queueIndex = 0;

  bool _ready = false;
  bool _failed = false;
  bool _controlsVisible = true;
  bool _boost = false;
  bool _buffering = false;

  Timer? _hideTimer;
  Timer? _flashTimer;
  Timer? _saveTimer;

  // gesture state
  _DragMode _drag = _DragMode.none;
  Offset _dragStart = Offset.zero;
  double _zoom = 1.0;
  double _zoomStart = 1.0;
  double _levelValue = 0; // brightness or volume 0..1
  Duration? _seekPreview;
  int? _seekFlash;
  bool _seekFlashLeft = false;

  StreamSubscription<bool>? _bufferingSub;

  // ---- v0.8: MX-parity extras ----
  static const _native = MethodChannel('maxplayer/native');

  AbState _ab = AbState.off; // A-B loop (mpv native props)
  final List<double> _bands =
      List<double>.from(equalizerPresets['Flat']!); // 5-band EQ
  bool _dialogueBoost = false;
  bool _enhance = false;
  bool _karaoke = false;
  String _toneMapping = 'auto';
  Timer? _sleepTimer;
  int _sleepMinutesLeft = 0;

  // live scrubbing state
  Duration _scrubStart = Duration.zero;
  Duration _lastAppliedSeek = Duration.zero;
  DateTime _lastLiveSeek = DateTime.fromMillisecondsSinceEpoch(0);

  /// Best-effort MPV property set (noop if the native player isn't up).
  Future<void> _mpvSet(String key, String value) async {
    try {
      final platform = _player.platform;
      if (platform != null) await (platform as dynamic).setProperty(key, value);
    } catch (_) {/* prop unsupported on this build */}
  }

  Future<void> _mpvSetMany(Map<String, String> props) async {
    for (final e in props.entries) {
      await _mpvSet(e.key, e.value);
    }
  }

  // ---------------- A-B loop ----------------

  void _cycleAbLoop() {
    _ab = _ab.advance(_player.state.position.inMilliseconds);
    CrashLog.crumb('ab.loop', {'phase': _ab.phase.name});
    switch (_ab.phase) {
      case AbPhase.off:
        unawaited(_mpvSet('ab-loop-a', 'no'));
        unawaited(_mpvSet('ab-loop-b', 'no'));
        break;
      case AbPhase.aSet:
        unawaited(_mpvSetMany({
          'ab-loop-a': '${_ab.aMs! / 1000}',
          'ab-loop-b': 'no',
        }));
        break;
      case AbPhase.abSet:
        unawaited(_mpvSetMany({
          'ab-loop-a': '${_ab.aMs! / 1000}',
          'ab-loop-b': '${_ab.bMs! / 1000}',
        }));
        break;
    }
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_ab.describe())),
    );
  }

  void _cancelAbLoop() {
    if (_ab.phase == AbPhase.off) return;
    _ab = AbState.off;
    unawaited(_mpvSet('ab-loop-a', 'no'));
    unawaited(_mpvSet('ab-loop-b', 'no'));
    setState(() {});
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('A-B loop off')));
  }

  // ---------------- audio FX (EQ + dialogue boost) ----------------

  Future<void> _applyAudioFilters() async {
    CrashLog.crumb('eq.apply', {'bands': _bands.join('/')});
    await _mpvSet(
        'af', combineAudioFilters(_bands, dialogueBoost: _dialogueBoost));
  }

  void _setBand(int i, double g) {
    _bands[i] = g;
    setState(() {});
    unawaited(_applyAudioFilters());
  }

  void _emitSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ---------------- video FX (enhance / HDR tone-mapping) ----------------

  Future<void> _toggleEnhance(bool on) async {
    _enhance = on;
    CrashLog.crumb('enhance.$on');
    setState(() {});
    if (on) {
      await _mpvSetMany({
        'contrast': '14',
        'saturation': '12',
        'gamma': '2',
        'vf': buildEnhanceFilter(),
      });
      _emitSnack('Enhance on — GPU sharpen + contrast boost');
    } else {
      await _mpvSetMany(
          {'contrast': '0', 'saturation': '0', 'gamma': '0', 'vf': ''});
    }
  }

  Future<void> _setToneMapping(String mode) async {
    _toneMapping = mode;
    CrashLog.crumb('tone_map.$mode');
    setState(() {});
    await _mpvSet('tone-mapping', mode);
  }

  // ---------------- karaoke subtitles (ASS preferred) ----------------

  Future<void> _toggleKaraoke(bool on) async {
    _karaoke = on;
    setState(() {});
    CrashLog.crumb('karaoke.$on');
    if (on) {
      final subs = _player.state.tracks.subtitle;
      dynamic ass;
      for (final s in subs) {
        if ('${(s as dynamic).codec}' == 'ass') {
          ass = s;
          break;
        }
      }
      if (ass != null) {
        await _player.setSubtitleTrack(ass as SubtitleTrack);
        _emitSnack('Karaoke subtitles on');
      } else {
        _karaoke = false;
        setState(() {});
        _emitSnack('No karaoke (ASS) subtitles inside this video');
      }
    } else {
      await _player.setSubtitleTrack(SubtitleTrack.no());
    }
  }

  // ---------------- lifecycle ----------------

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations(
        [DeviceOrientation.portraitUp, DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    _title = widget.title;
    _currentPath = widget.path;
    _queueIndex = widget.queueStart;
    _player = Player();
    _controller = VideoController(_player);
    _open(_currentPath, offerResume: true);
    _playingSub = _player.stream.playing.listen((playing) {
      if (playing) {
        WakelockPlus.enable();
        _scheduleHide();
      } else {
        WakelockPlus.disable();
        unawaited(_savePosition());
      }
    });
    _bufferingSub = _player.stream.buffering.listen((b) {
      if (mounted) setState(() => _buffering = b);
    });
    _completedSub = _player.stream.completed.listen((done) {
      if (done) unawaited(_playNext());
    });
    _saveTimer = Timer.periodic(_saveInterval, (_) => _savePosition());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      unawaited(_savePosition());
    }
  }

  Future<void> _open(String path, {required bool offerResume}) async {
    CrashLog.crumb('player.open', {'path': path});
    try {
      await _player.open(Media(path), play: true);
      _player.stream.error.listen(_onError);
      if (mounted) setState(() => _ready = true);
      if (offerResume && !widget.isStream) unawaited(_offerResume());
    } catch (e) {
      _onError(e);
    }
  }

  Future<void> _playNext() async {
    if (!mounted) return;
    if (widget.queueIds.isEmpty || _queueIndex >= widget.queueIds.length - 1) {
      CrashLog.crumb('queue.end');
      await _resume.clear(_currentPath); // finished the tail
      if (mounted) Navigator.of(context).maybePop();
      return;
    }
    _queueIndex++;
    final id = widget.queueIds[_queueIndex];
    try {
      final asset = await AssetEntity.fromId(id);
      final file = await asset?.file;
      if (file == null || !file.existsSync()) {
        throw StateError('queue item unavailable: $id');
      }
      await _resume.clear(_currentPath);
      _currentPath = file.path;
      _swFallbackTried = false; // fresh file = fresh fallback chance
      CrashLog.crumb('queue.next', {'id': id});
      setState(() => _title = asset!.title ?? 'Video');
      await _player.open(Media(file.path), play: true);
    } catch (e) {
      CrashLog.error('queue.next_failed', e, {'id': id});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Could not play the next video in queue')));
      }
    }
  }

  // ---------------- resume ----------------

  Future<void> _offerResume() async {
    if (widget.isStream) return; // no resume bookkeeping for network sources
    try {
      final saved = await _resume.readMs(_currentPath);
      if (saved == null || !mounted) return;
      var dur = _player.state.duration;
      if (dur <= Duration.zero) {
        dur = await _player.stream.duration
            .firstWhere((d) => d > Duration.zero)
            .timeout(const Duration(seconds: 5),
                onTimeout: () => Duration.zero);
      }
      final targetMs = resumeTargetMs(saved, dur.inMilliseconds);
      if (targetMs == null || !mounted) return;
      CrashLog.crumb('resume.offer', {'path': _currentPath, 'ms': targetMs});
      final resume = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppColors.border),
          ),
          title: const Text('Resume playback?',
              style:
                  TextStyle(color: AppColors.textPrimary, fontSize: 17)),
          content: Text(
            'Continue from ${formatDuration(Duration(milliseconds: targetMs))}?',
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Start over',
                  style: TextStyle(color: AppColors.textSecondary)),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accent,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Resume'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (resume == true) {
        _player.seek(Duration(milliseconds: targetMs));
      } else if (resume == false) {
        await _resume.clear(_currentPath);
      }
    } catch (e) {
      CrashLog.error('resume.offer_failed', e, {'path': _currentPath});
    }
  }

  Future<void> _savePosition() async {
    if (widget.isStream) return;
    if (!_ready || _failed) return;
    try {
      final pos = _player.state.position;
      final dur = _player.state.duration;
      if (pos <= Duration.zero) return;
      if (isFinishedMs(pos.inMilliseconds, dur.inMilliseconds)) {
        await _resume.clear(_currentPath);
        return;
      }
      await _resume.writeMs(_currentPath, pos.inMilliseconds);
    } catch (e) {
      CrashLog.error('resume.save_failed', e, {'path': _currentPath});
    }
  }

  bool _swFallbackTried = false;

  /// Deep technical card: source metadata (from the library) + live MPV
  /// decode/track parameters, shown from the top-bar (i) button.
  void _showVideoInfo() {
    final s = _player.state;
    final rows = <MapEntry<String, String>>[
      ...widget.meta.entries,
      MapEntry('Source', widget.isStream ? 'Network stream' : _currentPath),
      MapEntry('Position',
          '${formatDuration(s.position)} / ${formatDuration(s.duration)}'),
      MapEntry('Remaining', formatDuration(s.duration - s.position)),
      MapEntry('Playback speed', '${s.rate}x'),
      MapEntry('Video encoder params', s.videoParams.toString()),
      MapEntry('Audio decoder params', s.audioParams.toString()),
      if (s.audioBitrate != null)
        MapEntry('Audio bitrate', '${s.audioBitrate} bit/s'),
    ];
    final trackLines = <String>[
      for (final t in s.tracks.video) 'Video:  $t',
      for (final t in s.tracks.audio) 'Audio:  $t',
      for (final t in s.tracks.subtitle) 'Subtitle:  $t',
    ];
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.border),
        ),
        title: Text(_title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style:
                const TextStyle(color: AppColors.textPrimary, fontSize: 15)),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final r in rows)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r.key,
                          style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 11.5)),
                      const SizedBox(height: 2),
                      Text(r.value,
                          style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 12.5)),
                    ],
                  ),
                ),
              if (trackLines.isNotEmpty) ...[
                const Divider(color: AppColors.border, height: 18),
                const Text('Tracks (MPV)',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 11.5)),
                const SizedBox(height: 4),
                for (final l in trackLines)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(l,
                        style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 11,
                            height: 1.4)),
                  ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child:
                Text('Close', style: TextStyle(color: AppColors.accent)),
          ),
        ],
      ),
    );
  }


  /// 4K/HEVC/AV1 can fail on hardware decoders. Before declaring failure,
  /// retry once with software decode (hwdec=no) — MPV/ffmpeg eats it.
  void _onError(Object e) {
    if (_failed) return;
    unawaited(_recoverOrFail(e));
  }

  Future<void> _recoverOrFail(Object e) async {
    if (!_swFallbackTried) {
      _swFallbackTried = true;
      try {
        final platform = _player.platform;
        if (platform != null) {
          await (platform as dynamic).setProperty('hwdec', 'no');
        }
        CrashLog.crumb('player.hwdec_no_retry');
        await _player.open(Media(_currentPath), play: true);
        if (mounted) setState(() => _ready = true);
        return; // recovered via software decode
      } catch (e2) {
        CrashLog.error('player.sw_fallback_failed', e2);
      }
    }
    _failed = true;
    CrashLog.error('player.open_failed', e, {'path': _currentPath});
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("This video can't be played by MPV")),
    );
    Navigator.of(context).maybePop();
  }

  @override
  void dispose() {
    _sleepTimer?.cancel();
    _hideTimer?.cancel();
    _flashTimer?.cancel();
    _saveTimer?.cancel();
    _playingSub?.cancel();
    _bufferingSub?.cancel();
    _completedSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    WakelockPlus.disable();
    ScreenBrightness.instance.resetApplicationScreenBrightness();
    unawaited(_savePosition());
    CrashLog.crumb('player.close', {'path': _currentPath});
    unawaited(_player.dispose());
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  // ---------------- gestures ----------------

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) _scheduleHide();
  }

  void _onDoubleTap(TapDownDetails d) {
    final half = MediaQuery.of(context).size.width / 2;
    final left = d.globalPosition.dx < half;
    _seekRelative(left ? -_seekStepSecs : _seekStepSecs, flashLeft: left);
  }

  void _seekRelative(int seconds, {required bool flashLeft}) {
    final pos = _player.state.position;
    final dur = _player.state.duration;
    var target = pos + Duration(seconds: seconds);
    if (target < Duration.zero) target = Duration.zero;
    if (dur > Duration.zero && target > dur) target = dur;
    _player.seek(target);
    _flash(seconds, flashLeft);
  }

  void _flash(int seconds, bool flashLeft) {
    _flashTimer?.cancel();
    setState(() {
      _seekFlash = seconds;
      _seekFlashLeft = flashLeft;
    });
    _flashTimer = Timer(const Duration(milliseconds: 650), () {
      if (mounted) setState(() => _seekFlash = null);
    });
  }

  void _setBoost(bool on) {
    if (_boost == on) return;
    setState(() => _boost = on);
    _player.setRate(on ? _boostRate : 1.0);
  }

  void _onScaleStart(ScaleStartDetails d) {
    _dragStart = d.focalPoint;
    _zoomStart = _zoom;
    if (d.pointerCount >= 2) {
      _drag = _DragMode.zoom;
    } else {
      _drag = _DragMode.none;
    }
  }

  Future<void> _onScaleUpdate(ScaleUpdateDetails d) async {
    if (_drag == _DragMode.zoom) {
      setState(() {
        _zoom = (_zoomStart * d.scale).clamp(1.0, 4.0);
      });
      return;
    }
    final delta = d.focalPoint - _dragStart;
    if (_drag == _DragMode.none) {
      if (delta.distance < 14) return;
      final w = MediaQuery.of(context).size.width;
      if (delta.dx.abs() > delta.dy.abs() * 1.5) {
        _drag = _DragMode.seek;
        _scrubStart = _player.state.position;
        _lastAppliedSeek = _scrubStart;
        _seekPreview = _scrubStart;
      } else {
        _drag = _dragStart.dx < w / 2 ? _DragMode.brightness : _DragMode.volume;
        // capture starting level
        if (_drag == _DragMode.brightness) {
          _levelValue = await ScreenBrightness.instance.application;
        } else {
          _levelValue = await VolumeController.instance.getVolume();
        }
        _dragStart = d.focalPoint;
        return;
      }
    }
    final h = MediaQuery.of(context).size.height;
    final w = MediaQuery.of(context).size.width;
    if (_drag == _DragMode.brightness || _drag == _DragMode.volume) {
      final change = -(d.focalPoint.dy - _dragStart.dy) / (h * 0.5);
      final v = (_levelValue + change).clamp(0.0, 1.0);
      setState(() {});
      if (_drag == _DragMode.brightness) {
        await ScreenBrightness.instance.setApplicationScreenBrightness(v);
        if (mounted) setState(() => _levelValue = v);
      } else {
        await VolumeController.instance.setVolume(v);
        if (mounted) setState(() => _levelValue = v);
      }
    } else if (_drag == _DragMode.seek) {
      final dur = _player.state.duration;
      if (dur <= Duration.zero) return;
      final frac = d.focalPoint.dx / w; // 0..1 across screen
      final target = Duration(
          milliseconds:
              (frac.clamp(0.0, 1.0) * dur.inMilliseconds).round());
      setState(() => _seekPreview = target);
      // PREVIEW WHILE SLIDING: the video itself scrubs under the finger
      // (MPV seeks locally in ~10-30 ms). Throttled to ~8 seeks/s and
      // skips sub-second jitters so 4K decode isn't overwhelmed.
      final now = DateTime.now();
      if (now.difference(_lastLiveSeek).inMilliseconds > 120 &&
          (target - _lastAppliedSeek).abs().inMilliseconds > 800) {
        _lastLiveSeek = now;
        _lastAppliedSeek = target;
        unawaited(_player.seek(target));
      }
    }
  }

  void _onScaleEnd(ScaleEndDetails d) {
    if (_drag == _DragMode.seek && _seekPreview != null) {
      _player.seek(_seekPreview!);
      CrashLog.crumb('player.scrub', {'to_ms': _seekPreview!.inMilliseconds});
    }
    if (_drag == _DragMode.brightness ||
        _drag == _DragMode.volume ||
        _drag == _DragMode.seek) {
      // keep indicator for a beat
      _flashTimer?.cancel();
      _flashTimer = Timer(const Duration(milliseconds: 600), () {
        if (mounted) setState(() => _seekPreview = null);
      });
      if (_drag != _DragMode.seek) {
        Timer(const Duration(milliseconds: 600), () {
          if (mounted) setState(() => _drag = _DragMode.none);
        });
        return;
      }
    }
    setState(() {
      if (_drag == _DragMode.seek) _seekPreview = null;
      _drag = _DragMode.none;
    });
  }

  // ---------------- extras (MX-style sheets) ----------------

  Future<void> _showExtrasSheet() async {
    final st = _player.state;
    await showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              _extraAction(
                icon: Icons.subtitles_rounded,
                title: st.tracks.subtitle.isEmpty
                    ? 'Subtitles (none in this video)'
                    : 'Subtitles (${st.tracks.subtitle.length})',
                onTap: () {
                  Navigator.of(context).pop();
                  _showTrackPicker(subtitle: true);
                },
              ),
              _extraAction(
                icon: Icons.music_note_rounded,
                title: st.tracks.audio.length <= 1
                    ? 'Audio track (1 available)'
                    : 'Audio track (${st.tracks.audio.length} available)',
                onTap: () {
                  Navigator.of(context).pop();
                  _showTrackPicker(subtitle: false);
                },
              ),
              _extraAction(
                icon: Icons.repeat_one_rounded,
                title: 'A-B loop',
                subtitle: _ab.describe(),
                onTap: () {
                  Navigator.of(context).pop();
                  _cycleAbLoop();
                },
                onLongPress: _cancelAbLoop,
              ),
              _extraToggle(
                icon: Icons.album_rounded,
                title: 'Karaoke subtitles',
                subtitle:
                    'Words light up - other subtitles hide while on',
                value: _karaoke,
                onChanged: (v) {
                  setSheet(() => _karaoke = v);
                  unawaited(_toggleKaraoke(v));
                },
              ),
              _extraToggle(
                icon: Icons.auto_fix_high_rounded,
                title: 'Enhance video',
                subtitle: 'GPU sharpen + contrast + colour boost',
                value: _enhance,
                onChanged: (v) {
                  setSheet(() => _enhance = v);
                  unawaited(_toggleEnhance(v));
                },
              ),
              ListTile(
                leading: Container(
                  width: 30,
                  alignment: Alignment.center,
                  child: Text('HDR',
                      style: TextStyle(
                          color: AppColors.accent,
                          fontSize: 10,
                          fontWeight: FontWeight.w800)),
                ),
                title: const Text('HDR tone-mapping',
                    style: TextStyle(color: AppColors.textPrimary)),
                subtitle: const Text(
                    'How HDR10/Dolby sources fit your screen',
                    style: TextStyle(color: AppColors.textSecondary)),
                trailing: DropdownButton<String>(
                  value: _toneMapping,
                  dropdownColor: AppColors.surfaceAlt,
                  underline: const SizedBox.shrink(),
                  style: const TextStyle(color: AppColors.textPrimary),
                  items: const [
                    DropdownMenuItem(value: 'auto', child: Text('Auto')),
                    DropdownMenuItem(value: 'clip', child: Text('Clip')),
                    DropdownMenuItem(
                        value: 'mobius', child: Text('Mobius')),
                    DropdownMenuItem(
                        value: 'reinhard', child: Text('Reinhard')),
                    DropdownMenuItem(value: 'hable', child: Text('Hable')),
                    DropdownMenuItem(value: 'gamma', child: Text('Gamma')),
                    DropdownMenuItem(
                        value: 'linear', child: Text('Linear')),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      setSheet(() => _toneMapping = v);
                      unawaited(_setToneMapping(v));
                    }
                  },
                ),
              ),
              _extraToggle(
                icon: Icons.record_voice_over_rounded,
                title: 'Dialogue boost',
                subtitle:
                    'Lifts quiet speech (1-4 kHz). Off by default.',
                value: _dialogueBoost,
                onChanged: (v) {
                  setSheet(() => _dialogueBoost = v);
                  unawaited(_applyAudioFilters());
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  ListTile _extraAction({
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
    VoidCallback? onLongPress,
  }) =>
      ListTile(
        dense: true,
        leading: Icon(icon, color: AppColors.accent, size: 21),
        title: Text(title,
            style: const TextStyle(color: AppColors.textPrimary)),
        subtitle: subtitle == null
            ? null
            : Text(subtitle,
                style: const TextStyle(color: AppColors.textSecondary)),
        onTap: onTap,
        onLongPress: onLongPress,
      );

  Widget _extraToggle({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) =>
      ListTile(
        dense: true,
        leading: Icon(icon, color: AppColors.accent, size: 21),
        title: Text(title,
            style: const TextStyle(color: AppColors.textPrimary)),
        subtitle: Text(subtitle,
            style: const TextStyle(color: AppColors.textSecondary)),
        trailing: Switch(value: value, onChanged: onChanged),
        onTap: () => onChanged(!value),
      );

  void _showTrackPicker({required bool subtitle}) {
    final st = _player.state;
    final tracks = subtitle ? st.tracks.subtitle : st.tracks.audio;
    final selected = subtitle ? st.track.subtitle : st.track.audio;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 6),
              child: Text(subtitle ? 'Subtitles' : 'Audio track',
                  style: TextStyle(
                      color: AppColors.accent,
                      fontSize: 15,
                      fontWeight: FontWeight.w700)),
            ),
            if (subtitle)
              _trackRow(
                name: 'Off',
                sel: (selected as dynamic).id == 'no',
                onTap: () async {
                  Navigator.of(context).pop();
                  await _player.setSubtitleTrack(SubtitleTrack.no());
                },
              ),
            for (final tr in tracks)
              _trackRow(
                name: _trackLabel(tr),
                sel: (selected as dynamic).id == (tr as dynamic).id,
                onTap: () async {
                  Navigator.of(context).pop();
                  if (subtitle) {
                    await _player.setSubtitleTrack(tr as SubtitleTrack);
                  } else {
                    await _player.setAudioTrack(tr as AudioTrack);
                  }
                },
              ),
          ],
        ),
      ),
    );
  }

  String _trackLabel(dynamic tr) {
    final parts = <String>[
      if ('${tr.title}' != 'null' && '${tr.title}'.isNotEmpty)
        '${tr.title}',
      if ('${tr.language}' != 'null' && '${tr.language}'.isNotEmpty)
        '${tr.language}'.toUpperCase(),
      if ('${tr.codec}' != 'null' && '${tr.codec}'.isNotEmpty) '${tr.codec}',
    ];
    return parts.isEmpty ? 'Track ${tr.id}' : parts.join(' • ');
  }

  Widget _trackRow(
      {required String name,
      required bool sel,
      required Future<void> Function() onTap}) {
    return ListTile(
      title: Text(name,
          style: const TextStyle(color: AppColors.textPrimary)),
      trailing: sel
          ? Icon(Icons.check_circle_rounded, color: AppColors.accent)
          : const Icon(Icons.radio_button_off_rounded,
              color: AppColors.textSecondary),
      onTap: () => unawaited(onTap()),
    );
  }

  // ---------------- top-more menu actions ----------------

  Future<void> _showEqualizerSheet() async {
    const labels = ['60 Hz', '230 Hz', '910 Hz', '3.6 kHz', '14 kHz'];
    await showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(16),
            children: [
              Text('Equalizer & Audio FX',
                  style: TextStyle(
                      color: AppColors.accent,
                      fontSize: 16,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: [
                  for (final name in equalizerPresets.keys)
                    ChoiceChip(
                      label: Text(name),
                      selected: listEquals(
                          _bands, equalizerPresets[name]!),
                      onSelected: (_) {
                        for (var i = 0; i < _bands.length; i++) {
                          _setBand(i, equalizerPresets[name]![i]);
                        }
                        setSheet(() {});
                      },
                    ),
                ],
              ),
              const SizedBox(height: 4),
              for (var i = 0; i < labels.length; i++)
                Row(
                  children: [
                    SizedBox(
                        width: 56,
                        child: Text(labels[i],
                            style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12))),
                    Expanded(
                      child: Slider(
                        value: _bands[i],
                        min: -12,
                        max: 12,
                        divisions: 24,
                        onChanged: (v) {
                          _setBand(i, v);
                          setSheet(() {});
                        },
                      ),
                    ),
                    SizedBox(
                      width: 44,
                      child: Text(
                          '${_bands[i] >= 0 ? '+' : ''}'
                          '${_bands[i].toStringAsFixed(0)} dB',
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12)),
                    ),
                  ],
                ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Dialogue boost',
                    style: TextStyle(color: AppColors.textPrimary)),
                subtitle: const Text('Lifts quiet speech (1-4 kHz)',
                    style:
                        TextStyle(color: AppColors.textSecondary)),
                value: _dialogueBoost,
                onChanged: (v) {
                  setSheet(() => _dialogueBoost = v);
                  unawaited(_applyAudioFilters());
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _captureScreenshot() async {
    CrashLog.crumb('player.screenshot');
    try {
      final bytes = await _player.screenshot();
      if (bytes == null || bytes.isEmpty) {
        _emitSnack('Screenshot failed — video not ready yet');
        return;
      }
      await PhotoManager.editor.saveImage(
        bytes,
        filename: 'maxplayer_${DateTime.now().millisecondsSinceEpoch}.jpg',
        relativePath: 'Pictures/MaxPlayer',
        title: 'MaxPlayer',
      );
      _emitSnack('Saved to Gallery (MaxPlayer album)');
    } catch (e) {
      CrashLog.error('screenshot.failed', e);
      _emitSnack('Screenshot failed');
    }
  }

  Future<void> _enterPip() async {
    CrashLog.crumb('player.pip');
    final vp = _player.state.videoParams;
    final w = vp.dw ?? 16;
    final h = vp.dh ?? 9;
    try {
      final ok = await _native
          .invokeMethod<bool>('enterPip', {'w': w, 'h': h});
      if (ok != true) _emitSnack('Picture-in-Picture not available');
    } catch (e) {
      CrashLog.error('pip.failed', e);
      _emitSnack('Picture-in-Picture not supported on this device');
    }
  }

  Future<void> _openCastSettings() async {
    CrashLog.crumb('player.cast_settings');
    try {
      await _native.invokeMethod<bool>('openCastSettings');
      _emitSnack(
          'Pick your TV on the system screen-mirroring page');
    } catch (_) {
      _emitSnack(
          'Open Android Settings → Connected devices → Cast');
    }
  }

  Future<void> _showSleepTimerSheet() async {
    const mins = [0, 10, 15, 30, 45, 60];
    final picked = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(14),
              child: Text('Sleep timer',
                  style: TextStyle(
                      color: AppColors.accent,
                      fontSize: 16,
                      fontWeight: FontWeight.w700)),
            ),
            for (final m in mins)
              ListTile(
                title: Text(
                    m == 0
                        ? (_sleepTimer == null
                            ? 'Off'
                            : 'Cancel timer ($_sleepMinutesLeft min)')
                        : '$m minutes',
                    style: const TextStyle(color: AppColors.textPrimary)),
                onTap: () => Navigator.of(context).pop(m),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked == null) return;
    _sleepTimer?.cancel();
    if (picked > 0) {
      _sleepMinutesLeft = picked;
      CrashLog.crumb('sleep_armed', {'min': picked});
      _sleepTimer = Timer(Duration(minutes: picked), () {
        _player.pause();
        CrashLog.crumb('sleep_fired');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Sleep timer — playback paused. Good night')));
        }
      });
      _emitSnack('Sleeping in $picked minutes');
    } else {
      _emitSnack('Sleep timer off');
    }
  }

  Future<void> _onMenuAction(_PlayerMenuAction a) async {
    switch (a) {
      case _PlayerMenuAction.info:
        _showVideoInfo();
        break;
      case _PlayerMenuAction.eq:
        await _showEqualizerSheet();
        break;
      case _PlayerMenuAction.screenshot:
        await _captureScreenshot();
        break;
      case _PlayerMenuAction.cast:
        await _openCastSettings();
        break;
      case _PlayerMenuAction.pip:
        await _enterPip();
        break;
      case _PlayerMenuAction.sleep:
        await _showSleepTimerSheet();
        break;
    }
  }

  // ---------------- controls visibility ----------------

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _player.state.playing && !_boost) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  // ---------------- build ----------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggleControls,
        onDoubleTapDown: _onDoubleTap,
        onLongPressStart: (_) => _setBoost(true),
        onLongPressEnd: (_) => _setBoost(false),
        onLongPressCancel: () => _setBoost(false),
        onScaleStart: _onScaleStart,
        onScaleUpdate: (d) => unawaited(_onScaleUpdate(d)),
        onScaleEnd: _onScaleEnd,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_ready && !_failed)
              ClipRect(
                child: Transform.scale(
                  scale: _zoom,
                  child: Video(
                    controller: _controller,
                    controls: NoVideoControls,
                  ),
                ),
              )
            else
              Center(child: CircularProgressIndicator(color: AppColors.accent)),

            if (_buffering && _ready)
              Center(
                child: SizedBox(
                  width: 46,
                  height: 46,
                  child:
                      CircularProgressIndicator(color: AppColors.accent),
                ),
              ),

            // double-tap flash
            if (_seekFlash != null)
              Align(
                alignment: _seekFlashLeft
                    ? Alignment.centerLeft
                    : Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 36),
                  child: _SeekPill(seconds: _seekFlash!),
                ),
              ),

            // scrub preview bubble
            if (_seekPreview != null)
              Align(
                alignment: const Alignment(0, -0.35),
                child: _InfoPill(
                  icon: Icons.swap_horizontal_circle_outlined,
                  text:
                      '${formatDuration(_seekPreview!)}  '
                      '${(_seekPreview! - _scrubStart) >= Duration.zero ? '+' : '-'}'
                      '${formatDuration((_seekPreview! - _scrubStart).abs())}  '
                      '|  ${formatDuration(_player.state.duration)}',
                ),
              ),

            // brightness indicator
            if (_drag == _DragMode.brightness)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 28),
                  child: _LevelPill(
                      icon: Icons.brightness_6_rounded, value: _levelValue),
                ),
              ),

            // volume indicator
            if (_drag == _DragMode.volume)
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 28),
                  child: _LevelPill(
                      icon: _levelValue == 0
                          ? Icons.volume_off_rounded
                          : Icons.volume_up_rounded,
                      value: _levelValue),
                ),
              ),

            // zoom badge
            if (_zoom > 1.001)
              Align(
                alignment: const Alignment(0, -0.75),
                child: _InfoPill(
                    icon: Icons.zoom_in_rounded,
                    text: '${_zoom.toStringAsFixed(1)}×'),
              ),

            // speed boost badge
            if (_boost)
              const Align(alignment: Alignment(0, -0.55), child: _SpeedBadge()),

            if (_controlsVisible) ...[
              _TopBar(
                title: _title,
                onInfo: _showVideoInfo,
                onExtras: _showExtrasSheet,
                onMenu: (a) => unawaited(_onMenuAction(a)),
              ),
              _BottomBar(player: _player),
              _CenterControls(player: _player),
            ],
          ],
        ),
      ),
    );
  }
}

class _SeekPill extends StatelessWidget {
  const _SeekPill({required this.seconds});

  final int seconds;

  @override
  Widget build(BuildContext context) {
    final back = seconds < 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            back ? Icons.replay_10_rounded : Icons.forward_10_rounded,
            color: Colors.white,
            size: 26,
          ),
          const SizedBox(width: 6),
          Text(
            '${back ? '' : '+'}${seconds}s',
            style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 20),
          const SizedBox(width: 8),
          Text(text,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _LevelPill extends StatelessWidget {
  const _LevelPill({required this.icon, required this.value});

  final IconData icon;
  final double value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 24),
          const SizedBox(height: 8),
          SizedBox(
            height: 90,
            child: RotatedBox(
              quarterTurns: 3,
              child: LinearProgressIndicator(
                value: value,
                minHeight: 4,
                backgroundColor: Colors.white24,
                valueColor:
                    AlwaysStoppedAnimation<Color>(AppColors.accent),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text('${(value * 100).round()}%',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _SpeedBadge extends StatelessWidget {
  const _SpeedBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Text(
        '2×',
        style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.title,
    required this.onInfo,
    required this.onExtras,
    required this.onMenu,
  });

  final VoidCallback onInfo;
  final VoidCallback onExtras;
  final void Function(_PlayerMenuAction) onMenu;

  final String title;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + 8,
          left: 4,
          right: 16,
          bottom: 12,
        ),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black87, Colors.transparent],
          ),
        ),
        child: Row(
          children: [
            IconButton(
              icon:
                  const Icon(Icons.arrow_back_rounded, color: Colors.white),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600),
              ),
            ),
            IconButton(
              tooltip: 'Player settings',
              icon: const Icon(Icons.settings_outlined,
                  color: Colors.white, size: 21),
              onPressed: onExtras,
            ),
            PopupMenuButton<_PlayerMenuAction>(
              tooltip: 'More',
              padding: EdgeInsets.zero,
              iconSize: 21,
              icon: const Icon(Icons.more_vert_rounded,
                  color: Colors.white),
              color: AppColors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: const BorderSide(color: AppColors.border),
              ),
              onSelected: onMenu,
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: _PlayerMenuAction.info,
                  child: _MoreRow(
                      icon: Icons.info_outline_rounded,
                      label: 'Video info'),
                ),
                PopupMenuItem(
                  value: _PlayerMenuAction.eq,
                  child: _MoreRow(
                      icon: Icons.graphic_eq_rounded,
                      label: 'Equalizer & Audio FX'),
                ),
                PopupMenuItem(
                  value: _PlayerMenuAction.screenshot,
                  child: _MoreRow(
                      icon: Icons.photo_camera_outlined,
                      label: 'Screenshot'),
                ),
                PopupMenuItem(
                  value: _PlayerMenuAction.cast,
                  child: _MoreRow(
                      icon: Icons.cast_rounded, label: 'Cast to TV'),
                ),
                PopupMenuItem(
                  value: _PlayerMenuAction.pip,
                  child: _MoreRow(
                      icon: Icons.picture_in_picture_alt_rounded,
                      label: 'Picture-in-Picture'),
                ),
                PopupMenuItem(
                  value: _PlayerMenuAction.sleep,
                  child: _MoreRow(
                      icon: Icons.nightlight_round,
                      label: 'Sleep timer'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MoreRow extends StatelessWidget {
  const _MoreRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 19, color: AppColors.accent),
        const SizedBox(width: 12),
        Text(label, style: const TextStyle(color: AppColors.textPrimary)),
      ],
    );
  }
}

class _CenterControls extends StatelessWidget {
  const _CenterControls({required this.player});

  final Player player;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: StreamBuilder<bool>(
        stream: player.stream.playing,
        initialData: player.state.playing,
        builder: (context, snap) {
          final playing = snap.data ?? false;
          return IconButton(
            iconSize: 68,
            color: Colors.white,
            icon: Icon(playing
                ? Icons.pause_circle_filled_rounded
                : Icons.play_circle_filled_rounded),
            onPressed: player.playOrPause,
          );
        },
      ),
    );
  }
}

class _BottomBar extends StatefulWidget {
  const _BottomBar({required this.player});

  final Player player;

  @override
  State<_BottomBar> createState() => _BottomBarState();
}

class _BottomBarState extends State<_BottomBar> {
  /// While the user drags, the slider tracks the FINGER (not the position
  /// stream) and live MPV seeks preview frames continuously — that is the
  /// "preview when sliding" and the buttery-smooth scrub.
  double? _dragMs;
  DateTime _lastLiveSeek = DateTime.fromMillisecondsSinceEpoch(0);
  Duration _lastSent = Duration.zero;

  void _liveSeek(Duration target) {
    final now = DateTime.now();
    if (now.difference(_lastLiveSeek).inMilliseconds > 120 &&
        (target - _lastSent).abs().inMilliseconds > 800) {
      _lastLiveSeek = now;
      _lastSent = target;
      widget.player.seek(target);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 12,
          bottom: MediaQuery.of(context).padding.bottom + 16,
        ),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Colors.black87, Colors.transparent],
          ),
        ),
        child: StreamBuilder<Duration>(
          stream: widget.player.stream.position,
          initialData: widget.player.state.position,
          builder: (context, posSnap) {
            final position = posSnap.data ?? Duration.zero;
            return StreamBuilder<Duration>(
              stream: widget.player.stream.duration,
              initialData: widget.player.state.duration,
              builder: (context, durSnap) {
                final duration = durSnap.data ?? Duration.zero;
                final maxMs = duration.inMilliseconds > 0
                    ? duration.inMilliseconds.toDouble()
                    : 1.0;
                final shownMs = (_dragMs ??
                        position.inMilliseconds.clamp(0, maxMs.toInt()))
                    .clamp(0.0, maxMs)
                    .toDouble();
                final shownDuration = _dragMs == null
                    ? position
                    : Duration(milliseconds: shownMs.round());
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: AppColors.accent,
                        inactiveTrackColor: Colors.white24,
                        thumbColor: Colors.white,
                        trackHeight: 2.5,
                        thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 6),
                        overlayShape: SliderComponentShape.noOverlay,
                      ),
                      child: Slider(
                        value: shownMs,
                        max: maxMs,
                        onChangeStart: (ms) =>
                            setState(() => _dragMs = ms),
                        onChanged: (ms) {
                          setState(() => _dragMs = ms);
                          _liveSeek(Duration(milliseconds: ms.round()));
                        },
                        onChangeEnd: (ms) {
                          widget.player
                              .seek(Duration(milliseconds: ms.round()));
                          setState(() => _dragMs = null);
                        },
                      ),
                    ),
                    Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 4),
                      child: Row(
                        mainAxisAlignment:
                            MainAxisAlignment.spaceBetween,
                        children: [
                          Text(formatDuration(shownDuration),
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 12)),
                          Text(formatDuration(duration),
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}
