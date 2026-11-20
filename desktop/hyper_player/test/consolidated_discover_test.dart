import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_player/discover/catalog_pager.dart';
import 'package:hyper_player/discover/local_movie_match.dart';
import 'package:hyper_player/discover/cine_ui.dart';
import 'package:hyper_player/discover/category_screen.dart';
import 'package:hyper_player/discover/tmdb.dart';

const movie = TmdbMovie(id: 1, title: 'Dune', year: 2021, rating: 8);

class FixtureCategoryClient extends TmdbClient {
  @override
  Future<TmdbPage> browse(DiscoverFilter filter,
          {int page = 1, bool force = false}) async =>
      const TmdbPage(items: [movie], page: 1, totalPages: 1);
}

void main() {
  test('Category paging appends and deduplicates by kind plus id', () async {
    final pager = CatalogPager((page, force) async => TmdbPage(
        items: page == 1
            ? [movie]
            : [
                movie,
                const TmdbMovie(id: 1, title: 'Series', rating: 0, kind: 'tv')
              ],
        page: page,
        totalPages: 2));
    addTearDown(pager.dispose);
    await pager.load();
    await pager.load();
    expect(pager.items.length, 2);
    expect(pager.hasMore, isFalse);
  });
  test('Failed next page retains cards and retries the same page', () async {
    final calls = <int>[];
    var fail = true;
    final pager = CatalogPager((page, force) async {
      calls.add(page);
      if (page == 2 && fail) throw StateError('offline');
      return TmdbPage(
          items: [TmdbMovie(id: page, title: 'Title $page', rating: 0)],
          page: page,
          totalPages: 2);
    });
    addTearDown(pager.dispose);
    await pager.load();
    await pager.load();
    expect(pager.failed, isTrue);
    expect(pager.items.length, 1);
    expect(pager.page, 1);
    fail = false;
    await pager.load();
    expect(calls, [1, 2, 2]);
    expect(pager.items.length, 2);
  });
  test('Disposing pending category prevents notification after disposal',
      () async {
    final result = Completer<TmdbPage>();
    final pager = CatalogPager((page, force) => result.future);
    final pending = pager.load();
    pager.dispose();
    result.complete(const TmdbPage(items: [movie]));
    await pending;
    expect(pager.items, isEmpty);
  });
  test('Empty later page exhausts without erasing loaded titles', () async {
    final pager = CatalogPager((page, force) async => page == 1
        ? const TmdbPage(items: [movie], totalPages: 3)
        : const TmdbPage());
    addTearDown(pager.dispose);
    await pager.load();
    await pager.load();
    expect(pager.items, [movie]);
    expect(pager.hasMore, isFalse);
  });
  test('Local library match normalizes rip names and rejects other-year remake',
      () {
    expect(
        findLocalMovieSource('Dune', 2021, [
          r'C:\Videos\Dune.1984.1080p.mkv',
          r'C:\Videos\Dune.2021.1080p.BluRay.x265.mkv'
        ]),
        r'C:\Videos\Dune.2021.1080p.BluRay.x265.mkv');
    expect(findLocalMovieSource('Dune', 2021, [r'C:\Videos\Dune.1984.mkv']),
        isNull);
    expect(
        findLocalMovieSource('Dune', 2021,
            ['https://example.com/Dune.2021.mp4', r'C:\Music\Dune.mp3']),
        isNull);
  });
  testWidgets('Dedicated category route has Android header and opens title',
      (tester) async {
    TmdbMovie? opened;
    await tester.pumpWidget(MaterialApp(
        home: DiscoverCategoryScreen(
            filter: kDiscoverFilters.first,
            client: FixtureCategoryClient(),
            onOpen: (v) => opened = v)));
    await tester.pumpAndSettle();
    expect(find.text('Trending'), findsOneWidget);
    expect(find.text('Dune'), findsOneWidget);
    await tester.tap(find.text('Dune'));
    expect(opened, movie);
  });
  testWidgets('Actual Android cinematic hero remains safe at desktop width',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: CineFeaturedHero(
                    items: const [movie], onTap: (_) {}, onOpen: (_) {})))));
    await tester.pump(const Duration(milliseconds: 1500));
    expect(find.text('VIEW DETAILS'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
