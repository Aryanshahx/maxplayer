import 'dart:async';

import 'package:flutter/material.dart';

import '../theme.dart';
import '../utils/app_volume.dart';
import '../utils/audio_player.dart';
import '../utils/format.dart';
import '../utils/player_settings.dart';

/// v1.0.21 full-screen AUDIO PLAYER — separate from the video player on
/// purpose: it binds to the process-lifetime [AudioPlayerHolder] engine,
/// so leaving this screen (Back) keeps the music going; the Audio tab's
/// mini bar is the way back in. Slider/Speed/Shuffle/Repeat/Boost are all
/// real (mpv soft-gain like the video player).
class AudioPlayerScreen extends StatelessWidget {
  const AudioPlayerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final holder = AudioPlayerHolder.instance;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Now playing'),
        centerTitle: false,
      ),
      body: AnimatedBuilder(
        animation: Listenable.merge(
            [holder, AppVolume.instance, PlayerSettings.instance]),
        builder: (context, _) {
          if (!holder.hasTrack) {
            return const Center(
                child: Text('Nothing playing',
                    style: TextStyle(color: AppColors.textSecondary)));
          }
          final pos = holder.position;
          final dur = holder.duration;
          final maxMs = (dur.inMilliseconds > 0 ? dur.inMilliseconds : 1)
              .toDouble();
          final sliderMs =
              pos.inMilliseconds.clamp(0, dur.inMilliseconds).toDouble();
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
              child: Column(
                children: [
                  const Spacer(),
                  // Cover art placeholder — gradient disc with a note.
                  Container(
                    width: 210,
                    height: 210,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: SweepGradient(colors: [
                        AppColors.accent.withValues(alpha: 0.35),
                        AppColors.surfaceAlt,
                        AppColors.accent.withValues(alpha: 0.18),
                        AppColors.surfaceAlt,
                        AppColors.accent.withValues(alpha: 0.35),
                      ]),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.accent.withValues(alpha: 0.18),
                          blurRadius: 48,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Icon(Icons.music_note_rounded,
                        size: 96, color: AppColors.onAccent),
                  ),
                  const SizedBox(height: 26),
                  Text(
                    holder.currentTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${holder.currentIndex + 1} of ${holder.count}'
                    '${holder.error != null ? '  ·  ⚠ ${holder.error}' : ''}',
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 12.5),
                  ),
                  const Spacer(),
                  Slider(
                    value: sliderMs,
                    max: maxMs,
                    activeColor: AppColors.accent,
                    inactiveColor: AppColors.surfaceAlt,
                    onChanged: (v) =>
                        holder.seek(Duration(milliseconds: v.round())),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(formatDuration(pos),
                            style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12)),
                        Text(formatDuration(dur),
                            style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton(
                        tooltip: 'Shuffle',
                        icon: Icon(Icons.shuffle_rounded,
                            color: holder.shuffle
                                ? AppColors.accent
                                : AppColors.textSecondary),
                        onPressed: () => holder.setShuffle(!holder.shuffle),
                      ),
                      IconButton(
                        tooltip: 'Previous',
                        iconSize: 34,
                        icon: const Icon(Icons.skip_previous_rounded,
                            color: AppColors.textPrimary),
                        onPressed: () => unawaited(holder.prev()),
                      ),
                      Container(
                        width: 68,
                        height: 68,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.accent,
                        ),
                        child: IconButton(
                          iconSize: 38,
                          icon: Icon(
                            holder.playing
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            color: AppColors.onAccent,
                          ),
                          onPressed: () => unawaited(holder.toggle()),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Next',
                        iconSize: 34,
                        icon: const Icon(Icons.skip_next_rounded,
                            color: AppColors.textPrimary),
                        onPressed: () => unawaited(holder.next()),
                      ),
                      IconButton(
                        tooltip: switch (holder.repeat) {
                          AudioRepeatMode.off => 'Repeat: off',
                          AudioRepeatMode.all => 'Repeat: all',
                          AudioRepeatMode.one => 'Repeat: one',
                        },
                        icon: Icon(
                          holder.repeat == AudioRepeatMode.one
                              ? Icons.repeat_one_rounded
                              : Icons.repeat_rounded,
                          color: holder.repeat == AudioRepeatMode.off
                              ? AppColors.textSecondary
                              : AppColors.accent,
                        ),
                        onPressed: holder.cycleRepeat,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Speed chips.
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('Speed',
                          style: TextStyle(
                              color: AppColors.textSecondary, fontSize: 12)),
                      const SizedBox(width: 10),
                      for (final r in const [0.75, 1.0, 1.25, 1.5, 2.0])
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: ChoiceChip(
                            label: Text('${r}x',
                                style: const TextStyle(fontSize: 11.5)),
                            selected: holder.rate == r,
                            onSelected: (_) => unawaited(holder.setSpeed(r)),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Volume (with the same 200% boost ceiling as video).
                  Row(
                    children: [
                      Icon(
                        AppVolume.instance.muted || AppVolume.instance.level <= 0
                            ? Icons.volume_off_rounded
                            : Icons.volume_up_rounded,
                        color: AppColors.textSecondary,
                        size: 20,
                      ),
                      Expanded(
                        child: Slider(
                          value: AppVolume.instance.level.clamp(
                              0.0,
                              PlayerSettings.instance.volumeBoost
                                  ? kAppVolumeMax
                                  : kBoostStart),
                          max: PlayerSettings.instance.volumeBoost
                              ? kAppVolumeMax
                              : kBoostStart,
                          activeColor: AppColors.accent,
                          inactiveColor: AppColors.surfaceAlt,
                          onChanged: (v) =>
                              unawaited(AppVolume.instance.setLevel(v)),
                        ),
                      ),
                      SizedBox(
                        width: 42,
                        child: Text(
                          '${AppVolume.instance.level.round()}%',
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
