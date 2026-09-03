import 'dart:io';

import 'package:flutter/material.dart';

import '../models/video_track.dart';
import '../screens/player_screen.dart';
import '../services/native_bridge.dart';
import '../services/tmdb_client.dart';
import '../state/media_player_state.dart';
import '../state/theme_state.dart';
import '../services/subtitle_langs.dart';
import 'ask_ai_sheet.dart';
import 'tmdb_image.dart';

/// v93: Discover movie & web series detail sheet.
class MovieDetailSheet extends StatefulWidget {
  final TmdbMovie movie;
  final VideoTrack? localMatch;
  final MediaPlayerState player;

  final Future<TmdbFull?> Function() detailLoader;

  const MovieDetailSheet({
    super.key,
    required this.movie,
    required this.localMatch,
    required this.player,
    required this.detailLoader,
  });

  static Future<void> show(
    BuildContext context, {
    required TmdbMovie movie,
    required VideoTrack? localMatch,
    required MediaPlayerState player,
    required Future<TmdbFull?> Function() detailLoader,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF14141c),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        minChildSize: 0.45,
        maxChildSize: 0.95,
        builder: (_, controller) => SingleChildScrollView(
          controller: controller,
          child: MovieDetailSheet(
            movie: movie,
            localMatch: localMatch,
            player: player,
            detailLoader: detailLoader,
          ),
        ),
      ),
    );
  }

  @override
  State<MovieDetailSheet> createState() => _MovieDetailSheetState();
}

class _MovieDetailSheetState extends State<MovieDetailSheet> {
  late Future<TmdbFull?> _detailFuture = widget.detailLoader();

  void _retryDetail() {
    setState(() {
      _detailFuture = widget.detailLoader();
    });
  }

  Future<void> _playLocal(BuildContext context) async {
    final track = widget.localMatch;
    if (track == null) return;
    await widget.player.setPlaylistAndPlay([track], 0);
    if (!context.mounted) return;
    Navigator.of(context).pop();
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PlayerScreen(player: widget.player)),
    );
  }

  Future<void> _openTrailer(String key) async {
    await NativeBridge.openYouTube(key);
  }

  @override
  Widget build(BuildContext context) {
    final movie = widget.movie;
    final isTv = movie.kind == 'tv';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Header: Poster + Title + Rating + Kind badge
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 105,
                height: 155,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: TmdbImage(url: tmdbPosterUrl(movie.posterPath, big: true)),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      movie.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: themeState.accent.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: themeState.accent.withValues(alpha: 0.4)),
                          ),
                          child: Text(
                            isTv ? 'SERIES' : 'MOVIE',
                            style: TextStyle(
                              color: themeState.accent,
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (movie.year != null)
                          Text(
                            '${movie.year}',
                            style: const TextStyle(color: Colors.white70, fontSize: 13),
                          ),
                        const SizedBox(width: 8),
                        Text(
                          '⭐ ${tmdbRatingText(movie.rating)} / 10',
                          style: const TextStyle(
                            color: Colors.amberAccent,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Rating & data via TMDB',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.35),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Action Buttons: Ask AI + Watch Trailer + In My Library
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: themeState.accent.withValues(alpha: 0.18),
                    foregroundColor: themeState.accent,
                    side: BorderSide(color: themeState.accent.withValues(alpha: 0.4)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () => AskAiSheet.show(context, movie: movie),
                  icon: const Icon(Icons.auto_awesome, size: 16),
                  label: const Text('Ask AI', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FutureBuilder<TmdbFull?>(
                  future: _detailFuture,
                  builder: (context, snap) {
                    final key = snap.data?.movie.trailerKey;
                    return FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: themeState.accent,
                        foregroundColor: themeState.onAccent,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: (key != null && key.isNotEmpty) ? () => _openTrailer(key) : null,
                      icon: const Icon(Icons.play_circle_outline, size: 16),
                      label: const Text('Trailer', style: TextStyle(fontWeight: FontWeight.bold)),
                    );
                  },
                ),
              ),
            ],
          ),

          if (widget.localMatch != null) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.08),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () => _playLocal(context),
                icon: Icon(Icons.video_library, color: themeState.accent),
                label: Text(
                  'In My Library - Play "${widget.localMatch!.title}"',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],

          const SizedBox(height: 14),

          // Main Details Content
          FutureBuilder<TmdbFull?>(
            future: _detailFuture,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final full = snap.data;
              if (full == null) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Details could not load. Check network connection.',
                          style: TextStyle(color: Colors.white38, fontSize: 12),
                        ),
                      ),
                      TextButton(onPressed: _retryDetail, child: const Text('Retry')),
                    ],
                  ),
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Screenshots / Scene Stills
                  if (full.screenshots.isNotEmpty)
                    _ScreenshotsRow(paths: full.screenshots),

                  // v95: "show contents details ABOVE the storyline" -
                  // this production/technical block used to sit dead last.
                  _AllDataBlock(extras: full.extras, movieId: movie.id),

                  // Rich Storyline & Overview
                  _DetailedStoryBlock(movie: movie, extras: full.extras),

                  // Top Cast Slider with Profile Images
                  if (full.extras.castMembers.isNotEmpty)
                    _TopCastSlider(cast: full.extras.castMembers),

                  // Web Series Seasons & Episodes breakdown
                  if (isTv && full.seasons.isNotEmpty)
                    _SeasonsBlock(tvId: movie.id, seasons: full.seasons),

                  // Where to Watch
                  if (!full.watch.isEmpty)
                    _WatchBlock(info: full.watch),

                  // v95: "show ALL user reviews at the END of the details"
                  if (full.reviews.isNotEmpty)
                    _ReviewsBlock(reviews: full.reviews),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ScreenshotsRow extends StatelessWidget {
  final List<String> paths;

  const _ScreenshotsRow({required this.paths});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 8),
      child: SizedBox(
        height: 106,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: paths.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, i) => ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 176,
              child: TmdbImage(url: tmdbScreenshotUrl(paths[i])),
            ),
          ),
        ),
      ),
    );
  }
}

class _DetailedStoryBlock extends StatelessWidget {
  final TmdbMovie movie;
  final TmdbDetailExtras extras;

  const _DetailedStoryBlock({required this.movie, required this.extras});

  @override
  Widget build(BuildContext context) {
    final meta = <String>[
      if (formatRuntime(extras.runtimeMinutes).isNotEmpty)
        formatRuntime(extras.runtimeMinutes),
      if (extras.voteCount > 0) '${formatVoteCount(extras.voteCount)} votes',
      if (extras.status.isNotEmpty && extras.status != 'Released') extras.status,
    ];

    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (extras.tagline.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '"${extras.tagline}"',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13.5,
                  fontStyle: FontStyle.italic,
                  height: 1.4,
                ),
              ),
            ),

          if (meta.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                meta.join('  ·  '),
                style: const TextStyle(color: Colors.white60, fontSize: 12.5),
              ),
            ),

          if (extras.genres.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final g in extras.genres)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Text(
                        g,
                        style: const TextStyle(color: Colors.white70, fontSize: 11.5),
                      ),
                    ),
                ],
              ),
            ),

          const Text(
            'Storyline',
            style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            movie.overview.isNotEmpty ? movie.overview : 'No full synopsis available for this title.',
            style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
          ),

          if (extras.director.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Director: ${extras.director}',
                style: const TextStyle(color: Colors.white70, fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
            ),
        ],
      ),
    );
  }
}

class _TopCastSlider extends StatelessWidget {
  final List<TmdbCastMember> cast;

  const _TopCastSlider({required this.cast});

  @override
  Widget build(BuildContext context) {
    if (cast.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Top Cast',
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 124,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: cast.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, i) {
                final c = cast[i];
                return SizedBox(
                  width: 82,
                  child: Column(
                    children: [
                      Container(
                        width: 58,
                        height: 58,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: themeState.accent.withValues(alpha: 0.5),
                            width: 1.5,
                          ),
                        ),
                        child: ClipOval(
                          child: c.profilePath != null && c.profilePath!.isNotEmpty
                              ? TmdbImage(
                                  url: 'https://image.tmdb.org/t/p/w185${c.profilePath}',
                                )
                              : Container(
                                  color: Colors.white12,
                                  child: const Icon(
                                    Icons.person,
                                    color: Colors.white38,
                                    size: 32,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        c.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (c.character.isNotEmpty)
                        Text(
                          c.character,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 10,
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SeasonsBlock extends StatefulWidget {
  final int tvId;
  final List<TmdbSeason> seasons;

  const _SeasonsBlock({required this.tvId, required this.seasons});

  @override
  State<_SeasonsBlock> createState() => _SeasonsBlockState();
}

class _SeasonsBlockState extends State<_SeasonsBlock> {
  int _selectedSeason = 1;
  TmdbSeasonDetail? _seasonDetail;
  bool _loadingSeason = false;
  final TmdbClient _client = TmdbClient();

  @override
  void initState() {
    super.initState();
    if (widget.seasons.isNotEmpty) {
      _selectedSeason = widget.seasons.first.number;
      _loadSeasonDetail(_selectedSeason);
    }
  }

  Future<void> _loadSeasonDetail(int seasonNum) async {
    setState(() {
      _selectedSeason = seasonNum;
      _loadingSeason = true;
    });
    final path = await NativeBridge.cacheDirPath();
    if (path != null) _client.cacheDir = Directory(path);
    final detail = await _client.seasonDetail(widget.tvId, seasonNum);
    if (mounted) {
      setState(() {
        _seasonDetail = detail;
        _loadingSeason = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final seasons = widget.seasons;
    final totalEps = seasons.fold<int>(0, (a, s) => a + s.episodes);
    final currentSeasonInfo = seasons.firstWhere(
      (s) => s.number == _selectedSeason,
      orElse: () => seasons.first,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Seasons & Episodes (${seasons.length} Seasons, $totalEps Episodes)',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 38,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: seasons.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final s = seasons[i];
                final isSelected = s.number == _selectedSeason;
                final ratingStr = s.rating > 0 ? ' ⭐ ${s.rating.toStringAsFixed(1)}' : '';
                return ChoiceChip(
                  label: Text('${s.name}$ratingStr'),
                  selected: isSelected,
                  selectedColor: themeState.accent,
                  labelStyle: TextStyle(
                    // v95 FIX: the app's DEFAULT accent is white
                    // (theme_state.dart:23), so `selectedColor: accent`
                    // + a hardcoded white label = white-on-white, i.e.
                    // invisible season buttons. Use the app's own
                    // contrast helper, exactly like the Discover filter
                    // chips already do (discover_screen.dart:646).
                    color: isSelected
                        ? themeState.onAccent
                        : Colors.white70,
                    fontSize: 12,
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                  backgroundColor: Colors.white.withValues(alpha: 0.06),
                  side: BorderSide(
                    color: isSelected ? themeState.accent : Colors.white12,
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          // v95: the selected season's OWN rating + synopsis. TMDB's
          // /tv/{id} payload often omits vote_average per season, but the
          // /tv/{id}/season/{n} detail call always carries it - and that
          // call was already being made and thrown away.
          if (!_loadingSeason && _seasonDetail != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _seasonDetail!.name.isNotEmpty
                              ? _seasonDetail!.name
                              : 'Season $_selectedSeason',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (_seasonDetail!.rating > 0)
                        Text(
                          '⭐ ${_seasonDetail!.rating.toStringAsFixed(1)} / 10',
                          style: TextStyle(
                            color: themeState.onAccent == Colors.white
                                ? themeState.accent
                                : Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                    ],
                  ),
                  if (_seasonDetail!.overview.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Text(
                      _seasonDetail!.overview,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 11.5,
                        height: 1.4,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          if (_loadingSeason)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (_seasonDetail != null && _seasonDetail!.episodes.isNotEmpty)
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _seasonDetail!.episodes.length,
              separatorBuilder: (_, __) => const Divider(height: 1, color: Colors.white10),
              itemBuilder: (context, i) {
                final ep = _seasonDetail!.episodes[i];
                final ratingText = ep.rating > 0 ? '⭐ ${ep.rating.toStringAsFixed(1)}' : '';
                final durationText = ep.runtimeMinutes > 0 ? '⏱️ ${ep.runtimeMinutes}m' : '';
                final metaLine = [if (ratingText.isNotEmpty) ratingText, if (durationText.isNotEmpty) durationText].join('  ·  ');

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (ep.stillPath != null && ep.stillPath!.isNotEmpty)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: SizedBox(
                            width: 84,
                            height: 52,
                            child: TmdbImage(
                              url: 'https://image.tmdb.org/t/p/w300${ep.stillPath}',
                            ),
                          ),
                        )
                      else
                        Container(
                          width: 84,
                          height: 52,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Center(
                            child: Text(
                              'E${ep.episodeNumber}',
                              style: const TextStyle(color: Colors.white38, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${ep.episodeNumber}. ${ep.name}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (metaLine.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  metaLine,
                                  style: const TextStyle(color: Colors.amberAccent, fontSize: 11),
                                ),
                              ),
                            if (ep.overview.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 3),
                                child: Text(
                                  ep.overview,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Colors.white54, fontSize: 11.5, height: 1.3),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                '${currentSeasonInfo.episodes} episodes in ${currentSeasonInfo.name}',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }
}

class _WatchBlock extends StatelessWidget {
  final TmdbWatchInfo info;

  const _WatchBlock({required this.info});

  @override
  Widget build(BuildContext context) {
    Widget row(String label, List<String> names, Color color) {
      if (names.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 56,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: color, fontSize: 10, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                names.join(' · '),
                style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Where to watch (India)',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.75),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          row('Stream', info.stream, const Color(0xFF4ade80)),
          row('Rent', info.rent, const Color(0xFFfacc15)),
          row('Buy', info.buy, const Color(0xFF60a5fa)),
        ],
      ),
    );
  }
}

class _ReviewsBlock extends StatelessWidget {
  final List<TmdbReview> reviews;

  const _ReviewsBlock({required this.reviews});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'User Reviews',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '(${reviews.length})',
                style: const TextStyle(color: Colors.white38, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final r in reviews)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
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
                      CircleAvatar(
                        radius: 14,
                        backgroundColor: themeState.accent.withValues(alpha: 0.2),
                        child: Text(
                          r.author.isNotEmpty ? r.author[0].toUpperCase() : 'U',
                          style: TextStyle(color: themeState.accent, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          r.author.isNotEmpty ? r.author : 'TMDB User',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (r.rating != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '⭐ ${tmdbRatingText(r.rating!)}',
                            style: const TextStyle(color: Colors.amberAccent, fontSize: 10.5, fontWeight: FontWeight.bold),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    r.text,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _AllDataBlock extends StatelessWidget {
  final TmdbDetailExtras extras;
  final int movieId;

  const _AllDataBlock({required this.extras, required this.movieId});

  @override
  Widget build(BuildContext context) {
    Widget row(String l, String v) => Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 85,
            child: Text(
              l,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 11.5),
            ),
          ),
          Expanded(
            child: Text(v, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (extras.releaseDate.isNotEmpty) row('Release', extras.releaseDate),
          if (extras.originalTitle.isNotEmpty) row('Original', extras.originalTitle),
          if (extras.budgetUsd > 0) row('Budget', '\$${formatVoteCount(extras.budgetUsd)}'),
          if (extras.revenueUsd > 0) row('Revenue', '\$${formatVoteCount(extras.revenueUsd)}'),
          if (extras.companies.isNotEmpty) row('Studio', extras.companies.join(' · ')),
          if (extras.countries.isNotEmpty) row('Country', extras.countries.join(' · ')),
          if (extras.allLanguages.isNotEmpty) row('Languages', extras.allLanguages.join(', ')),
          _RealSubtitlesBlock(movieId: movieId),
        ],
      ),
    );
  }
}

class _RealSubtitlesBlock extends StatefulWidget {
  final int movieId;
  const _RealSubtitlesBlock({required this.movieId});

  @override
  State<_RealSubtitlesBlock> createState() => _RealSubtitlesBlockState();
}

class _RealSubtitlesBlockState extends State<_RealSubtitlesBlock> {
  final _client = OpenSubtitlesClient();
  List<String>? _langs;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    final cachePath = await NativeBridge.cacheDirPath();
    if (cachePath != null) _client.cacheDir = Directory(cachePath);
    final langs = await _client.languagesFor(widget.movieId);
    if (mounted) setState(() => _langs = langs);
  }

  @override
  Widget build(BuildContext context) {
    if (kOpenSubtitlesApiKey.isEmpty) return const SizedBox.shrink();
    final langs = _langs;
    if (langs == null || langs.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        'Subtitles available: ${langs.join('  ')}',
        style: const TextStyle(color: Colors.white54, fontSize: 11),
      ),
    );
  }
}
