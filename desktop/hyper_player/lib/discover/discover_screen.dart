import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'config.dart';
import 'tmdb.dart';
import 'android_browse.dart';
import 'android_details.dart';
import 'cine_ui.dart';
import 'category_screen.dart';
import 'local_movie_match.dart';

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
  final List<String> localSources;
  final ValueChanged<String>? onPlayLocal;
  const DiscoverScreen(
      {super.key, this.localSources = const [], this.onPlayLocal});
  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  final client = TmdbClient();
  final search = TextEditingController();
  final searchFocus = FocusNode();
  Timer? debounce;
  final shelves = <String, List<TmdbMovie>>{};
  bool shelvesLoading = false;
  DiscoverFilter filter = kDiscoverFilters.first;
  List<TmdbMovie> movies = [];
  bool loading = false;
  String? error;
  int page = 1, totalPages = 1, requestId = 0;
  @override
  void initState() {
    super.initState();
    searchFocus.addListener(() {
      if (mounted) {
        setState(() {});
      }
    });
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
      if (mounted) {
        unawaited(loadShelves());
      }
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
    debounce?.cancel();
    searchFocus.dispose();
    search.dispose();
    super.dispose();
  }

  void openMovie(TmdbMovie movie) {
    Navigator.push<void>(
        context,
        MaterialPageRoute(
            builder: (_) => DiscoverDetail(
                client: client,
                movie: movie,
                localSources: widget.localSources,
                onPlayLocal: widget.onPlayLocal)));
  }

  Future<void> loadShelves({bool force = false}) async {
    if (shelvesLoading || AppConfig.tmdbToken.isEmpty) {
      return;
    }
    setState(() => shelvesLoading = true);
    final chosen = kAllFilters.toList();
    // Bounded request fan-out: Android includes every movie/series rail, not
    // only four substituted categories. Keep source order independent of IO.
    for (var start = 0; start < chosen.length && mounted; start += 3) {
      await Future.wait(chosen.skip(start).take(3).map((f) async {
        try {
          final result = await client.browse(f, force: force);
          if (mounted) setState(() => shelves[f.key] = result.items);
        } catch (_) {
          if (mounted) setState(() => shelves[f.key] = []);
        }
      }));
    }
    if (mounted) {
      setState(() => shelvesLoading = false);
    }
  }

  void openCategory(DiscoverFilter value) {
    Navigator.push<void>(
        context,
        MaterialPageRoute(
            builder: (_) => DiscoverCategoryScreen(
                filter: value, client: client, onOpen: openMovie)));
  }

  List<TmdbMovie> topTen() {
    final seen = <String>{};
    return [...?shelves['trending'], ...movies]
        .where((m) =>
            (m.posterPath?.isNotEmpty ?? false) &&
            seen.add('${m.kind}:${m.id}'))
        .take(10)
        .toList();
  }

  void selectFilter(DiscoverFilter value) {
    search.clear();
    searchFocus.unfocus();
    setState(() => filter = value);
    load();
  }

  List<Widget> buildAllRails() {
    final seen = <String>{};
    final rows = <Widget>[];
    for (final f in kAllFilters) {
      if (!shelves.containsKey(f.key)) continue;
      final raw = shelves[f.key]!;
      final items = raw
          .where((m) =>
              (m.posterPath?.isNotEmpty ?? false) &&
              seen.add('${m.kind}:${m.id}'))
          .toList();
      final title = f.tv ? '${f.label} • Series' : f.label;
      if (raw.isEmpty) {
        rows.add(Padding(
            padding: const EdgeInsets.all(14),
            child: OutlinedButton(
                onPressed: () => openCategory(f),
                child: Text('$title · Open category / Retry'))));
      } else if (items.isNotEmpty) {
        rows.add(DiscoverShelf(
            title: title,
            movies: items,
            onOpen: openMovie,
            onSeeAll: () => openCategory(f)));
      }
    }
    return rows;
  }

  Widget socialButton(String label, IconData icon, String url) => Expanded(
          child: OutlinedButton.icon(
        onPressed: () => openDiscoverLink(context, Uri.parse(url)),
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            side: const BorderSide(color: Colors.white12),
            backgroundColor: Colors.white.withValues(alpha: .03)),
      ));
  @override
  Widget build(BuildContext context) {
    final home = search.text.trim().isEmpty &&
        filter.key == 'trending' &&
        page == 1 &&
        !searchFocus.hasFocus;
    final hot = searchFocus.hasFocus && search.text.trim().isEmpty;
    return Scaffold(
        backgroundColor: const Color(0xff0a0a10),
        body: SafeArea(
            child: Column(children: [
          Container(
              padding: const EdgeInsets.fromLTRB(6, 8, 14, 8),
              color: const Color(0xff0a0a10),
              child: Row(children: [
                const BackButton(),
                Expanded(
                    child: Container(
                        height: 44,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: .07),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                                color: search.text.isEmpty
                                    ? Colors.white10
                                    : Colors.white60)),
                        child: Row(children: [
                          const Icon(Icons.search,
                              size: 19, color: Colors.white54),
                          const SizedBox(width: 9),
                          Expanded(
                              child: TextField(
                                  controller: search,
                                  focusNode: searchFocus,
                                  style: const TextStyle(fontSize: 14.5),
                                  onChanged: (_) {
                                    debounce?.cancel();
                                    setState(() {});
                                    debounce = Timer(
                                        const Duration(milliseconds: 350),
                                        () => load());
                                  },
                                  onSubmitted: (_) {
                                    debounce?.cancel();
                                    searchFocus.unfocus();
                                    load();
                                  },
                                  decoration: const InputDecoration(
                                      hintText: 'Search movies, series…',
                                      hintStyle: TextStyle(
                                          color: Colors.white30, fontSize: 14),
                                      border: InputBorder.none,
                                      isDense: true))),
                          if (search.text.isNotEmpty)
                            IconButton(
                                tooltip: 'Clear search',
                                icon: const Icon(Icons.close_rounded, size: 18),
                                onPressed: () {
                                  search.clear();
                                  searchFocus.unfocus();
                                  selectFilter(kDiscoverFilters.first);
                                }),
                        ]))),
                const Tooltip(
                    message:
                        'Voice search is not implemented in this Windows build',
                    child: IconButton(
                        onPressed: null,
                        icon: Icon(Icons.mic_none_rounded, size: 21))),
                Tooltip(
                    message:
                        'AI Suggestor is not implemented in this Windows build',
                    child: Opacity(
                        opacity: .45,
                        child: Container(
                            height: 40,
                            padding: const EdgeInsets.symmetric(horizontal: 13),
                            decoration: BoxDecoration(
                                gradient: const LinearGradient(colors: [
                                  Color(0xff7b61ff),
                                  Color(0xffe553b3)
                                ]),
                                borderRadius: BorderRadius.circular(22)),
                            child: const Row(children: [
                              Icon(Icons.auto_awesome, size: 16),
                              SizedBox(width: 6),
                              Text('AI',
                                  style: TextStyle(fontWeight: FontWeight.w800))
                            ])))),
                IconButton(
                    tooltip: 'Refresh catalogue',
                    onPressed: loading
                        ? null
                        : () {
                            load(force: true);
                            loadShelves(force: true);
                          },
                    icon: const Icon(Icons.refresh, size: 20)),
              ])),
          if (AppConfig.tmdbToken.isEmpty)
            const Expanded(
                child: Center(
                    child: Padding(
                        padding: EdgeInsets.all(28),
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.vpn_key_off,
                              color: Colors.white24, size: 46),
                          SizedBox(height: 14),
                          Text('TMDB key missing',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold)),
                          SizedBox(height: 8),
                          Text(
                              'Set TMDB_API_KEY in GitHub Actions secrets and rebuild Windows.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: Colors.white38, fontSize: 12.5))
                        ]))))
          else ...[
            if (!hot)
              SizedBox(
                  height: 46,
                  child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      children: [
                        for (final f in kAllFilters)
                          Padding(
                              padding: const EdgeInsets.only(right: 7),
                              child: ChoiceChip(
                                  label: Text(
                                      f.tv ? 'Series · ${f.label}' : f.label,
                                      style: const TextStyle(fontSize: 12)),
                                  selected: f.key == filter.key &&
                                      search.text.isEmpty,
                                  onSelected: (_) => selectFilter(f)))
                      ])),
            if (loading)
              const LinearProgressIndicator(minHeight: 2, color: Colors.white),
            if (error != null)
              Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(children: [
                    Expanded(
                        child: Text(error!,
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 12))),
                    TextButton(
                        onPressed: () => load(force: true),
                        child: const Text('Retry'))
                  ])),
            Expanded(
                child: hot
                    ? ListView(padding: const EdgeInsets.all(14), children: [
                        const ListTile(
                            leading: Icon(Icons.local_fire_department_rounded,
                                color: Colors.deepOrangeAccent),
                            title: Text('Hot searches',
                                style: TextStyle(fontWeight: FontWeight.w800))),
                        for (final m in movies.take(12))
                          ListTile(
                              leading: const Icon(Icons.trending_up,
                                  color: Colors.white38),
                              title: Text(m.title),
                              onTap: () {
                                search.text = m.title;
                                searchFocus.unfocus();
                                load();
                              }),
                      ])
                    : home
                        ? ListView(children: [
                            if (movies.isNotEmpty)
                              CineFeaturedHero(
                                  items: movies.take(8).toList(),
                                  onTap: openMovie,
                                  onOpen: openMovie),
                            if (movies.isNotEmpty)
                              const Padding(
                                  padding: EdgeInsets.only(top: 2),
                                  child: CineTicker()),
                            const Padding(
                                padding: EdgeInsets.fromLTRB(12, 10, 12, 0),
                                child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(child: CineInstagramCard()),
                                      SizedBox(width: 8),
                                      Expanded(child: CineTelegramCard())
                                    ])),
                            if (topTen().isNotEmpty)
                              CineTopTen(items: topTen(), onTap: openMovie),
                            ...buildAllRails(),
                            if (shelvesLoading)
                              const Padding(
                                  padding: EdgeInsets.all(20),
                                  child: Center(
                                      child: CircularProgressIndicator())),
                            const Padding(
                                padding: EdgeInsets.all(18),
                                child: Text(
                                    'Top 10 is the first ten items from TMDB’s weekly trending response, not a Hyper Player viewing chart.',
                                    style: TextStyle(
                                        color: Colors.white38, fontSize: 10))),
                          ])
                        : GridView.builder(
                            padding: const EdgeInsets.all(14),
                            gridDelegate:
                                const SliverGridDelegateWithMaxCrossAxisExtent(
                                    maxCrossAxisExtent: 180,
                                    childAspectRatio: .55,
                                    crossAxisSpacing: 12,
                                    mainAxisSpacing: 16),
                            itemCount: movies.length,
                            itemBuilder: (context, i) => AndroidDiscoverPoster(
                                movie: movies[i],
                                onTap: () => openMovie(movies[i])))),
            if (!home && !hot)
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                TextButton(
                    onPressed: page > 1 && !loading
                        ? () => load(next: page - 1)
                        : null,
                    child: const Text('Previous')),
                Text('Page $page / $totalPages',
                    style: const TextStyle(fontSize: 12)),
                TextButton(
                    onPressed: page < totalPages && !loading
                        ? () => load(next: page + 1)
                        : null,
                    child: const Text('Next')),
              ]),
          ],
          const Padding(
              padding: EdgeInsets.all(8),
              child: Text(tmdbNotice,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 10, color: Colors.white38))),
        ])));
  }
}

Widget movieCard(BuildContext context, TmdbClient client, TmdbMovie movie) =>
    AndroidDiscoverPoster(
        movie: movie,
        onTap: () => Navigator.push<void>(
            context,
            MaterialPageRoute(
                builder: (_) => DiscoverDetail(
                    client: client,
                    movie: movie,
                    localSources: const [],
                    onPlayLocal: null))));

class DiscoverDetail extends StatefulWidget {
  final TmdbClient client;
  final TmdbMovie movie;
  final List<String> localSources;
  final ValueChanged<String>? onPlayLocal;
  const DiscoverDetail(
      {super.key,
      required this.client,
      required this.movie,
      this.localSources = const [],
      this.onPlayLocal});
  @override
  State<DiscoverDetail> createState() => _DiscoverDetailState();
}

class _DiscoverDetailState extends State<DiscoverDetail> {
  late Future<TmdbFull?> detail;
  late Future<List<TmdbMovie>> related;
  @override
  void initState() {
    super.initState();
    detail = widget.client.fullDetail(widget.movie.id, kind: widget.movie.kind);
    related = widget.client.similar(widget.movie.id, kind: widget.movie.kind);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xff14141c),
        body: Stack(children: [
          Positioned.fill(
              child: FutureBuilder<TmdbFull?>(
                  future: detail,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final full = snapshot.data;
                    if (full == null) {
                      return Center(
                          child: TextButton(
                              onPressed: () => setState(() => detail =
                                  widget.client.fullDetail(widget.movie.id,
                                      kind: widget.movie.kind, force: true)),
                              child: const Text(
                                  'Could not load details · Retry')));
                    }
                    final m = full.movie;
                    return SingleChildScrollView(
                        padding: EdgeInsets.only(
                            top: MediaQuery.paddingOf(context).top + 56),
                        child: Center(
                            child: ConstrainedBox(
                                constraints:
                                    const BoxConstraints(maxWidth: 1200),
                                child: Column(children: [
                                  AndroidMovieDetails(
                                    full: full,
                                    localSource: findLocalMovieSource(
                                        m.title, m.year, widget.localSources),
                                    onPlayLocal: widget.onPlayLocal,
                                    onTrailer: (key) => openDiscoverLink(
                                        context,
                                        Uri.https('www.youtube.com', '/watch',
                                            {'v': key})),
                                    onWatch: () => openDiscoverLink(
                                        context,
                                        Uri.https(
                                            'www.themoviedb.org',
                                            '/${m.kind}/${m.id}/watch',
                                            {'locale': 'IN'})),
                                    seasons: full.seasons.isEmpty
                                        ? null
                                        : AndroidSeasonBrowser(
                                            seasons: full.seasons,
                                            loader: (number, force) => widget
                                                .client
                                                .seasonDetail(m.id, number,
                                                    force: force)),
                                    related: FutureBuilder<List<TmdbMovie>>(
                                        future: related,
                                        builder: (context, results) {
                                          if (results.connectionState !=
                                              ConnectionState.done) {
                                            return const Padding(
                                                padding: EdgeInsets.all(16),
                                                child: LinearProgressIndicator(
                                                    minHeight: 2));
                                          }
                                          if ((results.data ?? []).isEmpty) {
                                            return const SizedBox.shrink();
                                          }
                                          return DiscoverShelf(
                                              title: 'Related titles',
                                              movies: results.data!,
                                              onOpen: (movie) => Navigator.push<
                                                      void>(
                                                  context,
                                                  MaterialPageRoute(
                                                      builder: (_) => DiscoverDetail(
                                                          client: widget.client,
                                                          movie: movie,
                                                          localSources: widget
                                                              .localSources,
                                                          onPlayLocal: widget
                                                              .onPlayLocal))));
                                        }),
                                  ),
                                  const Padding(
                                      padding:
                                          EdgeInsets.fromLTRB(16, 0, 16, 24),
                                      child: Text(tmdbNotice,
                                          style: TextStyle(
                                              color: Colors.white38,
                                              fontSize: 10))),
                                ]))));
                  })),
          Positioned(
              top: MediaQuery.paddingOf(context).top + 10,
              left: 12,
              child: Tooltip(
                  message: 'Back',
                  child: Material(
                    color: Colors.black.withValues(alpha: .45),
                    shape: const CircleBorder(),
                    child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => Navigator.maybePop(context),
                        child: const Padding(
                            padding: EdgeInsets.all(10),
                            child: Icon(Icons.arrow_back_ios_new_rounded,
                                color: Colors.white, size: 18))),
                  ))),
        ]),
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
          return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: AndroidEpisodeSection(detail: snapshot.data!));
        },
      ));
}

class DiscoverHomeBanner extends StatefulWidget {
  final List<String> localSources;
  final ValueChanged<String>? onPlayLocal;
  const DiscoverHomeBanner(
      {super.key, this.localSources = const [], this.onPlayLocal});
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
                            builder: (_) => DiscoverScreen(
                                localSources: widget.localSources,
                                onPlayLocal: widget.onPlayLocal))),
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
