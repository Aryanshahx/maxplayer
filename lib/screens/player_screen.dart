import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../state/media_player_state.dart';
import '../widgets/player_controls_overlay.dart';
import '../widgets/playlist_panel.dart';

class PlayerScreen extends StatefulWidget {
  final MediaPlayerState player;

  const PlayerScreen({super.key, required this.player});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> with WidgetsBindingObserver {
  // Shared, app-lifetime controller owned by MediaPlayerState (this media_kit
  // version has no VideoController.dispose, so per-visit controllers leaked
  // and glitched the player).
  late final VideoController _controller = widget.player.videoController;

  bool _controlsVisible = true;
  bool _isFullscreen = false;
  bool _showQueue = false;

  // Controls auto-hide while playing.
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

  // Gesture plumbing (double-tap seek / volume swipe).
  double _gestureWidth = 0;
  double _lastDoubleTapDx = 0;
  double? _volumeDragStart; // volume when the right-side drag began
  double _volumeDragDy = 0;

  // NOTE: no addListener/setState on the player here. The ticking parts
  // (overlay, spinner, queue, title) listen via their own AnimatedBuilder,
  // so the video surface itself is never rebuilt during playback.

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _noticeSub =
        widget.player.notices.listen((m) => _showIndicator(m, Icons.history));
    _startHideTimer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hideTimer?.cancel();
    _indicatorTimer?.cancel();
    _noticeSub?.cancel();
    if (_isFullscreen) _exitFullscreen();
    // Do NOT keep the audio running after leaving the player screen.
    unawaited(widget.player.pause());
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

  // ---------------------------------------------------------------------------
  // Controls visibility
  // ---------------------------------------------------------------------------

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      // Only auto-hide during playback; keep controls up while paused.
      if (mounted && widget.player.isPlaying) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  /// Called by the overlay on every button press / seek / menu selection so
  /// the 4-second auto-hide countdown restarts on any interaction.
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
  // Fullscreen & fit
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
    _showIndicator('Fit: ${_fitNames[_fitIndex]}', Icons.aspect_ratio);
    _onUserInteraction();
  }

  // ---------------------------------------------------------------------------
  // Gestures
  // ---------------------------------------------------------------------------

  void _onDoubleTap() {
    final third = _gestureWidth / 3;
    if (_lastDoubleTapDx < third) {
      widget.player.seekBy(-10);
      _showIndicator('-10s', Icons.replay_10);
    } else if (_lastDoubleTapDx > _gestureWidth - third) {
      widget.player.seekBy(10);
      _showIndicator('+10s', Icons.forward_10);
    }
    // Middle third double-tap intentionally does nothing.
  }

  void _onVerticalDragStart(DragStartDetails d) {
    // Only the right half of the screen drives volume.
    if (d.localPosition.dx > _gestureWidth / 2) {
      _volumeDragStart =
          widget.player.isMuted ? 0.0 : widget.player.volume;
      _volumeDragDy = 0;
    } else {
      _volumeDragStart = null;
    }
  }

  void _onVerticalDragUpdate(DragUpdateDetails d) {
    final start = _volumeDragStart;
    if (start == null) return;
    _volumeDragDy -= d.delta.dy; // dragging up = louder
    final v = (start + _volumeDragDy / 300).clamp(0.0, 1.0);
    widget.player.setVolume(v);
    _showIndicator('Volume ${(v * 100).round()}%',
        v == 0 ? Icons.volume_off : Icons.volume_up);
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
                    return GestureDetector(
                      onTap: _toggleControls,
                      onDoubleTapDown: (d) =>
                          _lastDoubleTapDx = d.localPosition.dx,
                      onDoubleTap: _onDoubleTap,
                      onVerticalDragStart: _onVerticalDragStart,
                      onVerticalDragUpdate: _onVerticalDragUpdate,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Center(
                            child: player.currentTrack != null
                                ? RepaintBoundary(
                                    child: Video(
                                      controller: _controller,
                                      controls: NoVideoControls,
                                      fit: _fits[_fitIndex],
                                    ),
                                  )
                                : const Text('No video loaded',
                                    style: TextStyle(color: Colors.white38)),
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
                          // Transient indicator (seek / volume / resume / fit).
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
