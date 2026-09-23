import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maxplayer/theme.dart';
import 'package:maxplayer/screens/history_screen.dart' show timeAgo;
import 'package:maxplayer/models/network_location.dart';
import 'package:maxplayer/models/saved_server.dart';
import 'package:maxplayer/utils/badges.dart';
import 'package:maxplayer/utils/collections.dart';
import 'package:maxplayer/utils/fit.dart';
import 'package:maxplayer/utils/format.dart';
import 'package:maxplayer/utils/iptv.dart' show kMaxPlayerUserAgent;
import 'package:maxplayer/utils/m3u.dart';
import 'package:maxplayer/utils/network_headers.dart'
    show kVlcFallbackUserAgent;
import 'package:maxplayer/utils/ab_loop.dart';
import 'package:maxplayer/utils/ai_subtitles.dart'
    show AiSubtitleRunner, isMusicOnlyCaption;
import 'package:maxplayer/utils/mpv_filters.dart';
import 'package:maxplayer/utils/local_store.dart';
import 'package:maxplayer/utils/resume.dart';
import 'package:maxplayer/utils/settings.dart'
    show accentPalette, defaultAccentIndex;
import 'package:maxplayer/utils/sha256.dart';
import 'package:maxplayer/utils/sort.dart';
import 'package:maxplayer/utils/srt.dart';
import 'package:maxplayer/utils/tmdb.dart';
import 'package:maxplayer/utils/tmdb_image.dart';
import 'package:maxplayer/utils/gesture_ticks.dart';
import 'package:maxplayer/utils/video_zoom.dart';
import 'package:maxplayer/utils/karaoke.dart';
import 'package:maxplayer/utils/ai.dart' show smartLocalMovieAnswer;
import 'package:maxplayer/services/recommendations.dart';
import 'package:maxplayer/services/ai_suggest.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:maxplayer/utils/ads.dart';
import 'package:maxplayer/utils/app_volume.dart';
import 'package:maxplayer/utils/movie_match.dart';
import 'package:maxplayer/utils/player_settings.dart';
import 'package:maxplayer/utils/watch_stats.dart';

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
      expect(
        formatDuration(const Duration(hours: 1, minutes: 2, seconds: 3)),
        '1:02:03',
      );
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

  group('FitMode (v0.12 player UI)', () {
    test('six modes in the old app loop order', () {
      expect(FitMode.values, const [
        FitMode.fit,
        FitMode.crop,
        FitMode.stretch,
        FitMode.sixteenNine,
        FitMode.fourThree,
        FitMode.original,
      ]);
    });

    test('boxFit mapping matches the old player', () {
      expect(FitMode.fit.boxFit, BoxFit.contain);
      expect(FitMode.crop.boxFit, BoxFit.cover);
      expect(FitMode.stretch.boxFit, BoxFit.fill);
      expect(FitMode.sixteenNine.boxFit, BoxFit.fill);
      expect(FitMode.fourThree.boxFit, BoxFit.fill);
      expect(FitMode.original.boxFit, BoxFit.none);
    });

    test('aspectRatio forces frames only for 16:9 and 4:3', () {
      expect(FitMode.sixteenNine.aspectRatio, 16 / 9);
      expect(FitMode.fourThree.aspectRatio, 4 / 3);
      for (final m in const [
        FitMode.fit,
        FitMode.crop,
        FitMode.stretch,
        FitMode.original,
      ]) {
        expect(m.aspectRatio, isNull, reason: '$m must not force a frame');
      }
    });

    test('labels match the old player', () {
      expect(FitMode.fit.label, 'Fit');
      expect(FitMode.crop.label, 'Crop');
      expect(FitMode.stretch.label, 'Stretch');
      expect(FitMode.sixteenNine.label, '16:9');
      expect(FitMode.fourThree.label, '4:3');
      expect(FitMode.original.label, 'Original');
    });

    test('nextFitMode walks the loop and wraps Original -> Fit', () {
      expect(nextFitMode(FitMode.fit), FitMode.crop);
      expect(nextFitMode(FitMode.stretch), FitMode.sixteenNine);
      expect(nextFitMode(FitMode.original), FitMode.fit);
    });

    test('previousFitMode walks backwards and wraps Fit -> Original', () {
      expect(previousFitMode(FitMode.fit), FitMode.original);
      expect(previousFitMode(FitMode.crop), FitMode.fit);
      expect(previousFitMode(FitMode.original), FitMode.fourThree);
    });

    test('full cycle visits all six modes', () {
      var m = FitMode.fit;
      final seen = <FitMode>{};
      for (var i = 0; i < 6; i++) {
        seen.add(m);
        m = nextFitMode(m);
      }
      expect(m, FitMode.fit);
      expect(seen.length, 6);
    });
  });

  group('video_zoom (Drop 2 two-finger gestures)', () {
    test('clampVideoZoom pins 1.0..4.0', () {
      expect(clampVideoZoom(0.5), 1.0);
      expect(clampVideoZoom(1.0), 1.0);
      expect(clampVideoZoom(4.0), 4.0);
      expect(clampVideoZoom(9.0), 4.0);
      expect(clampVideoZoom(2.5), 2.5);
    });

    test('fit ladder: scale 1.0 keeps the base fit', () {
      expect(fitLadderPosFor(basePos: 2, scale: 1.0), 2.0);
    });

    test('fit ladder: one spread step climbs one fit', () {
      final pos = fitLadderPosFor(basePos: 0, scale: kFitLadderStepScale);
      expect(wrapFitLadderPos(pos, 6), 1); // Fit -> Crop
    });

    test('fit ladder: pinch inward climbs down a fit', () {
      final pos = fitLadderPosFor(basePos: 2, scale: 1 / kFitLadderStepScale);
      expect(wrapFitLadderPos(pos, 6), 1); // Stretch -> Crop
    });

    test('wrapFitLadderPos wraps Original -> Fit and Fit -> Original', () {
      expect(wrapFitLadderPos(5, 6), 5);
      expect(wrapFitLadderPos(6, 6), 0); // past Original loops to Fit
      expect(wrapFitLadderPos(7, 6), 1);
      expect(wrapFitLadderPos(-1, 6), 5); // behind Fit loops to Original
      expect(wrapFitLadderPos(-6, 6), 0);
    });

    test('free zoom clamps to 1x..4x', () {
      expect(freeZoomFor(baseZoom: 1.0, scale: 1.0), 1.0);
      expect(freeZoomFor(baseZoom: 1.0, scale: 2.0), 2.0);
      expect(freeZoomFor(baseZoom: 2.0, scale: 3.0), 4.0); // clamped
      expect(freeZoomFor(baseZoom: 1.0, scale: 0.5), 1.0); // clamped
    });

    test('two-finger tap reset: quick, no pinch, no travel', () {
      expect(
        isTwoFingerTapReset(durationMs: 200, travelPx: 10, scaled: false),
        isTrue,
      );
    });

    test('two-finger tap reset rejects real pinches', () {
      expect(
        isTwoFingerTapReset(durationMs: 200, travelPx: 10, scaled: true),
        isFalse,
      );
      expect(
        isTwoFingerTapReset(durationMs: 900, travelPx: 10, scaled: false),
        isFalse,
      );
      expect(
        isTwoFingerTapReset(durationMs: 200, travelPx: 60, scaled: false),
        isFalse,
      );
    });
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
      expect(
        resumeTargetMs(3600000 - endMarginMs, 3600000),
        3600000 - endMarginMs,
      );
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
    // v1.0.14: real encodes are cropped just under the nominal width —
    // these must NOT fall a bucket (the user-reported 1916x1080 -> "720p").
    test('cropped 1080p Blu-ray (1916x1080)', () {
      expect(qualityBadge(1916, 1080), '1080p');
    });
    test('ultrawide 1080p (1920x804)', () {
      expect(qualityBadge(1920, 804), '1080p');
    });
    test('cropped 720p (1274x720)', () {
      expect(qualityBadge(1274, 720), '720p');
    });
    test('cropped 480p (848x480)', () {
      expect(qualityBadge(848, 480), '480p');
    });
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

  group('addId (Drop 6 playlist add)', () {
    test('appends when missing', () {
      expect(addId(['a'], 'b'), ['a', 'b']);
    });
    test('idempotent when present', () {
      expect(addId(['a', 'b'], 'b'), ['a', 'b']);
    });
    test('does not mutate input', () {
      final input = ['a'];
      addId(input, 'x');
      expect(input, ['a']);
    });
  });

  group('buildSrt (AI subtitles)', () {
    test('numbers, sorts and formats cues', () {
      final srt = buildSrt(const [
        SrtCue(5000, 6000, 'later'),
        SrtCue(1000, 2000, 'first'),
      ]);
      expect(
        srt,
        '1\n00:00:01,000 --> 00:00:02,000\nfirst\n\n'
        '2\n00:00:05,000 --> 00:00:06,000\nlater\n\n',
      );
    });
    test('drops empty-text cues', () {
      expect(buildSrt(const [SrtCue(1000, 2000, '  ')]), '');
    });
    test('bumps zero-length cue end by one second', () {
      final srt = buildSrt(const [SrtCue(1000, 1000, 'x')]);
      expect(srt, contains('00:00:01,000 --> 00:00:02,000'));
    });
  });

  group('parseSrt (AI subtitles)', () {
    test('round-trips buildSrt', () {
      const cues = [SrtCue(1000, 2000, 'hello'), SrtCue(5000, 6000, 'world')];
      final parsed = parseSrt(buildSrt(cues));
      expect(parsed.length, 2);
      expect(parsed[0].text, 'hello');
      expect(parsed[0].startMs, 1000);
      expect(parsed[1].endMs, 6000);
    });
    test('joins multi-line cue text', () {
      final parsed = parseSrt(
        '1\n00:00:01,000 --> 00:00:02,000\nline one\n'
        'line two\n\n',
      );
      expect(parsed.single.text, 'line one line two');
    });
    test('ignores garbage lines', () {
      final parsed = parseSrt(
        'garbage\n1\n00:00:01,000 --> 00:00:02,000\nok\n\n',
      );
      expect(parsed.single.text, 'ok');
    });
  });

  group('srtPathForVideo (AI subtitles)', () {
    test('swaps extension for .maxai.srt next to the video', () {
      expect(
        srtPathForVideo('/sdcard/Movies/clip.mp4'),
        '/sdcard/Movies/clip.maxai.srt',
      );
    });
    test('handles windows separators', () {
      expect(srtPathForVideo(r'C:\vids\clip.mkv'), 'C:/vids/clip.maxai.srt');
    });
    test('no extension still gets the suffix', () {
      expect(srtPathForVideo('/vids/clip'), '/vids/clip.maxai.srt');
    });
  });

  group('sidecarSrtCandidates (AI subtitles)', () {
    test('exact match first, then language suffixes', () {
      final picks = sidecarSrtCandidates([
        'movie.en.srt',
        'movie.srt',
        'other.srt',
      ], '/vids/movie.mp4');
      expect(picks, ['movie.srt', 'movie.en.srt']);
    });
    test('excludes the AI sidecar and non-subs', () {
      final picks = sidecarSrtCandidates([
        'movie.maxai.srt',
        'movie.srt',
        'poster.jpg',
      ], '/vids/movie.mp4');
      expect(picks, ['movie.srt']);
    });
  });

  group('isMusicOnlyText (AI subtitles)', () {
    test('music decorations', () {
      expect(isMusicOnlyText('[Music]'), isTrue);
      expect(isMusicOnlyText('(upbeat music)'), isTrue);
      expect(isMusicOnlyText('♪ ♪'), isTrue);
    });
    test('real speech kept', () {
      expect(isMusicOnlyText('I love music'), isFalse);
      expect(isMusicOnlyText('Hello there'), isFalse);
    });
  });

  group('computeSkipIntro (AI subtitles)', () {
    test('returns null when speech starts right away', () {
      expect(computeSkipIntro(const [SrtCue(5000, 6000, 'Hi')]), isNull);
    });
    test('returns the first speech cue minus 1s', () {
      final skip = computeSkipIntro(const [
        SrtCue(1000, 9000, '[Music]'),
        SrtCue(30000, 34000, 'And now our story begins'),
      ]);
      expect(skip, const Duration(milliseconds: 29000));
    });
  });

  group('computeSkipCredits (AI subtitles)', () {
    List<SrtCue> creditRun() => [
      for (var i = 0; i < 8; i++)
        SrtCue(
          1_800_000 + i * 2000,
          1_800_000 + i * 2000 + 800,
          'Name ${i + 1}',
        ),
    ];
    test('returns null for normal dialogue', () {
      expect(
        computeSkipCredits(const [
          SrtCue(1000, 2000, 'A normal line of spoken dialogue here'),
          SrtCue(3000, 4000, 'Another normal line of spoken dialogue'),
        ]),
        isNull,
      );
    });
    test('detects a dense trailing credit run', () {
      final skip = computeSkipCredits(creditRun(), durationMs: 2_000_000);
      expect(skip, isNotNull);
      expect(skip!.inMilliseconds, closeTo(1_800_000 - 1500, 1));
    });
  });

  group('isMusicOnlyCaption (AI subtitles)', () {
    test('music decorations', () {
      expect(isMusicOnlyCaption('[Music]'), isTrue);
      expect(isMusicOnlyCaption('(upbeat music)'), isTrue);
      expect(isMusicOnlyCaption('♪'), isTrue);
      expect(isMusicOnlyCaption('♪ ♫ ♪'), isTrue);
    });
    test('real speech kept', () {
      expect(isMusicOnlyCaption('I love music'), isFalse);
      expect(isMusicOnlyCaption('Hello there'), isFalse);
    });
    test('empty treated as decoration', () {
      expect(isMusicOnlyCaption('   '), isTrue);
    });
  });

  group('AiSubtitleRunner (AI subtitles)', () {
    test('normalizeModelId: fast is the default, saved picks respected', () {
      expect(AiSubtitleRunner.normalizeModelId(null), 'fast');
      expect(AiSubtitleRunner.normalizeModelId('tiny'), 'fast');
      expect(AiSubtitleRunner.normalizeModelId('fast'), 'fast');
      expect(AiSubtitleRunner.normalizeModelId('base'), 'base');
      expect(AiSubtitleRunner.normalizeModelId('small'), 'small');
    });
    test('modelSizeLabel maps every model id', () {
      expect(AiSubtitleRunner.modelSizeLabel('small'), '~466 MB');
      expect(AiSubtitleRunner.modelSizeLabel('base'), '~142 MB');
      expect(AiSubtitleRunner.modelSizeLabel('fast'), '~60 MB');
    });
  });

  group('timeAgo (Drop 6 history)', () {
    test('just now', () {
      expect(timeAgo(DateTime.now().millisecondsSinceEpoch), 'Just now');
    });
    test('minutes ago', () {
      final ts = DateTime.now()
          .subtract(const Duration(minutes: 3))
          .millisecondsSinceEpoch;
      expect(timeAgo(ts), '3m ago');
    });
    test('hours ago', () {
      final ts = DateTime.now()
          .subtract(const Duration(hours: 5))
          .millisecondsSinceEpoch;
      expect(timeAgo(ts), '5h ago');
    });
    test('days ago', () {
      final ts = DateTime.now()
          .subtract(const Duration(days: 2))
          .millisecondsSinceEpoch;
      expect(timeAgo(ts), '2d ago');
    });
    test('zero/negative is blank', () {
      expect(timeAgo(0), '');
      expect(timeAgo(-1), '');
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
      expect(movies[0].year, 2026);
      expect(movies[0].rating, 8.4);
      expect(
        tmdbPosterUrl(movies[0].posterPath),
        'https://image.tmdb.org/t/p/w342/abc.jpg',
      );
    });

    test('falls back to name, empty poster ok', () {
      final movies = parseTrending(sample);
      expect(movies[1].title, 'Show Only Name');
      expect(movies[1].posterPath, isNull);
      expect(movies[1].year, isNull);
    });
  });

  group('parseM3u (v0.7 IPTV)', () {
    const list = '''
#EXTM3U
#EXTINF:-1 tvg-logo="https://x/logo.png" group-title="News",DD National
https://cdn.tv/dd.m3u8

#EXTINF:-1,Star Sports
http://streams.tv/star.ts
plain-list-url.mp4
''';

    test('names + urls + logos', () {
      final chans = parseM3u(list);
      expect(chans.length, 3);
      expect(chans[0].name, 'DD National');
      expect(chans[0].logo, 'https://x/logo.png');
      expect(chans[0].url, 'https://cdn.tv/dd.m3u8');
      expect(chans[1].name, 'Star Sports');
      expect(chans[1].logo, isNull);
      expect(chans[2].name, 'Channel'); // url without EXTINF
    });

    test('CRLF tolerated', () {
      expect(parseM3u('#EXTM3U\r\n#EXTINF:-1,A\r\nhttp://a/b\r\n').length, 1);
    });

    test('group-title parsed (iptv-org format)', () {
      final chans = parseM3u(list);
      expect(chans[0].group, 'News');
      expect(chans[1].group, isNull);
      expect(chans[2].group, isNull);
    });

    test('json round-trip keeps group', () {
      const c = IptvChannel(
        name: 'Aaj Tak',
        url: 'http://x/y.m3u8',
        logo: 'l.png',
        group: 'News',
      );
      final b = IptvChannel.fromJson(c.toJson());
      expect(b.group, 'News');
      expect(b.name, 'Aaj Tak');
      // old dumped json without group still parses
      expect(IptvChannel.fromJson({'name': 'n', 'url': 'u'}).group, isNull);
    });
  });

  group('iptv-org index sample (v1.0.1+12)', () {
    const iptvOrg = '''
#EXTM3U
#EXTINF:-1 tvg-id="AajTak.in" status="online" tvg-logo="https://x/a.png" group-title="News",Aaj Tak (720p)
https://feeds.intoday.in/aajtak/api/aajtakhd/master.m3u8
#EXTINF:-1 tvg-id="SonySATHD.in" tvg-logo="https://x/b.png" group-title="Entertainment",Sony SAB HD
https://pubads.g.doubleclick.net/ssai/xyz/master.m3u8
#EXTINF:-1 tvg-id="AlJazeera.qa" tvg-logo="https://x/c.png" group-title="News",Al Jazeera English (1080p)
https://linear-xyz.frequency.mtv/munge/master.m3u8
''';
    test('parses big-list records incl groups', () {
      final chans = parseM3u(iptvOrg);
      expect(chans.length, 3);
      expect(chans[0].name, 'Aaj Tak (720p)');
      expect(chans[0].group, 'News');
      expect(chans[1].group, 'Entertainment');
      expect(chans[2].group, 'News');
      expect(chans[0].logo, 'https://x/a.png');
    });
  });

  group('stream headers ladder (v1.0.1+14)', () {
    test('VLC fallback UA is the classic whitelisted agent', () {
      expect(kVlcFallbackUserAgent.startsWith('VLC/'), true);
      expect(kVlcFallbackUserAgent.contains('LibVLC'), true);
    });

    test('indian regional + serial rails are registered', () {
      final movieKeys = {for (final f in kDiscoverFilters) f.key};
      final seriesKeys = {for (final f in kSeriesFilters) f.key};
      for (final k in const [
        'malayalam',
        'kannada',
        'bengali',
        'marathi',
        'punjabi',
      ]) {
        expect(movieKeys.contains(k), true, reason: k);
      }
      for (final k in const [
        'tv_hindi',
        'tv_tamil',
        'tv_telugu',
        'tv_malayalam',
      ]) {
        expect(seriesKeys.contains(k), true, reason: k);
      }
    });
  });

  group('stream user-agent default (v1.0.1+12)', () {
    test('UA looks browser-like, not dart default', () {
      expect(kMaxPlayerUserAgent.isNotEmpty, true);
      expect(kMaxPlayerUserAgent.toLowerCase().contains('http'), false);
    });
  });

  group('mpv filter builders (v0.8)', () {
    test('flat EQ produces no filter', () {
      expect(buildEqualizerFilter(const [0, 0, 0, 0, 0]), '');
    });
    test('non-zero bands build an equalizer chain', () {
      final f = buildEqualizerFilter(const [6, 0, -3, 0, 5]);
      expect(f.startsWith('lavfi=['), isTrue);
      expect(f.contains('f=60'), isTrue);
      expect(f.contains('f=910'), isTrue);
      expect(f.contains('f=230'), isFalse); // zero band skipped
      expect(f.endsWith(']'), isTrue);
    });
    test('dialogue boost combines with EQ', () {
      final f = combineAudioFilters(const [0, 0, 0, 0, 0], dialogueBoost: true);
      expect(f.contains('f=1200'), isTrue);
      expect(f.contains('f=3200'), isTrue);
    });
    test('wrong band count throws', () {
      expect(() => buildEqualizerFilter(const [1, 2]), throwsArgumentError);
    });
  });

  group('A-B loop state machine (v0.8)', () {
    test('off -> aSet -> abSet -> off', () {
      var s = AbState.off;
      expect(s.phase, AbPhase.off);
      s = s.advance(5000);
      expect(s.phase, AbPhase.aSet);
      expect(s.aMs, 5000);
      s = s.advance(12000);
      expect(s.phase, AbPhase.abSet);
      expect(s.aMs, 5000);
      expect(s.bMs, 12000);
      s = s.advance(13000);
      expect(s.phase, AbPhase.off);
    });
    test('B before A shifts B to A+1s', () {
      final s = AbState.off.advance(10000).advance(3000);
      expect(s.bMs, 11000);
    });
    test('labels describe phases', () {
      expect(AbState.off.describe(), contains('mark point A'));
      expect(AbState.off.advance(1).describe(), contains('mark B'));
      expect(
        AbState.off.advance(1).advance(2).describe(),
        contains('Looping A → B'),
      );
    });
  });

  group('TMDB deep parsers (Discover port)', () {
    test('parseTmdbDetail fills trailer key via pickTrailerKey', () {
      const d =
          '{"id":1,"title":"Spider","release_date":"2026-07-29",'
          '"vote_average":7.9,"videos":{"results":['
          '{"site":"YouTube","type":"Trailer","official":true,"key":"bbb"},'
          '{"site":"YouTube","type":"Teaser","key":"aaa"}]}}';
      final m = parseTmdbDetail(d)!;
      expect(m.title, 'Spider');
      expect(m.year, 2026);
      expect(m.trailerKey, 'bbb');
      expect(m.kind, 'movie');
    });

    test('parseTmdbExtras maps director, cast, runtime, genres, money', () {
      const d = '''
      {"runtime":145,"vote_count":2555,"status":"Released",
       "release_date":"2026-07-29","original_title":"The Spider",
       "budget":225000000,"revenue":2408062495,
       "production_companies":[{"name":"Marvel"},{"name":"Pascal"}],
       "production_countries":[{"name":"United States"}],
       "spoken_languages":[{"english_name":"English"}],
       "genres":[{"name":"Action"}],
       "credits":{"cast":[{"name":"Tom","character":"Peter",
          "profile_path":"/t.jpg"}],
        "crew":[{"job":"Director","name":"Destin"}]}}''';
      final e = parseTmdbExtras(d);
      expect(e.director, 'Destin');
      expect(e.castMembers.single.name, 'Tom');
      expect(e.runtimeMinutes, 145);
      expect(e.genres.single, 'Action');
      expect(e.budgetUsd, 225000000);
      expect(e.companies, ['Marvel', 'Pascal']);
      expect(formatRuntime(e.runtimeMinutes), '2h 25m');
      expect(formatVoteCount(e.voteCount), '2,555');
    });

    test('parseTmdbReviews keeps rating + author', () {
      final r =
          '{"reviews":{"results":[{"author":"Manuel",'
          '"author_details":{"rating":9.0},"content":"Great!"}]}}';
      final list = parseTmdbReviews(r);
      expect(list.single.rating, 9.0);
      expect(list.single.author, 'Manuel');
      expect(tmdbRatingText(list.single.rating!), '9.0');
    });

    test('parseTmdbScreenshots builds w500 urls', () {
      const i =
          '{"images":{"backdrops":[{"file_path":"/1.jpg"},'
          '{"file_path":"/2.jpg"}]}}';
      final list = parseTmdbScreenshots(i);
      expect(list.length, 2);
      expect(
        tmdbScreenshotUrl(list.first),
        'https://image.tmdb.org/t/p/w500/1.jpg',
      );
      expect(
        tmdbBackdropUrl('/hero.jpg'),
        'https://image.tmdb.org/t/p/w780/hero.jpg',
      );
      expect(tmdbBackdropUrl(null), '');
    });

    test('parseTmdbSeasons reads per-season ratings', () {
      const s =
          '{"seasons":[{"season_number":1,"name":"Season 1",'
          '"episode_count":8,"air_date":"2020-01-01","vote_average":8.4},'
          '{"season_number":0,"episode_count":2}]}';
      final list = parseTmdbSeasons(s);
      expect(list.length, 2);
      expect(list[0].rating, 8.4);
      expect(list[0].year, 2020);
      expect(list[1].name, 'Specials');
    });

    test('parseTmdbSeasonDetail maps episodes', () {
      const s =
          '{"name":"Season 1","vote_average":8.1,'
          '"overview":"About.","episodes":[{"episode_number":1,'
          '"name":"Pilot","vote_average":7.5,"runtime":48,'
          '"still_path":"/e.jpg"}]}';
      final d = parseTmdbSeasonDetail(s, seasonNumber: 1)!;
      expect(d.name, 'Season 1');
      expect(d.rating, 8.1);
      expect(d.episodes.single.name, 'Pilot');
      expect(d.episodes.single.runtimeMinutes, 48);
    });

    test('parseTmdbWatchProviders splits stream/rent/buy for IN', () {
      const w =
          '{"watch/providers":{"results":{"IN":{'
          '"flatrate":[{"provider_name":"Netflix"}],'
          '"rent":[{"provider_name":"Amazon"}],'
          '"buy":[{"provider_name":"Apple"}]}}}}';
      final info = parseTmdbWatchProviders(w);
      expect(info.stream, ['Netflix']);
      expect(info.rent, ['Amazon']);
      expect(info.buy, ['Apple']);
      expect(info.isEmpty, isFalse);
    });

    test('parseTmdbMultiPage keeps movies+tv, drops people', () {
      const m =
          '{"results":[{"media_type":"movie","id":1,"title":"A"},'
          '{"media_type":"tv","id":2,"name":"B"},'
          '{"media_type":"person","id":3,"name":"C"}]}';
      final page = parseTmdbMultiPage(m);
      expect(page.items.length, 2);
      expect(page.items[0].kind, 'movie');
      expect(page.items[1].kind, 'tv');
    });

    test('discover cache names + endpoints are deterministic', () {
      expect(
        discoverCacheName(kDiscoverFilters.first, 1),
        'tmdb_disc_trending_p1.json',
      );
      expect(
        discoverCacheName(kSeriesFilters.first, 2),
        'tmdb_disc_tv_hindi_tv_p2.json',
      );
      expect(
        tmdbEndpointPath(kDiscoverFilters.first),
        '/3/trending/movie/week',
      );
      expect(tmdbEndpointPath(kSeriesFilters.last), '/3/discover/tv');
      expect(
        tmdbDiscoverQuery(kDiscoverFilters[4], 3),
        containsPair('with_original_language', 'hi'),
      );
      expect(
        tmdbSearchCacheName('Hello World', 1),
        startsWith('tmdb_search_hello_world_'),
      );
    });

    test('kAllFilters merges movie + series chips', () {
      expect(
        kAllFilters.length,
        kDiscoverFilters.length + kSeriesFilters.length,
      );
      expect(kAllFilters.first.key, 'trending');
      expect(kAllFilters.last.key, 'tv_anime');
    });

    test('parseTotalResults reads total_results', () {
      expect(parseTotalResults('{"total_results":48212}'), 48212);
    });
  });

  group('Discover helpers (port)', () {
    test('normalizeTitle strips rip junk + years + brackets', () {
      expect(
        Recommendations.normalizeTitle(
          'The.Dark.Knight.2008.1080p.BluRay.x265',
        ),
        'dark knight',
      );
      expect(
        Recommendations.normalizeTitle('[YTS] Inception (2010) [1080p]'),
        'inception',
      );
    });

    test('parseAiSuggestionJson survives prose + fences', () {
      const raw =
          'Sure! Here you go: ```json [{"title":"3 Idiots",'
          '"year":2009},{"title":"Dhoom 2","year":2006}] ``` enjoy!';
      final picks = parseAiSuggestionJson(raw);
      expect(picks.length, 2);
      expect(picks.first.title, '3 Idiots');
      expect(picks.first.year, 2009);
      expect(parseAiSuggestionJson('no json here'), isEmpty);
    });

    test('tmdbImageCacheName keeps size folder + real name', () {
      final name = tmdbImageCacheName(
        'https://image.tmdb.org/t/p/w342/abc.jpg',
      );
      expect(name, startsWith('tmdb_img_w342_'));
      expect(name, endsWith('_abc.jpg'));
      expect(
        tmdbImageCacheName('https://image.tmdb.org/t/p/w500/abc.jpg'),
        isNot(equals(name)),
      );
    });

    test('normalizeMovieTitle strips rip junk', () {
      expect(
        normalizeMovieTitle('Interstellar.2014.1080p.BluRay.x265'),
        'interstellar',
      );
    });
  });

  group('SavedLink round-trip (v0.7)', () {
    test('json round trip', () {
      const l = SavedLink(name: 'NAS', url: 'smb://192.168.1.5/vids');
      final back = SavedLink.fromJson(l.toJson());
      expect(back.name, 'NAS');
      expect(back.url, 'smb://192.168.1.5/vids');
    });
  });

  group('v0.7 theme palette', () {
    test('white accent is default, surfaces are true black', () {
      expect(accentPalette[defaultAccentIndex], const Color(0xFFFFFFFF));
      expect(AppColors.accent.toARGB32(), 0xFFFFFFFF);
      expect(
        (AppColors.background.r * 255).round() <=
            (AppColors.background.b * 255).round(),
        isTrue,
      );
      expect(AppColors.onAccent, const Color(0xFF0B0B0E));
    });
  });

  group('Drop 4 helpers', () {
    test('statsKeyFor buckets a day', () {
      expect(statsKeyFor(DateTime(2026, 9, 12)), 'stats.20260912');
      expect(statsKeyFor(DateTime(2026, 1, 5)), 'stats.20260105');
    });

    test('weekBucketsFor ends today and spans 7 days', () {
      final now = DateTime(2026, 9, 12);
      final buckets = weekBucketsFor(now);
      expect(buckets.length, 7);
      expect(buckets.first.$2, statsKeyFor(DateTime(2026, 9, 6)));
      expect(buckets.last.$2, statsKeyFor(DateTime(2026, 9, 12)));
    });

    test('formatWatchTime is compact', () {
      expect(formatWatchTime(30), '30s');
      expect(formatWatchTime(59), '59s');
      expect(formatWatchTime(60), '1m');
      expect(formatWatchTime(2700), '45m');
      expect(formatWatchTime(3600), '1h 0m');
      expect(formatWatchTime(5400), '1h 30m');
    });

    test('playbackRates go up to 4x', () {
      expect(PlayerSettings.playbackRates.first, 0.5);
      expect(PlayerSettings.playbackRates.last, 4.0);
      expect(PlayerSettings.playbackRates, containsAll([3.5, 4.0]));
    });

    test('nearestPlaybackRate snaps to 0.25 steps in range', () {
      expect(nearestPlaybackRate(1.0), 1.0);
      expect(nearestPlaybackRate(1.12), 1.0);
      expect(nearestPlaybackRate(1.13), 1.25);
      expect(nearestPlaybackRate(3.6), 3.5);
      expect(nearestPlaybackRate(3.74), 3.75);
      expect(nearestPlaybackRate(0.1), 0.5); // clamps low
      expect(nearestPlaybackRate(9.0), 4.0); // clamps high
      expect(nearestPlaybackRate(2.0), 2.0);
    });
  });

  testWidgets('theme applies dark design language', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const Scaffold(body: Text('ok')),
      ),
    );
    expect(find.text('ok'), findsOneWidget);
    final theme = Theme.of(tester.element(find.text('ok')));
    expect(theme.scaffoldBackgroundColor, AppColors.background);
    expect(theme.brightness, Brightness.dark);
  });

  group('sha256Hex (vault PIN hashing)', () {
    test('empty input (standard vector)', () {
      expect(
        sha256Hex(''),
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      );
    });

    test('"abc" (standard vector)', () {
      expect(
        sha256Hex('abc'),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
    });

    test('deterministic and distinct per input', () {
      expect(sha256Hex('1234'), sha256Hex('1234'));
      expect(sha256Hex('1234'), isNot(sha256Hex('1235')));
    });
  });

  group('NetworkLocation (network storage)', () {
    const loc = NetworkLocation(
      name: 'NAS',
      protocol: 'smb',
      host: '192.168.1.100',
      port: 445,
      path: '/Movies/a.mp4',
      username: 'user',
      password: 'pass',
    );

    test('streamUrl builds user:pass@host:port/path', () {
      expect(loc.streamUrl, 'smb://user:pass@192.168.1.100:445/Movies/a.mp4');
    });

    test('streamUrl omits empty auth and zero port', () {
      const bare = NetworkLocation(
        name: 'x',
        protocol: 'ftp',
        host: '10.0.0.2',
        path: 'share',
      );
      expect(bare.streamUrl, 'ftp://10.0.0.2/share');
    });

    test('round-trips through json', () {
      final rt = NetworkLocation.fromJson(loc.toJson());
      expect(rt.name, loc.name);
      expect(rt.protocol, loc.protocol);
      expect(rt.host, loc.host);
      expect(rt.port, loc.port);
      expect(rt.streamUrl, loc.streamUrl);
    });

    test('parseNetworkLocationsJson drops malformed rows', () {
      final list = parseNetworkLocationsJson(
        '[{"host":"a"},{"name":"no host"}, 42, {"host":"b","protocol":"ftp"}]',
      );
      expect(list.length, 2);
      expect(list.first.host, 'a');
      expect(list.last.host, 'b');
    });

    test('parseNetworkLocationsJson empty on blank', () {
      expect(parseNetworkLocationsJson(null), isEmpty);
      expect(parseNetworkLocationsJson('   '), isEmpty);
    });
  });

  group('SavedServer (open stream)', () {
    test('addSavedServer dedupes by url', () {
      final list = addSavedServer(
        const [],
        const SavedServer(name: 'a', url: 'http://x'),
      );
      expect(list.length, 1);
      final deduped = addSavedServer(
        list,
        const SavedServer(name: 'b', url: 'http://x'),
      );
      expect(deduped.length, 1);
      expect(deduped.single.name, 'a');
    });

    test('serversToJson / parseServersJson round-trip', () {
      const servers = [
        SavedServer(name: 's1', url: 'http://a'),
        SavedServer(name: 's2', url: 'http://b'),
      ];
      final json = serversToJson(servers);
      final back = parseServersJson(json);
      expect(back.length, 2);
      expect(back.map((s) => s.url), ['http://a', 'http://b']);
    });

    test('parseServersJson drops entries without url', () {
      final list = parseServersJson(
        '[{"name":"no url"},{"name":"ok","url":"http://y"}]',
      );
      expect(list.length, 1);
      expect(list.single.url, 'http://y');
    });
  });

  group('isVideoFile (file manager)', () {
    test('recognises common containers', () {
      expect(isVideoFile('/a/b/movie.MKV'), isTrue);
      expect(isVideoFile('clip.mp4'), isTrue);
      expect(isVideoFile('/a/b/rec.m2ts'), isTrue);
    });

    test('rejects non-video', () {
      expect(isVideoFile('song.mp3'), isFalse);
      expect(isVideoFile('photo.jpg'), isFalse);
      expect(isVideoFile('notes.txt'), isFalse);
    });
  });

  group('karaokeWordIndex (word highlight)', () {
    const cue = SrtCue(1000, 5000, 'one two three');

    test('first word at cue start', () {
      expect(karaokeWordIndex(cue, 1000), 0);
    });

    test('middle word around the midpoint', () {
      expect(karaokeWordIndex(cue, 3000), 1);
    });

    test('last word near the end', () {
      expect(karaokeWordIndex(cue, 4999), 2);
    });

    test('clamps before start / after end', () {
      expect(karaokeWordIndex(cue, 0), 0);
      expect(karaokeWordIndex(cue, 9000), 2);
    });

    test('empty text -> -1', () {
      expect(karaokeWordIndex(const SrtCue(0, 1000, '  '), 500), -1);
    });
  });

  group('karaokeActiveCue (cue selection)', () {
    final cues = [
      const SrtCue(0, 500, 'first'),
      const SrtCue(600, 2000, '[Music]'),
      const SrtCue(2100, 3000, 'second'),
    ];

    test('picks the last started cue within its window', () {
      expect(karaokeActiveCue(cues, 2500)?.text, 'second');
    });

    test('music-only captions are skipped', () {
      // at 1500 only the [Music] cue is active -> nothing to show
      expect(karaokeActiveCue(cues, 1500), isNull);
    });

    test('trailing 600 ms grace avoids flicker', () {
      expect(karaokeActiveCue(cues, 3200)?.text, 'second');
      expect(karaokeActiveCue(cues, 3700), isNull);
    });
  });

  group('karaokeCueAt (overlay priority)', () {
    final sidecar = [const SrtCue(0, 2000, 'sidecar line')];

    test('live line wins while it is current', () {
      final live = SrtCue(500, 1500, 'live line');
      expect(karaokeCueAt(live, sidecar, 1200)?.text, 'live line');
    });

    test('falls back to sidecar when the live line ends', () {
      final live = SrtCue(500, 1500, 'live line');
      expect(karaokeCueAt(live, sidecar, 2200)?.text, 'sidecar line');
    });

    test('null when nothing is active', () {
      expect(karaokeCueAt(null, sidecar, 99999), isNull);
      expect(karaokeCueAt(null, null, 0), isNull);
    });
  });

  group('smartLocalMovieAnswer (offline Ask AI fallback)', () {
    const title = 'Test Movie';
    const overview = 'A hero rises. A villain falls. The city is saved.';

    test('worth-watching question cites the TMDB rating', () {
      final a = smartLocalMovieAnswer(
        title: title,
        year: 2020,
        rating: 8.2,
        overview: overview,
        question: 'Is this movie worth watching?',
      );
      expect(a, contains('worth watching'));
      expect(a, contains('8.2/10'));
    });

    test('plot question returns the first three sentences', () {
      final a = smartLocalMovieAnswer(
        title: title,
        year: 2020,
        rating: 8.2,
        overview: overview,
        question: 'Explain the story in 3 lines.',
      );
      expect(a, contains('A hero rises. A villain falls. The city is saved.'));
    });

    test('rating question returns the score', () {
      final a = smartLocalMovieAnswer(
        title: title,
        year: 2020,
        rating: 6.5,
        overview: overview,
        question: 'What is the TMDB rating?',
      );
      expect(a, contains('6.5/10'));
    });

    test('never returns an empty or internet-error answer', () {
      final a = smartLocalMovieAnswer(
        title: title,
        year: 2020,
        rating: 6.5,
        overview: overview,
        question: 'tell me about the ending please',
      );
      expect(a, isNotEmpty);
      expect(a.contains('No internet'), isFalse);
    });
  });

  group('app volume (device-independent, v1.0.10)', () {
    test('clamp holds the 0..200 boost range', () {
      expect(clampAppVolume(-5), 0);
      expect(clampAppVolume(50), 50);
      expect(clampAppVolume(100), 100);
      expect(clampAppVolume(150), 150);
      expect(clampAppVolume(250), 200);
    });

    test('hardware-key steps are 5% notches and saturate at the ends', () {
      expect(stepAppVolume(100, 1), 105);
      expect(stepAppVolume(100, -1), 95);
      expect(stepAppVolume(198, 1), 200);
      expect(stepAppVolume(200, 1), 200);
      expect(stepAppVolume(3, -1), 0);
      expect(stepAppVolume(0, -1), 0);
    });

    test('a 300px swipe spans 100 points; up swipe over 100 enters boost', () {
      expect(swipeAppVolume(100, -300), 200); // full up-swipe -> max boost
      expect(swipeAppVolume(100, 300), 0); // full down-swipe -> mute level
      expect(swipeAppVolume(50, -150), 100);
      expect(swipeAppVolume(180, -300), 200); // clamped at the boost ceiling
      expect(swipeAppVolume(20, 300), 0); // clamped at the floor
    });

    test('boost toggle caps the clamp at 100 when OFF', () {
      expect(clampAppVolumeBoost(150, true), 150);
      expect(clampAppVolumeBoost(150, false), 100);
      expect(clampAppVolumeBoost(50, false), 50);
      expect(clampAppVolumeBoost(250, true), 200);
      expect(clampAppVolumeBoost(250, false), 100);
    });

    test('icon buckets follow level and mute', () {
      expect(appVolumeIconName(0, false), 'off');
      expect(appVolumeIconName(30, false), 'down');
      expect(appVolumeIconName(49.9, false), 'down');
      expect(appVolumeIconName(50, false), 'up');
      expect(appVolumeIconName(150, false), 'up');
      expect(appVolumeIconName(100, true), 'off');
    });

    test(
      'setLevel clamps, unmutes on raise, no-op writes stay silent',
      () async {
        SharedPreferences.setMockInitialValues({});
        final av = AppVolume.instance;
        var pings = 0;
        void onChange() => pings++;
        av.addListener(onChange);
        try {
          await av.setMuted(true);
          pings = 0;
          await av.setLevel(240); // over the boost ceiling -> clamps to 200
          expect(av.level, 200);
          expect(av.muted, isFalse); // raising the volume unmutes
          expect(pings, 1);
          await av.setLevel(200); // no-op
          expect(pings, 1);
        } finally {
          av.removeListener(onChange);
          await av.setMuted(false);
          await av.setLevel(100);
        }
      },
    );
  });

  group('clampPanFor (v1.0.14 pinch-zoom pan)', () {
    const size = Size(360, 800);

    test('zoom 1x: any pan collapses to zero', () {
      expect(
        clampPanFor(pan: const Offset(99, -99), zoom: 1, size: size),
        Offset.zero,
      );
    });

    test('zoom 2x: full symmetric range reachable', () {
      const half = Offset(180, 400); // (z-1)*size/2
      expect(
        clampPanFor(pan: const Offset(9999, 9999), zoom: 2, size: size),
        half,
      );
      expect(
        clampPanFor(pan: const Offset(-9999, -9999), zoom: 2, size: size),
        -half,
      );
    });

    test('inside range passes through untouched', () {
      expect(
        clampPanFor(pan: const Offset(50, -60), zoom: 2, size: size),
        const Offset(50, -60),
      );
    });
  });

  group('pinchPanFor (v1.0.15 focal hinge)', () {
    const size = Size(360, 800);

    test('anchor under the fingers does not move while spreading', () {
      const startFocal = Offset(180, 400);
      // Touch-down at screen center, pan 0, zoom 1 -> zoom 2 keeping fingers.
      final pan = pinchPanFor(
        startFocal: startFocal,
        liveFocal: startFocal,
        startPan: Offset.zero,
        startZoom: 1,
        zoom: 2,
        size: size,
      );
      // center-facing (child-center pivot): pan must stay ZERO — the center
      // of the child IS the pivot, no drift off the finger.
      expect(pan, Offset.zero);
      // Old (origin-pivot) formula would have produced (-180,-400) == drift.
    });

    test('off-center anchor tracks exactly under the fingers', () {
      const startFocal = Offset(90, 200); // top-left quarter
      const liveFocal = Offset(100, 210); // fingers moved slightly
      final pan = pinchPanFor(
        startFocal: startFocal,
        liveFocal: liveFocal,
        startPan: Offset.zero,
        startZoom: 1,
        zoom: 2,
        size: size,
      );
      // Child point under the initial touch: c* in child coords =
      // C + (focal - C)/1 = focal (pan 0, zoom 1 == identity).
      // After zoom 2 about the center, that point lands at:
      //   screen = pan + C + (c* - C) * 2
      // We require screen == liveFocal exactly.
      const c = Offset(180, 400);
      final expected = liveFocal - c - (startFocal - c) * 2;
      expect(pan.dx, closeTo(expected.dx, 1e-6));
      expect(pan.dy, closeTo(expected.dy, 1e-6));
      // Sanity against the old formula (from-origin pivot):
      final old = liveFocal - (startFocal - Offset.zero) * 2;
      expect((pan - old).distance, greaterThan(10)); // not the old behavior
    });

    test('anchor works when already zoomed (recursive hinge)', () {
      // Already at zoom 2 with pan P; pinch again to 3.
      const startPan = Offset(30, 40);
      const startZoom = 2.0;
      const startFocal = Offset(200, 300);
      const liveFocal = Offset(220, 300);
      final pan = pinchPanFor(
        startFocal: startFocal,
        liveFocal: liveFocal,
        startPan: startPan,
        startZoom: startZoom,
        zoom: 3.0,
        size: size,
      );
      // Content point anchored at second-touch-down:
      const c = Offset(180, 400);
      final contentC = c + (startFocal - startPan - c) / startZoom;
      final expected = liveFocal - c - (contentC - c) * 3.0;
      expect(pan.dx, closeTo(expected.dx, 1e-6));
      expect(pan.dy, closeTo(expected.dy, 1e-6));
    });
  });

  group('gestureTickFor (v1.0.17 swipe haptics)', () {
    test('per-percent movement ticks (both directions)', () {
      expect(gestureTickFor(40, 41, 0, 100), GestureTick.tick);
      expect(gestureTickFor(41, 40, 0, 100), GestureTick.tick);
    });

    test('no movement or finger-arrival: no buzz', () {
      expect(gestureTickFor(50, 50, 0, 100), GestureTick.none);
      expect(gestureTickFor(null, 50, 0, 100), GestureTick.none);
    });

    test('hitting 0: edgeLow fires once, then silence', () {
      expect(gestureTickFor(1, 0, 0, 100), GestureTick.edgeLow);
      expect(gestureTickFor(0, 0, 0, 100), GestureTick.none);
      expect(gestureTickFor(1, -3, 0, 100), GestureTick.edgeLow);
      expect(gestureTickFor(-3, -3, 0, 100), GestureTick.none);
    });

    test('hitting the 200 ceiling: edgeHigh once, then silence', () {
      expect(gestureTickFor(199, 200, 0, 200), GestureTick.edgeHigh);
      expect(gestureTickFor(200, 200, 0, 200), GestureTick.none);
      expect(gestureTickFor(199, 210, 0, 200), GestureTick.edgeHigh);
    });

    test('boost OFF: 100 IS the ceiling', () {
      expect(gestureTickFor(98, 110, 0, 100), GestureTick.edgeHigh);
      expect(gestureTickFor(98, 99, 0, 100), GestureTick.tick);
    });
  });
  group('AdMob wiring (v1.0.1+16)', () {
    test('ships with Google demo ids until real units are pasted', () {
      // The app must never go live still pointing at demo units: this pair
      // of getters is the ONLY source of unit ids used by the banner and
      // the exit interstitial.
      expect(MaxAds.kUseTestAds, isTrue);
      expect(MaxAds.bannerUnitId, contains('3940256099942544/6300978111'));
      expect(
        MaxAds.interstitialUnitId,
        contains('3940256099942544/1033173712'),
      );
      expect(MaxAds.bannerUnitId, isNot(MaxAds.interstitialUnitId));
    });

    test('exit interstitial hard cooldown is 3 minutes', () {
      expect(ExitInterstitial.cooldown, const Duration(minutes: 3));
    });
  });
}

