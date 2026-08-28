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

/// v44: the Discover detail sheet - poster, TMDB rating (with credit),
/// and now the FULL story: tagline, runtime, genres, director, cast,
/// vote count, plus the same two actions:
///
///  - "Watch trailer on YouTube": opens the official YouTube app on the
///    trailer (Play-policy-safe; we never stream YouTube in-app).
///  - "In my library": shown ONLY when the movie is already on the phone -
///    then Max Player plays it instantly, offline.
///
/// DraggableScrollableSheet like every other sheet since v35 (landscape
/// safe, every control stays reachable).
class MovieDetailSheet extends StatefulWidget {
  final TmdbMovie movie;
  final VideoTrack? localMatch;
  final MediaPlayerState player;

  /// Lazily resolves trailer + extras in ONE call (detail is cached 24h).
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
      backgroundColor: const Color(0xFF1a1a24),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.62,
        minChildSize: 0.4,
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
  // Fired once - never inside build(), so no refetch on every rebuild.
  // v45: NOT final - a failed load (was common on slow networks) now has
  // a visible Retry instead of needing sheet close/open rounds.
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
      MaterialPageRoute(
          builder: (_) => PlayerScreen(player: widget.player)),
    );
  }

  Future<void> _openTrailer(String key) async {
    final ok = await NativeBridge.openYouTube(key);
    if (!ok) {
      // Exceptionally rare (no browser?!) - keep it silent, the button
      // simply does nothing visible instead of crashing the sheet.
    }
  }

  @override
  Widget build(BuildContext context) {
    final movie = widget.movie;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 110,
                height: 165,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: TmdbImage(
                      url: tmdbPosterUrl(movie.posterPath, big: true)),
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
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      [
                        if (movie.year != null) '${movie.year}',
                        '⭐ ${tmdbRatingText(movie.rating)} / 10',
                      ].join('  ·  '),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Rating & data: TMDB',
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
          // v44: the extra facts arrive with the trailer lookup (one call).
          // v45: that same call also brings the screenshots row, and a
          // failure offers Retry instead of a dead sheet.
          FutureBuilder<TmdbFull?>(
            future: _detailFuture,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'Loading details...',
                    style: TextStyle(color: Colors.white38, fontSize: 12),
                  ),
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
                          'Details could not load (network was busy).',
                          style:
                              TextStyle(color: Colors.white38, fontSize: 12),
                        ),
                      ),
                      TextButton(
                        onPressed: _retryDetail,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (full.screenshots.isNotEmpty)
                    _ScreenshotsRow(paths: full.screenshots),
                  _ExtrasBlock(extras: full.extras),
                  _LanguagesBlock(extras: full.extras, movieId: movie.id),
                  // v59 (user): web series must mention ALL their parts.
                  if (full.seasons.isNotEmpty)
                    _SeasonsBlock(seasons: full.seasons),
                  if (!full.watch.isEmpty) _WatchBlock(info: full.watch),
                  _AllDataBlock(extras: full.extras, movieId: movie.id),
                ],
              );
            },
          ),
          if (movie.overview.isNotEmpty)
            Text(
              movie.overview,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
                height: 1.5,
              ),
            )
          else
            Text(
              'No story summary available for this movie yet.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 13,
                height: 1.5,
              ),
            ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FutureBuilder<TmdbFull?>(
              future: _detailFuture,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return OutlinedButton.icon(
                    onPressed: null,
                    icon: const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    label: const Text('Finding trailer...'),
                  );
                }
                final key = snap.data?.movie.trailerKey;
                if (key == null || key.isEmpty) {
                  return const Text(
                    'No official trailer is available for this one.',
                    style: TextStyle(color: Colors.white38, fontSize: 12),
                  );
                }
                return FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: themeState.accent,
                    foregroundColor: themeState.onAccent,
                  ),
                  onPressed: () => _openTrailer(key),
                  icon: const Icon(Icons.smart_display),
                  label: const Text('Watch trailer on YouTube'),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          // v45: movie-restricted AI chat (free OpenRouter models).
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              onPressed: () =>
                  AskAiSheet.show(context, movie: widget.movie),
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Ask with AI about this movie'),
            ),
          ),
          if (widget.localMatch != null) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: () => _playLocal(context),
                icon: const Icon(Icons.video_library),
                label: Text(
                    'In my library - play "${widget.localMatch!.title}" now',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
            ),
          ],
          // v46: real TMDB user reviews (was asked: "real reviews").
          FutureBuilder<TmdbFull?>(
            future: _detailFuture,
            builder: (context, snap) {
              final full = snap.data;
              if (snap.connectionState != ConnectionState.done ||
                  full == null ||
                  full.reviews.isEmpty) {
                return const SizedBox.shrink();
              }
              return _ReviewsBlock(reviews: full.reviews);
            },
          ),
          const SizedBox(height: 14),
          Center(
            child: Text(
              // v46: short attribution line (the full legal phrasing lives
              // in the README and the Play listing, as TMDB requires).
              'Movie data & ratings: TMDB',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.3),
                fontSize: 10,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// v45: a horizontal strip of scene "screenshots" (TMDB backdrops) so the
/// sheet shows the movie, not just tells it.
class _ScreenshotsRow extends StatelessWidget {
  final List<String> paths;

  const _ScreenshotsRow({required this.paths});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: SizedBox(
        height: 104,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: paths.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, i) => ClipRRect(
            borderRadius: BorderRadius.circular(8),
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

/// v44: tagline, runtime, genres, votes, director, cast - everything TMDB
/// gives us beyond the poster. Any missing piece is simply skipped.
class _ExtrasBlock extends StatelessWidget {
  final TmdbDetailExtras extras;

  const _ExtrasBlock({required this.extras});

  @override
  Widget build(BuildContext context) {
    final meta = <String>[
      if (formatRuntime(extras.runtimeMinutes).isNotEmpty)
        formatRuntime(extras.runtimeMinutes),
      if (extras.voteCount > 0) '${formatVoteCount(extras.voteCount)} votes',
      if (extras.status.isNotEmpty && extras.status != 'Released')
        extras.status,
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (extras.tagline.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '"${extras.tagline}"',
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 13,
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
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ),
          // v46: audio languages + our own subtitle capability line.
          if (extras.spokenLanguages.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                'Languages: ${extras.spokenLanguages.join(' · ')}',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
          if (extras.genres.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final g in extras.genres.take(4))
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        g,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 11),
                      ),
                    ),
                ],
              ),
            ),
          if (extras.director.isNotEmpty)
            Text(
              'Director: ${extras.director}',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          if (extras.cast.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                'Cast: ${extras.cast.join(', ')}',
                style: const TextStyle(
                    color: Colors.white54, fontSize: 12, height: 1.4),
              ),
            ),
        ],
      ),
    );
  }
}

/// v46: "Where to watch" (India) with the compare split - Stream / Rent /
/// Buy provider names from TMDB's JustWatch-powered data.
/// v59: "in web series, when we select a content mention ALL parts of
/// the series in the detail" - every season as one clean line:
/// Season 1 · 8 episodes · 2011.
class _SeasonsBlock extends StatelessWidget {
  final List<TmdbSeason> seasons;

  const _SeasonsBlock({required this.seasons});

  @override
  Widget build(BuildContext context) {
    final totalEps = seasons.fold<int>(0, (a, s) => a + s.episodes);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Seasons & parts - ${seasons.length} season'
            '${seasons.length == 1 ? '' : 's'}, $totalEps episodes total',
            style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          for (final s in seasons)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      s.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 13),
                    ),
                  ),
                  Text(
                    '${s.episodes} ep'
                    '${s.year != null ? '  ·  ${s.year}' : ''}',
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ],
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
                style: const TextStyle(color: Colors.white70, fontSize: 12,
                    height: 1.4),
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
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

/// v46: real TMDB user reviews, trimmed, with the author's rating.
class _ReviewsBlock extends StatelessWidget {
  final List<TmdbReview> reviews;

  const _ReviewsBlock({required this.reviews});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'User reviews',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.75),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          for (final r in reviews)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    [
                      if (r.author.isNotEmpty) r.author else 'TMDB user',
                      if (r.rating != null)
                        '⭐ ${tmdbRatingText(r.rating!)}',
                    ].join('  ·  '),
                    style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    r.text,
                    style: const TextStyle(
                        color: Colors.white54, fontSize: 12, height: 1.45),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// v72: Comprehensive languages block showing Spoken Audio Tracks and All Dubbed / Translations.
class _LanguagesBlock extends StatelessWidget {
  final TmdbDetailExtras extras;
  final int movieId;

  const _LanguagesBlock({required this.extras, required this.movieId});

  @override
  Widget build(BuildContext context) {
    final spoken = extras.spokenLanguages;
    final all = extras.allLanguages;

    if (spoken.isEmpty && all.isEmpty) {
      return const SizedBox.shrink();
    }

    final accent = themeState.accent;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 4, bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.translate, size: 16, color: accent),
              const SizedBox(width: 8),
              const Text(
                'Audio & Dubbed Languages',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (spoken.isNotEmpty) ...[
            Text(
              'Spoken / Audio Tracks (${spoken.length})',
              style: TextStyle(
                color: accent,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final l in spoken)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: accent.withValues(alpha: 0.5)),
                    ),
                    child: Text(
                      l,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          if (all.isNotEmpty) ...[
            Text(
              'Available Dubbed & Translations (${all.length})',
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final l in all)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3.5),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Text(
                      spoken.contains(l) ? '$l (Audio)' : '$l (Dubbed)',
                      style: TextStyle(
                        color:
                            spoken.contains(l) ? Colors.white : Colors.white70,
                        fontSize: 11,
                        fontWeight: spoken.contains(l)
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// v47: EVERYTHING TMDB knows - dates, certificate, money, companies,
/// countries and ALL supported languages.
class _AllDataBlock extends StatelessWidget {
  final TmdbDetailExtras extras;
  final int movieId;
  const _AllDataBlock({required this.extras, required this.movieId});
  @override
  Widget build(BuildContext context) {
    Widget row(String l, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 78, child: Text(l, style: TextStyle(
              color: Colors.white.withValues(alpha: 0.4), fontSize: 11))),
          Expanded(child: Text(v, style: const TextStyle(
              color: Colors.white70, fontSize: 12))),
        ]));
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (extras.releaseDate.isNotEmpty) row('Release', extras.releaseDate),
        if (extras.certification.isNotEmpty) row('Certificate', extras.certification),
        if (extras.originalTitle.isNotEmpty) row('Original', extras.originalTitle),
        if (extras.budgetUsd > 0) row('Budget', '\$${formatVoteCount(extras.budgetUsd)}'),
        if (extras.revenueUsd > 0) row('Revenue', '\$${formatVoteCount(extras.revenueUsd)}'),
        if (extras.companies.isNotEmpty) row('Studio', extras.companies.join('  ')),
        if (extras.countries.isNotEmpty) row('Country', extras.countries.join('  ')),
        if (extras.allLanguages.isNotEmpty) row('Languages', extras.allLanguages.join(', ')),
        _RealSubtitlesBlock(movieId: movieId),
      ]),
    );
  }
}

/// v47: REAL subtitle availability (OpenSubtitles).
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
  void initState() { super.initState(); _boot(); }
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
      child: Text('Subtitles available: ${langs.join('  ')}',
          style: const TextStyle(color: Colors.white54, fontSize: 11)),
    );
  }
}
