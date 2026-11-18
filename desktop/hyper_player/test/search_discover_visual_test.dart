import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_player/screens/search_screen.dart';
import 'package:hyper_player/discover/android_browse.dart';
import 'package:hyper_player/discover/tmdb.dart';

void main() {
  testWidgets('Home Search opens directly as a search route', (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: DesktopSearchScreen(sources: [], listMode: false)));
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Type to search your Windows media collection'),
        findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
  });
  testWidgets('Search debounces deduplicates and clears results',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: DesktopSearchScreen(
            sources: ['movie.mp4', 'movie.mp4', 'song.mp3'], listMode: true)));
    await tester.enterText(find.byType(TextField), 'MOVIE');
    await tester.pump(const Duration(milliseconds: 220));
    expect(find.text('movie.mp4'), findsOneWidget);
    expect(find.text('song.mp3'), findsNothing);
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pump(const Duration(milliseconds: 220));
    expect(find.text('Type to search your Windows media collection'),
        findsOneWidget);
  });
  testWidgets('Discover poster retains Android title year and score',
      (tester) async {
    bool opened = false;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SizedBox(
                width: 138,
                height: 254,
                child: AndroidDiscoverPoster(
                    movie: const TmdbMovie(
                        id: 1, title: 'Sample title', rating: 7.5, year: 2024),
                    onTap: () => opened = true)))));
    expect(find.text('★ 7.5'), findsOneWidget);
    expect(find.text('2024'), findsOneWidget);
    await tester.tap(find.text('Sample title'));
    expect(opened, isTrue);
  });
  testWidgets('Featured carousel supports explicit PC navigation',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: AndroidFeaturedMovies(movies: const [
      TmdbMovie(id: 1, title: 'First title', rating: 7),
      TmdbMovie(id: 2, title: 'Second title', rating: 8),
    ], onOpen: (_) {})))));
    expect(find.text('First title'), findsOneWidget);
    await tester.tap(find.byTooltip('Next featured title'));
    await tester.pumpAndSettle();
    expect(find.text('Second title'), findsOneWidget);
  });
}
