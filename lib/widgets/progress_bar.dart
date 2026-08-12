import 'package:flutter/material.dart';
import '../utils/formatters.dart';
import '../state/theme_state.dart';

class VideoProgressBar extends StatefulWidget {
  final Duration position;
  final Duration duration;
  final ValueChanged<Duration> onSeek;

  const VideoProgressBar({
    super.key,
    required this.position,
    required this.duration,
    required this.onSeek,
  });

  @override
  State<VideoProgressBar> createState() => _VideoProgressBarState();
}

class _VideoProgressBarState extends State<VideoProgressBar> {
  double? _dragValue; // 0..1 while user is dragging

  @override
  Widget build(BuildContext context) {
    final totalMs = widget.duration.inMilliseconds.clamp(1, 1 << 62);
    final value = _dragValue ?? (widget.position.inMilliseconds / totalMs).clamp(0.0, 1.0);

    return Row(
      children: [
        Text(formatDuration(widget.position), style: _timeStyle),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              activeTrackColor: themeState.accent,
              inactiveTrackColor: Colors.white.withValues(alpha: 0.15),
              thumbColor: themeState.accent,
            ),
            child: Slider(
              value: value,
              onChanged: (v) => setState(() => _dragValue = v),
              onChangeEnd: (v) {
                widget.onSeek(Duration(milliseconds: (v * totalMs).round()));
                setState(() => _dragValue = null);
              },
            ),
          ),
        ),
        Text(formatDuration(widget.duration), style: _timeStyle),
      ],
    );
  }

  static const _timeStyle = TextStyle(fontSize: 12, color: Colors.white70);
}
