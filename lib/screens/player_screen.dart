import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../state/media_player_state.dart';
import '../state/player_settings.dart';
import '../widgets/player_controls_overlay.dart';
import '../widgets/player_settings_sheet.dart';
import '../widgets/playlist_panel.dart';

class PlayerScreen extends StatefulWidget {
  final MediaPlayerState player;

  const PlayerScreen({super.key, required this.player});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> with WidgetsBindingObserver {
  // Shared, app-lifetime controller owned by MediaPlayerState (this media_kit
  // version has no VideoController.dispose, so per-visit controllers leaked).
  late final VideoController _controller = widget.player.videoController;

  bool _controlsVisible = true;
  bool _isFullscreen = false;
  bool _showQueue = false;

  // Customizable behavior (persisted, edited in the Settings sheet).
  PlayerSettings _settings = const PlayerSettings();

  Timer? _hideTimer;

  // Transient center indicator ("+10s", "Volume 80%", "Resumed 12:34", ...).
  String? _indicatorText;
  IconData? _indicatorIcon;
  Timer? _indicatorTimer;
  StreamSubscription<String>? _noticeSub;

  // Aspect-ratio fit cycle: contain -> cover -> fill.
  static const List<BoxFit> _fits = [BoxFit.contain, BoxFit.cover, BoxFit.fill];
  static const List<String> _fitNames = ['Contain', 'Cover', 'Fill'];
  int _fitIndex = 0;
  static const List<IconData> _fitIcons = [
    Icons.fit_screen,
    Icons.crop_free,
    Icons.open_in_full,
  ];

  // Pinch zoom (1x..4x), anchored at the fingers' focal point, with
  // two-finger panning while zoomed.
  double _zoom = 1.0;
  double _zoomBase = 1.0;
  Offset _pan = Offset.zero;
  Offset _panBase = Offset.zero;
  Offset _focalBase = Offset.zero;

  // Gesture plumbing (double-tap seek / volume & brightness swipes).
  double _gestureWidth = 0;
  double _gestureHeight = 0;
  double _lastDoubleTapDx = 0;

  /// Which axis the current vertical drag drives.
  _DragMode _dragMode = _DragMode.none;
  double _dragStartValue = 0;
  double _dragDy = 0;

  // NOTE: no addListener/setState on the player here. The ticking parts
  // (overlay, spinner, queue, title) listen via their own AnimatedBuilder,
  // so the video surface itself is never rebuilt during playback.

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _noticeSub =
        widget.player.notices.listen((m) => _showIndicator(m, Icons.history));
    _reloadSettings();
    widget.player.currentBrightness(); // sync once for the swipe gesture
    _startHideTimer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hideTimer?.cancel();
    _indicatorTimer?.cancel();
    _noticeSub?.cancel();
    if (_isFullscreen) _exitFullscreen();
    // Do NOT keep the audio running after leaving the player screen, and
    // hand brightness control back to the system.
    unawaited(widget.player.pause());
    unawaited(widget.player.resetBrightness());
    super.dispose();
  }

  /// Pause when the app goes to the background (sound must not keep playing
  /// with the app hidden).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      widget.player.pause();
    }
  }

  Future<void> _reloadSettings() async {
    final s = await PlayerSettings.load();
    if (mounted) setState(() => _settings = s);
    _startHideTimer();
  }

  Future<void> _openSettings() async {
    await PlayerSettingsSheet.show(context);
    await _reloadSettings(); // apply changes immediately
  }

  // ---------------------------------------------------------------------------
  // Controls visibility (auto-hide)
  // ---------------------------------------------------------------------------

  void _startHideTimer() {
    _hideTimer?.cancel();
    final delay = _settings.autoHideSeconds;
    if (delay <= 0) return; // "never auto-hide"
    _hideTimer = Timer(Duration(seconds: delay), () {
      // Only auto-hide during playback; keep controls up while paused.
      if (mounted && widget.player.isPlaying) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  /// Called by the overlay on every button press / seek / menu selection so
  /// the auto-hide countdown restarts on any interaction.
  void _onUserInteraction() {
    if (_controlsVisible) _startHideTimer();
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) {
      _startHideTimer();
    } else {
      _hideTimer?.cancel();
    }
  }

  // ---------------------------------------------------------------------------
  // Transient indicator
  // ---------------------------------------------------------------------------

  void _showIndicator(String text, [IconData? icon]) {
    if (!mounted) return;
    _indicatorTimer?.cancel();
    setState(() {
      _indicatorText = text;
      _indicatorIcon = icon;
    });
    _indicatorTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _indicatorText = null);
    });
  }

  // ---------------------------------------------------------------------------
  // Fullscreen, fit, zoom
  // ---------------------------------------------------------------------------

  void _toggleFullscreen() {
    setState(() => _isFullscreen = !_isFullscreen);
    if (_isFullscreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      _exitFullscreen();
    }
    _onUserInteraction();
  }

  void _exitFullscreen() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
  }

  void _cycleFit() {
    setState(() => _fitIndex = (_fitIndex + 1) % _fits.length);
    _showIndicator('Fit: ${_fitNames[_fitIndex]}', _fitIcons[_fitIndex]);
    _onUserInteraction();
  }

  void _onScaleStart(ScaleStartDetails details) {
    if (!_settings.pinchZoom) return;
    _zoomBase = _zoom;
    _panBase = _pan;
    _focalBase = details.localFocalPoint;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (!_settings.pinchZoom) return;
    // One-finger moves only pan once already zoomed; otherwise leave them
    // for the tap / volume / brightness recognizers.
    if (details.pointerCount < 2 && _zoom <= 1.0) return;

    // Focal-anchored transform: the content point that was under the
    // fingers when the pinch started stays glued to the CURRENT focal
    // point. Because we track the live focal point, moving both fingers
    // together pans the zoomed video for free.
    final z = (_zoomBase * details.scale).clamp(1.0, 4.0);
    final contentV = (_focalBase - _panBase) / _zoomBase;
    final pan = _clampPan(details.localFocalPoint - contentV * z, z);

    if (z == _zoom && pan == _pan) return;
    setState(() {
      _zoom = z;
      _pan = pan;
    });
    if (details.scale != 1.0) {
      _showIndicator('Zoom ${z.toStringAsFixed(1)}x', Icons.pinch_outlined);
    }
  }

  void _onScaleEnd(ScaleEndDetails details) {
    if (!_settings.pinchZoom) return;
    // Snap back when barely zoomed.
    if (_zoom < 1.1) {
      setState(() {
        _zoom = 1.0;
        _pan = Offset.zero;
      });
    } else {
      setState(() => _pan = _clampPan(_pan, _zoom));
    }
  }

  /// Keep the scaled video covering the viewport (no drifting past edges).
  Offset _clampPan(Offset pan, double z) {
    final maxX = _gestureWidth * (z - 1);
    final maxY = _gestureHeight * (z - 1);
    return Offset(pan.dx.clamp(-maxX, 0.0), pan.dy.clamp(-maxY, 0.0));
  }

  // ---------------------------------------------------------------------------
  // Tap & swipe gestures
  // ---------------------------------------------------------------------------

  void _onDoubleTap() {
    final third = _gestureWidth / 3;
    if (_lastDoubleTapDx < third) {
      if (!_settings.doubleTapSeek) return;
      widget.player.seekBy(-_settings.seekSeconds);
      _showIndicator('-${_settings.seekSeconds}s', Icons.replay_10);
    } else if (_lastDoubleTapDx > _gestureWidth - third) {
      if (!_settings.doubleTapSeek) return;
      widget.player.seekBy(_settings.seekSeconds);
      _showIndicator('+${_settings.seekSeconds}s', Icons.forward_10);
    } else {
      // Middle third: play / pause.
      if (!_settings.doubleTapPlayPause) return;
      final wasPlaying = widget.player.isPlaying;
      widget.player.togglePlay();
      _showIndicator(
          wasPlaying ? 'Paused' : 'Playing',
          wasPlaying ? Icons.pause_circle_outline : Icons.play_circle_outline);
    }
  }

  void _onVerticalDragStart(DragStartDetails d) {
    final rightHalf = d.localPosition.dx > _gestureWidth / 2;
    if (rightHalf && _settings.volumeSwipe) {
      _dragMode = _DragMode.volume;
      _dragStartValue = widget.player.isMuted ? 0.0 : widget.player.volume;
      _dragDy = 0;
    } else if (!rightHalf && _settings.brightnessSwipe) {
      _dragMode = _DragMode.brightness;
      _dragStartValue = widget.player.brightness;
      _dragDy = 0;
    } else {
      _dragMode = _DragMode.none;
    }
  }

  void _onVerticalDragUpdate(DragUpdateDetails d) {
    if (_dragMode == _DragMode.none) return;
    _dragDy -= d.delta.dy; // dragging up = increase
    final v = (_dragStartValue + _dragDy / 300).clamp(0.0, 1.0);
    if (_dragMode == _DragMode.volume) {
      widget.player.setVolume(v);
      _showIndicator('Volume ${(v * 100).round()}%',
          v == 0 ? Icons.volume_off : Icons.volume_up);
    } else {
      widget.player.setBrightness(v);
      _showIndicator(
          'Brightness ${(v * 100).round()}%', Icons.brightness_6_outlined);
    }
  }

  void _onVerticalDragEnd(DragEndDetails d) {
    _dragMode = _DragMode.none;
  }

  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final player = widget.player;

    return PopScope(
      canPop: !_isFullscreen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _isFullscreen) _toggleFullscreen();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: _isFullscreen
            ? null
            : AppBar(
                backgroundColor: Colors.black,
                title: AnimatedBuilder(
                  animation: player,
                  builder: (context, _) => Text(
                    player.currentTrack?.title ?? 'Max Player',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                actions: [
                  IconButton(
                    tooltip: 'Player settings',
                    icon: const Icon(Icons.settings_outlined),
                    onPressed: _openSettings,
                  ),
                ],
              ),
        body: SafeArea(
          top: !_isFullscreen,
          // Lift controls above the gesture/nav bar in landscape fullscreen.
          bottom: true,
          child: Row(
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    _gestureWidth = constraints.maxWidth;
                    _gestureHeight = constraints.maxHeight;
                    return GestureDetector(
                      onTap: _toggleControls,
                      onDoubleTapDown: (d) =>
                          _lastDoubleTapDx = d.localPosition.dx,
                      onDoubleTap: _onDoubleTap,
                      onVerticalDragStart: _onVerticalDragStart,
                      onVerticalDragUpdate: _onVerticalDragUpdate,
                      onVerticalDragEnd: _onVerticalDragEnd,
                      onScaleStart: _onScaleStart,
                      onScaleUpdate: _onScaleUpdate,
                      onScaleEnd: _onScaleEnd,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          // Video surface - pinch zoom/pan applies a matrix
                          // (scale about the finger focal point), clipped to
                          // the available area.
                          Positioned.fill(
                            child: ClipRect(
                              child: Transform(
                                transform: Matrix4.identity()
                                  ..translateByDouble(_pan.dx, _pan.dy, 0, 1)
                                  ..scaleByDouble(_zoom, _zoom, _zoom, 1),
                                child: Center(
                                  child: player.currentTrack != null
                                      ? RepaintBoundary(
                                          child: Video(
                                            controller: _controller,
                                            controls: NoVideoControls,
                                            fit: _fits[_fitIndex],
                                          ),
                                        )
                                      : const Text('No video loaded',
                                          style: TextStyle(
                                              color: Colors.white38)),
                                ),
                              ),
                            ),
                          ),
                          // Buffering spinner - follows the player stream only.
                          Positioned.fill(
                            child: AnimatedBuilder(
                              animation: player,
                              builder: (context, _) => player.isLoading
                                  ? const Center(
                                      child: CircularProgressIndicator(
                                          color: Color(0xFFA855F7)),
                                    )
                                  : const SizedBox.shrink(),
                            ),
                          ),
                          // Transient indicator (seek / volume / brightness /
                          // zoom / resume / fit / play-pause).
                          if (_indicatorText != null)
                            Positioned(
                              top: 72,
                              left: 0,
                              right: 0,
                              child: IgnorePointer(
                                child: Center(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 10),
                                    decoration: BoxDecoration(
                                      color:
                                          Colors.black.withValues(alpha: 0.72),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (_indicatorIcon != null) ...[
                                          Icon(_indicatorIcon,
                                              color: Colors.white, size: 20),
                                          const SizedBox(width: 8),
                                        ],
                                        Text(
                                          _indicatorText!,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          if (_controlsVisible)
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: PlayerControlsOverlay(
                                player: player,
                                isFullscreen: _isFullscreen,
                                onToggleFullscreen: _toggleFullscreen,
                                onToggleQueue: () {
                                  setState(() => _showQueue = !_showQueue);
                                  _onUserInteraction();
                                },
                                onInteract: _onUserInteraction,
                                onCycleFit: _cycleFit,
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              if (_showQueue && !_isFullscreen)
                SizedBox(
                  width: 280,
                  child: Container(
                    color: const Color(0xFF12121a),
                    child: AnimatedBuilder(
                      animation: player,
                      builder: (context, _) => PlaylistPanel(
                        playlist: player.playlist,
                        currentIndex: player.currentIndex,
                        onPlay: player.playTrack,
                        onRemove: player.removeFromPlaylist,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _DragMode { none, volume, brightness }
