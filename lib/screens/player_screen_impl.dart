import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../theme.dart';
import '../utils/ab_loop.dart';
import '../utils/crash_log.dart';
import '../utils/fit.dart';
import '../utils/format.dart';
import '../utils/mpv_filters.dart';
import '../utils/player_settings.dart';
import '../utils/resume.dart';
import '../utils/video_zoom.dart';
import 'player_settings_screen.dart';

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
  final Map<String, String> meta;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

enum _DragMode { undecided, brightness, volume, seek, pan, zoom, cant }

enum _PlayerMenuAction { info, eq, screenshot, cast, pip, sleep }

enum _SleepChoiceKind { off, minutes, untilEnd }

class _SleepChoice {
  const _SleepChoice._(this.kind, [this.minutes]);
  const _SleepChoice.off() : this._(_SleepChoiceKind.off);
  const _SleepChoice.untilEnd() : this._(_SleepChoiceKind.untilEnd);
  const _SleepChoice.minutes(int value) : this._(_SleepChoiceKind.minutes, value);

  final _SleepChoiceKind kind;
  final int? minutes;
}

class _PlayerScreenState extends State<PlayerScreen>
    with WidgetsBindingObserver {
  static const _native = MethodChannel('maxplayer/native');

  late final Player _player;
  late final VideoController _controller;
  final ResumeStore _resume = ResumeStore();
  final PlayerSettings _settings = PlayerSettings.instance;

  StreamSubscription<bool>? _playingSub;
  StreamSubscription<bool>? _bufferingSub;
  StreamSubscription<bool>? _completedSub;
  StreamSubscription<String>? _errorSub;
  Timer? _hideTimer;
  Timer? _saveTimer;
  Timer? _indicatorTimer;
  Timer? _sleepTimer;
  VoidCallback? _settingsListener;

  late String _title;
  String _currentPath = '';
  int _queueIndex = 0;
  bool _ready = false;
  bool _failed = false;
  bool _buffering = false;
  bool _controlsVisible = true;
  bool _boost = false;
  bool _locked = false;
  bool _muted = false;
  double _volumePercent = 100;
  FitMode _fitMode = FitMode.fit;

  _DragMode _drag = _DragMode.undecided;
  Offset _dragStart = Offset.zero;
  Offset _focalBase = Offset.zero;
  double _zoom = 1;
  double _zoomBase = 1;
  double _levelValue = 0;
  double _volumeStart = 100;
  double _brightnessStart = 0;
  Offset _pan = Offset.zero;
  Offset _panBase = Offset.zero;
  int _ladderBaseIndex = 0;
  int _scaleStartMs = 0;
  double _pinchTravelPx = 0;
  bool _pinchScaled = false;
  double _lastDoubleTapDx = 0;
  bool _rotationLocked = false;

  // Old-player transient "sign": one pill that pops in (scale + fade) for
  // every gesture/fit/lock message and fades back out after 900ms.
  String? _indicatorText;
  IconData? _indicatorIcon;
  String? _indicatorKey;
  Duration? _seekPreview;
  Duration _scrubStart = Duration.zero;
  int _lastSeekSecond = -1;

  AbState _ab = AbState.off;
  final List<double> _bands =
      List<double>.from(equalizerPresets['Flat'] ?? const [0, 0, 0, 0, 0]);
  bool _dialogueBoost = false;
  bool _enhance = false;
  bool _karaoke = false;
  String _toneMapping = 'auto';
  int _sleepMinutesLeft = 0;
  bool _sleepUntilEnd = false;
  bool _softwareDecodeRetried = false;

  // Scrub thumbnail strip (native MediaMetadataRetriever frames).
  String? _thumbStripFor;
  String? _thumbStripDir;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    // MX/VLC-style rotation: the player rotates by accelerometer even when
    // the phone's system auto-rotate switch is OFF.
    unawaited(_native.invokeMethod('enableSensorRotate'));
    _title = widget.title;
    _currentPath = widget.path;
    _queueIndex = widget.queueStart;
    _player = Player();
    _controller = VideoController(_player);
    _settingsListener = () {
      if (!mounted) return;
      setState(() {});
      if (_settings.autoHide && _player.state.playing) {
        _scheduleHide();
      } else if (!_settings.autoHide) {
        _hideTimer?.cancel();
      }
    };
    _settings.addListener(_settingsListener!);
    _native.setMethodCallHandler((call) async {
      if (call.method == 'pipToggle') {
        await _player.playOrPause();
      }
      return null;
    });
    unawaited(_settings.load().then((_) {
      if (!mounted) return;
      // Start the session in the fit mode chosen in Settings (default: Fit).
      setState(() {
        _fitMode =
            FitMode.values[_settings.defaultFit.clamp(0, FitMode.values.length - 1)];
      });
    }));
    _open(_currentPath, offerResume: true);
    _playingSub = _player.stream.playing.listen((playing) {
      if (playing) {
        WakelockPlus.enable();
        if (_settings.autoHide) _scheduleHide();
      } else {
        WakelockPlus.disable();
        unawaited(_savePosition());
      }
      unawaited(_syncBackgroundAudio(playing));
      unawaited(_native.invokeMethod('updatePipPlaying', {'playing': playing}));
      if (mounted) setState(() {});
    });
    _bufferingSub = _player.stream.buffering.listen((b) {
      if (mounted) setState(() => _buffering = b);
    });
    _completedSub = _player.stream.completed.listen((done) {
      if (done) {
        if (_sleepUntilEnd) {
          _sleepUntilEnd = false;
          if (mounted) setState(() {});
          _emitSnack('Sleep timer — video ended');
        }
        unawaited(_playNext());
      }
    });
    _errorSub = _player.stream.error.listen((e) {
      _onError(e);
    });
    _saveTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      unawaited(_savePosition());
    });
  }

  Future<void> _syncBackgroundAudio(bool playing) async {
    if (!_settings.backgroundAudio) {
      try {
        await _native.invokeMethod('setBackgroundAudio', {'enabled': false});
      } catch (_) {}
      return;
    }
    try {
      await _native.invokeMethod('setBackgroundAudio', {
        'enabled': playing,
        'title': _title,
      });
    } catch (_) {}
  }

  Future<void> _open(String path, {required bool offerResume}) async {
    CrashLog.crumb('player.open', {'path': path});
    try {
      await _player.open(Media(path), play: true);
      _volumePercent = _player.state.volume.clamp(0.0, 100.0);
      _muted = _volumePercent <= 0;
      if (mounted) setState(() => _ready = true);
      unawaited(_ensureThumbStrip(path));
      unawaited(_applyPerformanceMode());
      if (offerResume && _settings.resume && !widget.isStream) {
        unawaited(_offerResume());
      }
    } catch (e) {
      _onError(e);
    }
  }

  Future<void> _mpvSet(String key, String value) async {
    try {
      final platform = _player.platform;
      if (platform != null) {
        await (platform as dynamic).setProperty(key, value);
      }
    } catch (_) {}
  }

  // VLC-style low-end profile (old-player "Performance mode"): drop late
  // frames instead of letting A/V drift, and lighten software decode.
  static const Map<String, String> _kLowPerfProps = {
    'framedrop': 'decoder+vo',
    'vd-lavc-skiploopfilter': 'all',
    'vd-lavc-skipframe': 'nonref',
    'vd-lavc-skipidct': 'nonref',
  };
  static const Map<String, String> _kLowPerfRestore = {
    'framedrop': 'no',
    'vd-lavc-skiploopfilter': 'nonref',
    'vd-lavc-skipframe': 'default',
    'vd-lavc-skipidct': 'default',
  };
  bool _lowPerfActive = false;

  /// Applies PlayerSettings.performanceMode ('on' forces the profile;
  /// 'auto'/'off' keep mpv defaults - the old app's 'auto' only enabled it
  /// on low-RAM devices). Safe to call repeatedly.
  Future<void> _applyPerformanceMode() async {
    final want = _settings.performanceMode == 'on';
    if (want == _lowPerfActive) return;
    _lowPerfActive = want;
    final map = want ? _kLowPerfProps : _kLowPerfRestore;
    for (final e in map.entries) {
      unawaited(_mpvSet(e.key, e.value));
    }
  }

  Future<void> _savePosition() async {
    if (widget.isStream || !_settings.resume || !_ready || _failed) return;
    try {
      final pos = _player.state.position;
      final dur = _player.state.duration;
      if (pos <= Duration.zero) return;
      if (isFinishedMs(pos.inMilliseconds, dur.inMilliseconds)) {
        await _resume.clear(_currentPath);
      } else {
        await _resume.writeMs(_currentPath, pos.inMilliseconds);
      }
    } catch (e) {
      CrashLog.error('resume.save_failed', e, {'path': _currentPath});
    }
  }

  Future<void> _offerResume() async {
    try {
      final saved = await _resume.readMs(_currentPath);
      if (saved == null || !mounted) return;
      var duration = _player.state.duration;
      if (duration <= Duration.zero) {
        duration = await _player.stream.duration
            .firstWhere((d) => d > Duration.zero)
            .timeout(const Duration(seconds: 5), onTimeout: () => Duration.zero);
      }
      final target = resumeTargetMs(saved, duration.inMilliseconds);
      if (target == null || !mounted) return;
      final resume = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppColors.border),
          ),
          title: const Text('Resume playback?',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 17)),
          content: Text(
            'Continue from ${formatDuration(Duration(milliseconds: target))}?',
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Start over'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Resume'),
            ),
          ],
        ),
      );
      if (resume == true) {
        await _player.seek(Duration(milliseconds: target));
      } else if (resume == false) {
        await _resume.clear(_currentPath);
      }
    } catch (e) {
      CrashLog.error('resume.offer_failed', e, {'path': _currentPath});
    }
  }

  Future<void> _playPrevious() async {
    if (!mounted || widget.queueIds.isEmpty || _queueIndex <= 0) return;
    _queueIndex--;
    await _openQueueIndex();
  }

  Future<void> _playNext() async {
    if (!mounted || widget.queueIds.isEmpty || _queueIndex >= widget.queueIds.length - 1) {
      await _resume.clear(_currentPath);
      if (mounted) Navigator.of(context).maybePop();
      return;
    }
    _queueIndex++;
    await _openQueueIndex();
  }

  Future<void> _openQueueIndex() async {
    final id = widget.queueIds[_queueIndex];
    try {
      final asset = await AssetEntity.fromId(id);
      final file = await asset?.file;
      if (file == null || !file.existsSync()) {
        throw StateError('queue item unavailable: $id');
      }
      await _resume.clear(_currentPath);
      _currentPath = file.path;
      _softwareDecodeRetried = false;
      _title = asset?.title ?? 'Video';
      if (mounted) setState(() {});
      await _player.open(Media(file.path), play: true);
    } catch (e) {
      CrashLog.error('queue.next_failed', e, {'id': id});
      _emitSnack('Could not play the selected video in queue');
    }
  }

  void _onError(Object e) {
    if (_failed) return;
    unawaited(_recoverOrFail(e));
  }

  Future<void> _recoverOrFail(Object e) async {
    if (!_softwareDecodeRetried) {
      _softwareDecodeRetried = true;
      try {
        await _mpvSet('hwdec', 'no');
        await _player.open(Media(_currentPath), play: true);
        if (mounted) setState(() => _ready = true);
        return;
      } catch (e2) {
        CrashLog.error('player.sw_fallback_failed', e2);
      }
    }
    _failed = true;
    CrashLog.error('player.open_failed', e, {'path': _currentPath});
    if (!mounted) return;
    _emitSnack("This video can't be played by MPV");
    Navigator.of(context).maybePop();
  }

  void _toggleControls() {
    if (_locked) return;
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible && _settings.autoHide) _scheduleHide();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    if (!_settings.autoHide) return;
    _hideTimer = Timer(Duration(seconds: _settings.autoHideDelay), () {
      if (mounted && _player.state.playing && !_boost && !_locked) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  /// While the seek bar is dragged the auto-hide countdown pauses — the
  /// controls must never fade away mid-scrub (old-player behavior).
  void _onScrubChanged(bool scrubbing) {
    if (scrubbing) {
      _hideTimer?.cancel();
    } else if (_controlsVisible) {
      _scheduleHide();
    }
  }

  /// Whether the tracks (tune) button should show its "active" chip:
  /// subtitles on, more than one audio track, or an A-B loop in use.
  bool get _tracksActive =>
      _ab != AbState.off ||
      _player.state.track.subtitle.id != 'no' ||
      _player.state.tracks.audio.length > 1;

  void _onTap() {
    if (_locked) {
      _showLockHint();
      return;
    }
    _toggleControls();
  }

  void _lockScreen() {
    _hideTimer?.cancel();
    setState(() {
      _locked = true;
      _controlsVisible = false;
    });
    _showIndicator('Screen locked', Icons.lock);
  }

  void _unlockScreen() {
    setState(() {
      _locked = false;
      _controlsVisible = true;
    });
    _scheduleHide();
    _showIndicator('Unlocked', Icons.lock_open);
  }

  /// "Locked - double-tap the lock to unlock" (the old kids-mode hint).
  void _showLockHint() {
    _showIndicator('Locked - double-tap the lock to unlock', Icons.lock);
  }

  void _onDoubleTap() {
    final width = MediaQuery.of(context).size.width;
    final third = width / 3;
    final x = _lastDoubleTapDx;
    if (x < third) {
      if (!_settings.doubleTapSides) return;
      _seekRelative(-_settings.seekStep);
    } else if (x > width - third) {
      if (!_settings.doubleTapSides) return;
      _seekRelative(_settings.seekStep);
    } else {
      if (!_settings.doubleTapMiddle) return;
      final wasPlaying = _player.state.playing;
      unawaited(_player.playOrPause());
      _showIndicator(
        wasPlaying ? 'Paused' : 'Playing',
        wasPlaying ? Icons.pause_circle_outline : Icons.play_circle_outline,
      );
    }
  }

  void _seekRelative(int seconds) {
    var target = _player.state.position + Duration(seconds: seconds);
    final duration = _player.state.duration;
    if (target < Duration.zero) target = Duration.zero;
    if (duration > Duration.zero && target > duration) target = duration;
    unawaited(_player.seek(target));
    _flash(seconds);
  }

  void _flash(int seconds) {
    setState(() => _controlsVisible = true);
    if (_settings.autoHide) _scheduleHide();
    _showIndicator(
      '${seconds < 0 ? '' : '+'}${seconds}s',
      seconds < 0 ? Icons.replay_10 : Icons.forward_10,
    );
  }

  Future<void> _setVolumePercent(double value) async {
    final maxVolume = _settings.volumeBoost ? 200.0 : 100.0;
    final v = value.clamp(0.0, maxVolume).toDouble();
    _volumePercent = v;
    _muted = false;
    try {
      // Do not use MPV's audio-filter chain for volume boost. Invalid/unsupported
      // filter strings can make MPV report that the video cannot be played.
      // MPV's volume-max property safely allows software volume above 100%.
      await _mpvSet('volume-max', maxVolume.round().toString());
      if (v <= 100) {
        await _player.setVolume(v);
      } else {
        await _mpvSet('volume', v.toStringAsFixed(1));
      }
      await _mpvSet('af', combineAudioFilters(_bands,
          dialogueBoost: _dialogueBoost));
    } catch (e) {
      CrashLog.error('player.volume_failed', e, {'value': v});
      if (v <= 100) {
        await _player.setVolume(v);
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _toggleMute() async {
    if (_muted || _volumePercent <= 0) {
      final restore = _volumePercent <= 0
          ? 100.0
          : _volumePercent;
      await _setVolumePercent(restore);
      _muted = false;
    } else {
      await _player.setVolume(0);
      _muted = true;
      if (mounted) setState(() {});
    }
  }

  void _setBoost(bool on) {
    if (!_settings.longPressSpeed || _locked) return;
    // No boost (and no badge) while the video is paused - old-player rule.
    if (on && !_player.state.playing) return;
    _boost = on;
    unawaited(_player.setRate(on ? _settings.longPressRate : 1.0));
    if (mounted) setState(() {});
  }

  /// The old player's fit button: one tap steps to the NEXT fit in the
  /// six-mode loop (Fit -> Crop -> Stretch -> 16:9 -> 4:3 -> Original -> Fit).
  /// No sheet — cycling is the only selection UI, exactly like the old app.
  void _cycleFit() {
    setState(() {
      _fitMode = nextFitMode(_fitMode);
      _zoom = 1;
    });
    _emitGesture(_fitMode.icon, 'Fit: ${_fitMode.label}');
  }

  /// 16:9 / 4:3 force the FRAME inside the screen (Center + AspectRatio,
  /// engine-independent, identical in landscape and portrait — the old
  /// player's VLC-style resize). Other fit modes pass straight through.
  Widget _fitFrame({required Widget child}) {
    final asp = _fitMode.aspectRatio;
    if (asp == null) return child;
    return Center(child: AspectRatio(aspectRatio: asp, child: child));
  }

  /// Asks the native side for a strip of small JPEG frames (idempotent;
  /// cached per file). Once ready, [_scrubThumbPath] serves the scrub
  /// preview bubble.
  Future<void> _ensureThumbStrip(String path) async {
    if (widget.isStream || path.startsWith('http')) return;
    if (_thumbStripFor == path) return;
    _thumbStripFor = path;
    _thumbStripDir = null;
    try {
      final dir = await _native.invokeMethod<String>('thumbStripEnsure', {
        'path': path,
      });
      if (dir != null && _thumbStripFor == path && mounted) {
        setState(() => _thumbStripDir = dir);
      }
    } catch (_) {
      // Best effort - the bubble just shows the timestamp without a frame.
    }
  }

  /// Maps a 0..1 scrub fraction to a strip frame path (old-player style),
  /// or null until the strip is ready.
  String? _scrubThumbPath(double fraction) {
    final dir = _thumbStripDir;
    if (dir == null) return null;
    const count = 36;
    final i = (fraction.clamp(0.0, 1.0) * (count - 1)).round();
    return '$dir/f_${i.toString().padLeft(3, '0')}.jpg';
  }

  /// Two-finger tap: back to the user's default fit with any pinch
  /// zoom/pan undone.
  void _resetToFitScreen() {
    final fit =
        FitMode.values[_settings.defaultFit.clamp(0, FitMode.values.length - 1)];
    if (_zoom != 1.0 || _pan != Offset.zero || _fitMode != fit) {
      setState(() {
        _zoom = 1.0;
        _pan = Offset.zero;
        _fitMode = fit;
      });
    }
    _emitGesture(fit.icon, 'Fit: ${fit.label}');
  }

  /// Keep the scaled video covering the viewport (no drifting past edges).
  Offset _clampPan(Offset pan, double z) {
    final size = MediaQuery.of(context).size;
    final maxX = size.width * (z - 1);
    final maxY = size.height * (z - 1);
    return Offset(pan.dx.clamp(-maxX, 0.0), pan.dy.clamp(-maxY, 0.0));
  }

  void _onScaleStart(ScaleStartDetails d) {
    if (_locked) return;
    _drag = _DragMode.undecided;
    _dragStart = d.focalPoint;
    _focalBase = d.focalPoint;
    _zoomBase = _zoom;
    _panBase = _pan;
    _volumeStart = _volumePercent;
    _brightnessStart = _levelValue;
    _scaleStartMs = DateTime.now().millisecondsSinceEpoch;
    _pinchTravelPx = 0;
    _pinchScaled = false;
    _ladderBaseIndex = _fitMode.index;
    _seekPreview = null;
  }

  Future<void> _onScaleUpdate(ScaleUpdateDetails d) async {
    if (_locked) return;
    final screenSize = MediaQuery.of(context).size;

    // Two+ fingers -> the two-finger gesture: EITHER the six-fit loop
    // (pinch-to-zoom OFF) OR focal pinch-zoom + pan (pinch-to-zoom ON).
    // Exactly the old app's split - never both at once.
    if (d.pointerCount >= 2) {
      _drag = _DragMode.zoom;
      _pinchTravelPx += d.focalPointDelta.distance;
      if ((d.scale - 1.0).abs() > 0.05) _pinchScaled = true;

      if (!_settings.pinchZoom) {
        final pos = fitLadderPosFor(
            basePos: _ladderBaseIndex.toDouble(), scale: d.scale);
        final nextIndex = wrapFitLadderPos(pos, FitMode.values.length);
        if (nextIndex != _fitMode.index) {
          setState(() {
            _fitMode = FitMode.values[nextIndex];
            _zoom = kMinVideoZoom;
            _pan = Offset.zero;
          });
          _emitGesture(_fitMode.icon, 'Fit: ${_fitMode.label}');
        }
        return;
      }

      final z = freeZoomFor(baseZoom: _zoomBase, scale: d.scale);
      final contentV = (_focalBase - _panBase) / _zoomBase;
      final pan = _clampPan(d.localFocalPoint - contentV * z, z);
      if (z == _zoom && pan == _pan) return;
      setState(() {
        _zoom = z;
        _pan = pan;
      });
      if (d.scale != 1.0) {
        _emitGesture(Icons.pinch_outlined, 'Zoom ${z.toStringAsFixed(1)}x');
      }
      return;
    }

    // One finger drag.
    if (_drag == _DragMode.zoom || _drag == _DragMode.cant) return;

    if (_drag == _DragMode.pan) {
      if (_zoom <= 1.0) return;
      final pan =
          _clampPan(_panBase + (d.localFocalPoint - _focalBase), _zoom);
      if (pan != _pan) setState(() => _pan = pan);
      return;
    }

    final delta = d.focalPoint - _dragStart;
    if (_drag == _DragMode.undecided && delta.distance >= 14) {
      final width = screenSize.width;
      if (delta.dx.abs() > delta.dy.abs() * 1.3) {
        if (_zoom > 1.0) {
          _drag = _DragMode.pan;
          _panBase = _pan;
          _focalBase = d.focalPoint;
        } else if (_settings.horizontalSeek &&
            _player.state.duration > Duration.zero) {
          _drag = _DragMode.seek;
          _scrubStart = _player.state.position;
          _lastSeekSecond = -1;
          _seekPreview = null;
        } else {
          _drag = _DragMode.cant;
        }
      } else if (delta.dy.abs() >= delta.dx.abs()) {
        if (_dragStart.dx < width / 2 && _settings.swipeBrightness) {
          _drag = _DragMode.brightness;
          _brightnessStart = await ScreenBrightness.instance.application;
          _levelValue = _brightnessStart;
          _dragStart = d.focalPoint;
        } else if (_dragStart.dx >= width / 2 && _settings.swipeVolume) {
          _drag = _DragMode.volume;
          _volumeStart = _volumePercent;
          _dragStart = d.focalPoint;
        } else {
          _drag = _DragMode.cant;
        }
      }
      return;
    }

    final width = screenSize.width;
    if (_drag == _DragMode.brightness) {
      // Old player: a 300px sweep covers the full brightness range.
      final v =
          (_brightnessStart - (d.focalPoint.dy - _dragStart.dy) / 300.0)
              .clamp(0.0, 1.0)
              .toDouble();
      await ScreenBrightness.instance.setApplicationScreenBrightness(v);
      _levelValue = v;
      _showIndicatorThrottled('Brightness ${(v * 100).round()}%',
          Icons.brightness_6_outlined);
    } else if (_drag == _DragMode.volume) {
      // Old player: 300px covers 100%; with boost ON the range grows to
      // 0..200% (300 * cap pixels for the full range).
      final maxVolume = _settings.volumeBoost ? 200.0 : 100.0;
      final v = (_volumeStart -
              (d.focalPoint.dy - _dragStart.dy) / (300.0 * maxVolume / 100.0))
          .clamp(0.0, maxVolume)
          .toDouble();
      await _setVolumePercent(v);
      _showIndicatorThrottled(
        'Volume ${v.round()}%',
        v.round() == 0 ? Icons.volume_off : Icons.volume_up,
      );
    } else if (_drag == _DragMode.seek) {
      final duration = _player.state.duration;
      if (duration <= Duration.zero) return;
      // Seek relative to the exact point where the finger touched.
      // One screen width corresponds to +/-90 seconds.
      const secondsPerScreen = 90.0;
      final offsetSeconds =
          (d.focalPoint.dx - _dragStart.dx) / width * secondsPerScreen;
      var targetMs =
          _scrubStart.inMilliseconds + (offsetSeconds * 1000).round();
      targetMs = targetMs.clamp(0, duration.inMilliseconds);
      final target = Duration(milliseconds: targetMs);
      setState(() => _seekPreview = target);
      final diffMs = targetMs - _scrubStart.inMilliseconds;
      final sign = diffMs >= 0 ? '+' : '-';
      _showIndicatorThrottled(
        '$sign${(diffMs.abs() / 1000).round()}s · ${formatDuration(target)}',
        diffMs >= 0 ? Icons.fast_forward : Icons.fast_rewind,
      );
      // Live-seek in 1s steps while the finger moves (mpv is fine with it).
      final s = target.inSeconds;
      if ((s - _lastSeekSecond).abs() >= 1) {
        _lastSeekSecond = s;
        unawaited(_player.seek(Duration(seconds: s)));
      }
    }
  }

  void _emitGesture(IconData icon, String label) => _showIndicator(label, icon);

  /// Old-player transient indicator: shows the message for ~900ms with the
  /// pill's scale+fade entrance/exit animation.
  void _showIndicator(String text, [IconData? icon]) {
    if (!mounted) return;
    _indicatorTimer?.cancel();
    _indicatorKey = '$text|${icon?.codePoint ?? 0}';
    setState(() {
      _indicatorText = text;
      _indicatorIcon = icon;
    });
    _indicatorTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _indicatorText = null);
    });
  }

  /// Same as [_showIndicator] but an unchanged message only refreshes the
  /// hide timer (no setState flood while a drag keeps reporting the same
  /// percentage).
  void _showIndicatorThrottled(String text, [IconData? icon]) {
    if (!mounted) return;
    final key = '$text|${icon?.codePoint ?? 0}';
    if (key == _indicatorKey) {
      _indicatorTimer?.cancel();
      _indicatorTimer = Timer(const Duration(milliseconds: 900), () {
        if (mounted) setState(() => _indicatorText = null);
      });
      return;
    }
    _showIndicator(text, icon);
  }

  void _onScaleEnd(ScaleEndDetails _) {
    if (_locked) return;

    final drag = _drag;
    final preview = _seekPreview;

    if (drag == _DragMode.seek && preview != null) {
      unawaited(_player.seek(preview));
    }

    // A quick two-finger tap (no real pinch, no travel) snaps back to the
    // default fit screen - the old player's "double finger tap" reset.
    if (drag == _DragMode.zoom &&
        isTwoFingerTapReset(
          durationMs: DateTime.now().millisecondsSinceEpoch - _scaleStartMs,
          travelPx: _pinchTravelPx,
          scaled: _pinchScaled,
        )) {
      _resetToFitScreen();
    }

    if (mounted) {
      setState(() {
        _drag = _DragMode.undecided;
        _seekPreview = null;
      });
    }
  }

  String? get _sleepLabel {
    if (_sleepUntilEnd) return 'Sleep: Until end';
    if (_sleepTimer != null && _sleepMinutesLeft > 0) {
      return 'Sleep: $_sleepMinutesLeft min';
    }
    return null;
  }

  /// Short label for the three-dots menu, old-player style
  /// ('Sleep timer (12 min)' / 'Sleep timer (end of video)').
  String? get _sleepMenuLabel {
    if (_sleepUntilEnd) return 'Sleep timer (end of video)';
    if (_sleepTimer != null && _sleepMinutesLeft > 0) {
      return 'Sleep timer ($_sleepMinutesLeft min)';
    }
    return null;
  }

  Future<void> _showPlayerSettings() async {
    await PlayerSettingsSheet.show(context);
  }

  void _showTrackSheet() => _showExtrasSheet();

  Future<void> _showExtrasSheet() async {
    final tracks = _player.state.tracks;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: 10),
            children: [
              _SheetHandle(),
              _extraAction(
                icon: Icons.subtitles_rounded,
                title: 'Subtitles ${tracks.subtitle.isEmpty ? '(none)' : '(on)'}',
                onTap: () async {
                  Navigator.of(context).pop();
                  await _showTrackPicker(subtitle: true);
                  if (mounted) setState(() {});
                },
              ),
              _extraAction(
                icon: Icons.music_note_rounded,
                title: 'Audio track (${tracks.audio.length} available)',
                onTap: () async {
                  Navigator.of(context).pop();
                  await _showTrackPicker(subtitle: false);
                  if (mounted) setState(() {});
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
                onLongPress: _cancelAb,
              ),
              _extraToggle(
                icon: Icons.closed_caption_outlined,
                title: 'Karaoke subtitles',
                subtitle: 'Words light up - other subtitles hide while on',
                value: _karaoke,
                onChanged: (v) {
                  setSheet(() {});
                  unawaited(_toggleKaraoke(v));
                },
              ),
              _extraToggle(
                icon: Icons.auto_fix_high_rounded,
                title: 'Enhance video',
                subtitle: 'GPU sharpen + contrast + colour boost',
                value: _enhance,
                onChanged: (v) {
                  setSheet(() {});
                  unawaited(_toggleEnhance(v));
                },
              ),
              ListTile(
                leading: SizedBox(
                  width: 30,
                  child: Center(
                    child: Text('HDR',
                        style: TextStyle(
                            color: AppColors.accent,
                            fontSize: 10,
                            fontWeight: FontWeight.w800)),
                  ),
                ),
                title: const Text('HDR tone-mapping',
                    style: TextStyle(color: AppColors.textPrimary)),
                subtitle: const Text(
                  'How HDR10/Dolby sources fit your screen',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
                trailing: DropdownButton<String>(
                  value: _toneMapping,
                  dropdownColor: AppColors.surfaceAlt,
                  underline: const SizedBox.shrink(),
                  style: const TextStyle(color: AppColors.textPrimary),
                  items: const [
                    DropdownMenuItem(value: 'auto', child: Text('Auto')),
                    DropdownMenuItem(value: 'mobius', child: Text('Mobius')),
                    DropdownMenuItem(value: 'hable', child: Text('Hable')),
                    DropdownMenuItem(value: 'bt.2390', child: Text('BT.2390')),
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
                subtitle: 'Lifts quiet speech (1-4 kHz). Off by default.',
                value: _dialogueBoost,
                onChanged: (v) {
                  setSheet(() {});
                  _dialogueBoost = v;
                  unawaited(_applyAudioFilters());
                },
              ),
              const SizedBox(height: 12),
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
  }) {
    final tile = ListTile(
      leading: Icon(icon, color: AppColors.accent, size: 24),
      title: Text(title,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 16)),
      subtitle: subtitle == null
          ? null
          : Text(subtitle,
              style: const TextStyle(color: AppColors.textSecondary)),
      onTap: onTap,
      onLongPress: onLongPress,
    );
    return tile;
  }

  ListTile _extraToggle({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return ListTile(
      leading: Icon(icon, color: AppColors.accent, size: 24),
      title: Text(title,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 16)),
      subtitle: Text(subtitle,
          style: const TextStyle(color: AppColors.textSecondary)),
      trailing: Switch(value: value, onChanged: onChanged),
      onTap: () => onChanged(!value),
    );
  }

  Future<void> _showTrackPicker({required bool subtitle}) async {
    final tracks = subtitle
        ? _player.state.tracks.subtitle
        : _player.state.tracks.audio;
    final selected = subtitle ? _player.state.track.subtitle : _player.state.track.audio;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 10),
          children: [
            _SheetHandle(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(subtitle ? 'Subtitles' : 'Audio track',
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w700)),
            ),
            if (subtitle)
              _trackRow(
                name: 'Off',
                selected: (selected as dynamic).id == 'no',
                onTap: () async {
                  await _player.setSubtitleTrack(SubtitleTrack.no());
                  if (context.mounted) Navigator.of(context).pop();
                },
              ),
            for (final track in tracks)
              _trackRow(
                name: _trackLabel(track),
                selected: (selected as dynamic).id == (track as dynamic).id,
                onTap: () async {
                  if (subtitle) {
                    await _player.setSubtitleTrack(track as SubtitleTrack);
                  } else {
                    await _player.setAudioTrack(track as AudioTrack);
                  }
                  if (context.mounted) Navigator.of(context).pop();
                },
              ),
          ],
        ),
      ),
    );
  }

  String _trackLabel(dynamic track) {
    final parts = <String>[];
    final title = '${track.title}';
    final language = '${track.language}';
    final codec = '${track.codec}';
    if (title != 'null' && title.isNotEmpty) parts.add(title);
    if (language != 'null' && language.isNotEmpty) {
      parts.add(language.toUpperCase());
    }
    if (codec != 'null' && codec.isNotEmpty) parts.add(codec);
    return parts.isEmpty ? 'Track ${track.id}' : parts.join(' • ');
  }

  ListTile _trackRow({
    required String name,
    required bool selected,
    required Future<void> Function() onTap,
  }) {
    return ListTile(
      title: Text(name,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 16)),
      trailing: selected
          ? Icon(Icons.check_circle_rounded, color: AppColors.accent)
          : const Icon(Icons.radio_button_off_rounded,
              color: AppColors.textSecondary),
      onTap: () => unawaited(onTap()),
    );
  }

  void _cycleAbLoop() {
    _ab = _ab.advance(_player.state.position.inMilliseconds);
    switch (_ab.phase) {
      case AbPhase.off:
        unawaited(_mpvSet('ab-loop-a', 'no'));
        unawaited(_mpvSet('ab-loop-b', 'no'));
        break;
      case AbPhase.aSet:
        unawaited(_mpvSet('ab-loop-a', '${_ab.aMs! / 1000}'));
        unawaited(_mpvSet('ab-loop-b', 'no'));
        break;
      case AbPhase.abSet:
        unawaited(_mpvSet('ab-loop-a', '${_ab.aMs! / 1000}'));
        unawaited(_mpvSet('ab-loop-b', '${_ab.bMs! / 1000}'));
        break;
    }
    setState(() {});
    _emitSnack(_ab.describe());
  }

  void _cancelAb() {
    _ab = AbState.off;
    unawaited(_mpvSet('ab-loop-a', 'no'));
    unawaited(_mpvSet('ab-loop-b', 'no'));
    setState(() {});
  }

  Future<void> _toggleKaraoke(bool value) async {
    _karaoke = value;
    setState(() {});
    if (!value) {
      await _player.setSubtitleTrack(SubtitleTrack.no());
      return;
    }
    SubtitleTrack? ass;
    for (final track in _player.state.tracks.subtitle) {
      if ('${(track as dynamic).codec}'.toLowerCase() == 'ass') {
        ass = track;
        break;
      }
    }
    if (ass == null) {
      _karaoke = false;
      setState(() {});
      _emitSnack('No karaoke (ASS) subtitles inside this video');
      return;
    }
    await _player.setSubtitleTrack(ass);
    _emitSnack('Karaoke subtitles on');
  }

  Future<void> _toggleEnhance(bool value) async {
    _enhance = value;
    setState(() {});
    if (value) {
      await _setVideoFilters(true);
      _emitSnack('Enhance on — GPU sharpen + contrast boost');
    } else {
      await _setVideoFilters(false);
    }
  }

  Future<void> _setVideoFilters(bool enabled) async {
    if (enabled) {
      await _mpvSet('contrast', '14');
      await _mpvSet('saturation', '12');
      await _mpvSet('gamma', '2');
      await _mpvSet('vf', buildEnhanceFilter());
    } else {
      await _mpvSet('contrast', '0');
      await _mpvSet('saturation', '0');
      await _mpvSet('gamma', '0');
      await _mpvSet('vf', '');
    }
  }

  Future<void> _setToneMapping(String value) async {
    _toneMapping = value;
    setState(() {});
    await _mpvSet('tone-mapping', value);
  }

  Future<void> _applyAudioFilters() async {
    final base = combineAudioFilters(
      _bands,
      dialogueBoost: _dialogueBoost,
    );
    await _mpvSet('af', base);
    if (mounted) setState(() {});
  }

  void _showEqualizerSheet() {
    const labels = ['60 Hz', '230 Hz', '910 Hz', '3.6 kHz', '14 kHz'];
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
            child: ListView(
              shrinkWrap: true,
              children: [
                _SheetHandle(),
                const Text('Equalizer & Audio FX',
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final name in equalizerPresets.keys)
                      ChoiceChip(
                        label: Text(name),
                        selected: listEquals(
                            _bands, equalizerPresets[name]!),
                        onSelected: (_) {
                          for (var i = 0; i < _bands.length; i++) {
                            _bands[i] = equalizerPresets[name]![i];
                          }
                          unawaited(_applyAudioFilters());
                          setSheet(() {});
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                for (var i = 0; i < labels.length; i++)
                  Row(
                    children: [
                      SizedBox(
                        width: 56,
                        child: Text(labels[i],
                            style: const TextStyle(
                                color: AppColors.textSecondary, fontSize: 12)),
                      ),
                      Expanded(
                        child: Slider(
                          value: _bands[i],
                          min: -12,
                          max: 12,
                          divisions: 24,
                          onChanged: (value) {
                            _bands[i] = value;
                            unawaited(_applyAudioFilters());
                            setSheet(() {});
                          },
                        ),
                      ),
                      SizedBox(
                        width: 44,
                        child: Text(
                          '${_bands[i] >= 0 ? '+' : ''}${_bands[i].toStringAsFixed(0)} dB',
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showVideoInfo() {
    final state = _player.state;
    final rows = <MapEntry<String, String>>[
      ...widget.meta.entries,
      MapEntry('Source', widget.isStream ? 'Network stream' : _currentPath),
      MapEntry('Position',
          '${formatDuration(state.position)} / ${formatDuration(state.duration)}'),
      MapEntry('Remaining', formatDuration(state.duration - state.position)),
      MapEntry('Playback speed', '${state.rate}x'),
      if (state.videoParams.w != null && state.videoParams.h != null)
        MapEntry('Resolution',
            '${state.videoParams.w} × ${state.videoParams.h}'),
      if (state.audioBitrate != null)
        MapEntry('Audio bitrate', '${state.audioBitrate} bit/s'),
    ];

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (context) => SafeArea(
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: .62,
          minChildSize: .35,
          maxChildSize: .92,
          builder: (context, controller) => Column(
            children: [
              _SheetHandle(),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 4, 20, 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Video info',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  controller: controller,
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  children: [
                    Text(
                      _title,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    for (final row in rows)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(row.key,
                                style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 11.5)),
                            const SizedBox(height: 2),
                            SelectableText(row.value,
                                style: const TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 12.5)),
                          ],
                        ),
                      ),
                    const Divider(color: AppColors.border),
                    if (state.tracks.video.isNotEmpty)
                      const Text('Video tracks',
                          style: TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w700)),
                    for (final track in state.tracks.video)
                      Padding(
                        padding: const EdgeInsets.only(top: 5),
                        child: Text(_trackLabel(track),
                            style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12)),
                      ),
                    if (state.tracks.audio.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const Text('Audio tracks',
                          style: TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w700)),
                    ],
                    for (final track in state.tracks.audio)
                      Padding(
                        padding: const EdgeInsets.only(top: 5),
                        child: Text(_trackLabel(track),
                            style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12)),
                      ),
                    if (state.tracks.subtitle.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const Text('Subtitle tracks',
                          style: TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w700)),
                    ],
                    for (final track in state.tracks.subtitle)
                      Padding(
                        padding: const EdgeInsets.only(top: 5),
                        child: Text(_trackLabel(track),
                            style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12)),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _captureScreenshot() async {
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
    if (!_ready || _failed) {
      _emitSnack('Start the video before using Picture-in-Picture');
      return;
    }
    try {
      final video = _player.state.videoParams;
      setState(() => _controlsVisible = false);
      final ok = await _native.invokeMethod<bool>('enterPip', {
        'w': video.dw ?? 16,
        'h': video.dh ?? 9,
      });
      if (ok != true && mounted) {
        setState(() => _controlsVisible = true);
        _emitSnack('Picture-in-Picture is not available on this device');
      }
    } catch (e) {
      CrashLog.error('pip.failed', e);
      if (mounted) setState(() => _controlsVisible = true);
      _emitSnack('Picture-in-Picture could not be started');
    }
  }

  Future<void> _openCastSettings() async {
    try {
      await _native.invokeMethod<bool>('openCastSettings');
      _emitSnack('Pick your TV on the system screen-mirroring page');
    } catch (_) {
      _emitSnack('Open Android Settings → Connected devices → Cast');
    }
  }

  Future<void> _showSleepTimerSheet() async {
    const mins = [10, 15, 30, 45, 60];
    final picked = await showModalBottomSheet<_SleepChoice>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _SheetHandle(),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 6, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Sleep timer',
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w700)),
              ),
            ),
            if (_sleepTimer != null || _sleepUntilEnd)
              ListTile(
                title: const Text('Turn off timer',
                    style: TextStyle(color: AppColors.textPrimary)),
                onTap: () => Navigator.of(context).pop(_SleepChoice.off()),
              ),
            for (final min in mins)
              ListTile(
                title: Text('$min minutes',
                    style: const TextStyle(color: AppColors.textPrimary)),
                onTap: () => Navigator.of(context).pop(_SleepChoice.minutes(min)),
              ),
            ListTile(
              title: const Text('Until end',
                  style: TextStyle(color: AppColors.textPrimary)),
              subtitle: const Text(
                  'Pause when this video reaches the end',
                  style: TextStyle(color: AppColors.textSecondary)),
              onTap: () =>
                  Navigator.of(context).pop(_SleepChoice.untilEnd()),
            ),
          ],
        ),
      ),
    );
    if (picked == null) return;

    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepMinutesLeft = 0;
    _sleepUntilEnd = false;

    switch (picked.kind) {
      case _SleepChoiceKind.off:
        _emitSnack('Sleep timer off');
        break;
      case _SleepChoiceKind.minutes:
        final minutes = picked.minutes!;
        _sleepMinutesLeft = minutes;
        _sleepTimer = Timer(Duration(minutes: minutes), () {
          _player.pause();
          if (mounted) {
            setState(() {
              _sleepTimer = null;
              _sleepMinutesLeft = 0;
            });
          }
          _emitSnack('Sleep timer — playback paused');
        });
        _emitSnack('Sleeping in $minutes minutes');
        break;
      case _SleepChoiceKind.untilEnd:
        _sleepUntilEnd = true;
        _emitSnack('Sleep timer set until end');
        break;
    }
    if (mounted) setState(() {});
  }

  Future<void> _onMenuAction(_PlayerMenuAction action) async {
    switch (action) {
      case _PlayerMenuAction.info:
        _showVideoInfo();
        break;
      case _PlayerMenuAction.eq:
        _showEqualizerSheet();
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

  Future<void> _showPlaylistSheet() async {
    if (widget.queueIds.isEmpty) {
      _emitSnack('Playlist is empty');
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: .55,
          minChildSize: .3,
          maxChildSize: .9,
          builder: (context, controller) => Column(
            children: [
              _SheetHandle(),
              const Padding(
                padding: EdgeInsets.fromLTRB(18, 4, 18, 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Playlist', style: TextStyle(
                    color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  controller: controller,
                  itemCount: widget.queueIds.length,
                  itemBuilder: (context, index) => ListTile(
                    leading: CircleAvatar(
                      radius: 17,
                      backgroundColor: AppColors.surfaceAlt,
                      child: Text('${index + 1}', style: const TextStyle(color: AppColors.textSecondary)),
                    ),
                    title: FutureBuilder<AssetEntity?>(
                      future: AssetEntity.fromId(widget.queueIds[index]),
                      builder: (context, snapshot) => Text(
                        snapshot.data?.title ?? 'Video ${index + 1}',
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.textPrimary)),
                    ),
                    trailing: index == _queueIndex
                        ? Icon(Icons.play_arrow_rounded, color: AppColors.accent)
                        : null,
                    onTap: () async {
                      Navigator.of(sheetContext).pop();
                      if (index == _queueIndex) return;
                      _queueIndex = index;
                      await _openQueueIndex();
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Old-player rotation button: LOCK pins the current landscape/portrait;
  /// UNLOCK hands back the accelerometer sensor rotation. Sensor rotation
  /// is already enabled while the player is open (see initState), exactly
  /// like the old app - the system auto-rotate switch is ignored.
  Future<void> _toggleRotationLock() async {
    try {
      if (_rotationLocked) {
        await _native.invokeMethod<bool>('enableSensorRotate');
        if (!mounted) return;
        setState(() => _rotationLocked = false);
        _showIndicator('Auto-rotate on', Icons.screen_rotation);
      } else {
        final landscape = MediaQuery.of(context).orientation ==
            Orientation.landscape;
        await _native.invokeMethod<bool>('lockRotation', {
          'landscape': landscape,
        });
        if (!mounted) return;
        setState(() => _rotationLocked = true);
        _showIndicator('Rotation locked', Icons.screen_lock_rotation);
      }
    } catch (e) {
      CrashLog.error('rotation.lock_failed', e);
      _emitSnack('Rotation lock is not available');
    }
  }

  void _emitSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _sleepTimer?.cancel();
    _hideTimer?.cancel();
    _indicatorTimer?.cancel();
    _saveTimer?.cancel();
    _playingSub?.cancel();
    _bufferingSub?.cancel();
    _completedSub?.cancel();
    _errorSub?.cancel();
    if (_settingsListener != null) _settings.removeListener(_settingsListener!);
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_native.invokeMethod('disableSensorRotate'));
    WakelockPlus.disable();
    ScreenBrightness.instance.resetApplicationScreenBrightness();
    unawaited(_savePosition());
    unawaited(_player.dispose());
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      unawaited(_savePosition());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // While locked every gesture collapses to a lock hint (old player).
        onTap: _onTap,
        onDoubleTapDown: _locked
            ? null
            : (d) => _lastDoubleTapDx = d.localPosition.dx,
        onDoubleTap: _locked ? null : _onDoubleTap,
        onLongPressStart: _locked ? null : (_) => _setBoost(true),
        onLongPressEnd: _locked ? null : (_) => _setBoost(false),
        onLongPressCancel: _locked ? null : () => _setBoost(false),
        onScaleStart: _locked ? (_) => _showLockHint() : _onScaleStart,
        onScaleUpdate: _locked
            ? null
            : (details) => unawaited(_onScaleUpdate(details)),
        onScaleEnd: _locked ? null : _onScaleEnd,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_ready && !_failed)
              ClipRect(
                child: Transform.translate(
                  offset: _pan,
                  child: Transform.scale(
                    scale: _zoom,
                    child: _fitFrame(
                      child: Video(
                        controller: _controller,
                        fit: _fitMode.boxFit,
                        aspectRatio: null,
                        controls: NoVideoControls,
                      ),
                    ),
                  ),
                ),
              )
            else
              const Center(child: CircularProgressIndicator(color: Colors.white)),
            if (_buffering && _ready)
              const Center(
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              ),
            Align(
              alignment: const Alignment(0, -.72),
              child: IgnorePointer(
                child: Center(
                  child: AnimatedScale(
                    scale: _indicatorText != null ? 1.0 : 0.85,
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutBack,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOutCubic,
                      opacity: _indicatorText != null ? 1.0 : 0.0,
                      child: _IndicatorPill(
                        icon: _indicatorIcon ?? Icons.touch_app_rounded,
                        label: _indicatorText ?? '',
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // v20: BIG centred speed sign for the WHOLE long-press boost
            // (old look: accent pill + fast-forward icon, scale+fade in/out).
            Positioned.fill(
              child: IgnorePointer(
                child: Center(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 160),
                    transitionBuilder: (child, anim) => FadeTransition(
                      opacity: anim,
                      child: ScaleTransition(scale: anim, child: child),
                    ),
                    child: _boost
                        ? _BoostBadge(
                            key: const ValueKey('speedBadge'),
                            label: '${_settings.longPressRate}x',
                          )
                        : const SizedBox.shrink(key: ValueKey('noSpeedBadge')),
                  ),
                ),
              ),
            ),
            // Screen-lock ENTER chip (left edge, shown with the controls,
            // MX-Player style).
            Positioned(
              left: 4,
              top: 0,
              bottom: 0,
              child: IgnorePointer(
                ignoring: !(_controlsVisible &&
                    !_locked &&
                    _settings.screenLock),
                child: AnimatedOpacity(
                  opacity: (_controlsVisible && !_locked && _settings.screenLock)
                      ? 1.0
                      : 0.0,
                  duration: const Duration(milliseconds: 180),
                  child: Center(
                    child: _LockChip(
                      icon: Icons.lock_open_outlined,
                      onTap: _lockScreen,
                    ),
                  ),
                ),
              ),
            ),
            // Screen-lock EXIT chip (right edge, always visible while locked).
            if (_locked)
              Positioned(
                right: 4,
                top: 0,
                bottom: 0,
                child: Center(
                  child: _LockChip(
                    icon: Icons.lock,
                    onTap: _showLockHint,
                    onDoubleTap: _unlockScreen,
                    onLongPress: _unlockScreen,
                  ),
                ),
              ),
            // Top bar: slides down + fades in/out with the controls.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: IgnorePointer(
                ignoring: !_controlsVisible,
                child: AnimatedSlide(
                  offset: (_controlsVisible && !_locked)
                      ? Offset.zero
                      : const Offset(0, -0.5),
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  child: AnimatedOpacity(
                    opacity: (_controlsVisible && !_locked) ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 180),
                    child: _TopBar(
                      title: _title,
                      sleepLabel: _sleepLabel,
                      sleepMenuLabel: _sleepMenuLabel,
                      onSettings: _showPlayerSettings,
                      onMenu: (action) => unawaited(_onMenuAction(action)),
                    ),
                  ),
                ),
              ),
            ),
            // Bottom controls: slide up + fade in/out with the controls.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: IgnorePointer(
                ignoring: !_controlsVisible,
                child: AnimatedSlide(
                  offset: (_controlsVisible && !_locked)
                      ? Offset.zero
                      : const Offset(0, 0.45),
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  child: AnimatedOpacity(
                    opacity: (_controlsVisible && !_locked) ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 180),
                    child: _BottomBar(
                      player: _player,
                      isMuted: _muted,
                      tracksActive: _tracksActive,
                      onTrackSheet: _showTrackSheet,
                      onQueue: _showPlaylistSheet,
                      onRotate: _toggleRotationLock,
                      rotationLocked: _rotationLocked,
                      onFit: _cycleFit,
                      onMute: _toggleMute,
                      onScrubbing: _onScrubChanged,
                      previewThumb: _scrubThumbPath,
                      canSkip: widget.queueIds.length > 1,
                      onPrevious: _playPrevious,
                      onNext: _playNext,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.title,
    required this.sleepLabel,
    required this.sleepMenuLabel,
    required this.onSettings,
    required this.onMenu,
  });

  final String title;
  final String? sleepLabel;
  final String? sleepMenuLabel;
  final VoidCallback onSettings;
  final ValueChanged<_PlayerMenuAction> onMenu;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 2,
        left: 2,
        right: 2,
        bottom: 14,
      ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withValues(alpha: 0.75),
              Colors.transparent,
            ],
          ),
        ),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Back',
              icon: Icon(Icons.arrow_back, size: 22, color: AppColors.accent),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _LoopingTitle(title: title),
                  if (sleepLabel != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.bedtime_outlined,
                              size: 11, color: AppColors.accent),
                          const SizedBox(width: 4),
                          Text(
                            sleepLabel!,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.accent,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            PopupMenuButton<_PlayerMenuAction>(
              tooltip: 'More actions',
              icon: Icon(Icons.more_vert, size: 22, color: AppColors.accent),
              color: const Color(0xFF1a1a24),
              elevation: 8,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              onSelected: onMenu,
              itemBuilder: (context) => [
                _topMenuItem(_PlayerMenuAction.info,
                    Icons.info_outline, 'Video info'),
                _topMenuItem(_PlayerMenuAction.eq,
                    Icons.graphic_eq, 'Equalizer & Audio FX'),
                _topMenuItem(_PlayerMenuAction.screenshot,
                    Icons.camera_alt_outlined, 'Screenshot'),
                _topMenuItem(
                    _PlayerMenuAction.cast, Icons.cast_outlined, 'Cast to TV'),
                _topMenuItem(_PlayerMenuAction.pip,
                    Icons.picture_in_picture_alt_outlined, 'Picture-in-Picture'),
                _topMenuItem(
                    _PlayerMenuAction.sleep,
                    Icons.bedtime_outlined,
                    sleepMenuLabel ?? 'Sleep timer'),
              ],
            ),
            IconButton(
              tooltip: 'Player settings',
              icon: Icon(Icons.settings_outlined,
                  size: 22, color: AppColors.accent),
              onPressed: onSettings,
            ),
          ],
        ),
      );
  }

  PopupMenuItem<_PlayerMenuAction> _topMenuItem(
      _PlayerMenuAction value, IconData icon, String label) {
    return PopupMenuItem(
      value: value,
      height: 44,
      child: Row(
        children: [
          Icon(icon, size: 19, color: AppColors.accent),
          const SizedBox(width: 12),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _LoopingTitle extends StatefulWidget {
  const _LoopingTitle({required this.title});

  final String title;

  @override
  State<_LoopingTitle> createState() => _LoopingTitleState();
}

class _LoopingTitleState extends State<_LoopingTitle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  double _textWidth = 0;
  bool _scrolling = false;

  static const _style = TextStyle(
    color: Colors.white,
    fontSize: 15.5,
    fontWeight: FontWeight.w600,
  );
  static const _gap = 42.0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    );
  }

  @override
  void didUpdateWidget(covariant _LoopingTitle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.title != widget.title) {
      _controller.stop();
      _controller.reset();
      _scrolling = false;
      _textWidth = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: widget.title, style: _style),
          textDirection: TextDirection.ltr,
          maxLines: 1,
        )..layout();

        final shouldScroll = painter.width > constraints.maxWidth;
        if (shouldScroll != _scrolling || painter.width != _textWidth) {
          _textWidth = painter.width;
          _scrolling = shouldScroll;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            if (_scrolling) {
              final distance = _textWidth + _gap;
              _controller.duration = Duration(
                milliseconds:
                    (distance / 34 * 1000).round().clamp(5000, 16000),
              );
              if (!_controller.isAnimating) _controller.repeat();
            } else {
              _controller.stop();
              _controller.reset();
            }
          });
        }

        if (!shouldScroll) {
          return Text(
            widget.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _style,
          );
        }

        final distance = _textWidth + _gap;
        return ClipRect(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final offset = -(_controller.value * distance);
              return Transform.translate(
                offset: Offset(offset, 0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(widget.title, style: _style, maxLines: 1),
                    const SizedBox(width: _gap),
                    Text(widget.title, style: _style, maxLines: 1),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _BottomBar extends StatefulWidget {
  const _BottomBar({
    required this.player,
    required this.isMuted,
    required this.tracksActive,
    required this.onTrackSheet,
    required this.onQueue,
    required this.onRotate,
    required this.rotationLocked,
    required this.onFit,
    required this.onMute,
    required this.onScrubbing,
    required this.previewThumb,
    required this.canSkip,
    required this.onPrevious,
    required this.onNext,
  });

  final Player player;
  final bool isMuted;
  final bool tracksActive;
  final VoidCallback onTrackSheet;
  final VoidCallback onQueue;
  final VoidCallback onRotate;
  final bool rotationLocked;
  final VoidCallback onFit;
  final VoidCallback onMute;
  final ValueChanged<bool> onScrubbing;

  /// Maps a 0..1 scrub fraction to a thumbnail-frame path (old 36-frame
  /// strip), or null while the strip isn't ready.
  final String? Function(double fraction)? previewThumb;
  final bool canSkip;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  State<_BottomBar> createState() => _BottomBarState();
}

class _BottomBarState extends State<_BottomBar> {
  double? _dragValue; // 0..1 while the user scrubs the seek bar

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.transparent,
              Colors.black.withValues(alpha: 0.85),
            ],
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _progressBar(),
            // Row 1: previous / play-pause / next — the transport trio. These
            // three stay white; the theme accent shows only as the press flash
            // behind them (old-player look).
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _iconBtn(
                  icon: Icons.skip_previous,
                  size: 30,
                  accentPress: true,
                  tooltip: 'Previous video',
                  onTap: widget.canSkip ? widget.onPrevious : null,
                ),
                const SizedBox(width: 22),
                _playPause(),
                const SizedBox(width: 22),
                _iconBtn(
                  icon: Icons.skip_next,
                  size: 30,
                  accentPress: true,
                  tooltip: 'Next video',
                  onTap: widget.canSkip ? widget.onNext : null,
                ),
              ],
            ),
            // Row 2 (compact): mute speed tracks | queue fit rotate.
            Row(
              children: [
                _iconBtn(
                  icon: widget.isMuted ? Icons.volume_off : Icons.volume_up,
                  active: widget.isMuted,
                  tooltip: 'Mute',
                  onTap: widget.onMute,
                  compact: true,
                ),
                _speedMenu(),
                _iconBtn(
                  tooltip: 'Subtitles, audio tracks, A-B loop, karaoke',
                  icon: Icons.tune,
                  active: widget.tracksActive,
                  onTap: widget.onTrackSheet,
                  compact: true,
                ),
                const Spacer(),
                _iconBtn(
                  icon: Icons.queue_music,
                  tooltip: 'Queue',
                  onTap: widget.onQueue,
                  compact: true,
                ),
                _iconBtn(
                  tooltip: 'Fit: Fit / Crop / Stretch / 16:9 / 4:3 / Original',
                  icon: Icons.aspect_ratio,
                  onTap: widget.onFit,
                  compact: true,
                ),
                _iconBtn(
                  tooltip: widget.rotationLocked
                      ? 'Rotation locked - tap for auto'
                      : 'Auto-rotate - tap to lock',
                  icon: widget.rotationLocked
                      ? Icons.screen_lock_rotation
                      : Icons.screen_rotation,
                  active: widget.rotationLocked,
                  onTap: widget.onRotate,
                  compact: true,
                ),
              ],
            ),
          ],
        ),
      );
  }

  Widget _playPause() {
    return StreamBuilder<bool>(
      stream: widget.player.stream.playing,
      initialData: widget.player.state.playing,
      builder: (context, snapshot) {
        final playing = snapshot.data ?? false;
        return _iconBtn(
          icon: playing
              ? Icons.pause_circle_filled
              : Icons.play_circle_filled,
          size: 46,
          accentPress: true,
          onTap: widget.player.playOrPause,
        );
      },
    );
  }

  /// v22-old speed popup: 0.5x .. 3.0x, anchored to the accent-coloured label.
  Widget _speedMenu() {
    return StreamBuilder<double>(
      stream: widget.player.stream.rate,
      initialData: widget.player.state.rate,
      builder: (context, snapshot) {
        final rate = snapshot.data ?? 1.0;
        return PopupMenuButton<double>(
          initialValue: rate,
          color: const Color(0xFF1a1a24),
          onSelected: (r) => widget.player.setRate(r),
          itemBuilder: (context) =>
              const [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0]
                  .map((r) => PopupMenuItem(
                        value: r,
                        child: Text('${r}x',
                            style: const TextStyle(color: Colors.white)),
                      ))
                  .toList(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
            child: Text('${rate}x',
                style: TextStyle(color: AppColors.accent, fontSize: 11)),
          ),
        );
      },
    );
  }

  /// The seek slider + time labels. While the user DRAGS, a bubble floats
  /// above the thumb with the exact timestamp (the old player also showed a
  /// video-frame thumbnail here; that needs the background thumbnailer,
  /// which lands in a later drop).
  Widget _progressBar() {
    return StreamBuilder<Duration>(
      stream: widget.player.stream.position,
      initialData: widget.player.state.position,
      builder: (context, posSnapshot) {
        return StreamBuilder<Duration>(
          stream: widget.player.stream.duration,
          initialData: widget.player.state.duration,
          builder: (context, durSnapshot) {
            final position = posSnapshot.data ?? Duration.zero;
            final duration = durSnapshot.data ?? Duration.zero;
            final totalMs = duration.inMilliseconds.clamp(1, 1 << 62);
            final value = _dragValue ??
                (position.inMilliseconds / totalMs).clamp(0.0, 1.0);
            final shownMs = (_dragValue != null
                    ? _dragValue! * totalMs
                    : position.inMilliseconds)
                .round();
            return Row(
              children: [
                Text(formatDuration(Duration(milliseconds: shownMs)),
                    style: _timeStyle),
                const SizedBox(width: 4),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, c) {
                      final w = c.maxWidth;
                      const bubbleW = 132.0;
                      final dragging = _dragValue != null;
                      final rawLeft = dragging
                          ? _dragValue! * (w - 28) + 14 - bubbleW / 2
                          : 0.0;
                      final left = rawLeft
                          .clamp(0.0, (w - bubbleW).clamp(0.0, w))
                          .toDouble();
                      return Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.center,
                        children: [
                          SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 3,
                              thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 6),
                              overlayShape: const RoundSliderOverlayShape(
                                  overlayRadius: 14),
                              activeTrackColor: AppColors.accent,
                              inactiveTrackColor:
                                  Colors.white.withValues(alpha: 0.15),
                              thumbColor: AppColors.accent,
                            ),
                            child: Slider(
                              value: value,
                              onChangeStart: (v) {
                                widget.onScrubbing(true);
                                setState(() => _dragValue = v);
                              },
                              onChanged: (v) =>
                                  setState(() => _dragValue = v),
                              onChangeEnd: (v) {
                                widget.player.seek(Duration(
                                    milliseconds: (v * totalMs).round()));
                                setState(() => _dragValue = null);
                                widget.onScrubbing(false);
                              },
                            ),
                          ),
                          if (dragging)
                            Positioned(
                              bottom: 30,
                              left: left,
                              child: IgnorePointer(
                                child: _ScrubBubble(
                                  time: Duration(milliseconds: shownMs),
                                  thumbPath: widget.previewThumb
                                      ?.call(_dragValue!),
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(width: 4),
                Text(formatDuration(duration), style: _timeStyle),
              ],
            );
          },
        );
      },
    );
  }

  /// One control button. Every button follows the picked theme accent,
  /// EXCEPT the transport trio (accentPress), which stays white and only
  /// flashes the accent while pressed. An "on" state (muted, tracks in use,
  /// rotation locked) sits on a translucent accent chip.
  Widget _iconBtn({
    required IconData icon,
    VoidCallback? onTap,
    bool active = false,
    double size = 24,
    bool compact = false,
    String? tooltip,
    bool accentPress = false,
  }) {
    final accent = AppColors.accent;
    final enabled = onTap != null;
    final IconData shownIcon = icon;
    final Color color = accentPress
        ? (enabled ? Colors.white : Colors.white38)
        : accent;
    return IconButton(
      tooltip: tooltip,
      icon: Icon(shownIcon, size: compact ? 20 : size, color: color),
      splashColor: accentPress ? accent.withValues(alpha: 0.45) : null,
      highlightColor: accentPress ? accent.withValues(alpha: 0.28) : null,
      style: active
          ? ButtonStyle(
              backgroundColor:
                  WidgetStateProperty.all(accent.withValues(alpha: 0.22)),
            )
          : null,
      constraints: compact
          ? const BoxConstraints.tightFor(width: 34, height: 40)
          : null,
      padding: compact ? EdgeInsets.zero : null,
      visualDensity: compact ? VisualDensity.compact : null,
      onPressed: enabled ? onTap : null,
    );
  }

  static const _timeStyle = TextStyle(fontSize: 12, color: Colors.white70);
}

class _LockChip extends StatelessWidget {
  const _LockChip({
    required this.icon,
    required this.onTap,
    this.onDoubleTap,
    this.onLongPress,
  });

  final IconData icon;
  final VoidCallback onTap;
  final VoidCallback? onDoubleTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: .3),
      shape: const CircleBorder(side: BorderSide(color: Colors.white30)),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        onDoubleTap: onDoubleTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }
}

/// The old player's seek bubble: a video-frame thumbnail from the 36-frame
/// strip above the exact timestamp. Falls back to a dark placeholder until
/// the native strip is ready.
class _ScrubBubble extends StatelessWidget {
  const _ScrubBubble({required this.time, this.thumbPath});

  final Duration time;
  final String? thumbPath;

  @override
  Widget build(BuildContext context) {
    const bubbleW = 132.0;
    return Container(
      width: bubbleW,
      padding: const EdgeInsets.fromLTRB(5, 5, 5, 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              width: bubbleW - 10,
              height: (bubbleW - 10) * 9 / 16,
              child: thumbPath != null
                  ? Image.file(
                      File(thumbPath!),
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      // Frames can arrive mid-drag.
                      errorBuilder: (_, _, _) => const _NoThumb(),
                    )
                  : const _NoThumb(),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            formatDuration(time),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _NoThumb extends StatelessWidget {
  const _NoThumb();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1e1e2a),
      alignment: Alignment.center,
      child: const Icon(
        Icons.movie_outlined,
        color: Colors.white24,
        size: 18,
      ),
    );
  }
}

/// The old player's transient indicator: a pill that pops with scale+fade,
/// accent icon + accent border, values swap instantly.
class _IndicatorPill extends StatelessWidget {
  const _IndicatorPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF161622).withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: AppColors.accent.withValues(alpha: 0.35),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppColors.accent, size: 20),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14.5,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// Big centred speed badge shown for the whole long-press boost (old look).
class _BoostBadge extends StatelessWidget {
  const _BoostBadge({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.fast_forward, color: AppColors.onAccent, size: 19),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: AppColors.onAccent,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 38,
        height: 4,
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: AppColors.textSecondary.withValues(alpha: .5),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}
