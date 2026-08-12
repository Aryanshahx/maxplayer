import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart' hide VideoTrack;
import '../state/theme_state.dart';

import '../state/media_player_state.dart';

/// Bottom sheet listing the current media's audio or subtitle tracks, with a
/// check on the active one. Opened from the player controls.
class TrackSelectionSheet extends StatelessWidget {
  final MediaPlayerState player;
  final bool isSubtitle;

  const TrackSelectionSheet({
    super.key,
    required this.player,
    required this.isSubtitle,
  });

  static Color get _accent => themeState.accent;
  static const Color _surface = Color(0xFF1a1a24);

  static Future<void> show(
    BuildContext context,
    MediaPlayerState player, {
    required bool isSubtitle,
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: _surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) =>
          TrackSelectionSheet(player: player, isSubtitle: isSubtitle),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
            child: Text(
              isSubtitle ? 'Subtitles' : 'Audio track',
              style: TextStyle(
                color: _accent,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Flexible(
            child: isSubtitle ? _subtitleList(context) : _audioList(context),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _audioList(BuildContext context) {
    // Dedupe by id - some containers list an entry twice.
    final tracks = <String, AudioTrack>{};
    for (final t in player.audioTracks) {
      if (t.id == 'no') continue;
      tracks[t.id] = t;
    }
    final list = tracks.values.toList();
    if (list.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Text('No audio tracks found',
            style: TextStyle(color: Colors.white38)),
      );
    }
    return ListView(
      shrinkWrap: true,
      children: [
        for (var i = 0; i < list.length; i++)
          _TrackTile(
            label: _audioLabel(list[i], i),
            detail: list[i].language,
            selected: player.currentAudioTrack?.id == list[i].id,
            onTap: () {
              player.selectAudioTrack(list[i]);
              Navigator.of(context).pop();
            },
          ),
      ],
    );
  }

  Widget _subtitleList(BuildContext context) {
    // "no" is the explicit OFF entry; dedupe the rest by id.
    final tracks = <String, SubtitleTrack>{};
    for (final t in player.subtitleTracks) {
      if (t.id == 'no') continue;
      tracks[t.id] = t;
    }
    final list = [SubtitleTrack.no(), ...tracks.values];
    return ListView(
      shrinkWrap: true,
      children: [
        for (var i = 0; i < list.length; i++)
          _TrackTile(
            label: _subtitleLabel(list[i], i),
            detail: list[i].language ?? list[i].codec,
            selected: player.currentSubtitleTrack?.id == list[i].id,
            onTap: () {
              player.selectSubtitleTrack(list[i]);
              Navigator.of(context).pop();
            },
          ),
      ],
    );
  }

  String _audioLabel(AudioTrack t, int index) {
    if (t.id == 'auto') return 'Auto';
    final title = t.title?.trim() ?? '';
    if (title.isNotEmpty) return title;
    return t.language?.toUpperCase() ?? 'Audio ${index + 1}';
  }

  String _subtitleLabel(SubtitleTrack t, int index) {
    if (t.id == 'no') return 'Off';
    if (t.id == 'auto') return 'Auto';
    final title = t.title?.trim() ?? '';
    if (title.isNotEmpty) return title;
    return t.language?.toUpperCase() ?? 'Subtitle $index';
  }
}

class _TrackTile extends StatelessWidget {
  final String label;
  final String? detail;
  final bool selected;
  final VoidCallback onTap;

  const _TrackTile({
    required this.label,
    required this.detail,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      onTap: onTap,
      leading: SizedBox(
        width: 24,
        child: selected
            ? Icon(Icons.check,
                size: 18, color: TrackSelectionSheet._accent)
            : null,
      ),
      title: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: selected ? Colors.white : Colors.white70,
          fontSize: 15,
          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      subtitle: (detail != null && detail!.isNotEmpty)
          ? Text(detail!,
              style: const TextStyle(color: Colors.white38, fontSize: 12))
          : null,
    );
  }
}
