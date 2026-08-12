import 'package:flutter/material.dart';

import '../state/media_player_state.dart';
import '../state/theme_state.dart';
import '../utils/formatters.dart';

/// Weekly watch-time statistics - a 7-day bar chart plus totals.
class StatsScreen extends StatelessWidget {
  final MediaPlayerState player;

  const StatsScreen({super.key, required this.player});

  @override
  Widget build(BuildContext context) {
    final accent = themeState.accent;
    return Scaffold(
      backgroundColor: const Color(0xFF0a0a0f),
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: 0.3),
        elevation: 0,
        title: const Text('Statistics'),
      ),
      body: FutureBuilder<List<WatchDay>>(
        future: player.getWeekStats(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return Center(
              child: CircularProgressIndicator(color: accent),
            );
          }
          final days = snapshot.data!;
          final weekTotal =
              days.fold<int>(0, (sum, d) => sum + d.seconds);
          final maxSecs =
              days.fold<int>(60, (m, d) => d.seconds > m ? d.seconds : m);

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                formatWatchTime(weekTotal),
                style: TextStyle(
                  color: accent,
                  fontSize: 34,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Text(
                'watched this week',
                style: TextStyle(color: Colors.white38, fontSize: 14),
              ),
              const SizedBox(height: 28),
              SizedBox(
                height: 190,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final d in days) _DayBar(day: d, maxSecs: maxSecs),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Daily average: ${formatWatchTime(weekTotal ~/ 7)}',
                style:
                    const TextStyle(color: Colors.white54, fontSize: 14),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DayBar extends StatelessWidget {
  final WatchDay day;
  final int maxSecs;

  const _DayBar({required this.day, required this.maxSecs});

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  Widget build(BuildContext context) {
    final accent = themeState.accent;
    final isToday = _isSameDay(day.day, DateTime.now());
    final fraction = (day.seconds / maxSecs).clamp(0.0, 1.0);
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              day.seconds > 0 ? formatWatchTime(day.seconds) : '',
              style: const TextStyle(color: Colors.white38, fontSize: 10),
            ),
            const SizedBox(height: 4),
            Flexible(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: FractionallySizedBox(
                  heightFactor: fraction == 0 ? 0.02 : fraction,
                  child: Container(
                    decoration: BoxDecoration(
                      color: isToday
                          ? accent
                          : Colors.white.withValues(alpha: 0.16),
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(6)),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _weekdays[day.day.weekday - 1],
              style: TextStyle(
                color: isToday ? accent : Colors.white38,
                fontSize: 11,
                fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
