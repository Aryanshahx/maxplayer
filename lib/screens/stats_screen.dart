import 'package:flutter/material.dart';

import '../state/media_player_state.dart';
import '../state/theme_state.dart';
import '../utils/formatters.dart';

/// Watch-time statistics (v27: advanced).
///
///  - headline week total + the 7-day bar chart (as before)
///  - stat cards: Today · Daily average · Best day · Last 30 days ·
///    day streak (days in a row with something watched)
///  - "Most watched": the videos you have spent the most time on
///    (cumulative, tracked from v27 onwards)
class StatsScreen extends StatelessWidget {
  final MediaPlayerState player;

  const StatsScreen({super.key, required this.player});

  Future<_StatsBundle> _load() async {
    final days = await player.getWeekStats();
    final month = await player.getWatchSecondsForLastDays(30);
    final streak = await player.getWatchStreakDays();
    return _StatsBundle(days, month, streak);
  }

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
      body: FutureBuilder<_StatsBundle>(
        future: _load(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return Center(
              child: CircularProgressIndicator(color: accent),
            );
          }
          final bundle = snapshot.data!;
          final days = bundle.days;
          final weekTotal = days.fold<int>(0, (sum, d) => sum + d.seconds);
          final maxSecs =
              days.fold<int>(60, (m, d) => d.seconds > m ? d.seconds : m);
          final todaySecs = days.isEmpty ? 0 : days.last.seconds;
          final bestSecs = days.fold<int>(
              0, (m, d) => d.seconds > m ? d.seconds : m);
          final topWatched = player.getTopWatchedVideos();
          final topMax = topWatched.isEmpty ? 1 : topWatched.first.value;

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
              const SizedBox(height: 20),
              // v27: the advanced stat cards.
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _StatCard(
                    icon: Icons.today_outlined,
                    label: 'Today',
                    value: formatWatchTime(todaySecs),
                  ),
                  _StatCard(
                    icon: Icons.functions,
                    label: 'Daily average',
                    value: formatWatchTime(weekTotal ~/ 7),
                  ),
                  _StatCard(
                    icon: Icons.emoji_events_outlined,
                    label: 'Best day',
                    value: bestSecs > 0 ? formatWatchTime(bestSecs) : '-',
                  ),
                  _StatCard(
                    icon: Icons.calendar_month_outlined,
                    label: 'Last 30 days',
                    value: formatWatchTime(bundle.monthSecs),
                  ),
                  _StatCard(
                    icon: Icons.local_fire_department_outlined,
                    label: 'Day streak',
                    value: bundle.streakDays > 0
                        ? '${bundle.streakDays} ${bundle.streakDays == 1 ? 'day' : 'days'}'
                        : '-',
                  ),
                ],
              ),
              const SizedBox(height: 24),
              SizedBox(
                height: 190,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final d in days) _DayBar(day: d, maxSecs: maxSecs),
                  ],
                ),
              ),
              if (topWatched.isNotEmpty) ...[
                const SizedBox(height: 28),
                Text(
                  'Most watched',
                  style: TextStyle(
                    color: accent,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Total time spent per video (since this update)',
                  style: TextStyle(color: Colors.white38, fontSize: 12),
                ),
                const SizedBox(height: 10),
                for (var i = 0; i < topWatched.length; i++)
                  _TopWatchedRow(
                    rank: i + 1,
                    title: player.titleForPath(topWatched[i].key),
                    seconds: topWatched[i].value,
                    fraction: topWatched[i].value / topMax,
                  ),
              ],
              const SizedBox(height: 12),
            ],
          );
        },
      ),
    );
  }
}

class _StatsBundle {
  final List<WatchDay> days;
  final int monthSecs;
  final int streakDays;
  const _StatsBundle(this.days, this.monthSecs, this.streakDays);
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final accent = themeState.accent;
    return Container(
      width: 150,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: accent),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      const TextStyle(color: Colors.white38, fontSize: 11.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _TopWatchedRow extends StatelessWidget {
  final int rank;
  final String title;
  final int seconds;
  final double fraction;

  const _TopWatchedRow({
    required this.rank,
    required this.title,
    required this.seconds,
    required this.fraction,
  });

  @override
  Widget build(BuildContext context) {
    final accent = themeState.accent;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 20,
                child: Text(
                  '$rank.',
                  style:
                      const TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                formatWatchTime(seconds),
                style: TextStyle(
                  color: accent,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Padding(
            padding: const EdgeInsets.only(left: 20),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: Stack(
                children: [
                  Container(
                    height: 4,
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                  FractionallySizedBox(
                    widthFactor: fraction.clamp(0.0, 1.0),
                    child: Container(height: 4, color: accent),
                  ),
                ],
              ),
            ),
          ),
        ],
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
