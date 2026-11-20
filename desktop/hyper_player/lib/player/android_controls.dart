import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'fit.dart';
import 'queue_order.dart';

@immutable
class PlaybackSnapshot {
  final Duration position, duration;
  final bool playing, buffering;
  final double volume, rate;
  const PlaybackSnapshot(
      {this.position = Duration.zero,
      this.duration = Duration.zero,
      this.playing = false,
      this.buffering = false,
      this.volume = 100,
      this.rate = 1});
}

String playbackClock(Duration time) {
  final value = time.inSeconds.clamp(0, 999999999);
  final prefix = value >= 3600 ? '${value ~/ 3600}:' : '';
  return '$prefix${(value ~/ 60 % 60).toString().padLeft(2, '0')}:${(value % 60).toString().padLeft(2, '0')}';
}

/// Android TopBar/BottomBar organisation; mouse/keyboard instead of phone rotation.
/// Native callbacks live outside this presentation widget so it is testable without
/// constructing a native player or claiming unsupported controls work.
class AndroidPlayerControls extends StatefulWidget {
  final ValueListenable<PlaybackSnapshot> playback;
  final String title;
  final bool shuffle;
  final QueueRepeat repeat;
  final FitMode fit;
  final bool canPrevious, canNext;
  final bool autoHide;
  final VoidCallback onBack,
      onPlayPause,
      onPrevious,
      onNext,
      onShuffle,
      onRepeat,
      onFit,
      onSpeed,
      onExtras,
      onQueue,
      onSettings;
  final Future<void> Function() onFullscreen;
  final ValueChanged<String> onMenu;
  final ValueChanged<Duration> onSeek;
  final ValueChanged<double> onVolume;
  const AndroidPlayerControls(
      {super.key,
      required this.playback,
      required this.title,
      required this.shuffle,
      required this.repeat,
      required this.fit,
      required this.canPrevious,
      required this.canNext,
      required this.onBack,
      required this.onPlayPause,
      required this.onPrevious,
      required this.onNext,
      required this.onShuffle,
      required this.onRepeat,
      required this.onFit,
      required this.onSpeed,
      required this.onExtras,
      required this.onQueue,
      required this.onSettings,
      required this.onFullscreen,
      required this.onMenu,
      required this.onSeek,
      required this.onVolume,
      this.autoHide = true});
  @override
  State<AndroidPlayerControls> createState() => _AndroidPlayerControlsState();
}

class _AndroidPlayerControlsState extends State<AndroidPlayerControls> {
  bool visible = true, locked = false;
  double? dragging;
  double beforeMute = 100;
  Timer? hide;
  final focus = FocusNode(debugLabel: 'Android player controls');
  @override
  void initState() {
    super.initState();
    widget.playback.addListener(playbackChanged);
    armHide();
  }

  @override
  void didUpdateWidget(covariant AndroidPlayerControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playback != widget.playback) {
      oldWidget.playback.removeListener(playbackChanged);
      widget.playback.addListener(playbackChanged);
    }
    if (oldWidget.autoHide != widget.autoHide) {
      if (!widget.autoHide) setState(() => visible = true);
      armHide();
    }
  }

  void playbackChanged() {
    if (!widget.playback.value.playing) {
      hide?.cancel();
      if (mounted && !visible) setState(() => visible = true);
    } else if (visible && hide?.isActive != true) {
      armHide();
    }
  }

  void armHide() {
    hide?.cancel();
    if (widget.autoHide && widget.playback.value.playing && visible) {
      hide = Timer(const Duration(seconds: 4), () {
        if (mounted && dragging == null) setState(() => visible = false);
      });
    }
  }

  void wake() {
    if (!visible) setState(() => visible = true);
    armHide();
  }

  void seekBy(int seconds) {
    final state = widget.playback.value;
    final ms = (state.position.inMilliseconds + seconds * 1000)
        .clamp(0, state.duration.inMilliseconds.clamp(0, 1 << 53));
    widget.onSeek(Duration(milliseconds: ms));
  }

  void mute() {
    final volume = widget.playback.value.volume;
    if (volume > 0) {
      beforeMute = volume;
      widget.onVolume(0);
    } else {
      widget.onVolume(beforeMute);
    }
  }

  KeyEventResult key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final k = event.logicalKey;
    if (k == LogicalKeyboardKey.escape && locked) {
      setState(() {
        locked = false;
        visible = true;
      });
      armHide();
      return KeyEventResult.handled;
    }
    if (locked) return KeyEventResult.ignored;
    if (HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isAltPressed ||
        HardwareKeyboard.instance.isMetaPressed) {
      return KeyEventResult.ignored;
    }
    if (k == LogicalKeyboardKey.space) {
      widget.onPlayPause();
    } else if (k == LogicalKeyboardKey.arrowLeft) {
      seekBy(-10);
    } else if (k == LogicalKeyboardKey.arrowRight) {
      seekBy(10);
    } else if (k == LogicalKeyboardKey.keyM) {
      mute();
    } else if (k == LogicalKeyboardKey.keyF) {
      widget.onFullscreen();
    } else if (k == LogicalKeyboardKey.arrowUp ||
        k == LogicalKeyboardKey.arrowDown) {
      widget.onVolume((widget.playback.value.volume +
              (k == LogicalKeyboardKey.arrowUp ? 5 : -5))
          .clamp(0, 100));
    } else {
      return KeyEventResult.ignored;
    }
    wake();
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    hide?.cancel();
    widget.playback.removeListener(playbackChanged);
    focus.dispose();
    super.dispose();
  }

  Widget button(String tooltip, IconData icon, VoidCallback? action,
          {bool active = false, double size = 22}) =>
      IconButton(
          tooltip: tooltip,
          icon: Icon(icon,
              size: size,
              color: action == null
                  ? Colors.white24
                  : active
                      ? const Color(0xffc4b5fd)
                      : Colors.white),
          onPressed: action == null
              ? null
              : () {
                  wake();
                  action();
                });
  @override
  Widget build(BuildContext context) => Focus(
      autofocus: true,
      focusNode: focus,
      onKeyEvent: key,
      child: MouseRegion(
          onHover: (_) => wake(),
          child: ValueListenableBuilder<PlaybackSnapshot>(
              valueListenable: widget.playback,
              builder: (context, state, _) =>
                  Stack(fit: StackFit.expand, children: [
                    GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: () {
                          focus.requestFocus();
                          if (locked) {
                            wake();
                          } else {
                            setState(() => visible = !visible);
                            armHide();
                          }
                        },
                        onDoubleTap:
                            locked ? null : () => widget.onFullscreen(),
                        child: const SizedBox.expand()),
                    if (state.buffering)
                      const Center(
                          child: SizedBox(
                              width: 30,
                              height: 30,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2))),
                    if (visible && !locked) ...[
                      Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          child: DecoratedBox(
                              decoration: const BoxDecoration(
                                  gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                    Colors.black87,
                                    Colors.transparent
                                  ])),
                              child: SafeArea(
                                  bottom: false,
                                  child: Row(children: [
                                    button('Back', Icons.arrow_back,
                                        widget.onBack),
                                    Expanded(
                                        child: Text(widget.title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 15,
                                                fontWeight: FontWeight.w600))),
                                    PopupMenuButton<String>(
                                        tooltip: 'More actions',
                                        color: const Color(0xff1a1a24),
                                        icon: const Icon(Icons.more_vert,
                                            color: Colors.white),
                                        onOpened: () => hide?.cancel(),
                                        onCanceled: armHide,
                                        onSelected: (value) {
                                          widget.onMenu(value);
                                          armHide();
                                        },
                                        itemBuilder: (_) => [
                                              for (final row in const [
                                                (
                                                  'Video info',
                                                  Icons.info_outline
                                                ),
                                                (
                                                  'Equalizer & Audio FX',
                                                  Icons.graphic_eq
                                                ),
                                                (
                                                  'Screenshot',
                                                  Icons.camera_alt_outlined
                                                ),
                                                (
                                                  'Sleep timer',
                                                  Icons.bedtime_outlined
                                                )
                                              ])
                                                PopupMenuItem(
                                                    value: row.$1,
                                                    child: Row(children: [
                                                      Icon(row.$2,
                                                          color: Colors.white,
                                                          size: 19),
                                                      const SizedBox(width: 12),
                                                      Text(row.$1)
                                                    ])),
                                              const PopupMenuItem(
                                                  enabled: false,
                                                  child: Tooltip(
                                                      message:
                                                          'Native Windows casting integration is not implemented',
                                                      child: Text(
                                                          'Cast to TV · unavailable'))),
                                              const PopupMenuItem(
                                                  enabled: false,
                                                  child: Tooltip(
                                                      message:
                                                          'Native picture-in-picture window is not implemented',
                                                      child: Text(
                                                          'Picture-in-Picture · unavailable'))),
                                            ]),
                                    button(
                                        'Player settings',
                                        Icons.settings_outlined,
                                        widget.onSettings),
                                  ])))),
                      Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          child: DecoratedBox(
                              decoration: const BoxDecoration(
                                  gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                    Colors.transparent,
                                    Colors.black87
                                  ])),
                              child: SafeArea(
                                  top: false,
                                  child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Padding(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 14),
                                            child: Row(children: [
                                              Text(
                                                  playbackClock(Duration(
                                                      milliseconds: dragging
                                                              ?.round() ??
                                                          state.position
                                                              .inMilliseconds)),
                                                  style: const TextStyle(
                                                      color: Colors.white70,
                                                      fontSize: 11)),
                                              Expanded(
                                                  child: Slider(
                                                      value: (dragging ??
                                                              state.position
                                                                  .inMilliseconds
                                                                  .toDouble())
                                                          .clamp(
                                                              0,
                                                              state.duration
                                                                  .inMilliseconds
                                                                  .clamp(1,
                                                                      1 << 53)
                                                                  .toDouble()),
                                                      max: state.duration
                                                          .inMilliseconds
                                                          .clamp(1, 1 << 53)
                                                          .toDouble(),
                                                      activeColor: Colors.white,
                                                      inactiveColor:
                                                          Colors.white24,
                                                      onChangeStart: state
                                                                  .duration >
                                                              Duration.zero
                                                          ? (v) {
                                                              hide?.cancel();
                                                              setState(() =>
                                                                  dragging = v);
                                                            }
                                                          : null,
                                                      onChanged: state.duration >
                                                              Duration.zero
                                                          ? (v) =>
                                                              setState(() => dragging = v)
                                                          : null,
                                                      onChangeEnd: state.duration > Duration.zero
                                                          ? (v) {
                                                              widget.onSeek(Duration(
                                                                  milliseconds:
                                                                      v.round()));
                                                              setState(() =>
                                                                  dragging =
                                                                      null);
                                                              armHide();
                                                            }
                                                          : null)),
                                              Text(
                                                  playbackClock(state.duration),
                                                  style: const TextStyle(
                                                      color: Colors.white70,
                                                      fontSize: 11))
                                            ])),
                                        Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              button(
                                                  'Shuffle: ${widget.shuffle ? "on" : "off"}',
                                                  Icons.shuffle,
                                                  widget.onShuffle,
                                                  active: widget.shuffle),
                                              button(
                                                  'Previous video',
                                                  Icons.skip_previous,
                                                  widget.canPrevious
                                                      ? widget.onPrevious
                                                      : null,
                                                  size: 30),
                                              const SizedBox(width: 16),
                                              button(
                                                  state.playing
                                                      ? 'Pause'
                                                      : 'Play',
                                                  state.playing
                                                      ? Icons
                                                          .pause_circle_filled
                                                      : Icons.play_circle_fill,
                                                  widget.onPlayPause,
                                                  size: 50),
                                              const SizedBox(width: 16),
                                              button(
                                                  'Next video',
                                                  Icons.skip_next,
                                                  widget.canNext
                                                      ? widget.onNext
                                                      : null,
                                                  size: 30),
                                              button(
                                                  'Repeat: ${widget.repeat.name}',
                                                  widget.repeat ==
                                                          QueueRepeat.one
                                                      ? Icons.repeat_one
                                                      : Icons.repeat,
                                                  widget.onRepeat,
                                                  active: widget.repeat !=
                                                      QueueRepeat.off),
                                            ]),
                                        SizedBox(
                                            height: 46,
                                            child: SingleChildScrollView(
                                                scrollDirection:
                                                    Axis.horizontal,
                                                child: Row(children: [
                                                  button(
                                                      state.volume == 0
                                                          ? 'Unmute'
                                                          : 'Mute',
                                                      state.volume == 0
                                                          ? Icons.volume_off
                                                          : Icons.volume_up,
                                                      mute),
                                                  SizedBox(
                                                      width: 100,
                                                      child: Slider(
                                                          value: state.volume
                                                              .clamp(0, 100),
                                                          max: 100,
                                                          activeColor:
                                                              Colors.white,
                                                          inactiveColor:
                                                              Colors.white24,
                                                          onChanged:
                                                              widget.onVolume)),
                                                  TextButton(
                                                      onPressed: widget.onSpeed,
                                                      child: Text(
                                                          '${state.rate}x',
                                                          style: const TextStyle(
                                                              color:
                                                                  Colors.white,
                                                              fontSize: 13,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold))),
                                                  button(
                                                      'Subtitles, audio tracks, A-B loop, karaoke',
                                                      Icons.tune,
                                                      widget.onExtras),
                                                  button(
                                                      'Playlists',
                                                      Icons.playlist_play,
                                                      widget.onQueue),
                                                  button(
                                                      'Fit: ${widget.fit.label}',
                                                      Icons.aspect_ratio,
                                                      widget.onFit),
                                                  button(
                                                      'Lock controls (Escape to unlock)',
                                                      Icons.lock_open,
                                                      () => setState(() {
                                                            locked = true;
                                                            visible = true;
                                                          })),
                                                  button(
                                                      'Fullscreen (F)',
                                                      Icons.fullscreen,
                                                      () => widget
                                                          .onFullscreen()),
                                                ]))),
                                      ])))),
                    ],
                    if (locked && visible)
                      Positioned(
                          right: 12,
                          top: 60,
                          child: button(
                              'Unlock controls (Escape)',
                              Icons.lock,
                              () => setState(() {
                                    locked = false;
                                    visible = true;
                                  }))),
                  ]))));
}
