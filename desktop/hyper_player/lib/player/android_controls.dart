import '../utils/player_settings.dart';
import 'video_zoom.dart';
import 'timeline_preview.dart';
import 'sleep_status.dart';
import 'package:flutter/gestures.dart';
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
  final Widget? karaokeOverlay;
  final String previewSourceKey;
  final void Function(double zoom, Offset pan)? onTransform;
  final ValueChanged<double>? onTemporaryRate;
  final ValueChanged<FitMode>? onSelectFit;
  final PreviewLoader? previewLoader;
  final bool shuffle;
  final QueueRepeat repeat;
  final FitMode fit;
  final bool canPrevious, canNext;
  final bool autoHide;
  final DateTime? sleepDeadline;
  final bool sleepUntilEnd;
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
      this.previewSourceKey = '',
      this.karaokeOverlay,
      this.onTransform,
      this.onTemporaryRate,
      this.onSelectFit,
      this.previewLoader,
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
      this.sleepDeadline,
      this.sleepUntilEnd = false,
      this.autoHide = true});
  @override
  State<AndroidPlayerControls> createState() => _AndroidPlayerControlsState();
}

class _AndroidPlayerControlsState extends State<AndroidPlayerControls> {
  bool visible = true, locked = false;
  double? dragging;
  double beforeMute = 100;
  bool touchInput = false, fitGestureDone = false;
  Offset gestureStart = Offset.zero;
  Duration gesturePosition = Duration.zero;
  double gestureVolume = 100, brightness = 1, startBrightness = 1;
  Duration? touchSeek;
  String? gestureAxis, gestureMessage;
  TapDownDetails? doubleTapDetails;
  PlayerSettings get prefs => PlayerSettings.instance;
  double get maximumVolume => prefs.volumeBoost ? 200 : 100;
  double zoom = 1, startZoom = 1;
  Offset pan = Offset.zero, startPan = Offset.zero;
  bool multiple = false, scaled = false;
  double travel = 0;
  int baseFit = 0;
  DateTime? touchStart;
  double? heldRate;
  Timer? feedbackTimer;
  void feedback(String text) {
    feedbackTimer?.cancel();
    if (mounted) setState(() => gestureMessage = text);
    feedbackTimer = Timer(const Duration(milliseconds: 1100), () {
      if (mounted) setState(() => gestureMessage = null);
    });
  }

  void changeVolume(double value) {
    final next = value.clamp(0.0, maximumVolume);
    widget.onVolume(next);
    feedback('Volume ${next.round()}%');
  }

  void changeBrightness(double value) {
    setState(() => brightness = value.clamp(.15, 1.0));
    feedback('Video brightness ${(brightness * 100).round()}%');
  }

  Future<void> adjustments() async {
    hide?.cancel();
    var volume = widget.playback.value.volume.clamp(0.0, maximumVolume);
    await showModalBottomSheet<void>(
        context: context,
        builder: (sheetContext) => StatefulBuilder(
            builder: (_, update) => SafeArea(
                child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Text('Brightness & volume',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                      Text(
                          'Video brightness ${(brightness * 100).round()}% · [ / ]'),
                      Slider(
                          value: brightness,
                          min: .15,
                          max: 1,
                          onChanged: (value) {
                            changeBrightness(value);
                            update(() {});
                          }),
                      Text(
                          'Media volume ${volume.round()}% · Up/Down or mouse wheel'),
                      Slider(
                          value: volume,
                          min: 0,
                          max: maximumVolume,
                          onChanged: (value) {
                            volume = value;
                            changeVolume(value);
                            update(() {});
                          }),
                      const Text(
                          'Brightness dims this video, not the Windows display. Check system output/mixer if media remains silent.',
                          style: TextStyle(fontSize: 12)),
                    ])))));
    armHide();
  }

  void emitTransform() {
    final size = context.size ?? const Size(800, 450);
    widget.onTransform?.call(zoom,
        Offset(pan.dx / (size.width * zoom), pan.dy / (size.height * zoom)));
  }

  void restoreHeldRate() {
    final rate = heldRate;
    heldRate = null;
    if (rate != null) widget.onTemporaryRate?.call(rate);
  }

  void startTouch(ScaleStartDetails details) {
    if (!touchInput || locked) return;
    hide?.cancel();
    feedbackTimer?.cancel();
    gestureStart = details.localFocalPoint;
    gesturePosition = widget.playback.value.position;
    gestureVolume = widget.playback.value.volume;
    startBrightness = brightness;
    gestureAxis = null;
    touchSeek = null;
    fitGestureDone = false;
    startZoom = zoom;
    startPan = pan;
    multiple = details.pointerCount > 1;
    scaled = false;
    travel = 0;
    baseFit = widget.fit.index;
    touchStart = DateTime.now();
  }

  void updateTouch(ScaleUpdateDetails details) {
    if (!touchInput || locked) return;
    if (details.pointerCount > 1) {
      multiple = true;
      travel += details.focalPointDelta.distance;
      scaled = scaled || (details.scale - 1).abs() > .05;
      touchSeek = null;
      final size = context.size ?? const Size(800, 450);
      if (prefs.pinchZoom && widget.onTransform != null) {
        zoom = freeZoomFor(baseZoom: startZoom, scale: details.scale);
        pan = clampPanFor(
            pan: pinchPanFor(
                startFocal: gestureStart,
                liveFocal: details.localFocalPoint,
                startPan: startPan,
                startZoom: startZoom,
                zoom: zoom,
                size: size),
            zoom: zoom,
            size: size);
        emitTransform();
        setState(() => gestureMessage = 'Zoom ${zoom.toStringAsFixed(1)}x');
      } else {
        final next = wrapFitLadderPos(
            fitLadderPosFor(basePos: baseFit.toDouble(), scale: details.scale),
            FitMode.values.length);
        if (next != widget.fit.index && scaled) {
          if (widget.onSelectFit != null) {
            widget.onSelectFit!(FitMode.values[next]);
          } else if (!fitGestureDone) {
            widget.onFit();
            fitGestureDone = true;
          }
          setState(() => gestureMessage = 'Video fit');
        }
      }
      return;
    }
    if (multiple) return;
    final delta = details.localFocalPoint - gestureStart;
    if (gestureAxis == null && delta.distance < 14) return;
    gestureAxis ??= delta.dx.abs() > delta.dy.abs() ? 'seek' : 'vertical';
    final size = context.size ?? const Size(800, 450);
    if (zoom > 1 && widget.onTransform != null) {
      pan = clampPanFor(pan: startPan + delta, zoom: zoom, size: size);
      emitTransform();
      return;
    }
    if (gestureAxis == 'seek') {
      if (!prefs.horizontalSeek) return;
      final duration = widget.playback.value.duration.inMilliseconds;
      if (duration <= 0) return;
      final change = delta.dx / size.width * 90000;
      touchSeek = Duration(
          milliseconds: (gesturePosition.inMilliseconds + change)
              .round()
              .clamp(0, duration));
      setState(() => gestureMessage = 'Seek ${playbackClock(touchSeek!)}');
    } else if (gestureStart.dx >= size.width / 2) {
      if (!prefs.swipeVolume) return;
      final next = (gestureVolume - delta.dy / size.height * 100)
          .clamp(0.0, maximumVolume);
      widget.onVolume(next);
      setState(() => gestureMessage = 'Volume ${next.round()}%');
    } else {
      if (!prefs.swipeBrightness) return;
      setState(() {
        brightness = (startBrightness - delta.dy / size.height).clamp(.15, 1.0);
        gestureMessage = 'Video brightness ${(brightness * 100).round()}%';
      });
    }
  }

  void endTouch(ScaleEndDetails details) {
    if (!touchInput || locked) return;
    if (multiple &&
        isTwoFingerTapReset(
            durationMs: DateTime.now()
                .difference(touchStart ?? DateTime.now())
                .inMilliseconds,
            travelPx: travel,
            scaled: scaled)) {
      zoom = 1;
      pan = Offset.zero;
      emitTransform();
      widget.onSelectFit?.call(FitMode.values[prefs.defaultFit]);
    }
    if (touchSeek != null) widget.onSeek(touchSeek!);
    setState(() {
      touchSeek = null;
    });
    if (gestureMessage != null) feedback(gestureMessage!);
    armHide();
  }

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
    if (oldWidget.previewSourceKey != widget.previewSourceKey ||
        oldWidget.fit != widget.fit) {
      zoom = 1;
      pan = Offset.zero;
      emitTransform();
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
      hide = Timer(Duration(seconds: prefs.autoHideDelay), () {
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
    feedback('Seek ${playbackClock(Duration(milliseconds: ms))}');
  }

  void mute() {
    final volume = widget.playback.value.volume;
    if (volume > 0) {
      beforeMute = volume;
      changeVolume(0);
    } else {
      changeVolume(beforeMute);
    }
  }

  KeyEventResult key(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent &&
        event.logicalKey == LogicalKeyboardKey.keyR &&
        heldRate != null) {
      restoreHeldRate();
      return KeyEventResult.handled;
    }
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
    if (HardwareKeyboard.instance.isShiftPressed &&
        zoom > 1 &&
        [
          LogicalKeyboardKey.arrowLeft,
          LogicalKeyboardKey.arrowRight,
          LogicalKeyboardKey.arrowUp,
          LogicalKeyboardKey.arrowDown
        ].contains(k)) {
      final dx = k == LogicalKeyboardKey.arrowLeft
          ? 40.0
          : k == LogicalKeyboardKey.arrowRight
              ? -40.0
              : 0.0;
      final dy = k == LogicalKeyboardKey.arrowUp
          ? 40.0
          : k == LogicalKeyboardKey.arrowDown
              ? -40.0
              : 0.0;
      pan = clampPanFor(
          pan: pan + Offset(dx, dy),
          zoom: zoom,
          size: context.size ?? const Size(800, 450));
      emitTransform();
      feedback('Pan');
    } else if (k == LogicalKeyboardKey.keyH) {
      setState(() => visible = !visible);
      armHide();
      return KeyEventResult.handled;
    } else if (k == LogicalKeyboardKey.keyL && prefs.screenLock) {
      setState(() {
        locked = true;
        visible = true;
      });
    } else if (k == LogicalKeyboardKey.keyB) {
      adjustments();
    } else if (k == LogicalKeyboardKey.bracketLeft ||
        k == LogicalKeyboardKey.bracketRight) {
      changeBrightness(
          brightness + (k == LogicalKeyboardKey.bracketRight ? .05 : -.05));
    } else if (k == LogicalKeyboardKey.keyZ) {
      widget.onFit();
      feedback('Fit: ${nextFitMode(widget.fit).label}');
    } else if ((k == LogicalKeyboardKey.keyI || k == LogicalKeyboardKey.keyO) &&
        widget.onTransform != null) {
      zoom =
          (zoom + (k == LogicalKeyboardKey.keyI ? .25 : -.25)).clamp(1.0, 4.0);
      pan = clampPanFor(
          pan: pan, zoom: zoom, size: context.size ?? const Size(800, 450));
      emitTransform();
      feedback('Zoom ${zoom.toStringAsFixed(2)}x');
    } else if (k == LogicalKeyboardKey.keyR &&
        prefs.longPressSpeed &&
        widget.onTemporaryRate != null) {
      if (heldRate == null) {
        heldRate = widget.playback.value.rate;
        widget.onTemporaryRate!(prefs.longPressRate);
        feedback('Speed ${prefs.longPressRate}x');
      }
    } else if (k == LogicalKeyboardKey.space) {
      widget.onPlayPause();
    } else if (k == LogicalKeyboardKey.arrowLeft) {
      seekBy(-prefs.seekStep);
    } else if (k == LogicalKeyboardKey.arrowRight) {
      seekBy(prefs.seekStep);
    } else if (k == LogicalKeyboardKey.keyM) {
      mute();
    } else if (k == LogicalKeyboardKey.keyF) {
      widget.onFullscreen();
    } else if (k == LogicalKeyboardKey.arrowUp ||
        k == LogicalKeyboardKey.arrowDown) {
      changeVolume((widget.playback.value.volume +
              (k == LogicalKeyboardKey.arrowUp ? 5 : -5))
          .clamp(0, maximumVolume));
    } else {
      return KeyEventResult.ignored;
    }
    wake();
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    feedbackTimer?.cancel();
    restoreHeldRate();
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
                        onDoubleTapDown: (details) =>
                            doubleTapDetails = details,
                        onDoubleTap: locked
                            ? null
                            : () {
                                final details = doubleTapDetails;
                                if (details?.kind == PointerDeviceKind.touch) {
                                  final width = context.size?.width ?? 800;
                                  if (details!.localPosition.dx < width / 3) {
                                    if (!prefs.doubleTapSides) return;
                                    seekBy(-prefs.seekStep);
                                  } else if (details.localPosition.dx >
                                      width * 2 / 3) {
                                    if (!prefs.doubleTapSides) return;
                                    seekBy(prefs.seekStep);
                                  } else {
                                    if (prefs.doubleTapMiddle) {
                                      widget.onPlayPause();
                                    }
                                  }
                                  wake();
                                } else {
                                  widget.onFullscreen();
                                }
                              },
                        onLongPressStart: (_) {
                          if (!locked &&
                              touchInput &&
                              prefs.longPressSpeed &&
                              widget.onTemporaryRate != null) {
                            heldRate = widget.playback.value.rate;
                            widget.onTemporaryRate!(prefs.longPressRate);
                            feedback('Speed ${prefs.longPressRate}x');
                          }
                        },
                        onLongPressEnd: (_) => restoreHeldRate(),
                        onLongPressCancel: restoreHeldRate,
                        onScaleStart: locked ? null : startTouch,
                        onScaleUpdate: locked ? null : updateTouch,
                        onScaleEnd: locked ? null : endTouch,
                        child: Listener(
                          behavior: HitTestBehavior.translucent,
                          onPointerSignal: (event) {
                            if (!locked && event is PointerScrollEvent) {
                              changeVolume((widget.playback.value.volume +
                                      (event.scrollDelta.dy < 0 ? 5 : -5))
                                  .clamp(0, maximumVolume));
                              wake();
                            }
                          },
                          onPointerDown: (event) => touchInput =
                              event.kind == PointerDeviceKind.touch,
                          child: const SizedBox.expand(),
                        )),
                    if (brightness < 1)
                      Positioned.fill(
                          child: IgnorePointer(
                              child: ColoredBox(
                                  color: Colors.black
                                      .withValues(alpha: 1 - brightness)))),
                    if (gestureMessage != null)
                      Center(
                          child: IgnorePointer(
                              child: DecoratedBox(
                        decoration: BoxDecoration(
                            color: Colors.black87,
                            borderRadius: BorderRadius.circular(12)),
                        child: Padding(
                            padding: const EdgeInsets.all(16),
                            child:
                                Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(
                                  gestureMessage!.startsWith('Volume')
                                      ? Icons.volume_up
                                      : gestureMessage!.contains('brightness')
                                          ? Icons.brightness_6
                                          : gestureMessage!.startsWith('Fit') ||
                                                  gestureMessage!
                                                      .startsWith('Video fit')
                                              ? Icons.aspect_ratio
                                              : gestureMessage!
                                                      .startsWith('Speed')
                                                  ? Icons.speed
                                                  : gestureMessage!
                                                          .startsWith('Zoom')
                                                      ? Icons.zoom_in
                                                      : Icons.swap_horiz,
                                  color: Colors.white),
                              const SizedBox(width: 10),
                              Text(gestureMessage!,
                                  style: const TextStyle(color: Colors.white)),
                            ])),
                      ))),
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
                                        child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(widget.title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 15,
                                                fontWeight: FontWeight.w600)),
                                        SleepStatusChip(
                                            deadline: widget.sleepDeadline,
                                            untilEnd: widget.sleepUntilEnd),
                                      ],
                                    )),
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
                                                  'Playback queue',
                                                  Icons.queue_music
                                                ),
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
                                                  value: 'Cast to TV',
                                                  child: Text(
                                                      'Cast to TV · Windows wireless display')),
                                              const PopupMenuItem(
                                                value: 'Picture-in-Picture',
                                                child: Text(
                                                    'Picture-in-Picture · Windows mini-player'),
                                              ),
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
                                                  child: HoverTimeline(
                                                      sourceKey: widget
                                                          .previewSourceKey,
                                                      duration: state.duration,
                                                      loader:
                                                          widget.previewLoader,
                                                      child: Slider(
                                                          value: (dragging ?? state.position.inMilliseconds.toDouble()).clamp(
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
                                                          activeColor:
                                                              Colors.white,
                                                          inactiveColor:
                                                              Colors.white24,
                                                          onChangeStart: state
                                                                      .duration >
                                                                  Duration.zero
                                                              ? (v) {
                                                                  hide?.cancel();
                                                                  setState(() =>
                                                                      dragging =
                                                                          v);
                                                                }
                                                              : null,
                                                          onChanged: state.duration >
                                                                  Duration.zero
                                                              ? (v) => setState(
                                                                  () => dragging = v)
                                                              : null,
                                                          onChangeEnd: state.duration > Duration.zero
                                                              ? (v) {
                                                                  widget.onSeek(
                                                                      Duration(
                                                                          milliseconds:
                                                                              v.round()));
                                                                  setState(() =>
                                                                      dragging =
                                                                          null);
                                                                  armHide();
                                                                }
                                                              : null))),
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
                                              const SizedBox(width: 22),
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
                                              const SizedBox(width: 22),
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
                                            child: Row(children: [
                                              button(
                                                  state.volume == 0
                                                      ? 'Unmute'
                                                      : 'Mute',
                                                  state.volume == 0
                                                      ? Icons.volume_off
                                                      : Icons.volume_up,
                                                  mute),
                                              TextButton(
                                                  onPressed: widget.onSpeed,
                                                  child: Text('${state.rate}x',
                                                      style: const TextStyle(
                                                          color: Colors.white,
                                                          fontSize: 13,
                                                          fontWeight: FontWeight
                                                              .bold))),
                                              button(
                                                  'Subtitles, audio tracks, A-B loop, karaoke',
                                                  Icons.tune,
                                                  widget.onExtras),
                                              const Spacer(),
                                              button(
                                                  'Playlists',
                                                  Icons.playlist_play,
                                                  widget.onQueue),
                                              button('Fit: ${widget.fit.label}',
                                                  Icons.aspect_ratio, () {
                                                widget.onFit();
                                                feedback(
                                                    'Fit: ${nextFitMode(widget.fit).label}');
                                              }),
                                              button(
                                                  'Fullscreen (F)',
                                                  Icons.fullscreen,
                                                  () => widget.onFullscreen()),
                                            ])),
                                      ])))),
                    ],
                    if (!locked && widget.karaokeOverlay != null)
                      Positioned(
                          left: 24,
                          right: 24,
                          bottom: visible ? 180 : 48,
                          child: widget.karaokeOverlay!),
                    if (!locked && visible)
                      Positioned(
                          left: 12,
                          top: 60,
                          child: button('Brightness & volume (B)',
                              Icons.brightness_6_outlined, adjustments)),
                    if (!locked && visible && prefs.screenLock)
                      Positioned(
                          right: 12,
                          top: 60,
                          child: button(
                              'Lock controls (Escape to unlock)',
                              Icons.lock_open,
                              () => setState(() {
                                    locked = true;
                                    visible = true;
                                  }))),
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
