import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'config.dart';
import 'tmdb.dart';

const tmdbNotice =
    'This product uses the TMDB API but is not endorsed or certified by TMDB. Ratings via TMDB. Provider availability via TMDB / JustWatch (India).';
Future<void> openDiscoverLink(BuildContext context, Uri uri) async {
  try {
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw const FormatException('No application could open this link.');
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not open link. Check your default browser.')));
    }
  }
}

Widget poster(String? path, {double? width, double? height}) => path == null
    ? SizedBox(
        width: width,
        height: height,
        child: const Center(child: Icon(Icons.movie_outlined, size: 40)))
    : Image.network(tmdbPosterUrl(path),
        width: width,
        height: height,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stack) => SizedBox(
            width: width,
            height: height,
            child: const Center(child: Icon(Icons.broken_image_outlined))));

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});
  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  final client = TmdbClient();
  final search = TextEditingController();
  DiscoverFilter filter = kDiscoverFilters.first;
  List<TmdbMovie> movies = [];
  bool loading = false;
  String? error;
  int page = 1, totalPages = 1, requestId = 0;
  @override
  void initState() {
    super.initState();
    boot();
  }

  Future<void> boot() async {
    try {
      final dir = await getApplicationCacheDirectory();
      client.cacheDir =
          await Directory('${dir.path}/discover').create(recursive: true);
    } catch (_) {/* Network browsing remains usable without disk cache. */}
    if (mounted) {
      await load();
    }
  }

  Future<void> load({int next = 1, bool force = false}) async {
    final id = ++requestId;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = search.text.trim().isEmpty
          ? await client.browse(filter, page: next, force: force)
          : await client.searchMulti(search.text.trim(),
              page: next, force: force);
      if (!mounted || id != requestId) {
        return;
      }
      setState(() {
        movies = result.items;
        page = result.page;
        totalPages = result.totalPages;
        if (movies.isEmpty) {
          error =
              'No results. Check your query, connection and TMDB token, then retry. Cached results may be available after a previous successful visit.';
        }
      });
    } catch (_) {
      if (mounted && id == requestId) {
        setState(() => error =
            'Could not load Discover. Check your connection and retry.');
      }
    } finally {
      if (mounted && id == requestId) {
        setState(() => loading = false);
      }
    }
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Discover movies'), actions: [
          IconButton(
              tooltip: 'Refresh catalogue',
              onPressed: () => load(force: true),
              icon: const Icon(Icons.refresh))
        ]),
        body: AppConfig.tmdbToken.isEmpty
            ? const Center(
                child: Padding(
                    padding: EdgeInsets.all(30),
                    child: SelectableText(
                        'Discover needs the TMDB_API_KEY repository secret. Add your TMDB API read-access token in GitHub Settings → Secrets and variables → Actions, then build a new Windows artifact. No token is embedded in source.')))
            : Column(children: [
                Padding(
                    padding: const EdgeInsets.all(16),
                    child: TextField(
                        controller: search,
                        decoration: InputDecoration(
                            hintText: 'Search movies and series',
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon: IconButton(
                                onPressed: () => load(),
                                icon: const Icon(Icons.arrow_forward))),
                        onSubmitted: (_) => load())),
                SizedBox(
                    height: 48,
                    child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        children: [
                          for (final f in kAllFilters)
                            Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  label: Text(
                                      f.tv ? 'Series · ${f.label}' : f.label),
                                  selected: f.key == filter.key &&
                                      search.text.trim().isEmpty,
                                  onSelected: (_) {
                                    search.clear();
                                    setState(() => filter = f);
                                    load();
                                  },
                                )),
                        ])),
                if (loading) const LinearProgressIndicator(),
                if (error != null)
                  Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(children: [
                        Expanded(child: Text(error!)),
                        TextButton(
                            onPressed: () => load(force: true),
                            child: const Text('Retry'))
                      ])),
                Expanded(
                    child: GridView.builder(
                        padding: const EdgeInsets.all(16),
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 210,
                                childAspectRatio: .57,
                                crossAxisSpacing: 14,
                                mainAxisSpacing: 14),
                        itemCount: movies.length,
                        itemBuilder: (context, i) =>
                            movieCard(context, client, movies[i]))),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  TextButton(
                      onPressed: page > 1 && !loading
                          ? () => load(next: page - 1)
                          : null,
                      child: const Text('Previous')),
                  Text('Page $page / $totalPages'),
                  TextButton(
                      onPressed: page < totalPages && !loading
                          ? () => load(next: page + 1)
                          : null,
                      child: const Text('Next')),
                ]),
                const Padding(
                    padding: EdgeInsets.all(8),
                    child: Text(tmdbNotice,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 10, color: Colors.grey))),
              ]),
      );
}

Widget movieCard(BuildContext context, TmdbClient client, TmdbMovie movie) =>
    Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                  builder: (_) =>
                      DiscoverDetail(client: client, movie: movie))),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
                child: SizedBox(
                    width: double.infinity, child: poster(movie.posterPath))),
            Padding(
                padding: const EdgeInsets.fromLTRB(10, 9, 10, 3),
                child: Text(movie.title,
                    maxLines: 2, overflow: TextOverflow.ellipsis)),
            Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                child: Text(
                    '${movie.year ?? "—"} · ${movie.kind == "tv" ? "Series" : "Movie"} · ★ ${tmdbRatingText(movie.rating)}',
                    style: const TextStyle(fontSize: 11, color: Colors.grey))),
          ]),
        ));

class DiscoverDetail extends StatefulWidget {
  final TmdbClient client;
  final TmdbMovie movie;
  const DiscoverDetail({super.key, required this.client, required this.movie});
  @override
  State<DiscoverDetail> createState() => _DiscoverDetailState();
}

class _DiscoverDetailState extends State<DiscoverDetail> {
  late Future<TmdbFull?> detail;
  @override
  void initState() {
    super.initState();
    detail = widget.client.fullDetail(widget.movie.id, kind: widget.movie.kind);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.movie.title)),
        body: FutureBuilder<TmdbFull?>(
            future: detail,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              final full = snapshot.data;
              if (full == null) {
                return Center(
                    child: FilledButton(
                        onPressed: () => setState(() => detail = widget.client
                            .fullDetail(widget.movie.id,
                                kind: widget.movie.kind, force: true)),
                        child: const Text('Could not load details · Retry')));
              }
              final m = full.movie;
              final e = full.extras;
              return ListView(padding: const EdgeInsets.all(24), children: [
                Wrap(spacing: 24, runSpacing: 18, children: [
                  SizedBox(
                      width: 210,
                      height: 310,
                      child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: poster(m.posterPath))),
                  SizedBox(
                      width: 620,
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(m.title,
                                style: const TextStyle(
                                    fontSize: 30, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 12),
                            Text(
                                '${m.year ?? "—"} · ★ ${tmdbRatingText(m.rating)} via TMDB · ${e.runtimeMinutes} min · ${e.certification}'),
                            const SizedBox(height: 12),
                            Text(e.genres.join(' · ')),
                            const SizedBox(height: 12),
                            Text(e.tagline,
                                style: const TextStyle(
                                    fontStyle: FontStyle.italic,
                                    color: Colors.grey)),
                            const SizedBox(height: 12),
                            SelectableText(m.overview),
                            const SizedBox(height: 18),
                            if (m.trailerKey != null)
                              FilledButton.icon(
                                  onPressed: () => openDiscoverLink(
                                      context,
                                      Uri.https('www.youtube.com', '/watch',
                                          {'v': m.trailerKey!})),
                                  icon: const Icon(Icons.play_arrow),
                                  label:
                                      const Text('Watch trailer on YouTube ↗')),
                            for (final trailer in m.trailerVariants)
                              TextButton(
                                  onPressed: () => openDiscoverLink(
                                      context,
                                      Uri.https('www.youtube.com', '/watch',
                                          {'v': trailer.key})),
                                  child: Text('Trailer · ${trailer.name} ↗')),
                            TextButton(
                                onPressed: () => openDiscoverLink(
                                    context,
                                    Uri.https(
                                        'www.themoviedb.org',
                                        '/${m.kind}/${m.id}/watch',
                                        {'locale': 'IN'})),
                                child: const Text(
                                    'Where to watch · Open provider listings ↗')),
                            const Text(
                                'Discover provides metadata and trailers, not full-length films. Provider subscriptions may be required.',
                                style: TextStyle(
                                    color: Colors.grey, fontSize: 12)),
                          ])),
                ]),
                const SizedBox(height: 24),
                Text(
                    'Director / creator: ${e.director}\nStatus: ${e.status}\nRelease: ${e.releaseDate}\nLanguages: ${e.spokenLanguages.join(", ")}\nProduction: ${e.companies.join(", ")}'),
                const SizedBox(height: 20),
                const Text('Cast',
                    style:
                        TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Wrap(spacing: 12, runSpacing: 12, children: [
                  for (final member in e.castMembers.take(24))
                    SizedBox(
                        width: 115,
                        child: Column(children: [
                          SizedBox(
                              height: 145,
                              width: 105,
                              child: poster(member.profilePath)),
                          const SizedBox(height: 6),
                          Text(member.name),
                          Text(member.character,
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.grey)),
                        ]))
                ]),
                const SizedBox(height: 20),
                if (!full.watch.isEmpty)
                  SelectableText(
                      'Where to watch (India)\nStream: ${full.watch.stream.join(", ")}\nRent: ${full.watch.rent.join(", ")}\nBuy: ${full.watch.buy.join(", ")}\nAvailability via TMDB / JustWatch; check providers for current offers.'),
                for (final season in full.seasons)
                  ListTile(
                      title: Text(season.name),
                      subtitle: Text('${season.episodes} episodes'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                              builder: (_) => SeasonScreen(
                                  client: widget.client,
                                  tvId: m.id,
                                  season: season)))),
                if (full.screenshots.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  const Text('Images'),
                  SizedBox(
                      height: 190,
                      child:
                          ListView(scrollDirection: Axis.horizontal, children: [
                        for (final path in full.screenshots.take(12))
                          Padding(
                              padding: const EdgeInsets.all(6),
                              child: Image.network(
                                  'https://image.tmdb.org/t/p/w500$path',
                                  errorBuilder: (context, error, stack) =>
                                      const Icon(Icons.broken_image_outlined)))
                      ]))
                ],
                if (full.reviews.isNotEmpty)
                  const Padding(
                      padding: EdgeInsets.only(top: 20),
                      child: Text('TMDB user reviews',
                          style: TextStyle(fontSize: 21))),
                for (final review in full.reviews.take(5))
                  ExpansionTile(
                      title: Text(review.author),
                      subtitle: Text(review.rating == null
                          ? 'No score'
                          : '★ ${review.rating}'),
                      children: [
                        Padding(
                            padding: const EdgeInsets.all(16),
                            child: SelectableText(review.text))
                      ]),
                const SizedBox(height: 24),
                const Text('Related titles', style: TextStyle(fontSize: 21)),
                SizedBox(
                    height: 320,
                    child: FutureBuilder<List<TmdbMovie>>(
                        future: widget.client.similar(m.id, kind: m.kind),
                        builder: (context, related) => ListView(
                                scrollDirection: Axis.horizontal,
                                children: [
                                  for (final title
                                      in related.data ?? <TmdbMovie>[])
                                    SizedBox(
                                        width: 180,
                                        child: movieCard(
                                            context, widget.client, title))
                                ]))),
                const Text(tmdbNotice,
                    style: TextStyle(color: Colors.grey, fontSize: 11)),
              ]);
            }),
      );
}

class SeasonScreen extends StatefulWidget {
  final TmdbClient client;
  final int tvId;
  final TmdbSeason season;
  const SeasonScreen(
      {super.key,
      required this.client,
      required this.tvId,
      required this.season});
  @override
  State<SeasonScreen> createState() => _SeasonScreenState();
}

class _SeasonScreenState extends State<SeasonScreen> {
  late Future<TmdbSeasonDetail?> data;
  @override
  void initState() {
    super.initState();
    data = widget.client.seasonDetail(widget.tvId, widget.season.number);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: Text(widget.season.name)),
      body: FutureBuilder<TmdbSeasonDetail?>(
        future: data,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.data == null) {
            return Center(
                child: TextButton(
                    onPressed: () => setState(() => data = widget.client
                        .seasonDetail(widget.tvId, widget.season.number,
                            force: true)),
                    child: const Text('Could not load episodes · Retry')));
          }
          return ListView(children: [
            for (final episode in snapshot.data!.episodes)
              ExpansionTile(
                title: Text('${episode.episodeNumber}. ${episode.name}'),
                subtitle: Text(
                    '${episode.airDate ?? ""} · ${episode.runtimeMinutes} min · ★ ${episode.rating.toStringAsFixed(1)}'),
                children: [
                  Padding(
                      padding: const EdgeInsets.all(18),
                      child: SelectableText(episode.overview))
                ],
              )
          ]);
        },
      ));
}

class DiscoverHomeBanner extends StatefulWidget {
  const DiscoverHomeBanner({super.key});
  @override
  State<DiscoverHomeBanner> createState() => _DiscoverHomeBannerState();
}

class _DiscoverHomeBannerState extends State<DiscoverHomeBanner> {
  List<TmdbMovie> movies = [];
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    if (AppConfig.tmdbToken.isEmpty) {
      return;
    }
    try {
      final client = TmdbClient();
      final dir = await getApplicationCacheDirectory();
      client.cacheDir =
          await Directory('${dir.path}/discover').create(recursive: true);
      final result = await client.browse(kDiscoverFilters.first);
      if (mounted) {
        setState(() => movies = result.items.take(14).toList());
      }
    } catch (_) {/* The gradient remains as a fallback. */}
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
          height: 118,
          child: Stack(fit: StackFit.expand, children: [
            const DecoratedBox(
                decoration: BoxDecoration(
                    gradient: LinearGradient(
                        colors: [Color(0xff241d3d), Color(0xff16222e)]))),
            if (movies.isNotEmpty)
              ListView(scrollDirection: Axis.horizontal, children: [
                for (final m in movies)
                  SizedBox(width: 78, child: poster(m.posterPath))
              ]),
            const IgnorePointer(
                child: DecoratedBox(
                    decoration: BoxDecoration(
                        gradient: LinearGradient(
                            colors: [Color(0xe6000000), Color(0x59000000)])))),
            Material(
                color: Colors.transparent,
                child: InkWell(
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                            builder: (_) => const DiscoverScreen())),
                    child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 20),
                        child: Row(children: [
                          Expanded(
                              child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                Text('Discover movies',
                                    style: TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold)),
                                SizedBox(height: 6),
                                Text('Latest posters, ratings & trailers',
                                    style: TextStyle(
                                        color: Colors.white70, fontSize: 12))
                              ])),
                          Icon(Icons.arrow_forward),
                        ])))),
          ])));
}
