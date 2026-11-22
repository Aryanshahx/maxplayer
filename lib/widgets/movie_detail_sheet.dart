import '../utils/app_language.dart';
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:url_launcher/url_launcher.dart';

import 'trailer_player_screen.dart';

import '../theme.dart';
import '../utils/tmdb.dart';
import '../utils/crash_log.dart';
import '../utils/tmdb_image.dart';
import 'ask_ai_sheet.dart';
import 'video_grid.dart';

/// Discover movie & web series detail sheet (ported from the canonical old
/// app's `movie_detail_sheet.dart`).
class MovieDetailSheet extends StatefulWidget {
  final TmdbMovie movie;
  final AssetEntity? localMatch;

  /// The Discover screen's own context — stays mounted after this sheet is
  /// popped, so "In My Library" can push the player onto it.
  final BuildContext hostContext;

  final Future<TmdbFull?> Function() detailLoader;

  /// The bottom-sheet drag handle only makes sense when this widget is
  /// shown AS a bottom sheet. Embedded in the full detail page it reads
  /// as a stray "notch" at the top — the page passes false. (v1.0.1+16)
  final bool showHandle;

  const MovieDetailSheet({
    super.key,
    required this.movie,
    required this.localMatch,
    required this.hostContext,
    required this.detailLoader,
    this.showHandle = true,
  });

  static Future<void> show(
    BuildContext context, {
    required TmdbMovie movie,
    required AssetEntity? localMatch,
    required Future<TmdbFull?> Function() detailLoader,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
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
            hostContext: context,
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

  // v1.0.1+32: trailer HAND-OFF to the YouTube app. The in-app WebView
  // embed is hard-gated by YouTube on the field devices: error 152-4 on
  // EVERY video, on Wi-Fi AND mobile data alike, while the normal watch
  // page plays fine in Chrome (field-tested across +29/+30/+31 origin
  // recipes — nocookie, www, enablejsapi+origin+widget_referrer). YouTube
  // refuses embedded playback inside this WebView regardless; the watch
  // URL opened externally is the only playback path YouTube controls
  // end-to-end, so that is what the card launches on tap. The language
  // chips now re-aim the launch target (and swap the thumbnail) BEFORE
  // the tap.
  String? _inlineKey;
  bool _inlineTrailerLoading = false;
  bool _inlineTrailerFailed = false;
  String _inlineTrailerFailDetail = '';

  void _retryDetail() {
    setState(() {
      _detailFuture = widget.detailLoader();
    });
  }

  /// v1.0.1+32: tap the top trailer card -> open the trailer in the
  /// YouTube app (or browser). The WebView embed path is dead on the
  /// field devices (see the field block note), so the card hands the
  /// plain watch URL to Android, which resolves it to YouTube's own app —
  /// the one player YouTube never 152-4s. A launch failure lands in the
  /// card's error state with the exact detail — never an MPV screen,
  /// never a vague panel.
  Future<void> _launchTrailer(TmdbMovie detailMovie) async {
    if (_inlineTrailerLoading) return;
    final variants = detailMovie.trailerVariants;
    final key =
        _inlineKey ??
        (variants.isNotEmpty
            ? variants.first.key
            : (detailMovie.trailerKey ?? ''));
    if (key.isEmpty) return;
    setState(() {
      _inlineTrailerLoading = true;
      _inlineTrailerFailed = false;
      _inlineTrailerFailDetail = '';
    });
    final uri = Uri.parse(youtubeWatchUrl(key));
    var ok = false;
    String? errorDetail;
    try {
      ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      errorDetail = '$e';
    }
    if (!mounted) return;
    if (ok) {
      setState(() => _inlineTrailerLoading = false);
      CrashLog.crumb('trailer.youtube_handoff', {'key': key});
      return;
    }
    final detail = errorDetail ?? 'No app accepted the YouTube link';
    CrashLog.error('trailer.youtube_handoff', detail);
    setState(() {
      _inlineTrailerLoading = false;
      _inlineTrailerFailed = true;
      _inlineTrailerFailDetail = detail;
    });
  }

  /// v1.0.1+32: re-aim the card at another language variant — the chips
  /// swap the thumbnail AND the launch target before the tap.
  void _selectVariant(TrailerVariant v) {
    if (v.key.isEmpty || v.key == _inlineKey) return;
    setState(() {
      _inlineKey = v.key;
      _inlineTrailerFailed = false;
      _inlineTrailerFailDetail = '';
    });
  }

  /// v1.0.1+32: clear the card's error state back to the thumbnail.
  void _clearTrailerError() {
    setState(() {
      _inlineTrailerLoading = false;
      _inlineTrailerFailed = false;
      _inlineTrailerFailDetail = '';
    });
  }

  /// v1.0.1+32: the TOP-OF-DETAILS trailer card — the selected variant's
  /// thumbnail with a play affordance; tapping launches the trailer in
  /// the YouTube app, the chips below pick WHICH variant launches, and a
  /// launch failure lands in the card with the exact detail + RETRY.
  Widget _inlineTrailerCard(TmdbMovie detailMovie) {
    final variants = detailMovie.trailerVariants;
    final selectedKey =
        _inlineKey ??
        (variants.isNotEmpty
            ? variants.first.key
            : (detailMovie.trailerKey ?? ''));
    if (selectedKey.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(color: Colors.black),
                  _trailerThumbImage(selectedKey),
                  // Tap-to-start surface (thumbnail state only — while
                  // playing, YouTube's own controls own the gestures).
                  if (!_inlineTrailerLoading && !_inlineTrailerFailed)
                    Positioned.fill(
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => _launchTrailer(detailMovie),
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ),
                  if (!_inlineTrailerLoading && !_inlineTrailerFailed) ...[
                    const IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment(0, 0.25),
                            colors: [Colors.black87, Colors.transparent],
                          ),
                        ),
                      ),
                    ),
                    IgnorePointer(
                      child: Center(
                        child: Container(
                          width: 58,
                          height: 58,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.55),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.85),
                              width: 2,
                            ),
                          ),
                          child: const Icon(
                            Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 36,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 12,
                      bottom: 10,
                      child: IgnorePointer(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.accent,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: LText(
                            'TRAILER',
                            style: TextStyle(
                              color: AppColors.onAccent,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (_inlineTrailerLoading)
                    const ColoredBox(
                      color: Color(0x66000000),
                      child: Center(
                        child: SizedBox(
                          width: 44,
                          height: 44,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  if (_inlineTrailerFailed) ...[
                    Container(color: Colors.black.withValues(alpha: 0.7)),
                    IgnorePointer(
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.error_outline,
                                color: Colors.white70,
                                size: 30,
                              ),
                              const SizedBox(height: 8),
                              const LText(
                                'Trailer could not be loaded right now.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (_inlineTrailerFailDetail.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  _inlineTrailerFailDetail,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.white54,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 10,
                      right: 12,
                      child: TextButton.icon(
                        onPressed: () => _launchTrailer(detailMovie),
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const LText('RETRY'),
                      ),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Material(
                        color: Colors.black.withValues(alpha: 0.5),
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: _clearTrailerError,
                          child: const Padding(
                            padding: EdgeInsets.all(6),
                            child: Icon(
                              Icons.close_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        if (variants.length > 1)
          Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: SizedBox(
              height: 30,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: variants.length,
                separatorBuilder: (_, _) => SizedBox(width: 6),
                itemBuilder: (context, i) {
                  final v = variants[i];
                  final selected = v.key == selectedKey;
                  return ChoiceChip(
                    selected: selected,
                    onSelected: (_) => _selectVariant(v),
                    visualDensity: VisualDensity.compact,
                    labelPadding: EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: -2,
                    ),
                    label: Text(
                      v.lang.toUpperCase(),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: selected
                            ? AppColors.onAccent
                            : AppColors.textSecondary,
                      ),
                    ),
                    selectedColor: AppColors.accent,
                    backgroundColor: AppColors.textPrimary.withValues(
                      alpha: 0.06,
                    ),
                  );
                },
              ),
            ),
          ),
        SizedBox(height: 6),
      ],
    );
  }

  Future<void> _playLocal(BuildContext sheetContext) async {
    final asset = widget.localMatch;
    if (asset == null) return;
    Navigator.of(sheetContext).pop(); // close the sheet first
    await VideoGrid.openVideo(widget.hostContext, asset);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final movie = widget.movie;
    final isTv = movie.kind == 'tv';

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.showHandle) ...[
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            SizedBox(height: 14),
          ],

          // v1.0.1+32: TRAILER CARD AT THE TOP of the details — tapping
          // it hands the trailer to the YouTube app (no dedicated player
          // screen; the in-app WebView embed is hard-gated 152-4 here).
          FutureBuilder<TmdbFull?>(
            future: _detailFuture,
            builder: (context, snap) {
              final detailMovie = snap.data?.movie;
              if (detailMovie == null) return SizedBox.shrink();
              return _inlineTrailerCard(detailMovie);
            },
          ),

          // Header: Poster + Title + Rating + Kind badge
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 105,
                height: 155,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: TmdbImage(
                    url: tmdbPosterUrl(movie.posterPath, big: true),
                  ),
                ),
              ),
              SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      movie.title,
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        height: 1.25,
                      ),
                    ),
                    SizedBox(height: 6),
                    Row(
                      children: [
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.accent.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: AppColors.accent.withValues(alpha: 0.4),
                            ),
                          ),
                          child: Text(
                            isTv ? 'SERIES' : 'MOVIE',
                            style: TextStyle(
                              color: AppColors.accent,
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        SizedBox(width: 8),
                        if (movie.year != null)
                          Text(
                            '${movie.year}',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                        SizedBox(width: 8),
                        Text(
                          '⭐ ${tmdbRatingText(movie.rating)} / 10',
                          style: TextStyle(
                            color: AppColors.rating,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),

          SizedBox(height: 14),

          // Action Buttons: Ask AI (the trailer lives in the top card).
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent.withValues(alpha: 0.18),
                    foregroundColor: AppColors.accent,
                    side: BorderSide(
                      color: AppColors.accent.withValues(alpha: 0.4),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () => AskAiSheet.show(context, movie: movie),
                  icon: Icon(Icons.auto_awesome, size: 16),
                  label: LText(
                    'Ask AI',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),

          if (widget.localMatch != null) ...[
            SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.textPrimary.withValues(
                    alpha: 0.08,
                  ),
                  foregroundColor: AppColors.textPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () => _playLocal(context),
                icon: Icon(Icons.video_library, color: AppColors.accent),
                label: Text(
                  'In My Library - Play "${widget.localMatch!.title}"',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],

          SizedBox(height: 14),

          // Main Details Content
          FutureBuilder<TmdbFull?>(
            future: _detailFuture,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final full = snap.data;
              if (full == null) {
                return Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: LText(
                          'Details could not load. Check network connection.',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _retryDetail,
                        child: LText('Retry'),
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
                  _AllDataBlock(extras: full.extras),
                  _DetailedStoryBlock(movie: movie, extras: full.extras),
                  if (!full.watch.isEmpty)
                    _WatchBlock(
                      info: full.watch,
                      title: movie.title,
                      year: movie.year,
                    ),
                  if (full.extras.castMembers.isNotEmpty)
                    _TopCastSlider(cast: full.extras.castMembers),
                  if (isTv && full.seasons.isNotEmpty)
                    _SeasonsBlock(tvId: movie.id, seasons: full.seasons),
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
    Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(top: 10, bottom: 8),
      child: SizedBox(
        height: 106,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: paths.length,
          separatorBuilder: (_, _) => SizedBox(width: 8),
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
    Theme.of(context);
    final meta = <String>[
      if (formatRuntime(extras.runtimeMinutes).isNotEmpty)
        formatRuntime(extras.runtimeMinutes),
      if (extras.voteCount > 0) '${formatVoteCount(extras.voteCount)} votes',
      if (extras.status.isNotEmpty && extras.status != 'Released')
        extras.status,
    ];

    return Padding(
      padding: EdgeInsets.only(top: 12, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (extras.tagline.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                '"${extras.tagline}"',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13.5,
                  fontStyle: FontStyle.italic,
                  height: 1.4,
                ),
              ),
            ),
          if (meta.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                meta.join('  ·  '),
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12.5,
                ),
              ),
            ),
          if (extras.genres.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final g in extras.genres)
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.textPrimary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Text(
                        g,
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11.5,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          LText(
            'Storyline',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 6),
          Text(
            movie.overview.isNotEmpty
                ? movie.overview
                : 'No full synopsis available for this title.',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              height: 1.5,
            ),
          ),
          if (extras.director.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Director: ${extras.director}',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
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
    Theme.of(context);
    if (cast.isEmpty) return SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LText(
            'Top Cast',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 10),
          SizedBox(
            height: 124,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: cast.length,
              separatorBuilder: (_, _) => SizedBox(width: 12),
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
                            color: AppColors.accent.withValues(alpha: 0.5),
                            width: 1.5,
                          ),
                        ),
                        child: ClipOval(
                          child:
                              c.profilePath != null && c.profilePath!.isNotEmpty
                              ? TmdbImage(
                                  url:
                                      'https://image.tmdb.org/t/p/w185${c.profilePath}',
                                )
                              : Container(
                                  color: AppColors.border,
                                  child: Icon(
                                    Icons.person,
                                    color: AppColors.textSecondary,
                                    size: 32,
                                  ),
                                ),
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        c.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.textPrimary,
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
                          style: TextStyle(
                            color: AppColors.textSecondary,
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
    final path = await TmdbImage.initCacheDir();
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
    Theme.of(context);
    final seasons = widget.seasons;
    final totalEps = seasons.fold<int>(0, (a, s) => a + s.episodes);
    final currentSeasonInfo = seasons.firstWhere(
      (s) => s.number == _selectedSeason,
      orElse: () => seasons.first,
    );

    return Padding(
      padding: EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Seasons & Episodes (${seasons.length} Seasons, $totalEps Episodes)',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 10),
          SizedBox(
            height: 38,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: seasons.length,
              separatorBuilder: (_, _) => SizedBox(width: 8),
              itemBuilder: (context, i) {
                final s = seasons[i];
                final isSelected = s.number == _selectedSeason;
                final ratingStr = s.rating > 0
                    ? ' ⭐ ${s.rating.toStringAsFixed(1)}'
                    : '';
                return ChoiceChip(
                  label: Text('${s.name}$ratingStr'),
                  selected: isSelected,
                  selectedColor: AppColors.accent,
                  labelStyle: TextStyle(
                    color: isSelected
                        ? AppColors.onAccent
                        : AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: isSelected
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                  backgroundColor: AppColors.textPrimary.withValues(
                    alpha: 0.06,
                  ),
                  side: BorderSide(
                    color: isSelected ? AppColors.accent : AppColors.border,
                  ),
                  onSelected: (_) => _loadSeasonDetail(s.number),
                );
              },
            ),
          ),
          SizedBox(height: 10),
          if (!_loadingSeason && _seasonDetail != null)
            Container(
              width: double.infinity,
              margin: EdgeInsets.only(bottom: 10),
              padding: EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: AppColors.textPrimary.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: AppColors.border),
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
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (_seasonDetail!.rating > 0)
                        Text(
                          '⭐ ${_seasonDetail!.rating.toStringAsFixed(1)} / 10',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                    ],
                  ),
                  if (_seasonDetail!.overview.isNotEmpty) ...[
                    SizedBox(height: 5),
                    Text(
                      _seasonDetail!.overview,
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11.5,
                        height: 1.4,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          if (_loadingSeason)
            Padding(
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
              physics: NeverScrollableScrollPhysics(),
              itemCount: _seasonDetail!.episodes.length,
              separatorBuilder: (_, _) =>
                  Divider(height: 1, color: AppColors.border),
              itemBuilder: (context, i) {
                final ep = _seasonDetail!.episodes[i];
                final ratingText = ep.rating > 0
                    ? '⭐ ${ep.rating.toStringAsFixed(1)}'
                    : '';
                final durationText = ep.runtimeMinutes > 0
                    ? '⏱️ ${ep.runtimeMinutes}m'
                    : '';
                final metaLine = [
                  if (ratingText.isNotEmpty) ratingText,
                  if (durationText.isNotEmpty) durationText,
                ].join('  ·  ');

                return Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
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
                              url:
                                  'https://image.tmdb.org/t/p/w300${ep.stillPath}',
                            ),
                          ),
                        )
                      else
                        Container(
                          width: 84,
                          height: 52,
                          decoration: BoxDecoration(
                            color: AppColors.textPrimary.withValues(
                              alpha: 0.05,
                            ),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Center(
                            child: Text(
                              'E${ep.episodeNumber}',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${ep.episodeNumber}. ${ep.name}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (metaLine.isNotEmpty)
                              Padding(
                                padding: EdgeInsets.only(top: 2),
                                child: Text(
                                  metaLine,
                                  style: TextStyle(
                                    color: AppColors.rating,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            if (ep.overview.isNotEmpty)
                              Padding(
                                padding: EdgeInsets.only(top: 3),
                                child: Text(
                                  ep.overview,
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 11.5,
                                    height: 1.3,
                                  ),
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
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                '${currentSeasonInfo.episodes} episodes in ${currentSeasonInfo.name}',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }
}

class _WatchBlock extends StatelessWidget {
  final TmdbWatchInfo info;

  /// Title + year power the Amazon affiliate search (v1.0.1+6); when empty
  /// the CTA simply doesn't render.
  final String title;
  final int? year;

  const _WatchBlock({required this.info, this.title = '', this.year});

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    Widget row(String label, List<String> names, Color color) {
      if (names.isEmpty) return SizedBox.shrink();
      return Padding(
        padding: EdgeInsets.only(bottom: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 56,
              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                names.join(' · '),
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LText(
            'Where to watch (India)',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: 6),
          row(
            'Stream',
            info.stream,
            AppColors.isDark
                ? const Color(0xFF4ade80)
                : const Color(0xFF166534),
          ),
          row('Rent', info.rent, AppColors.rating),
          row(
            'Buy',
            info.buy,
            AppColors.isDark
                ? const Color(0xFF60a5fa)
                : const Color(0xFF1D4ED8),
          ),
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
    Theme.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              LText(
                'User Reviews',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(width: 8),
              Text(
                '(${reviews.length})',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            ],
          ),
          SizedBox(height: 8),
          for (final r in reviews)
            Container(
              width: double.infinity,
              margin: EdgeInsets.only(bottom: 8),
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.textPrimary.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 14,
                        backgroundColor: AppColors.accent.withValues(
                          alpha: 0.2,
                        ),
                        child: Text(
                          r.author.isNotEmpty ? r.author[0].toUpperCase() : 'U',
                          style: TextStyle(
                            color: AppColors.accent,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          r.author.isNotEmpty ? r.author : 'TMDB User',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (r.rating != null)
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '⭐ ${tmdbRatingText(r.rating!)}',
                            style: TextStyle(
                              color: AppColors.rating,
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                  SizedBox(height: 6),
                  Text(
                    r.text,
                    style: TextStyle(
                      color: AppColors.textSecondary,
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

  const _AllDataBlock({required this.extras});

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    Widget row(String l, String v) => Padding(
      padding: EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 85,
            child: Text(
              l,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 11.5),
            ),
          ),
          Expanded(
            child: Text(
              v,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ),
        ],
      ),
    );

    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (extras.releaseDate.isNotEmpty) row('Release', extras.releaseDate),
          if (extras.originalTitle.isNotEmpty)
            row('Original', extras.originalTitle),
          if (extras.budgetUsd > 0)
            row('Budget', '\$${formatVoteCount(extras.budgetUsd)}'),
          if (extras.revenueUsd > 0)
            row('Revenue', '\$${formatVoteCount(extras.revenueUsd)}'),
          if (extras.companies.isNotEmpty)
            row('Studio', extras.companies.join(' · ')),
          if (extras.countries.isNotEmpty)
            row('Country', extras.countries.join(' · ')),
          if (extras.allLanguages.isNotEmpty)
            row('Languages', extras.allLanguages.join(', ')),
        ],
      ),
    );
  }
}

/// v1.0.1+24: trailer thumbnail for the clickable detail-section card.
/// maxresdefault (1280x720) first; older/small videos only publish
/// hqdefault, so fall back to that on HTTP error.
Widget _trailerThumbImage(String key) {
  return Image.network(
    ytThumbUrl(key),
    fit: BoxFit.cover,
    errorBuilder: (ctx, err, stack) => Image.network(
      'https://i.ytimg.com/vi/$key/hqdefault.jpg',
      fit: BoxFit.cover,
      errorBuilder: (a, b, c) => SizedBox.shrink(),
    ),
  );
}
