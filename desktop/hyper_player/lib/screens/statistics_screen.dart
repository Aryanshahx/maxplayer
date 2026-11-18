import 'package:flutter/material.dart';
import '../utils/app_language.dart';
import '../watch_days.dart';

class DesktopStatisticsScreen extends StatelessWidget {
  final WatchDays stats;
  final int lifetimeSeconds;
  final int starts;
  const DesktopStatisticsScreen(
      {super.key,
      required this.stats,
      required this.lifetimeSeconds,
      required this.starts});
  Widget statCard(IconData icon, String label, String value) => Container(
        width: 150,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .05),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white10)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: Colors.white54, size: 20),
          const SizedBox(height: 8),
          Text(value,
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 3),
          LText(label,
              style: const TextStyle(color: Colors.white38, fontSize: 11))
        ]),
      );
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xff0a0a0f),
        appBar: AppBar(
            backgroundColor: Colors.black.withValues(alpha: .3),
            title: const LText('Statistics')),
        body: AnimatedBuilder(
            animation: stats,
            builder: (context, child) {
              final now = DateTime.now();
              final dates = stats.dates(now, 7);
              final values =
                  dates.map((date) => stats.days[dayKey(date)] ?? 0).toList();
              final week = values.fold(0, (sum, value) => sum + value);
              final best = values.fold(0, (a, b) => a > b ? a : b);
              final ceiling = best < 60 ? 60 : best;
              final top = stats.titles.entries.toList()
                ..sort((a, b) => b.value.compareTo(a.value));
              final maxTitle = top.isEmpty ? 1 : top.first.value;
              return ListView(padding: const EdgeInsets.all(20), children: [
                Text(watchTime(week),
                    style: const TextStyle(
                        fontSize: 34, fontWeight: FontWeight.bold)),
                const LText('watched this week',
                    style: TextStyle(color: Colors.white38, fontSize: 14)),
                const SizedBox(height: 20),
                Wrap(spacing: 10, runSpacing: 10, children: [
                  statCard(
                      Icons.today_outlined, 'Today', watchTime(values.last)),
                  statCard(
                      Icons.functions, 'Daily average', watchTime(week ~/ 7)),
                  statCard(Icons.emoji_events_outlined, 'Best day',
                      best > 0 ? watchTime(best) : '—'),
                  statCard(Icons.calendar_month_outlined, 'Last 30 days',
                      watchTime(stats.total(now, 30))),
                  statCard(Icons.local_fire_department_outlined, 'Day streak',
                      '${stats.streak(now)} days'),
                ]),
                const SizedBox(height: 24),
                SizedBox(
                    height: 190,
                    child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          for (var i = 0; i < dates.length; i++)
                            Expanded(
                                child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 5),
                                    child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.end,
                                        children: [
                                          Text(watchTime(values[i]),
                                              style: const TextStyle(
                                                  color: Colors.white54,
                                                  fontSize: 10)),
                                          const SizedBox(height: 6),
                                          Container(
                                              height:
                                                  130 * values[i] / ceiling + 2,
                                              constraints: const BoxConstraints(
                                                  maxWidth: 54),
                                              decoration: BoxDecoration(
                                                  color: i == dates.length - 1
                                                      ? Colors.white
                                                      : Colors.white24,
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          6))),
                                          const SizedBox(height: 8),
                                          Text(
                                              [
                                                'Mon',
                                                'Tue',
                                                'Wed',
                                                'Thu',
                                                'Fri',
                                                'Sat',
                                                'Sun'
                                              ][dates[i].weekday - 1],
                                              style: const TextStyle(
                                                  color: Colors.white38,
                                                  fontSize: 11)),
                                        ]))),
                        ])),
                if (top.isNotEmpty) ...[
                  const SizedBox(height: 28),
                  const LText('Most watched',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  const Text(
                      'Sampled playback time by filename since this update',
                      style: TextStyle(color: Colors.white38, fontSize: 12)),
                  const SizedBox(height: 10),
                  for (var i = 0; i < top.length && i < 10; i++)
                    Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(children: [
                          SizedBox(
                              width: 30,
                              child: Text('${i + 1}',
                                  style:
                                      const TextStyle(color: Colors.white38))),
                          Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                Text(top[i].key,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 13)),
                                const SizedBox(height: 6),
                                LinearProgressIndicator(
                                    value: top[i].value / maxTitle,
                                    minHeight: 3,
                                    backgroundColor: Colors.white10,
                                    color: Colors.white)
                              ])),
                          const SizedBox(width: 12),
                          Text(watchTime(top[i].value),
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.white54)),
                        ])),
                ],
                const SizedBox(height: 22),
                Text(
                    'Lifetime counter on opening: ${watchTime(lifetimeSeconds)} · $starts playback starts',
                    style:
                        const TextStyle(color: Colors.white54, fontSize: 12)),
                const SizedBox(height: 8),
                const Text(
                    'Daily tracking starts with this update. No historical lifetime time is backfilled. This week means the last seven local calendar days. Playback is sampled once per second while playing and not buffering; not attention or verified viewing. Filenames are stored locally, capped to 100 top entries; identical names are combined. Up to 366 daily records are retained.',
                    style: TextStyle(color: Colors.white38, fontSize: 11)),
              ]);
            }),
      );
}
