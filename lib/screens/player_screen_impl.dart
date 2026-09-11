import 'dart:async';

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

enum _DragMode { none, brightness, volume, seek, zoom }

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
  Timer? _flashTimer;
  Timer? _sleepTimer;
  Timer? _lockedHintTimer;
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

  _DragMode _drag = _DragMode.none;
  Offset _dragStart = Offset.zero;
  double _zoom = 1;
  double _zoomStart = 1;
  double _levelValue = 0;
  double _volumeStart = 100;
  double _brightnessStart = 0;
  bool _gestureActive = false;
  bool _lockedHintVisible = false;
  bool _rotationLocked = false;
  bool _twoFingerFitGesture = false;
  bool _twoFingerFitDidCycle = false;
  IconData _gestureIcon = Icons.touch_app_rounded;
  String _gestureLabel = '';
  Duration? _seekPreview;
  Duration _scrubStart = Duration.zero;
  Duration _lastSentSeek = Duration.zero;
  DateTime _lastLiveSeek = DateTime.fromMillisecondsSinceEpoch(0);
  int? _seekFlash;

  AbState _ab = AbState.off;
  final List<double> _bands =
      List<double>.from(equalizerPresets['Flat'] ?? const [0, 0, 0, 0, 0]);
  bool _dialogueBoost = false;
  bool _enhance = false;
  bool _karaoke = false;
  String _toneMapping = 'auto';
  DateTime? _sleepDeadline;
  bool _sleepUntilEnd = false;
  bool _softwareDecodeRetried = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
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
    unawaited(_settings.load());
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
      if (!done) return;
      if (_sleepUntilEnd) {
        _sleepUntilEnd = false;
        _sleepTimer?.cancel();
        _sleepTimer = null;
        _sleepDeadline = null;
        if (mounted) setState(() {});
        _emitSnack('Sleep timer — video ended');
        return;
      }
      unawaited(_playNext());
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

  void _onTap() {
    if (_locked) {
      _lockedHintTimer?.cancel();
      setState(() => _lockedHintVisible = true);
      _lockedHintTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() => _lockedHintVisible = false);
      });
      return;
    }
    _toggleControls();
  }

  void _onDoubleTap(TapDownDetails details) {
    if (_locked) {
      setState(() {
        _locked = false;
        _lockedHintVisible = false;
        _controlsVisible = true;
      });
      _scheduleHide();
      return;
    }
    final width = MediaQuery.of(context).size.width;
    final x = details.globalPosition.dx;
    if (x < width * .35 && _settings.doubleTapSides) {
      _seekRelative(-_settings.seekStep, true);
    } else if (x > width * .65 && _settings.doubleTapSides) {
      _seekRelative(_settings.seekStep, false);
    } else if (x >= width * .35 && x <= width * .65 &&
        _settings.doubleTapMiddle) {
      _player.playOrPause();
    }
  }

  void _seekRelative(int seconds, bool left) {
    var target = _player.state.position + Duration(seconds: seconds);
    final duration = _player.state.duration;
    if (target < Duration.zero) target = Duration.zero;
    if (duration > Duration.zero && target > duration) target = duration;
    _player.seek(target);
    _flash(seconds);
  }

  void _flash(int seconds) {
    _flashTimer?.cancel();
    _lockedHintTimer?.cancel();
    setState(() {
      _seekFlash = seconds;
      _controlsVisible = true;
      _gestureActive = true;
    });
    if (_settings.autoHide) _scheduleHide();
    _flashTimer = Timer(const Duration(milliseconds: 650), () {
      if (mounted) {
        setState(() {
          _seekFlash = null;
          _gestureActive = false;
        });
      }
    });
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

  Future<void> _showSpeedSheet() async {
    const rates = <double>[0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0];
    final current = _player.state.rate;
    final picked = await showModalBottomSheet<double>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _SheetHandle(),
            const Padding(
              padding: EdgeInsets.fromLTRB(18, 4, 18, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Playback speed',
                    style: TextStyle(color: AppColors.textPrimary,
                        fontSize: 18, fontWeight: FontWeight.w700)),
              ),
            ),
            for (final rate in rates)
              ListTile(
                title: Text('${rate}x',
                    style: const TextStyle(color: AppColors.textPrimary)),
                trailing: (rate - current).abs() < .001
                    ? Icon(Icons.check_rounded, color: AppColors.accent)
                    : null,
                onTap: () => Navigator.of(context).pop(rate),
              ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    await _player.setRate(picked);
    if (mounted) setState(() {});
  }

  void _setBoost(bool on) {
    if (!_settings.longPressSpeed || _locked) return;
    _boost = on;
    unawaited(_player.setRate(on ? _settings.longPressRate : 1.0));
    if (mounted) setState(() {});
  }


  /// Advances the fit mode by [delta] (+1 next, -1 previous) and resets any
  /// manual pinch-zoom. Shared by the fit button and the pinch-cycle gesture.
  void _cycleFit(int delta) {
    final values = FitMode.values;
    setState(() {
      _fitMode = values[cycleIndex(_fitMode.index, values.length, delta)];
      _zoom = 1;
    });
    _emitGesture(Icons.fit_screen_rounded, _fitMode.label);
  }

  void _showFitMenu() {
    if (!_settings.pinchZoom) {
      _cycleFit(1);
      return;
    }

    showModalBottomSheet<FitMode>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _SheetHandle(),
            const ListTile(
              title: Text('Screen fit', style: TextStyle(
                  color: AppColors.textPrimary, fontSize: 18,
                  fontWeight: FontWeight.w700)),
            ),
            for (final mode in FitMode.values)
              ListTile(
                leading: Icon(
                  mode == FitMode.fit ? Icons.fit_screen_rounded : Icons.crop_rounded,
                  color: AppColors.accent),
                title: Text(mode.label,
                    style: const TextStyle(color: AppColors.textPrimary)),
                trailing: mode == _fitMode
                    ? Icon(Icons.check_rounded, color: AppColors.accent)
                    : null,
                onTap: () => Navigator.of(context).pop(mode),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    ).then((mode) {
      if (mode != null) {
        setState(() {
          _fitMode = mode;
          _zoom = 1;
        });
      }
    });
  }

  void _onScaleStart(ScaleStartDetails d) {
    if (_locked) return;

    _dragStart = d.focalPoint;
    _zoomStart = _zoom;
    _volumeStart = _volumePercent;
    _brightnessStart = _levelValue;
    _gestureActive = false;
    _gestureLabel = '';
    _seekPreview = null;

    _twoFingerFitGesture =
        d.pointerCount >= 2 && !_settings.pinchZoom;
    _twoFingerFitDidCycle = false;

    _drag = d.pointerCount >= 2 && _settings.pinchZoom
        ? _DragMode.zoom
        : _DragMode.none;
  }


  Future<void> _onScaleUpdate(ScaleUpdateDetails d) async {
    if (_locked) return;

    if (_twoFingerFitGesture) {
      // Pinch-zoom is OFF: expanding two fingers cycles to the NEXT fit
      // mode, closing them cycles to the PREVIOUS one. Fire once per
      // gesture (scale keeps changing while fingers move).
      if (!_twoFingerFitDidCycle) {
        if (d.scale > 1.06) {
          _twoFingerFitDidCycle = true;
          _cycleFit(1);
        } else if (d.scale < 0.94) {
          _twoFingerFitDidCycle = true;
          _cycleFit(-1);
        }
      }
      return;
    }

    final screenSize = MediaQuery.of(context).size;

    if (_drag == _DragMode.zoom) {
      final scale = d.scale;
      final nextZoom =
          (_zoomStart * scale).clamp(.75, 4.0).toDouble();
      if (scale > 1.08 || scale < .92) {
        setState(() {
          _zoom = nextZoom;
          _gestureActive = true;
        });
      }
      return;
    }

    final delta = d.focalPoint - _dragStart;
    if (_drag == _DragMode.none && delta.distance >= 14) {
      final width = screenSize.width;
      if (delta.dx.abs() > delta.dy.abs() * 1.35 &&
          _settings.horizontalSeek) {
        _drag = _DragMode.seek;
        _scrubStart = _player.state.position;
        _lastSentSeek = _scrubStart;
        _seekPreview = _scrubStart;
      } else if (delta.dy.abs() >= delta.dx.abs()) {
        if (_dragStart.dx < width / 2 &&
            _settings.swipeBrightness) {
          _drag = _DragMode.brightness;
          _levelValue =
              await ScreenBrightness.instance.application;
          _brightnessStart = _levelValue;
          _dragStart = d.focalPoint;
        } else if (_dragStart.dx >= width / 2 &&
            _settings.swipeVolume) {
          _drag = _DragMode.volume;
          _volumeStart = _volumePercent;
          _dragStart = d.focalPoint;
        }
      }
    }

    final height = screenSize.height;
    final width = screenSize.width;

    if (_drag == _DragMode.brightness) {
      final change =
          -(d.focalPoint.dy - _dragStart.dy) / (height * .5);
      final v =
          (_brightnessStart + change).clamp(0.0, 1.0).toDouble();
      await ScreenBrightness.instance
          .setApplicationScreenBrightness(v);
      _levelValue = v;
      _emitGesture(
        Icons.brightness_6_rounded,
        '${(v * 100).round()}%',
      );
    } else if (_drag == _DragMode.volume) {
      final change =
          -(d.focalPoint.dy - _dragStart.dy) /
              (height * .5) * 100;
      final maxVolume =
          _settings.volumeBoost ? 200.0 : 100.0;
      final v =
          (_volumeStart + change).clamp(0.0, maxVolume).toDouble();
      await _setVolumePercent(v);
      _emitGesture(Icons.volume_up_rounded, '${v.round()}%');
    } else if (_drag == _DragMode.seek) {
      final duration = _player.state.duration;
      if (duration <= Duration.zero) return;

      const secondsPerScreen = 90.0;
      final offsetSeconds =
          (d.focalPoint.dx - _dragStart.dx) /
              width * secondsPerScreen;
      var targetMs =
          _scrubStart.inMilliseconds +
              (offsetSeconds * 1000).round();
      targetMs = targetMs.clamp(0, duration.inMilliseconds);
      final target = Duration(milliseconds: targetMs);

      setState(() {
        _seekPreview = target;
        _gestureActive = true;
      });

      final now = DateTime.now();
      if (now.difference(_lastLiveSeek).inMilliseconds > 120 &&
          (target - _lastSentSeek).abs().inMilliseconds > 800) {
        _lastLiveSeek = now;
        _lastSentSeek = target;
        unawaited(_player.seek(target));
      }
    }
  }


  void _emitGesture(IconData icon, String label) {
    if (!mounted) return;
    setState(() {
      _gestureIcon = icon;
      _gestureLabel = label;
      _gestureActive = true;
    });
    _flashTimer?.cancel();
    _flashTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _gestureActive = false);
    });
  }

  void _onScaleEnd(ScaleEndDetails _) {
    if (_locked) return;

    if (_twoFingerFitGesture) {
      _twoFingerFitGesture = false;
      _twoFingerFitDidCycle = false;
      _gestureActive = false;
      _gestureLabel = '';
      return;
    }

    final drag = _drag;
    final preview = _seekPreview;

    if (drag == _DragMode.seek && preview != null) {
      unawaited(_player.seek(preview));
    }

    if (drag == _DragMode.zoom && _zoom < .9) {
      setState(() {
        _zoom = 1;
        _fitMode = FitMode.fit;
      });
    }

    _flashTimer?.cancel();
    if (mounted) {
      setState(() {
        _drag = _DragMode.none;
        _seekPreview = null;
        _gestureActive = false;
        _gestureLabel = '';
      });
    }
  }


  String? get _sleepLabel {
    if (_sleepUntilEnd) return 'Sleep: Until end';

    final deadline = _sleepDeadline;
    if (deadline == null) return null;
    final remaining = deadline.difference(DateTime.now());
    if (remaining <= Duration.zero) return null;
    return formatSleepLabel(remaining);
  }

  Future<void> _showPlayerSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PlayerSettingsScreen()),
    );
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
                onTap: () {
                  Navigator.of(context).pop();
                  _showTrackPicker(subtitle: true);
                },
              ),
              _extraAction(
                icon: Icons.music_note_rounded,
                title: 'Audio track (${tracks.audio.length} available)',
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
                    DropdownMenuItem(value: 'clip', child: Text('Clip')),
                    DropdownMenuItem(value: 'mobius', child: Text('Mobius')),
                    DropdownMenuItem(value: 'reinhard', child: Text('Reinhard')),
                    DropdownMenuItem(value: 'hable', child: Text('Hable')),
                    DropdownMenuItem(value: 'gamma', child: Text('Gamma')),
                    DropdownMenuItem(value: 'linear', child: Text('Linear')),
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
    _sleepDeadline = null;
    _sleepUntilEnd = false;

    switch (picked.kind) {
      case _SleepChoiceKind.off:
        _emitSnack('Sleep timer off');
        break;
      case _SleepChoiceKind.minutes:
        final minutes = picked.minutes!;
        _sleepDeadline = DateTime.now().add(Duration(minutes: minutes));
        // Tick every second so the countdown under the title counts
        // down live (mm:ss) and pauses exactly at zero.
        _sleepTimer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (!mounted) return;
          if (_sleepDeadline != null &&
              _sleepDeadline!.isAfter(DateTime.now())) {
            setState(() {});
            return;
          }
          _sleepTimer?.cancel();
          _sleepTimer = null;
          _sleepDeadline = null;
          _player.pause();
          if (mounted) setState(() {});
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

  Future<void> _toggleRotationLock() async {
    try {
      final locked =
          await _native.invokeMethod<bool>('toggleRotationLock') ?? false;
      if (!mounted) return;
      setState(() => _rotationLocked = locked);
      _emitGesture(
        locked
            ? Icons.screen_lock_rotation_rounded
            : Icons.screen_rotation_alt_rounded,
        locked ? 'Rotation locked' : 'Rotation unlocked',
      );
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
    _flashTimer?.cancel();
    _saveTimer?.cancel();
    _playingSub?.cancel();
    _bufferingSub?.cancel();
    _completedSub?.cancel();
    _errorSub?.cancel();
    if (_settingsListener != null) _settings.removeListener(_settingsListener!);
    WidgetsBinding.instance.removeObserver(this);
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
        onTap: _onTap,
        onDoubleTapDown: _onDoubleTap,
        onLongPressStart: (_) => _setBoost(true),
        onLongPressEnd: (_) => _setBoost(false),
        onLongPressCancel: () => _setBoost(false),
        onScaleStart: _onScaleStart,
        onScaleUpdate: (details) => unawaited(_onScaleUpdate(details)),
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
                    fit: _fitMode.boxFit,
                    aspectRatio: _fitMode == FitMode.sixteenNine ? 16 / 9 : null,
                    controls: NoVideoControls,
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
            if (_seekFlash != null)
              Align(
                alignment: const Alignment(0, -.72),
                child: _SeekPill(seconds: _seekFlash!),
              ),
            if (_gestureActive && _gestureLabel.isNotEmpty)
              Align(
                alignment: const Alignment(0, -.72),
                child: _GesturePill(icon: _gestureIcon, label: _gestureLabel),
              ),
            if (_seekPreview != null)
              Align(
                alignment: const Alignment(0, -0.38),
                child: _InfoPill(
                  icon: Icons.swap_horizontal_circle_outlined,
                  text:
                      '${formatDuration(_seekPreview!)}  '
                      '${(_seekPreview! - _scrubStart).isNegative ? '-' : '+'}'
                      '${formatDuration((_seekPreview! - _scrubStart).abs())}  |  '
                      '${formatDuration(_player.state.duration)}',
                ),
              ),
            if (_boost)
              Align(
                alignment: const Alignment(0, -.72),
                child: _GesturePill(
                  icon: Icons.speed_rounded,
                  label: '${_settings.longPressRate.toStringAsFixed(2)}x',
                ),
              ),
            if (_locked) ...[
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: _EdgeButton(icon: Icons.lock_rounded, onTap: () {}),
                ),
              ),
              if (_lockedHintVisible)
                const Align(
                  alignment: Alignment.center,
                  child: _GesturePill(
                    icon: Icons.lock_open_rounded,
                    label: 'Double tap to unlock',
                  ),
                ),
            ],
            if (_controlsVisible && !_locked) ...[
              _TopBar(
                title: _title,
                sleepLabel: _sleepLabel,
                onSettings: _showPlayerSettings,
                onMenu: (action) => unawaited(_onMenuAction(action)),
              ),
              _BottomBar(
                player: _player,
                onTrackSheet: _showTrackSheet,
                onPlaylist: _showPlaylistSheet,
                onRotate: _toggleRotationLock,
                rotationLocked: _rotationLocked,
                onFit: _showFitMenu,
                onMute: _toggleMute,
                onSpeed: _showSpeedSheet,
                isMuted: _muted,
                canSkip: widget.queueIds.length > 1,
                onPrevious: _playPrevious,
                onNext: _playNext,
              ),
              if (_settings.screenLock)
                Positioned(
                  right: 6,
                  top: MediaQuery.of(context).size.height * .34,
                  child: _EdgeButton(
                    icon: Icons.lock_outline_rounded,
                    onTap: () => setState(() => _locked = true),
                  ),
                ),
            ],
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
    required this.onSettings,
    required this.onMenu,
  });

  final String title;
  final String? sleepLabel;
  final VoidCallback onSettings;
  final ValueChanged<_PlayerMenuAction> onMenu;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + 6,
          left: 4,
          right: 10,
          bottom: 16,
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
              icon: const Icon(Icons.arrow_back_rounded,
                  color: Colors.white, size: 31),
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
                      child: Text(
                        sleepLabel!,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            PopupMenuButton<_PlayerMenuAction>(
              tooltip: 'More',
              padding: EdgeInsets.zero,
              iconSize: 30,
              icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
              color: AppColors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
                side: const BorderSide(color: AppColors.border),
              ),
              onSelected: onMenu,
              itemBuilder: (context) => const [
                PopupMenuItem(
                    value: _PlayerMenuAction.info,
                    child: _MoreRow(icon: Icons.info_outline_rounded, label: 'Video info')),
                PopupMenuItem(
                    value: _PlayerMenuAction.eq,
                    child: _MoreRow(icon: Icons.graphic_eq_rounded, label: 'Equalizer & Audio FX')),
                PopupMenuItem(
                    value: _PlayerMenuAction.screenshot,
                    child: _MoreRow(icon: Icons.photo_camera_outlined, label: 'Screenshot')),
                PopupMenuItem(
                    value: _PlayerMenuAction.cast,
                    child: _MoreRow(icon: Icons.cast_rounded, label: 'Cast to TV')),
                PopupMenuItem(
                    value: _PlayerMenuAction.pip,
                    child: _MoreRow(icon: Icons.picture_in_picture_alt_rounded, label: 'Picture-in-Picture')),
                PopupMenuItem(
                    value: _PlayerMenuAction.sleep,
                    child: _MoreRow(icon: Icons.nightlight_round, label: 'Sleep timer')),
              ],
            ),
            IconButton(
              tooltip: 'Player settings',
              icon: const Icon(Icons.settings_outlined, color: Colors.white, size: 30),
              onPressed: onSettings,
            ),
          ],
        ),
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

class _MoreRow extends StatelessWidget {
  const _MoreRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: AppColors.accent),
        const SizedBox(width: 12),
        Text(label, style: const TextStyle(color: AppColors.textPrimary)),
      ],
    );
  }
}

class _BottomBar extends StatefulWidget {
  const _BottomBar({
    required this.player,
    required this.onTrackSheet,
    required this.onPlaylist,
    required this.onRotate,
    required this.rotationLocked,
    required this.onFit,
    required this.onMute,
    required this.onSpeed,
    required this.isMuted,
    required this.canSkip,
    required this.onPrevious,
    required this.onNext,
  });

  final Player player;
  final VoidCallback onTrackSheet;
  final VoidCallback onPlaylist;
  final VoidCallback onRotate;
  final bool rotationLocked;
  final VoidCallback onFit;
  final VoidCallback onMute;
  final VoidCallback onSpeed;
  final bool isMuted;
  final bool canSkip;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  State<_BottomBar> createState() => _BottomBarState();
}

class _BottomBarState extends State<_BottomBar> {
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
          left: 14,
          right: 14,
          top: 18,
          bottom: MediaQuery.of(context).padding.bottom + 10,
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
          builder: (context, positionSnapshot) {
            final position = positionSnapshot.data ?? Duration.zero;
            return StreamBuilder<Duration>(
              stream: widget.player.stream.duration,
              initialData: widget.player.state.duration,
              builder: (context, durationSnapshot) {
                final duration = durationSnapshot.data ?? Duration.zero;
                final max = duration.inMilliseconds > 0
                    ? duration.inMilliseconds.toDouble()
                    : 1.0;
                final shown = (_dragMs ?? position.inMilliseconds.toDouble())
                    .clamp(0.0, max)
                    .toDouble();
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Text(formatDuration(Duration(milliseconds: shown.round())),
                            style: const TextStyle(color: Colors.white70, fontSize: 13)),
                        const Spacer(),
                        Text(formatDuration(duration),
                            style: const TextStyle(color: Colors.white70, fontSize: 13)),
                      ],
                    ),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: Colors.white,
                        inactiveTrackColor: Colors.white24,
                        thumbColor: Colors.white,
                        trackHeight: 2.6,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                        overlayShape: SliderComponentShape.noOverlay,
                      ),
                      child: Slider(
                        value: shown,
                        max: max,
                        onChangeStart: (value) => setState(() => _dragMs = value),
                        onChanged: (value) {
                          setState(() => _dragMs = value);
                          _liveSeek(Duration(milliseconds: value.round()));
                        },
                        onChangeEnd: (value) {
                          widget.player.seek(Duration(milliseconds: value.round()));
                          setState(() => _dragMs = null);
                        },
                      ),
                    ),
                    const SizedBox(height: 4),
                    StreamBuilder<bool>(
                      stream: widget.player.stream.playing,
                      initialData: widget.player.state.playing,
                      builder: (context, snapshot) {
                        final playing = snapshot.data ?? false;
                        return Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                              tooltip: 'Previous',
                              iconSize: 32,
                              color: widget.canSkip ? Colors.white : Colors.white38,
                              onPressed: widget.canSkip ? widget.onPrevious : null,
                              icon: const Icon(Icons.skip_previous_rounded),
                            ),
                            const SizedBox(width: 26),
                            IconButton(
                              tooltip: 'Play/Pause',
                              iconSize: 58,
                              color: Colors.white,
                              onPressed: widget.player.playOrPause,
                              icon: Icon(playing
                                  ? Icons.pause_circle_filled_rounded
                                  : Icons.play_circle_filled_rounded),
                            ),
                            const SizedBox(width: 26),
                            IconButton(
                              tooltip: 'Next',
                              iconSize: 32,
                              color: widget.canSkip ? Colors.white : Colors.white38,
                              onPressed: widget.canSkip ? widget.onNext : null,
                              icon: const Icon(Icons.skip_next_rounded),
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        IconButton(
                          tooltip: widget.isMuted ? 'Unmute' : 'Mute',
                          icon: Icon(
                            widget.isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                            color: Colors.white, size: 27),
                          onPressed: widget.onMute,
                        ),
                        GestureDetector(
                          onTap: widget.onSpeed,
                          child: StreamBuilder<double>(
                            stream: widget.player.stream.rate,
                            initialData: widget.player.state.rate,
                            builder: (context, snapshot) => Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              child: Text(
                                '${(snapshot.data ?? 1).toStringAsFixed((snapshot.data ?? 1) % 1 == 0 ? 1 : 2)}x',
                                style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          tooltip: 'Track sheet',
                          icon: const Icon(Icons.tune_rounded,
                              color: Colors.white, size: 28),
                          onPressed: widget.onTrackSheet,
                        ),
                        IconButton(
                          tooltip: 'Screen fit',
                          icon: const Icon(Icons.fit_screen_rounded,
                              color: Colors.white, size: 27),
                          onPressed: widget.onFit,
                        ),
                        IconButton(
                          tooltip: 'Playlist',
                          icon: const Icon(Icons.playlist_play_rounded,
                              color: Colors.white, size: 28),
                          onPressed: widget.onPlaylist,
                        ),
                        IconButton(
                          tooltip: widget.rotationLocked
                              ? 'Unlock rotation'
                              : 'Lock rotation',
                          icon: Icon(
                            widget.rotationLocked
                                ? Icons.screen_lock_rotation_rounded
                                : Icons.screen_rotation_alt_rounded,
                            color: Colors.white,
                            size: 29,
                          ),
                          onPressed: widget.onRotate,
                        ),
                      ],
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

class _EdgeButton extends StatelessWidget {
  const _EdgeButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: .3),
      shape: const CircleBorder(side: BorderSide(color: Colors.white30)),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, color: Colors.white, size: 20),
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
    final backwards = seconds < 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
      decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: .62),
          borderRadius: BorderRadius.circular(14)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(backwards ? Icons.replay_10_rounded : Icons.forward_10_rounded,
              color: Colors.white, size: 25),
          const SizedBox(width: 6),
          Text('${backwards ? '' : '+'}${seconds}s',
              style: const TextStyle(
                  color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _GesturePill extends StatelessWidget {
  const _GesturePill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .72),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 21),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
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
          color: Colors.black.withValues(alpha: .68),
          borderRadius: BorderRadius.circular(12)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 19),
          const SizedBox(width: 7),
          Text(text,
              style: const TextStyle(
                  color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
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
