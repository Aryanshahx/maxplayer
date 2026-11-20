import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'android_controls.dart';
import 'queue_order.dart';

/// Adapted from Android AudioPlayerScreen: disc, title/count, progress,
/// shuffle/previous/circular transport/next/repeat/speed and volume.
class AudioNowPlaying extends StatelessWidget {
  final ValueListenable<PlaybackSnapshot> playback;
  final String title;
  final int index, count;
  final bool shuffle, canPrevious, canNext;
  final QueueRepeat repeat;
  final VoidCallback onBack,
      onQueue,
      onSettings,
      onPlayPause,
      onPrevious,
      onNext,
      onShuffle,
      onRepeat,
      onSpeed;
  final ValueChanged<Duration> onSeek;
  final ValueChanged<double> onVolume;
  const AudioNowPlaying(
      {super.key,
      required this.playback,
      required this.title,
      required this.index,
      required this.count,
      required this.shuffle,
      required this.repeat,
      required this.canPrevious,
      required this.canNext,
      required this.onBack,
      required this.onQueue,
      required this.onSettings,
      required this.onPlayPause,
      required this.onPrevious,
      required this.onNext,
      required this.onShuffle,
      required this.onRepeat,
      required this.onSpeed,
      required this.onSeek,
      required this.onVolume});
  @override
  Widget build(BuildContext context) => ColoredBox(
      color: const Color(0xff060608),
      child: Column(children: [
        SafeArea(
            bottom: false,
            child: SizedBox(
                height: 56,
                child: Row(children: [
                  IconButton(
                      tooltip: 'Back',
                      onPressed: onBack,
                      icon: const Icon(Icons.arrow_back)),
                  const Expanded(
                      child: Text('Now playing',
                          style: TextStyle(
                              fontSize: 20, fontWeight: FontWeight.w500))),
                  IconButton(
                      tooltip: 'Playlists',
                      onPressed: onQueue,
                      icon: const Icon(Icons.playlist_play)),
                  IconButton(
                      tooltip: 'Player settings',
                      onPressed: onSettings,
                      icon: const Icon(Icons.settings_outlined))
                ]))),
        Expanded(
            child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                    child: ConstrainedBox(
                        constraints:
                            BoxConstraints(minHeight: constraints.maxHeight),
                        child: Center(
                            child: ConstrainedBox(
                                constraints:
                                    const BoxConstraints(maxWidth: 760),
                                child: Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                        24, 16, 24, 20),
                                    child: ValueListenableBuilder<
                                            PlaybackSnapshot>(
                                        valueListenable: playback,
                                        builder: (context, state, _) => Column(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  Container(
                                                      width: 210,
                                                      height: 210,
                                                      decoration: BoxDecoration(
                                                          shape:
                                                              BoxShape.circle,
                                                          gradient:
                                                              SweepGradient(
                                                                  colors: [
                                                                Colors.white
                                                                    .withValues(
                                                                        alpha:
                                                                            .35),
                                                                const Color(
                                                                    0xff18181c),
                                                                Colors.white
                                                                    .withValues(
                                                                        alpha:
                                                                            .18),
                                                                const Color(
                                                                    0xff18181c),
                                                                Colors.white
                                                                    .withValues(
                                                                        alpha:
                                                                            .35)
                                                              ]),
                                                          boxShadow: [
                                                            BoxShadow(
                                                                color: Colors
                                                                    .white
                                                                    .withValues(
                                                                        alpha:
                                                                            .18),
                                                                blurRadius: 48,
                                                                spreadRadius: 2)
                                                          ]),
                                                      child: const Icon(
                                                          Icons
                                                              .music_note_rounded,
                                                          size: 96,
                                                          color: Colors.black)),
                                                  const SizedBox(height: 26),
                                                  Text(title,
                                                      maxLines: 2,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      textAlign:
                                                          TextAlign.center,
                                                      style: const TextStyle(
                                                          fontSize: 18,
                                                          fontWeight:
                                                              FontWeight.w700)),
                                                  const SizedBox(height: 6),
                                                  Text('${index + 1} of $count',
                                                      style: const TextStyle(
                                                          color:
                                                              Color(0xff9296a0),
                                                          fontSize: 12.5)),
                                                  const SizedBox(height: 24),
                                                  if (state.buffering)
                                                    const LinearProgressIndicator(
                                                        minHeight: 2),
                                                  Slider(
                                                      value: state.position
                                                          .inMilliseconds
                                                          .toDouble()
                                                          .clamp(
                                                              0,
                                                              state.duration
                                                                  .inMilliseconds
                                                                  .clamp(1,
                                                                      1 << 53)
                                                                  .toDouble()),
                                                      max: state.duration
                                                          .inMilliseconds
                                                          .clamp(1, 1 << 53)
                                                          .toDouble(),
                                                      activeColor: Colors.white,
                                                      inactiveColor:
                                                          const Color(
                                                              0xff18181c),
                                                      onChanged: state
                                                                  .duration >
                                                              Duration.zero
                                                          ? (v) => onSeek(
                                                              Duration(
                                                                  milliseconds:
                                                                      v.round()))
                                                          : null),
                                                  Padding(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                          horizontal: 8),
                                                      child: Row(
                                                          mainAxisAlignment:
                                                              MainAxisAlignment
                                                                  .spaceBetween,
                                                          children: [
                                                            Text(
                                                                playbackClock(state
                                                                    .position),
                                                                style: const TextStyle(
                                                                    color: Colors
                                                                        .white54,
                                                                    fontSize:
                                                                        12)),
                                                            Text(
                                                                playbackClock(state
                                                                    .duration),
                                                                style: const TextStyle(
                                                                    color: Colors
                                                                        .white54,
                                                                    fontSize:
                                                                        12))
                                                          ])),
                                                  const SizedBox(height: 4),
                                                  Wrap(
                                                      alignment:
                                                          WrapAlignment.center,
                                                      crossAxisAlignment:
                                                          WrapCrossAlignment
                                                              .center,
                                                      spacing: 8,
                                                      children: [
                                                        IconButton(
                                                            tooltip: 'Shuffle',
                                                            onPressed:
                                                                onShuffle,
                                                            icon: Icon(
                                                                Icons
                                                                    .shuffle_rounded,
                                                                color: shuffle
                                                                    ? Colors
                                                                        .white
                                                                    : Colors
                                                                        .white54)),
                                                        IconButton(
                                                            tooltip: 'Previous',
                                                            iconSize: 34,
                                                            onPressed:
                                                                canPrevious
                                                                    ? onPrevious
                                                                    : null,
                                                            icon: const Icon(Icons
                                                                .skip_previous_rounded)),
                                                        Container(
                                                            width: 68,
                                                            height: 68,
                                                            decoration: const BoxDecoration(
                                                                shape: BoxShape
                                                                    .circle,
                                                                color: Colors
                                                                    .white),
                                                            child: IconButton(
                                                                tooltip: state
                                                                        .playing
                                                                    ? 'Pause'
                                                                    : 'Play',
                                                                iconSize: 38,
                                                                onPressed:
                                                                    onPlayPause,
                                                                icon: Icon(
                                                                    state.playing
                                                                        ? Icons
                                                                            .pause_rounded
                                                                        : Icons
                                                                            .play_arrow_rounded,
                                                                    color: Colors
                                                                        .black))),
                                                        IconButton(
                                                            tooltip: 'Next',
                                                            iconSize: 34,
                                                            onPressed: canNext
                                                                ? onNext
                                                                : null,
                                                            icon: const Icon(Icons
                                                                .skip_next_rounded)),
                                                        IconButton(
                                                            tooltip:
                                                                'Repeat: ${repeat.name}',
                                                            onPressed: onRepeat,
                                                            icon: Icon(
                                                                repeat ==
                                                                        QueueRepeat
                                                                            .one
                                                                    ? Icons
                                                                        .repeat_one_rounded
                                                                    : Icons
                                                                        .repeat_rounded,
                                                                color: repeat ==
                                                                        QueueRepeat
                                                                            .off
                                                                    ? Colors
                                                                        .white54
                                                                    : Colors
                                                                        .white)),
                                                        TextButton(
                                                            onPressed: onSpeed,
                                                            child: Text(
                                                                '${state.rate}x',
                                                                style: const TextStyle(
                                                                    color: Colors
                                                                        .white70,
                                                                    fontSize:
                                                                        13,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w700))),
                                                      ]),
                                                  const SizedBox(height: 8),
                                                  Row(children: [
                                                    Icon(
                                                        state.volume <= 0
                                                            ? Icons
                                                                .volume_off_rounded
                                                            : Icons
                                                                .volume_up_rounded,
                                                        size: 20,
                                                        color: Colors.white54),
                                                    Expanded(
                                                        child: Slider(
                                                            value: state.volume
                                                                .clamp(0, 100),
                                                            max: 100,
                                                            activeColor:
                                                                Colors.white,
                                                            inactiveColor:
                                                                const Color(
                                                                    0xff18181c),
                                                            onChanged:
                                                                onVolume)),
                                                    SizedBox(
                                                        width: 42,
                                                        child: Text(
                                                            '${state.volume.round()}%',
                                                            style:
                                                                const TextStyle(
                                                                    color: Colors
                                                                        .white54,
                                                                    fontSize:
                                                                        12)))
                                                  ]),
                                                ]))))))))),
      ]));
}
