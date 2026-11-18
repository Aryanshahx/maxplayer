import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_player/discover/android_details.dart';
import 'package:hyper_player/discover/discover_screen.dart';
import 'package:hyper_player/discover/tmdb.dart';

const movie = TmdbMovie(
    id: 1,
    title: 'Example movie',
    year: 2024,
    rating: 7.5,
    overview: 'Example story.',
    trailerKey: 'example');
const full = TmdbFull(
    movie, TmdbDetailExtras(genres: ['Drama'], director: 'Example director'));

class FixtureClient extends TmdbClient {
  @override
  Future<TmdbFull?> fullDetail(int id,
          {String kind = 'movie', bool force = false}) async =>
      full;
  @override
  Future<List<TmdbMovie>> similar(int id,
          {String kind = 'movie', bool force = false}) async =>
      [];
}

Widget host(Widget child) =>
    MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));
void main() {
  testWidgets('Details use compact Android header and external trailer action',
      (tester) async {
    String? trailer;
    await tester.pumpWidget(host(AndroidMovieDetails(
        full: full, onTrailer: (key) => trailer = key, onWatch: () {})));
    expect(find.text('MOVIE'), findsOneWidget);
    expect(find.text('★ 7.5 / 10'), findsOneWidget);
    expect(find.text('Storyline'), findsOneWidget);
    await tester.tap(find.text('Watch trailer on YouTube ↗'));
    expect(trailer, 'example');
  });
  testWidgets('Narrow details header does not overflow', (tester) async {
    tester.view.physicalSize = const Size(420, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(host(
        AndroidMovieDetails(full: full, onTrailer: (_) {}, onWatch: () {})));
    expect(tester.takeException(), isNull);
  });
  testWidgets('Seasons switch inline using loaded episode metadata',
      (tester) async {
    await tester.pumpWidget(host(AndroidSeasonBrowser(
      seasons: const [
        TmdbSeason(number: 1, name: 'Season 1', episodes: 1),
        TmdbSeason(number: 2, name: 'Season 2', episodes: 1)
      ],
      loader: (number, force) async => TmdbSeasonDetail(
          seasonNumber: number,
          name: 'Season $number',
          episodes: [
            TmdbEpisode(episodeNumber: 1, name: 'Episode for $number')
          ]),
    )));
    await tester.pumpAndSettle();
    expect(find.text('1. Episode for 1'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Season 2'));
    await tester.pumpAndSettle();
    expect(find.text('1. Episode for 2'), findsOneWidget);
  });
  testWidgets('Episodes use expandable metadata cards not fake play actions',
      (tester) async {
    await tester.pumpWidget(host(const AndroidEpisodeSection(
        detail: TmdbSeasonDetail(seasonNumber: 1, name: 'Season', episodes: [
      TmdbEpisode(episodeNumber: 1, name: 'Pilot', overview: 'Episode synopsis')
    ]))));
    await tester.tap(find.text('1. Pilot'));
    await tester.pumpAndSettle();
    expect(find.text('Episode synopsis'), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
  });
  testWidgets('Details route has pinned circular Back instead of AppBar',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: DiscoverDetail(client: FixtureClient(), movie: movie)));
    await tester.pumpAndSettle();
    expect(find.byType(AppBar), findsNothing);
    expect(find.byTooltip('Back'), findsOneWidget);
    expect(find.text('Example movie'), findsOneWidget);
  });
}
