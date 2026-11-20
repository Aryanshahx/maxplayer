import 'ask_ai_sheet.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/material.dart';
import '../utils/app_language.dart';
import 'android_browse.dart';
import 'tmdb.dart';
import '../playlist.dart';

class AndroidMovieDetails extends StatelessWidget {
  final TmdbFull full;
  final ValueChanged<String> onTrailer;
  final VoidCallback onWatch;
  final Widget? seasons;
  final Widget? related;
  final String? localSource;
  final ValueChanged<String>? onPlayLocal;
  const AndroidMovieDetails(
      {super.key,
      required this.full,
      required this.onTrailer,
      required this.onWatch,
      this.seasons,
      this.related,
      this.localSource,
      this.onPlayLocal});
  Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 8),
      child: LText(text,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)));
  Widget badge(String value) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white12)),
      child: Text(value,
          style: const TextStyle(fontSize: 11.5, color: Colors.white70)));
  @override
  Widget build(BuildContext context) {
    final m = full.movie, e = full.extras;
    final trailer = m.trailerKey ??
        (m.trailerVariants.isEmpty ? null : m.trailerVariants.first.key);
    return Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (trailer != null) ...[
            LayoutBuilder(
                builder: (context, size) => ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Material(
                        color: const Color(0xff1b1b24),
                        child: InkWell(
                            onTap: () => onTrailer(trailer),
                            child: SizedBox(
                                height:
                                    (size.maxWidth * 9 / 16).clamp(160, 340),
                                child: Stack(fit: StackFit.expand, children: [
                                  movieImage(m.backdropPath ?? m.posterPath,
                                      backdrop: m.backdropPath != null),
                                  const DecoratedBox(
                                      decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                              begin: Alignment.topCenter,
                                              end: Alignment.bottomCenter,
                                              colors: [
                                        Colors.black26,
                                        Colors.black87
                                      ]))),
                                  const Center(
                                      child: CircleAvatar(
                                          radius: 27,
                                          backgroundColor: Colors.white,
                                          child: Icon(Icons.play_arrow_rounded,
                                              size: 34, color: Colors.black))),
                                  const Positioned(
                                      bottom: 12,
                                      left: 14,
                                      child: Text('Watch trailer on YouTube ↗',
                                          style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.bold))),
                                ])))))),
            const SizedBox(height: 8),
            if (m.trailerVariants.length > 1)
              Wrap(spacing: 6, children: [
                for (final variant in m.trailerVariants)
                  ActionChip(
                      label: Text(
                          '${variant.lang.toUpperCase()} · ${variant.name}',
                          style: const TextStyle(fontSize: 11)),
                      onPressed: () => onTrailer(variant.key))
              ]),
            const SizedBox(height: 14),
          ],
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
                width: 105,
                height: 155,
                child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: movieImage(m.posterPath))),
            const SizedBox(width: 14),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(m.title,
                      style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          height: 1.25)),
                  const SizedBox(height: 6),
                  Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: .18),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.white38)),
                            child: Text(m.kind == 'tv' ? 'SERIES' : 'MOVIE',
                                style: const TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.bold))),
                        if (m.year != null)
                          Text('${m.year}',
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 13)),
                        Text('★ ${tmdbRatingText(m.rating)} / 10',
                            style: const TextStyle(
                                color: Colors.amberAccent,
                                fontSize: 13,
                                fontWeight: FontWeight.w600)),
                      ]),
                  if (e.certification.isNotEmpty)
                    Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: badge(e.certification)),
                ])),
          ]),
          const SizedBox(height: 14),
          if (localSource != null && onPlayLocal != null)
            Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonalIcon(
                        onPressed: () => onPlayLocal!(localSource!),
                        icon: const Icon(Icons.video_library),
                        label: Text(
                            'In My Library - Play "${labelFor(localSource!)}"',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis)))),
          SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                  onPressed: () => AskAiSheet.show(context, movie: m),
                  icon: const Icon(Icons.auto_awesome, size: 16),
                  label: const Text('Ask AI'))),
          if (e.tagline.isNotEmpty)
            Padding(
                padding: const EdgeInsets.only(top: 14, bottom: 8),
                child: Text('“${e.tagline}”',
                    style: const TextStyle(
                        fontSize: 13.5,
                        color: Colors.white70,
                        fontStyle: FontStyle.italic,
                        height: 1.4))),
          Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 10),
              child: Text(
                  [
                    if (e.runtimeMinutes > 0) formatRuntime(e.runtimeMinutes),
                    if (e.voteCount > 0)
                      '${formatVoteCount(e.voteCount)} votes',
                    if (e.status.isNotEmpty) e.status,
                  ].join(' · '),
                  style:
                      const TextStyle(color: Colors.white60, fontSize: 12.5))),
          Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [for (final genre in e.genres) badge(genre)]),
          heading('Storyline'),
          SelectableText(
              m.overview.isEmpty
                  ? 'No full synopsis available for this title.'
                  : m.overview,
              style: const TextStyle(
                  color: Colors.white70, fontSize: 13, height: 1.5)),
          if (e.director.isNotEmpty)
            Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Director: ${e.director}',
                    style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600))),
          if (e.castMembers.isNotEmpty) ...[
            heading('Top cast'),
            SizedBox(
                height: 145,
                child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: e.castMembers.take(24).length,
                    separatorBuilder: (context, i) => const SizedBox(width: 12),
                    itemBuilder: (context, i) {
                      final cast = e.castMembers[i];
                      return SizedBox(
                          width: 86,
                          child: Column(children: [
                            ClipOval(
                                child: SizedBox(
                                    width: 68,
                                    height: 68,
                                    child: movieImage(cast.profilePath))),
                            const SizedBox(height: 7),
                            Text(cast.name,
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11.5)),
                            const SizedBox(height: 3),
                            Text(cast.character,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: Colors.white38, fontSize: 10))
                          ]));
                    })),
          ],
          if (full.screenshots.isNotEmpty) ...[
            heading('Images'),
            SizedBox(
                height: 106,
                child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: full.screenshots.take(12).length,
                    separatorBuilder: (context, i) => const SizedBox(width: 8),
                    itemBuilder: (context, i) => ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: SizedBox(
                            width: 176,
                            child: movieImage(full.screenshots[i],
                                backdrop: true))))),
          ],
          if (seasons != null) ...[const SizedBox(height: 18), seasons!],
          heading('Details'),
          for (final entry in {
            'Original title': e.originalTitle,
            'Release date': e.releaseDate,
            'Spoken languages': e.spokenLanguages.join(', '),
            'Production': e.companies.join(', '),
            'Countries': e.countries.join(', ')
          }.entries)
            if (entry.value.isNotEmpty)
              Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                            width: 120,
                            child: Text(entry.key,
                                style: const TextStyle(
                                    color: Colors.white38, fontSize: 12))),
                        Expanded(
                            child: Text(entry.value,
                                style: const TextStyle(
                                    fontSize: 12, color: Colors.white70)))
                      ])),
          heading('Where to watch'),
          if (!full.watch.isEmpty)
            Text(
                'Stream: ${full.watch.stream.join(", ")}\nRent: ${full.watch.rent.join(", ")}\nBuy: ${full.watch.buy.join(", ")}',
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
          if ([...full.watch.stream, ...full.watch.rent, ...full.watch.buy].any(
              (name) =>
                  name.toLowerCase().contains('amazon') ||
                  name.toLowerCase().contains('prime video'))) ...[
            FilledButton.icon(
                onPressed: () => launchUrl(
                    Uri.https('www.amazon.in', '/s', {
                      'k': '${m.title} ${m.year ?? ''} movie',
                      'i': 'instant-video',
                      'tag': 'maxplayer0a-21'
                    }),
                    mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.play_circle),
                label: const Text('Watch on Prime Video')),
            const Text(
                'Partner link — As an Amazon Associate, Hyper Player earns from qualifying purchases.',
                style: TextStyle(fontSize: 11, color: Colors.white54)),
          ] else
            const Text('No supported watch link is available for this title.',
                style: TextStyle(color: Colors.white54)),
          if (full.reviews.isNotEmpty) heading('Reviews'),
          for (final review in full.reviews.take(5))
            ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title:
                    Text(review.author, style: const TextStyle(fontSize: 13)),
                subtitle: Text(
                    review.rating == null
                        ? 'TMDB user review'
                        : '★ ${review.rating}',
                    style:
                        const TextStyle(color: Colors.white38, fontSize: 11)),
                children: [
                  Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: SelectableText(review.text,
                          style: const TextStyle(
                              fontSize: 12, color: Colors.white70)))
                ]),
          if (related != null) ...[const SizedBox(height: 14), related!],
        ]));
  }
}

class AndroidSeasonBrowser extends StatefulWidget {
  final List<TmdbSeason> seasons;
  final Future<TmdbSeasonDetail?> Function(int number, bool force) loader;
  const AndroidSeasonBrowser(
      {super.key, required this.seasons, required this.loader});
  @override
  State<AndroidSeasonBrowser> createState() => _AndroidSeasonBrowserState();
}

class _AndroidSeasonBrowserState extends State<AndroidSeasonBrowser> {
  int? selected;
  Future<TmdbSeasonDetail?>? data;
  @override
  void initState() {
    super.initState();
    if (widget.seasons.isNotEmpty) {
      choose(widget.seasons.first.number);
    }
  }

  void choose(int number, {bool force = false}) {
    setState(() {
      selected = number;
      data = widget.loader(number, force);
    });
  }

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
            'Seasons & Episodes (${widget.seasons.length} Seasons, ${widget.seasons.fold<int>(0, (sum, s) => sum + s.episodes)} Episodes)',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        SizedBox(
            height: 38,
            child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: widget.seasons.length,
                separatorBuilder: (context, i) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final s = widget.seasons[i];
                  return ChoiceChip(
                      label: Text(
                          '${s.name}${s.rating > 0 ? " ★ ${s.rating.toStringAsFixed(1)}" : ""}',
                          style: TextStyle(
                              fontSize: 12,
                              color: selected == s.number
                                  ? Colors.black
                                  : Colors.white70)),
                      selected: selected == s.number,
                      selectedColor: Colors.white,
                      backgroundColor: Colors.white.withValues(alpha: .06),
                      side: BorderSide(
                          color: selected == s.number
                              ? Colors.white
                              : Colors.white12),
                      onSelected: (_) => choose(s.number));
                })),
        const SizedBox(height: 10),
        FutureBuilder<TmdbSeasonDetail?>(
            future: data,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(
                        child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2))));
              }
              if (snapshot.data == null) {
                return TextButton(
                    onPressed: selected == null
                        ? null
                        : () => choose(selected!, force: true),
                    child: const Text('Could not load episodes · Retry'));
              }
              return AndroidEpisodeSection(detail: snapshot.data!);
            }),
      ]);
}

class AndroidEpisodeSection extends StatelessWidget {
  final TmdbSeasonDetail detail;
  const AndroidEpisodeSection({super.key, required this.detail});
  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
            width: double.infinity,
            padding: const EdgeInsets.all(11),
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .05),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: Colors.white10)),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                    child: Text(detail.name,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700))),
                if (detail.rating > 0)
                  Text('★ ${detail.rating.toStringAsFixed(1)} / 10',
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.bold))
              ]),
              if (detail.overview.isNotEmpty) ...[
                const SizedBox(height: 5),
                Text(detail.overview,
                    style: const TextStyle(
                        color: Colors.white60, fontSize: 11.5, height: 1.4))
              ],
            ])),
        for (final episode in detail.episodes)
          Card(
              margin: const EdgeInsets.only(bottom: 8),
              color: const Color(0xff1b1b24),
              child: ExpansionTile(
                tilePadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                title: Text('${episode.episodeNumber}. ${episode.name}',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
                subtitle: Text(
                    [
                      if (episode.airDate?.isNotEmpty ?? false)
                        episode.airDate!,
                      if (episode.runtimeMinutes > 0)
                        '${episode.runtimeMinutes} min',
                      if (episode.rating > 0)
                        '★ ${episode.rating.toStringAsFixed(1)}'
                    ].join(' · '),
                    style:
                        const TextStyle(color: Colors.white38, fontSize: 11)),
                children: [
                  Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (episode.stillPath != null)
                              SizedBox(
                                  height: 140,
                                  width: 250,
                                  child: ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: movieImage(episode.stillPath,
                                          backdrop: true))),
                            const SizedBox(height: 8),
                            SelectableText(
                                episode.overview.isEmpty
                                    ? 'No synopsis available.'
                                    : episode.overview,
                                style: const TextStyle(
                                    fontSize: 12,
                                    height: 1.4,
                                    color: Colors.white70)),
                          ]))
                ],
              )),
        if (detail.episodes.isEmpty)
          const Padding(
              padding: EdgeInsets.all(12),
              child: Text('No episode information available.',
                  style: TextStyle(color: Colors.white54, fontSize: 12))),
      ]);
}
