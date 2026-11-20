import 'dart:async';
import 'package:flutter/material.dart';

String sleepStatusLabel(DateTime? deadline, bool untilEnd, DateTime now) {
  if (untilEnd) return 'Sleep · until end';
  if (deadline == null) return '';
  final seconds = deadline.difference(now).inSeconds;
  if (seconds <= 0) return '';
  return 'Sleep ${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
}

class SleepStatusChip extends StatefulWidget {
  final DateTime? deadline;
  final bool untilEnd;
  const SleepStatusChip({super.key, this.deadline, this.untilEnd = false});
  @override
  State<SleepStatusChip> createState() => _SleepStatusChipState();
}

class _SleepStatusChipState extends State<SleepStatusChip> {
  Timer? ticker;
  @override
  void initState() {
    super.initState();
    syncTimer();
  }

  @override
  void didUpdateWidget(covariant SleepStatusChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.deadline != widget.deadline) syncTimer();
  }

  void syncTimer() {
    ticker?.cancel();
    if (widget.deadline != null) {
      ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
        if (!widget.deadline!.isAfter(DateTime.now())) ticker?.cancel();
      });
    }
  }

  @override
  void dispose() {
    ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final label =
        sleepStatusLabel(widget.deadline, widget.untilEnd, DateTime.now());
    if (label.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.bedtime_outlined, size: 13, color: Colors.white70),
        const SizedBox(width: 5),
        Text(label,
            style: const TextStyle(fontSize: 11, color: Colors.white70)),
      ]),
    );
  }
}
