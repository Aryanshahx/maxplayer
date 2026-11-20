import 'package:flutter/material.dart';
import '../utils/app_language.dart';
import 'tmdb.dart';

Widget movieImage(String? path, {bool backdrop = false}) => path == null ||
        path.isEmpty
    ? const ColoredBox(
        color: Color(0xff1a1a26),
        child: Center(
            child: Icon(Icons.movie_outlined, color: Colors.white24, size: 42)))
    : Image.network(backdrop ? tmdbBackdropUrl(path) : tmdbPosterUrl(path),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stack) => const ColoredBox(
            color: Color(0xff1a1a26),
            child: Center(
                child:
                    Icon(Icons.broken_image_outlined, color: Colors.white24))));

class AndroidDiscoverPoster extends StatelessWidget {
  final TmdbMovie movie;
  final VoidCallback onTap;
  const AndroidDiscoverPoster(
      {super.key, required this.movie, required this.onTap});
  @override
  Widget build(BuildContext context) => Material(
      color: Colors.transparent,
      child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
                child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Stack(fit: StackFit.expand, children: [
                      movieImage(movie.posterPath),
                      if (movie.rating > 0)
                        Positioned(
                            left: 6,
                            bottom: 6,
                            child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: .6),
                                    borderRadius: BorderRadius.circular(5)),
                                child: Text('★ ${tmdbRatingText(movie.rating)}',
                                    style: const TextStyle(fontSize: 10)))),
                    ]))),
            const SizedBox(height: 6),
            SizedBox(
                height: 30,
                child: Text(movie.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11.5, height: 1.15))),
            const SizedBox(height: 2),
            SizedBox(
                height: 11,
                child: Text('${movie.year ?? ""}',
                    maxLines: 1,
                    style:
                        const TextStyle(color: Colors.white38, fontSize: 10))),
          ])));
}

class DiscoverShelf extends StatelessWidget {
  final String title;
  final List<TmdbMovie> movies;
  final ValueChanged<TmdbMovie> onOpen;
  final VoidCallback? onSeeAll;
  final bool ranked;
  const DiscoverShelf(
      {super.key,
      required this.title,
      required this.movies,
      required this.onOpen,
      this.onSeeAll,
      this.ranked = false});
  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
            padding: const EdgeInsets.fromLTRB(14, 20, 10, 10),
            child: Row(children: [
              Expanded(
                  child: Text(title,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800))),
              if (onSeeAll != null)
                TextButton(
                    onPressed: onSeeAll,
                    child: const Row(children: [
                      Text('SEE ALL',
                          style: TextStyle(
                              fontSize: 10,
                              letterSpacing: 1.4,
                              color: Colors.white54)),
                      Icon(Icons.chevron_right, size: 16, color: Colors.white54)
                    ])),
            ])),
        SizedBox(
            height: 254,
            child: Scrollbar(
                child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              itemCount: movies.length,
              separatorBuilder: (context, i) => const SizedBox(width: 10),
              itemBuilder: (context, i) => SizedBox(
                  width: ranked ? 175 : 138,
                  child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (ranked)
                          SizedBox(
                              width: 36,
                              child: Text('${i + 1}',
                                  style: const TextStyle(
                                      fontSize: 62,
                                      height: 1.3,
                                      color: Colors.white24,
                                      fontWeight: FontWeight.w900))),
                        Expanded(
                            child: AndroidDiscoverPoster(
                                movie: movies[i],
                                onTap: () => onOpen(movies[i]))),
                      ])),
            ))),
      ]);
}

class AndroidFeaturedMovies extends StatefulWidget {
  final List<TmdbMovie> movies;
  final ValueChanged<TmdbMovie> onOpen;
  const AndroidFeaturedMovies(
      {super.key, required this.movies, required this.onOpen});
  @override
  State<AndroidFeaturedMovies> createState() => _AndroidFeaturedMoviesState();
}

class _AndroidFeaturedMoviesState extends State<AndroidFeaturedMovies> {
  int page = 0;
  final pages = PageController();
  @override
  void dispose() {
    pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final movies = widget.movies.take(6).toList();
    return Column(children: [
      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        IconButton(
            tooltip: 'Previous featured title',
            onPressed: page > 0
                ? () => pages.previousPage(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOut)
                : null,
            icon: const Icon(Icons.chevron_left)),
        IconButton(
            tooltip: 'Next featured title',
            onPressed: page + 1 < movies.length
                ? () => pages.nextPage(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOut)
                : null,
            icon: const Icon(Icons.chevron_right)),
      ]),
      SizedBox(
          height: MediaQuery.sizeOf(context).width > 900 ? 420 : 310,
          child: PageView.builder(
              controller: pages,
              itemCount: movies.length,
              onPageChanged: (value) => setState(() => page = value),
              itemBuilder: (context, i) {
                final m = movies[i];
                return Stack(fit: StackFit.expand, children: [
                  movieImage(m.backdropPath ?? m.posterPath,
                      backdrop: m.backdropPath != null),
                  const DecoratedBox(
                      decoration: BoxDecoration(
                          gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                        Color(0x550a0a10),
                        Color(0x990a0a10),
                        Color(0xff0a0a10)
                      ]))),
                  Positioned(
                      left: 24,
                      right: 24,
                      bottom: 26,
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                m.kind == 'tv'
                                    ? 'FEATURED SERIES'
                                    : 'FEATURED MOVIE',
                                style: const TextStyle(
                                    color: Colors.white54,
                                    fontSize: 10,
                                    letterSpacing: 2)),
                            const SizedBox(height: 8),
                            Text(m.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 30, fontWeight: FontWeight.w900)),
                            const SizedBox(height: 8),
                            Text(
                                '${m.year ?? ""} · ★ ${tmdbRatingText(m.rating)}',
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 12)),
                            const SizedBox(height: 10),
                            ConstrainedBox(
                                constraints:
                                    const BoxConstraints(maxWidth: 650),
                                child: Text(m.overview,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        color: Colors.white54, fontSize: 12))),
                            const SizedBox(height: 14),
                            FilledButton.icon(
                                onPressed: () => widget.onOpen(m),
                                icon: const Icon(Icons.info_outline, size: 18),
                                label: const LText('Details')),
                          ])),
                ]);
              })),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        for (var i = 0; i < movies.length; i++)
          Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              height: 4,
              width: page == i ? 16 : 5,
              decoration: BoxDecoration(
                  color: page == i ? Colors.white : Colors.white24,
                  borderRadius: BorderRadius.circular(3)))
      ]),
    ]);
  }
}
