import 'dart:io';

import 'package:flutter/material.dart';
import '../utils/formatters.dart';
import '../state/theme_state.dart';

/// The seek slider + time labels.
///
/// v19: while the user DRAGS, a preview bubble floats above the thumb
/// showing the video frame at that position (once the native thumbnail
/// strip is ready) plus the exact timestamp.
class VideoProgressBar extends StatefulWidget {
  final Duration position;
  final Duration duration;
  final ValueChanged<Duration> onSeek;

  /// Optional thumbnail lookup for the scrub preview bubble: receives a
  /// 0..1 fraction of the video and returns an image path, or null while
  /// that frame hasn't been generated yet (the bubble shows a placeholder).
  final String? Function(double fraction)? previewThumb;

  const VideoProgressBar({
    super.key,
    required this.position,
    required this.duration,
    required this.onSeek,
    this.previewThumb,
  });

  @override
  State<VideoProgressBar> createState() => _VideoProgressBarState();
}

class _VideoProgressBarState extends State<VideoProgressBar> {
  double? _dragValue; // 0..1 while the user is dragging

  @override
  Widget build(BuildContext context) {
    final totalMs = widget.duration.inMilliseconds.clamp(1, 1 << 62);
    final value =
        _dragValue ?? (widget.position.inMilliseconds / totalMs).clamp(0.0, 1.0);
    final shownMs = (_dragValue != null
            ? _dragValue! * totalMs
            : widget.position.inMilliseconds)
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
              final thumbPath = dragging && widget.previewThumb != null
                  ? widget.previewThumb!(_dragValue!)
                  : null;
              // Keep the bubble fully on screen.
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
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 6),
                      overlayShape:
                          const RoundSliderOverlayShape(overlayRadius: 14),
                      activeTrackColor: themeState.accent,
                      inactiveTrackColor:
                          themeState.accent.withValues(alpha: 0.15),
                      thumbColor: themeState.accent,
                    ),
                    child: Slider(
                      value: value,
                      onChanged: (v) => setState(() => _dragValue = v),
                      onChangeEnd: (v) {
                        widget.onSeek(
                            Duration(milliseconds: (v * totalMs).round()));
                        setState(() => _dragValue = null);
                      },
                    ),
                  ),
                  if (dragging)
                    Positioned(
                      bottom: 30,
                      left: left,
                      child: IgnorePointer(
                        child: Container(
                          width: bubbleW,
                          padding: const EdgeInsets.fromLTRB(5, 5, 5, 6),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.88),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: themeState.accent
                                    .withValues(alpha: 0.35)),
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
                                          File(thumbPath),
                                          fit: BoxFit.cover,
                                          gaplessPlayback: true,
                                          // Frames arriving mid-drag.
                                          errorBuilder: (_, __, ___) =>
                                              const _NoThumb(),
                                        )
                                      : const _NoThumb(),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                formatDuration(
                                    Duration(milliseconds: shownMs)),
                                style: TextStyle(
                                  color: themeState.accent,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        const SizedBox(width: 4),
        Text(formatDuration(widget.duration), style: _timeStyle),
      ],
    );
  }

  // v23: time labels ride the theme colour (75% strength, like all
  // secondary player chrome).
  static final _timeStyle = TextStyle(
      fontSize: 12, color: themeState.accent.withValues(alpha: 0.75));
}

class _NoThumb extends StatelessWidget {
  const _NoThumb();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1e1e2a),
      child: Center(
        child: Icon(Icons.movie_outlined,
            size: 18, color: themeState.accent.withValues(alpha: 0.35)),
      ),
    );
  }
}
