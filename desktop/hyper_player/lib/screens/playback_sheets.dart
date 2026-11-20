import 'package:flutter/material.dart';
import '../utils/app_language.dart';

Future<T?> showPlaybackSheet<T>(BuildContext context, Widget child,
        {Color color = const Color(0xff101013)}) =>
    showModalBottomSheet<T>(
        context: context,
        isScrollControlled: true,
        backgroundColor: color,
        constraints: const BoxConstraints(maxWidth: 1000),
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
        builder: (_) => SafeArea(child: SingleChildScrollView(child: child)));

class PlaybackSheetHandle extends StatelessWidget {
  const PlaybackSheetHandle({super.key});
  @override
  Widget build(BuildContext context) => Center(
      child: Container(
          width: 36,
          height: 4,
          margin: const EdgeInsets.only(top: 10, bottom: 14),
          decoration: BoxDecoration(
              color: Colors.white24, borderRadius: BorderRadius.circular(2))));
}

class PlaybackSpeedSheet extends StatefulWidget {
  final double rate;
  final Future<void> Function(double) onRate;
  const PlaybackSpeedSheet(
      {super.key, required this.rate, required this.onRate});
  @override
  State<PlaybackSpeedSheet> createState() => _PlaybackSpeedSheetState();
}

class _PlaybackSpeedSheetState extends State<PlaybackSpeedSheet> {
  late double current;
  late double applied;
  bool busy = false;
  String? error;
  double snap(double v) => ((v * 4).round() / 4).clamp(.5, 4.0);
  @override
  void initState() {
    super.initState();
    applied = current = snap(widget.rate);
  }

  Future<void> apply(double value) async {
    if (busy) return;
    setState(() {
      current = snap(value);
      busy = true;
      error = null;
    });
    try {
      await widget.onRate(current);
      applied = current;
    } catch (_) {
      if (mounted) {
        setState(() {
          current = applied;
          error = 'Could not change playback speed. Please try again.';
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const PlaybackSheetHandle(),
        const Align(
            alignment: Alignment.centerLeft,
            child: LText('Playback speed',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
        Text('${current}x',
            style: const TextStyle(
                color: Colors.white,
                fontSize: 30,
                fontWeight: FontWeight.bold)),
        Slider(
            value: current,
            min: .5,
            max: 4,
            divisions: 14,
            activeColor: Colors.white,
            inactiveColor: Colors.white10,
            onChanged: busy ? null : (v) => setState(() => current = snap(v)),
            onChangeEnd: busy ? null : apply),
        const Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('0.5×', style: TextStyle(color: Colors.white54, fontSize: 11.5)),
          Text('4.0×', style: TextStyle(color: Colors.white54, fontSize: 11.5))
        ]),
        const SizedBox(height: 10),
        Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              for (final rate in [.5, .75, 1.0, 1.25, 1.5, 2.0, 3.0, 4.0])
                ChoiceChip(
                    label: Text('$rate×'),
                    selected: current == rate,
                    selectedColor: Colors.white,
                    labelStyle: TextStyle(
                        color: current == rate ? Colors.black : Colors.white70),
                    backgroundColor: Colors.white.withValues(alpha: .06),
                    onSelected: busy ? null : (_) => apply(rate))
            ]),
        if (busy)
          const Padding(
              padding: EdgeInsets.only(top: 12),
              child: LinearProgressIndicator(minHeight: 2)),
        if (error != null)
          Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(error!,
                  style:
                      const TextStyle(color: Colors.redAccent, fontSize: 12))),
      ]));
}

class SleepTimerSheet extends StatelessWidget {
  final DateTime? deadline;
  final VoidCallback? onEnd;
  final bool untilEnd;
  final ValueChanged<int> onMinutes;
  const SleepTimerSheet(
      {super.key,
      required this.onMinutes,
      this.deadline,
      this.onEnd,
      this.untilEnd = false});
  @override
  Widget build(BuildContext context) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const PlaybackSheetHandle(),
            const Padding(
                padding: EdgeInsets.fromLTRB(20, 6, 20, 8),
                child: LText('Sleep timer',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
            if (deadline != null || untilEnd) ...[
              Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                  child: Text(
                      untilEnd
                          ? 'Pauses at the end of this item'
                          : 'Pauses at ${TimeOfDay.fromDateTime(deadline!).format(context)}',
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 12))),
              ListTile(
                  title: const LText('Turn off timer'),
                  onTap: () => onMinutes(0)),
            ],
            for (final minutes in [10, 15, 30, 45, 60, 90, 120])
              ListTile(
                  title: Text('$minutes minutes',
                      style: const TextStyle(fontSize: 16)),
                  onTap: () => onMinutes(minutes)),
            if (onEnd != null)
              ListTile(
                  title: const Text('Until end'),
                  subtitle: const Text('Pause when this video reaches the end'),
                  onTap: onEnd)
            else
              const Tooltip(
                  message:
                      'Pause-at-end timer is not implemented in this Windows build',
                  child: ListTile(
                      enabled: false,
                      title: LText('Until end'),
                      subtitle: Text('Not available on Windows yet',
                          style: TextStyle(fontSize: 12)))),
            const SizedBox(height: 18),
          ]);
}
