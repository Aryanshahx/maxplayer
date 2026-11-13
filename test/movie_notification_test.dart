import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maxplayer/services/notification_destination.dart';
import 'package:maxplayer/screens/notification_movie_screen.dart';
import 'package:maxplayer/utils/tmdb.dart';

void main() {
  final movie = {
    'screen': 'movie',
    'movieId': '550',
    'movieKind': 'movie',
    'movieTitle': 'Test movie',
  };
  test('movie notification fields are all required and allowlisted', () {
    expect(notificationDestination(movie), 'movie');
    for (final changes in [
      {'movieId': '0'},
      {'movieKind': 'person'},
      {'movieTitle': ''},
      {'movieId': 'execute'},
    ]) {
      expect(notificationDestination({...movie, ...changes}), 'home');
    }
  });
  testWidgets(
    'movie route shows loading then retryable error without leaving app',
    (tester) async {
      var tries = 0;
      final pending = Completer<TmdbFull?>();
      await tester.pumpWidget(
        MaterialApp(
          home: NotificationMovieScreen(
            data: movie,
            detailLoader: () {
              tries++;
              return pending.future;
            },
          ),
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      pending.complete(null);
      await tester.pumpAndSettle();
      expect(find.text('Retry'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(tries, 2);
      expect(find.text('Go Home'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
