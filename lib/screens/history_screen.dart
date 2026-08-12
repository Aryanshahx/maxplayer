import 'dart:io';

import 'package:flutter/material.dart';

import '../models/history_entry.dart';
import '../state/media_player_state.dart';
import '../utils/formatters.dart';
import 'player_screen.dart';
import '../state/theme_state.dart';

/// Watch history - most recently opened videos first, each with its saved
/// progress. Tapping resumes where you left off.
class HistoryScreen extends StatelessWidget {
  final MediaPlayerState player;

  const HistoryScreen({super.key, required this.player});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0a0a0f),
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: 0.3),
        elevation: 0,
        title: const Text('History'),
        actions: [
          AnimatedBuilder(
            animation: player,
            builder: (context, _) => player.history.isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    tooltip: 'Clear history',
                    icon: const Icon(Icons.delete_sweep_outlined),
                    onPressed: () => _confirmClear(context),
                  ),
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: player,
        builder: (context, _) {
          final entries = player.history;
          if (entries.isEmpty) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.history, size: 48, color: Colors.white24),
                  SizedBox(height: 12),
                  Text(
                    'Nothing watched yet.\nVideos you open will show up here.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white54, fontSize: 16),
                  ),
                ],
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: entries.length,
            separatorBuilder: (_, __) => const Divider(
              height: 1,
              indent: 120,
              color: Color(0xFF1a1a24),
            ),
            itemBuilder: (context, i) =>
                _HistoryTile(entry: entries[i], player: player),
          );
        },
      ),
    );
  }

  void _confirmClear(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a24),
        title: const Text('Clear history?',
            style: TextStyle(color: Colors.white)),
        content: const Text(
          'This also resets the saved resume position of every video.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: themeState.accent),
            onPressed: () {
              player.clearHistory();
              Navigator.of(dialogContext).pop();
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  final HistoryEntry entry;
  final MediaPlayerState player;

  const _HistoryTile({required this.entry, required this.player});

  @override
  Widget build(BuildContext context) {
    final position = Duration(seconds: entry.lastPositionSecs);
    final total = Duration(seconds: entry.durationSecs);
    final posLabel = formatDuration(position);
    final totalLabel = formatDuration(total);
    final hasProgress = entry.durationSecs > 0 && entry.lastPositionSecs > 0;

    return ListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 96,
          height: 54,
          child: _thumb(),
        ),
      ),
      title: Text(
        entry.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
            fontSize: 14, color: Colors.white, fontWeight: FontWeight.w500),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 2),
          Text(
            hasProgress
                ? '${timeAgo(entry.playedAtMs)}  ·  $posLabel / $totalLabel'
                : timeAgo(entry.playedAtMs),
            style: const TextStyle(fontSize: 12, color: Colors.white38),
          ),
          if (hasProgress) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: entry.progress,
                minHeight: 3,
                backgroundColor: Colors.white10,
                color: themeState.accent,
              ),
            ),
          ],
        ],
      ),
      trailing: IconButton(
        icon: const Icon(Icons.close, size: 18, color: Colors.white38),
        tooltip: 'Remove from history',
        onPressed: () => player.removeHistoryEntry(entry.path),
      ),
      onTap: () {
        player.playHistoryEntry(entry);
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => PlayerScreen(player: player)),
        );
      },
    );
  }

  Widget _thumb() {
    if (entry.thumbnailPath != null) {
      return Image.file(
        File(entry.thumbnailPath!),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const _Placeholder(),
      );
    }
    return const _Placeholder();
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF12121a),
      child: const Center(
        child: Icon(Icons.movie_outlined, size: 22, color: Colors.white24),
      ),
    );
  }
}
