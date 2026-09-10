import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maxplayer/theme.dart';
import 'package:maxplayer/utils/badges.dart';
import 'package:maxplayer/utils/collections.dart';
import 'package:maxplayer/utils/format.dart';
import 'package:maxplayer/utils/local_store.dart';
import 'package:maxplayer/utils/resume.dart';
import 'package:maxplayer/utils/sort.dart';
import 'package:maxplayer/utils/tmdb.dart';

void main() {
  group('formatDuration', () {
    test('zero', () => expect(formatDuration(Duration.zero), '0:00'));
    test('seconds', () {
      expect(formatDuration(const Duration(seconds: 7)), '0:07');
    });
    test('minutes', () {
      expect(formatDuration(const Duration(minutes: 1, seconds: 5)), '1:05');
    });
    test('hours', () {
      expect(formatDuration(const Duration(hours: 1, minutes: 2, seconds: 3)),
          '1:02:03');
    });
    test('negative clamps to zero', () {
      expect(formatDuration(const Duration(seconds: -5)), '0:00');
    });
  });

  group('formatBytes', () {
    test('bytes', () => expect(formatBytes(512), '512B'));
    test('kilobytes', () => expect(formatBytes(1536), '1.5 KB'));
    test('megabytes', () => expect(formatBytes(734003200), '700.0 MB'));
    test('negative clamps', () => expect(formatBytes(-1), '0B'));
  });

  group('resumeTargetMs (v0.3 resume)', () {
    test('under 10s saved -> no prompt', () {
      expect(resumeTargetMs(5000, 600000), isNull);
    });
    test('boundary: exactly 10s saved -> prompt', () {
      expect(resumeTargetMs(minPromptMs, 600000), minPromptMs);
    });
    test('mid-video -> prompt at saved spot', () {
      expect(resumeTargetMs(754000, 3600000), 754000);
    });
    test('inside end margin -> treated as finished, no prompt', () {
      expect(resumeTargetMs(3600000 - endMarginMs + 1, 3600000), isNull);
    });
    test('just outside end margin -> prompt', () {
      expect(resumeTargetMs(3600000 - endMarginMs, 3600000),
          3600000 - endMarginMs);
    });
    test('unknown duration (0) -> prompt for big save', () {
      expect(resumeTargetMs(60000, 0), 60000);
    });
  });

  group('isFinishedMs (v0.3 resume)', () {
    test('near end -> finished', () {
      expect(isFinishedMs(3595000, 3600000), isTrue);
    });
    test('mid -> not finished', () {
      expect(isFinishedMs(1800000, 3600000), isFalse);
    });
    test('unknown duration -> not finished', () {
      expect(isFinishedMs(999999, 0), isFalse);
    });
  });

  group('qualityBadge (v0.4)', () {
    test('4K landscape', () => expect(qualityBadge(3840, 2160), '4K'));
    test('2K', () => expect(qualityBadge(2560, 1440), '2K'));
    test('1080p landscape', () => expect(qualityBadge(1920, 1080), '1080p'));
    test('1080p portrait (short side rules)', () {
      expect(qualityBadge(1080, 1920), '1080p');
    });
    test('720p', () => expect(qualityBadge(1280, 720), '720p'));
    test('480p', () => expect(qualityBadge(854, 480), '480p'));
    test('SD', () => expect(qualityBadge(320, 240), 'SD'));
  });

  group('upsertRecent (v0.4 history)', () {
    RecentItem it(String id, int ts) =>
        RecentItem(id: id, title: 't$id', path: '/$id', ts: ts);

    test('newest first', () {
      final out = upsertRecent([it('a', 1)], it('b', 2));
      expect(out.map((e) => e.id).toList(), ['b', 'a']);
    });
    test('dedupes by id, moves to front', () {
      final out = upsertRecent([it('a', 1), it('b', 2)], it('a', 3));
      expect(out.map((e) => e.id).toList(), ['a', 'b']);
      expect(out.first.ts, 3);
    });
    test('caps at 25', () {
      var list = <RecentItem>[];
      for (var i = 0; i < 30; i++) {
        list = upsertRecent(list, it('$i', i));
      }
      expect(list.length, 25);
      expect(list.first.id, '29'); // newest kept
      expect(list.last.id, '5'); // oldest dropped
    });
  });

  group('toggleId (v0.4 playlists)', () {
    test('adds when missing', () {
      expect(toggleId(['a'], 'b'), ['a', 'b']);
    });
    test('removes when present', () {
      expect(toggleId(['a', 'b'], 'b'), ['a']);
    });
    test('does not mutate input', () {
      final input = ['a'];
      toggleId(input, 'x');
      expect(input, ['a']);
    });
  });

  group('sort comparators (v0.5)', () {
    test('cmpNum asc/desc', () {
      expect(cmpNum(1, 2, true) < 0, isTrue);
      expect(cmpNum(1, 2, false) > 0, isTrue);
      expect(cmpNum(7, 7, true), 0);
    });
    test('cmpStr case-insensitive asc/desc', () {
      expect(cmpStr('Alpha', 'beta', true) < 0, isTrue);
      expect(cmpStr('Alpha', 'beta', false) > 0, isTrue);
    });
    test('direction labels match design', () {
      expect(sortDirectionLabel(SortField.name, true), 'A → Z');
      expect(sortDirectionLabel(SortField.name, false), 'Z → A');
      expect(sortDirectionLabel(SortField.dateAdded, false), 'Newest first');
      expect(sortDirectionLabel(SortField.size, true), 'Smallest first');
      expect(sortDirectionLabel(SortField.length, true), 'Shortest first');
    });
  });

  group('appendUnique (v0.6 duplicate guard)', () {
    test('skips already-present ids', () {
      final out = appendUnique(['a', 'b'], ['b', 'c'], (e) => e);
      expect(out, ['a', 'b', 'c']);
    });
    test('empty batch is identity', () {
      expect(appendUnique(['a'], <String>[], (e) => e), ['a']);
    });
    test('batch dups within itself collapse', () {
      final out = appendUnique(<String>[], ['x', 'x'], (e) => e);
      expect(out, ['x']);
    });
  });

  group('parseTrending (v0.6 TMDB)', () {
    const sample = '''
    {"results":[
      {"id":101,"title":"Cool Movie","release_date":"2026-03-01",
       "vote_average":8.4,"overview":"A tale.","poster_path":"/abc.jpg"},
      {"id":102,"name":"Show Only Name","vote_average":7,"poster_path":null}
    ]}''';

    test('parses movies with posters', () {
      final movies = parseTrending(sample);
      expect(movies.length, 2);
      expect(movies[0].title, 'Cool Movie');
      expect(movies[0].year, '2026');
      expect(movies[0].rating, 8.4);
      expect(movies[0].posterUrl,
          'https://image.tmdb.org/t/p/w342/abc.jpg');
    });

    test('falls back to name, empty poster ok', () {
      final movies = parseTrending(sample);
      expect(movies[1].title, 'Show Only Name');
      expect(movies[1].posterUrl, '');
      expect(movies[1].year, '');
    });
  });

  testWidgets('theme applies dark design language', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: const Scaffold(body: Text('ok')),
    ));
    expect(find.text('ok'), findsOneWidget);
    final theme = Theme.of(tester.element(find.text('ok')));
    expect(theme.scaffoldBackgroundColor, AppColors.background);
    expect(theme.brightness, Brightness.dark);
  });
}
