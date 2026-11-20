import 'package:flutter/material.dart';
import 'android_browse.dart';
import 'catalog_pager.dart';
import 'tmdb.dart';

class DiscoverCategoryScreen extends StatefulWidget {
  final DiscoverFilter filter;
  final TmdbClient client;
  final ValueChanged<TmdbMovie> onOpen;
  const DiscoverCategoryScreen(
      {super.key,
      required this.filter,
      required this.client,
      required this.onOpen});
  @override
  State<DiscoverCategoryScreen> createState() => _DiscoverCategoryScreenState();
}

class _DiscoverCategoryScreenState extends State<DiscoverCategoryScreen> {
  late final pager = CatalogPager((page, force) =>
      widget.client.browse(widget.filter, page: page, force: force));
  final scroll = ScrollController();
  @override
  void initState() {
    super.initState();
    scroll.addListener(onScroll);
    pager.load();
  }

  void onScroll() {
    if (scroll.hasClients &&
        scroll.position.extentAfter < 420 &&
        !pager.failed) {
      pager.load();
    }
  }

  @override
  void dispose() {
    scroll.dispose();
    pager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      backgroundColor: const Color(0xff0a0a10),
      body: SafeArea(
          child: Column(children: [
        Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 14, 10),
            child: Row(children: [
              const BackButton(),
              const SizedBox(width: 2),
              Container(
                  width: 11,
                  height: 11,
                  decoration: const BoxDecoration(
                      color: Color(0xffa78bfa), shape: BoxShape.circle)),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(
                      widget.filter.tv
                          ? '${widget.filter.label} • Series'
                          : widget.filter.label,
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w800))),
              IconButton(
                  tooltip: 'Refresh category',
                  onPressed: () => pager.load(refresh: true, force: true),
                  icon: const Icon(Icons.refresh_rounded))
            ])),
        Expanded(
            child: AnimatedBuilder(
                animation: pager,
                builder: (context, _) => RefreshIndicator(
                    onRefresh: () => pager.load(refresh: true, force: true),
                    child: CustomScrollView(
                        controller: scroll,
                        physics: const AlwaysScrollableScrollPhysics(),
                        slivers: [
                          if (pager.items.isEmpty && !pager.loading)
                            SliverFillRemaining(
                                hasScrollBody: false,
                                child: Center(
                                    child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                      const Icon(Icons.movie_outlined,
                                          size: 42, color: Colors.white24),
                                      const SizedBox(height: 12),
                                      const Text(
                                          'Could not load this category.',
                                          style:
                                              TextStyle(color: Colors.white54)),
                                      TextButton(
                                          onPressed: () =>
                                              pager.load(force: true),
                                          child: const Text('Retry'))
                                    ]))),
                          SliverPadding(
                              padding: const EdgeInsets.fromLTRB(14, 4, 14, 16),
                              sliver: SliverGrid(
                                  gridDelegate:
                                      const SliverGridDelegateWithMaxCrossAxisExtent(
                                          maxCrossAxisExtent: 180,
                                          childAspectRatio: .55,
                                          mainAxisSpacing: 16,
                                          crossAxisSpacing: 12),
                                  delegate: SliverChildBuilderDelegate(
                                      (context, i) => AndroidDiscoverPoster(
                                          movie: pager.items[i],
                                          onTap: () =>
                                              widget.onOpen(pager.items[i])),
                                      childCount: pager.items.length))),
                          SliverToBoxAdapter(
                              child: Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: Center(
                                      child: pager.loading
                                          ? const SizedBox(
                                              width: 24,
                                              height: 24,
                                              child: CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  color: Colors.white))
                                          : pager.items.isEmpty
                                              ? const SizedBox.shrink()
                                              : pager.hasMore
                                                  ? TextButton(
                                                      onPressed: () =>
                                                          pager.load(
                                                              force:
                                                                  pager.failed),
                                                      child: Text(pager.failed
                                                          ? 'Could not load more · Retry'
                                                          : 'Load more'))
                                                  : const Text(
                                                      'You’ve reached the end',
                                                      style: TextStyle(
                                                          color: Colors.white38,
                                                          fontSize: 12))))),
                        ])))),
      ])));
}
