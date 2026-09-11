import 'dart:async';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:volume_controller/volume_controller.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../theme.dart';
import '../utils/ab_loop.dart';
import '../utils/crash_log.dart';
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
  bool _fullscreen = false;

  _DragMode _drag = _DragMode.none;
  Offset _dragStart = Offset.zero;
  double _zoom = 1;
  double _zoomStart = 1;
  double _levelValue = 0;
  Duration? _seekPreview;
  Duration _scrubStart = Duration.zero;
  Duration _lastSentSeek = Duration.zero;
  DateTime _lastLiveSeek = DateTime.fromMillisecondsSinceEpoch(0);
  int? _seekFlash;
  bool _seekFlashLeft = false;

  AbState _ab = AbState.off;
  final List<double> _bands =
      List<double>.from(equalizerPresets['Flat'] ?? const [0, 0, 0, 0, 0]);
  bool _dialogueBoost = false;
  bool _enhance = false;
  bool _karaoke = false;
  String _toneMapping = 'auto';
  int _sleepMinutesLeft = 0;
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
      _applyPerformanceMode();
    };
    _settings.addListener(_settingsListener!);
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
      if (mounted) setState(() {});
    });
    _bufferingSub = _player.stream.buffering.listen((b) {
      if (mounted) setState(() => _buffering = b);
    });
    _completedSub = _player.stream.completed.listen((done) {
      if (done) unawaited(_playNext());
    });
    _errorSub = _player.stream.error.listen((e) {
      _onError(e);
    });
    _saveTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      unawaited(_savePosition());
    });
    _applyPerformanceMode();
  }

  Future<void> _open(String path, {required bool offerResume}) async {
    CrashLog.crumb('player.open', {'path': path});
    try {
      await _player.open(Media(path), play: true);
      if (mounted) setState(() => _ready = true);
      if (offerResume && _settings.resume && !widget.isStream) {
        unawaited(_offerResume());
      }
    } catch (e) {
      _onError(e);
    }
  }

  Future<void> _applyPerformanceMode() async {
    if (!_ready) return;
    if (_settings.performanceMode) {
      await _mpvSet('framedrop', 'vo');
      await _mpvSet('vd-lavc-fast', 'yes');
    } else {
      await _mpvSet('framedrop', 'no');
      await _mpvSet('vd-lavc-fast', 'no');
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
      await _applyPerformanceMode();
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

  void _onDoubleTap(TapDownDetails details) {
    if (_locked) return;
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
    _flash(seconds, left);
  }

  void _flash(int seconds, bool left) {
    _flashTimer?.cancel();
    setState(() {
      _seekFlash = seconds;
      _seekFlashLeft = left;
      _controlsVisible = true;
    });
    if (_settings.autoHide) _scheduleHide();
    _flashTimer = Timer(const Duration(milliseconds: 650), () {
      if (mounted) setState(() => _seekFlash = null);
    });
  }

  void _setBoost(bool on) {
    if (!_settings.longPressSpeed || _locked) return;
    _boost = on;
    _player.setRate(on ? _settings.longPressRate : 1.0);
    if (mounted) setState(() {});
  }

  void _onScaleStart(ScaleStartDetails d) {
    if (_locked) return;
    _dragStart = d.focalPoint;
    _zoomStart = _zoom;
    _drag = d.pointerCount >= 2 && _settings.pinchZoom
        ? _DragMode.zoom
        : _DragMode.none;
  }

  Future<void> _onScaleUpdate(ScaleUpdateDetails d) async {
    final screenSize = MediaQuery.of(context).size;
    if (_locked) return;
    if (_drag == _DragMode.zoom) {
      setState(() => _zoom = (_zoomStart * d.scale).clamp(1.0, 4.0));
      return;
    }
    final delta = d.focalPoint - _dragStart;
    if (_drag == _DragMode.none && delta.distance >= 14) {
      final width = MediaQuery.of(context).size.width;
      if (delta.dx.abs() > delta.dy.abs() * 1.5 && _settings.horizontalSeek) {
        _drag = _DragMode.seek;
        _scrubStart = _player.state.position;
        _lastSentSeek = _scrubStart;
        _seekPreview = _scrubStart;
      } else if (delta.dy.abs() >= delta.dx.abs()) {
        if (_dragStart.dx < width / 2 && _settings.swipeBrightness) {
          _drag = _DragMode.brightness;
        } else if (_dragStart.dx >= width / 2 && _settings.swipeVolume) {
          _drag = _DragMode.volume;
        }
        if (_drag == _DragMode.brightness) {
          _levelValue = await ScreenBrightness.instance.application;
        } else if (_drag == _DragMode.volume) {
          _levelValue = await VolumeController.instance.getVolume();
        }
        _dragStart = d.focalPoint;
      }
    }

    final height = screenSize.height;
    final width = screenSize.width;
    if (_drag == _DragMode.brightness || _drag == _DragMode.volume) {
      final change = -(d.focalPoint.dy - _dragStart.dy) / (height * .5);
      final v = (_levelValue + change).clamp(0.0, 1.0);
      if (_drag == _DragMode.brightness) {
        await ScreenBrightness.instance.setApplicationScreenBrightness(v);
      } else {
        await VolumeController.instance.setVolume(v);
      }
      if (mounted) setState(() => _levelValue = v);
    } else if (_drag == _DragMode.seek) {
      final duration = _player.state.duration;
      if (duration <= Duration.zero) return;
      final fraction = (d.focalPoint.dx / width).clamp(0.0, 1.0);
      final target = Duration(
        milliseconds: (fraction * duration.inMilliseconds).round(),
      );
      setState(() => _seekPreview = target);
      final now = DateTime.now();
      if (now.difference(_lastLiveSeek).inMilliseconds > 120 &&
          (target - _lastSentSeek).abs().inMilliseconds > 800) {
        _lastLiveSeek = now;
        _lastSentSeek = target;
        unawaited(_player.seek(target));
      }
    }
  }

  void _onScaleEnd(ScaleEndDetails _) {
    if (_locked) return;
    if (_drag == _DragMode.seek && _seekPreview != null) {
      _player.seek(_seekPreview!);
    }
    _flashTimer?.cancel();
    setState(() {
      _drag = _DragMode.none;
      _seekPreview = null;
    });
  }

  Future<void> _showPlayerSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PlayerSettingsScreen()),
    );
    if (mounted) _applyPerformanceMode();
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
    await _mpvSet(
      'af',
      combineAudioFilters(_bands, dialogueBoost: _dialogueBoost),
    );
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
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Dialogue boost',
                      style: TextStyle(color: AppColors.textPrimary)),
                  subtitle: const Text('Lifts quiet speech (1-4 kHz)',
                      style: TextStyle(color: AppColors.textSecondary)),
                  value: _dialogueBoost,
                  onChanged: (value) {
                    _dialogueBoost = value;
                    unawaited(_applyAudioFilters());
                    setSheet(() {});
                  },
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
      MapEntry('Video encoder params', state.videoParams.toString()),
      MapEntry('Audio decoder params', state.audioParams.toString()),
      if (state.audioBitrate != null)
        MapEntry('Audio bitrate', '${state.audioBitrate} bit/s'),
    ];
    showDialog<void>(
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
            style: const TextStyle(
                color: AppColors.textPrimary, fontSize: 15)),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final row in rows)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(row.key,
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 11.5)),
                      const SizedBox(height: 2),
                      Text(row.value,
                          style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 12.5)),
                    ],
                  ),
                ),
              const Divider(color: AppColors.border),
              for (final track in state.tracks.video)
                Text('Video: $track',
                    style: const TextStyle(
                        color: AppColors.textPrimary, fontSize: 11)),
              for (final track in state.tracks.audio)
                Text('Audio: $track',
                    style: const TextStyle(
                        color: AppColors.textPrimary, fontSize: 11)),
              for (final track in state.tracks.subtitle)
                Text('Subtitle: $track',
                    style: const TextStyle(
                        color: AppColors.textPrimary, fontSize: 11)),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close')),
        ],
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
    try {
      final video = _player.state.videoParams;
      final ok = await _native.invokeMethod<bool>('enterPip', {
        'w': video.dw ?? 16,
        'h': video.dh ?? 9,
      });
      if (ok != true) _emitSnack('Picture-in-Picture not available');
    } catch (e) {
      CrashLog.error('pip.failed', e);
      _emitSnack('Picture-in-Picture not supported on this device');
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
    const mins = [0, 10, 15, 30, 45, 60];
    final picked = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
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
            for (final min in mins)
              ListTile(
                title: Text(
                  min == 0
                      ? (_sleepTimer == null
                          ? 'Off'
                          : 'Cancel timer ($_sleepMinutesLeft min)')
                      : '$min minutes',
                  style: const TextStyle(color: AppColors.textPrimary),
                ),
                onTap: () => Navigator.of(context).pop(min),
              ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    _sleepTimer?.cancel();
    _sleepMinutesLeft = picked;
    if (picked > 0) {
      _sleepTimer = Timer(Duration(minutes: picked), () {
        _player.pause();
        _emitSnack('Sleep timer — playback paused. Good night');
      });
      _emitSnack('Sleeping in $picked minutes');
    } else {
      _emitSnack('Sleep timer off');
    }
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

  Future<void> _toggleFullscreen() async {
    _fullscreen = !_fullscreen;
    setState(() {});
    if (_fullscreen) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
  }

  Future<void> _rotateOrientation() async {
    final orientation = MediaQuery.of(context).orientation;
    if (orientation == Orientation.portrait) {
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
      ]);
    } else {
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
      ]);
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
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
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
        onTap: _toggleControls,
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
                  child: Video(controller: _controller, controls: NoVideoControls),
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
                alignment: _seekFlashLeft
                    ? Alignment.centerLeft
                    : Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 34),
                  child: _SeekPill(seconds: _seekFlash!),
                ),
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
            if (_drag == _DragMode.brightness)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 22),
                  child: _LevelPill(
                    icon: Icons.brightness_6_rounded,
                    value: _levelValue,
                  ),
                ),
              ),
            if (_drag == _DragMode.volume)
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 22),
                  child: _LevelPill(
                    icon: _levelValue == 0
                        ? Icons.volume_off_rounded
                        : Icons.volume_up_rounded,
                    value: _levelValue,
                  ),
                ),
              ),
            if (_boost)
              const Align(alignment: Alignment(0, -.55), child: _SpeedBadge()),
            if (_locked)
              Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: .72),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 14),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.lock_rounded,
                            color: Colors.white, size: 22),
                        const SizedBox(width: 10),
                        TextButton(
                          onPressed: () => setState(() => _locked = false),
                          child: const Text('Tap to unlock'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (_controlsVisible && !_locked) ...[
              _TopBar(
                title: _title,
                onSettings: _showPlayerSettings,
                onMenu: (action) => unawaited(_onMenuAction(action)),
              ),
              _BottomBar(
                player: _player,
                onTrackSheet: _showTrackSheet,
                onFullscreen: _toggleFullscreen,
                onRotate: _rotateOrientation,
                onLock: _settings.screenLock
                    ? () => setState(() => _locked = true)
                    : null,
              ),
              _CenterControls(
                player: _player,
                canSkip: widget.queueIds.length > 1,
                onPrevious: _playPrevious,
                onNext: _playNext,
              ),
              if (_settings.screenLock)
                Positioned(
                  left: 8,
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
  const _TopBar({required this.title, required this.onSettings, required this.onMenu});

  final String title;
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
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white, fontSize: 15.5, fontWeight: FontWeight.w600),
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
    required this.onFullscreen,
    required this.onRotate,
    this.onLock,
  });

  final Player player;
  final VoidCallback onTrackSheet;
  final VoidCallback onFullscreen;
  final VoidCallback onRotate;
  final VoidCallback? onLock;

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
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        IconButton(
                          tooltip: 'Volume',
                          icon: const Icon(Icons.volume_up_rounded,
                              color: Colors.white, size: 27),
                          onPressed: () {},
                        ),
                        StreamBuilder<double>(
                          stream: widget.player.stream.rate,
                          initialData: widget.player.state.rate,
                          builder: (context, snapshot) => Text(
                            '${(snapshot.data ?? 1).toStringAsFixed((snapshot.data ?? 1) % 1 == 0 ? 1 : 2)}x',
                            style: const TextStyle(color: Colors.white, fontSize: 15),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Tracks & video controls',
                          icon: const Icon(Icons.tune_rounded, color: Colors.white, size: 28),
                          onPressed: widget.onTrackSheet,
                        ),
                        const Spacer(),
                        IconButton(
                          tooltip: 'Tracks',
                          icon: const Icon(Icons.queue_music_rounded,
                              color: Colors.white, size: 28),
                          onPressed: widget.onTrackSheet,
                        ),
                        IconButton(
                          tooltip: 'Fullscreen',
                          icon: const Icon(Icons.fullscreen_rounded,
                              color: Colors.white, size: 30),
                          onPressed: widget.onFullscreen,
                        ),
                        IconButton(
                          tooltip: 'Rotate',
                          icon: const Icon(Icons.screen_rotation_alt_rounded,
                              color: Colors.white, size: 29),
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

class _CenterControls extends StatelessWidget {
  const _CenterControls({
    required this.player,
    required this.canSkip,
    required this.onPrevious,
    required this.onNext,
  });

  final Player player;
  final bool canSkip;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: StreamBuilder<bool>(
        stream: player.stream.playing,
        initialData: player.state.playing,
        builder: (context, snapshot) {
          final playing = snapshot.data ?? false;
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Previous',
                iconSize: 46,
                color: Colors.white,
                onPressed: canSkip ? onPrevious : null,
                icon: const Icon(Icons.skip_previous_rounded),
              ),
              const SizedBox(width: 18),
              IconButton(
                tooltip: 'Play/Pause',
                iconSize: 78,
                color: Colors.white,
                onPressed: player.playOrPause,
                icon: Icon(playing
                    ? Icons.pause_circle_filled_rounded
                    : Icons.play_circle_filled_rounded),
              ),
              const SizedBox(width: 18),
              IconButton(
                tooltip: 'Next',
                iconSize: 46,
                color: Colors.white,
                onPressed: canSkip ? onNext : null,
                icon: const Icon(Icons.skip_next_rounded),
              ),
            ],
          );
        },
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
        child: const Padding(
          padding: EdgeInsets.all(17),
          child: Icon(Icons.lock_outline_rounded, color: Colors.white, size: 28),
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

class _LevelPill extends StatelessWidget {
  const _LevelPill({required this.icon, required this.value});

  final IconData icon;
  final double value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: .66),
          borderRadius: BorderRadius.circular(14)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 24),
          const SizedBox(height: 7),
          SizedBox(
            height: 88,
            child: RotatedBox(
              quarterTurns: 3,
              child: LinearProgressIndicator(
                value: value,
                backgroundColor: Colors.white24,
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                minHeight: 4,
              ),
            ),
          ),
          const SizedBox(height: 7),
          Text('${(value * 100).round()}%',
              style: const TextStyle(
                  color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
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
          color: Colors.white.withValues(alpha: .88),
          borderRadius: BorderRadius.circular(20)),
      child: const Text('2×',
          style: TextStyle(
              color: Colors.black, fontSize: 16, fontWeight: FontWeight.w800)),
    );
  }
}

class _SheetHandle extends StatelessWidget {
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
