import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maxplayer/theme.dart';
import 'package:maxplayer/models/network_location.dart';
import 'package:maxplayer/models/saved_server.dart';
import 'package:maxplayer/utils/badges.dart';
import 'package:maxplayer/utils/collections.dart';
import 'package:maxplayer/utils/fit.dart';
import 'package:maxplayer/utils/format.dart';
import 'package:maxplayer/utils/m3u.dart';
import 'package:maxplayer/utils/ab_loop.dart';
import 'package:maxplayer/utils/mpv_filters.dart';
import 'package:maxplayer/utils/local_store.dart';
import 'package:maxplayer/utils/resume.dart';
import 'package:maxplayer/utils/settings.dart' show accentPalette, defaultAccentIndex;
import 'package:maxplayer/utils/sha256.dart';
import 'package:maxplayer/utils/sort.dart';
import 'package:maxplayer/utils/tmdb.dart';
import 'package:maxplayer/utils/tmdb_image.dart';
import 'package:maxplayer/utils/video_zoom.dart';
import 'package:maxplayer/services/recommendations.dart';
import 'package:maxplayer/services/ai_suggest.dart';
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
      expect(movies[0].year, 2026);
      expect(movies[0].rating, 8.4);
      expect(tmdbPosterUrl(movies[0].posterPath),
          'https://image.tmdb.org/t/p/w342/abc.jpg');
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
      final f = combineAudioFilters(const [0, 0, 0, 0, 0],
          dialogueBoost: true);
      expect(f.contains('f=1200'), isTrue);
      expect(f.contains('f=3200'), isTrue);
    });
    test('wrong band count throws', () {
      expect(() => buildEqualizerFilter(const [1, 2]),
          throwsArgumentError);
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
      expect(AbState.off.advance(1).advance(2).describe(),
          contains('Looping A → B'));
    });
  });

  group('TMDB deep parsers (Discover port)', () {
    test('parseTmdbDetail fills trailer key via pickTrailerKey', () {
      const d = '{"id":1,"title":"Spider","release_date":"2026-07-29",'
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
      final r = '{"reviews":{"results":[{"author":"Manuel",'
          '"author_details":{"rating":9.0},"content":"Great!"}]}}';
      final list = parseTmdbReviews(r);
      expect(list.single.rating, 9.0);
      expect(list.single.author, 'Manuel');
      expect(tmdbRatingText(list.single.rating!), '9.0');
    });

    test('parseTmdbScreenshots builds w500 urls', () {
      const i = '{"images":{"backdrops":[{"file_path":"/1.jpg"},'
          '{"file_path":"/2.jpg"}]}}';
      final list = parseTmdbScreenshots(i);
      expect(list.length, 2);
      expect(tmdbScreenshotUrl(list.first),
          'https://image.tmdb.org/t/p/w500/1.jpg');
    });

    test('parseTmdbSeasons reads per-season ratings', () {
      const s = '{"seasons":[{"season_number":1,"name":"Season 1",'
          '"episode_count":8,"air_date":"2020-01-01","vote_average":8.4},'
          '{"season_number":0,"episode_count":2}]}';
      final list = parseTmdbSeasons(s);
      expect(list.length, 2);
      expect(list[0].rating, 8.4);
      expect(list[0].year, 2020);
      expect(list[1].name, 'Specials');
    });

    test('parseTmdbSeasonDetail maps episodes', () {
      const s = '{"name":"Season 1","vote_average":8.1,'
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
      const w = '{"watch/providers":{"results":{"IN":{'
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
      const m = '{"results":[{"media_type":"movie","id":1,"title":"A"},'
          '{"media_type":"tv","id":2,"name":"B"},'
          '{"media_type":"person","id":3,"name":"C"}]}';
      final page = parseTmdbMultiPage(m);
      expect(page.items.length, 2);
      expect(page.items[0].kind, 'movie');
      expect(page.items[1].kind, 'tv');
    });

    test('discover cache names + endpoints are deterministic', () {
      expect(discoverCacheName(kDiscoverFilters.first, 1),
          'tmdb_disc_trending_p1.json');
      expect(discoverCacheName(kSeriesFilters.first, 2),
          'tmdb_disc_tv_hindi_tv_p2.json');
      expect(tmdbEndpointPath(kDiscoverFilters.first),
          '/3/trending/movie/week');
      expect(tmdbEndpointPath(kSeriesFilters.last), '/3/discover/tv');
      expect(tmdbDiscoverQuery(kDiscoverFilters[4], 3),
          containsPair('with_original_language', 'hi'));
      expect(tmdbSearchCacheName('Hello World', 1),
          startsWith('tmdb_search_hello_world_'));
    });

    test('kAllFilters merges movie + series chips', () {
      expect(kAllFilters.length,
          kDiscoverFilters.length + kSeriesFilters.length);
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
              'The.Dark.Knight.2008.1080p.BluRay.x265'),
          'dark knight');
      expect(Recommendations.normalizeTitle('[YTS] Inception (2010) [1080p]'),
          'inception');
    });

    test('parseAiSuggestionJson survives prose + fences', () {
      const raw = 'Sure! Here you go: ```json [{"title":"3 Idiots",'
          '"year":2009},{"title":"Dhoom 2","year":2006}] ``` enjoy!';
      final picks = parseAiSuggestionJson(raw);
      expect(picks.length, 2);
      expect(picks.first.title, '3 Idiots');
      expect(picks.first.year, 2009);
      expect(parseAiSuggestionJson('no json here'), isEmpty);
    });

    test('tmdbImageCacheName keeps size folder + real name', () {
      final name =
          tmdbImageCacheName('https://image.tmdb.org/t/p/w342/abc.jpg');
      expect(name, startsWith('tmdb_img_w342_'));
      expect(name, endsWith('_abc.jpg'));
      expect(tmdbImageCacheName('https://image.tmdb.org/t/p/w500/abc.jpg'),
          isNot(equals(name)));
    });

    test('normalizeMovieTitle strips rip junk', () {
      expect(normalizeMovieTitle('Interstellar.2014.1080p.BluRay.x265'),
          'interstellar');
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
      expect((AppColors.background.r * 255).round() <= (AppColors.background.b * 255).round(), isTrue);
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
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: const Scaffold(body: Text('ok')),
    ));
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
          '[{"host":"a"},{"name":"no host"}, 42, {"host":"b","protocol":"ftp"}]');
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
      final list = addSavedServer(const [], const SavedServer(name: 'a', url: 'http://x'));
      expect(list.length, 1);
      final deduped = addSavedServer(list, const SavedServer(name: 'b', url: 'http://x'));
      expect(deduped.length, 1);
      expect(deduped.single.name, 'a');
    });

    test('serversToJson / parseServersJson round-trip', () {
      const servers = [SavedServer(name: 's1', url: 'http://a'), SavedServer(name: 's2', url: 'http://b')];
      final json = serversToJson(servers);
      final back = parseServersJson(json);
      expect(back.length, 2);
      expect(back.map((s) => s.url), ['http://a', 'http://b']);
    });

    test('parseServersJson drops entries without url', () {
      final list = parseServersJson('[{"name":"no url"},{"name":"ok","url":"http://y"}]');
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
}
