import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maxplayer/services/remote_theme.dart';
import 'package:maxplayer/services/notification_destination.dart';
import 'package:maxplayer/widgets/festive_visuals.dart';
import 'package:maxplayer/screens/notification_movie_screen.dart';
import 'package:maxplayer/utils/tmdb.dart';

void main() {
  Map<String, dynamic> theme() => {
    'schemaVersion': 2,
    'name': 'Christmas',
    'palette': <String, String>{},
    'decoration': 'christmas',
    'visuals': {
      'buttonStyle': 'snowcap',
      'cardStyle': 'ribbon',
      'background': 'snow',
      'rounded': 'pill',
    },
  };
  final movie = {
    'screen': 'movie',
    'movieId': '550',
    'movieKind': 'movie',
    'movieTitle': 'Test movie',
  };
  tearDown(() => RemoteTheme.instance.current = null);
  test('schema2 bounded visuals and schema1 compatibility', () {
    expect(validateTheme(theme())['visuals']['buttonStyle'], 'snowcap');
    expect(
      () => validateTheme({
        ...theme(),
        'visuals': {'script': 'bad'},
      }),
      throwsFormatException,
    );
    expect(
      () => validateTheme({...theme(), 'schemaVersion': 1}),
      throwsFormatException,
    );
    expect(
      validateTheme({
        'schemaVersion': 1,
        'name': 'Legacy',
        'palette': <String, String>{},
      })['schemaVersion'],
      1,
    );
  });
  test(
    'country-specific themes override global; no match preserves global',
    () {
      final global = {
        'enabled': true,
        'theme': {...theme(), 'name': 'Global'},
      };
      final audience = {
        'slots': {
          'ALL': global,
          'IN': {'enabled': true, 'theme': theme()},
          'NP': {'enabled': false},
        },
      };
      expect(
        selectThemePublication(audience, 'IN', null)?['name'],
        'Christmas',
      );
      expect(selectThemePublication(audience, 'US', null)?['name'], 'Global');
      expect(selectThemePublication(audience, '', null)?['name'], 'Global');
      expect(selectThemePublication(audience, 'NP', global), isNull);
      expect(
        selectThemePublication(
          {
            'slots': {
              'IN': {'enabled': true, 'theme': theme()},
            },
          },
          'US',
          global,
        )?['name'],
        'Global',
      );
    },
  );
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
  testWidgets('festive vector layer does not intercept tile taps', (
    tester,
  ) async {
    RemoteTheme.instance.current = validateTheme(theme());
    var tapped = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FestiveBackdrop(
            child: FestiveTile(
              child: SizedBox(
                width: 220,
                height: 60,
                child: TextButton(
                  onPressed: () => tapped++,
                  child: const Text('Audio'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Audio'));
    expect(tapped, 1);
    expect(tester.takeException(), isNull);
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
