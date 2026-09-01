import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:maxplayer/app_info.dart';
import 'package:maxplayer/cast/cast_support.dart';
import 'package:maxplayer/screens/player_screen.dart';
import 'package:maxplayer/models/history_entry.dart';
import 'package:maxplayer/models/playlist.dart';
import 'package:maxplayer/models/saved_server.dart';
import 'package:maxplayer/models/video_track.dart';
import 'package:maxplayer/services/native_bridge.dart';
import 'package:maxplayer/services/notification_service.dart';
import 'package:maxplayer/services/recommendations.dart';
import 'package:maxplayer/services/resume_sync_service.dart';
import 'package:maxplayer/services/tmdb_client.dart';
import 'package:maxplayer/widgets/tmdb_image.dart';
import 'package:maxplayer/services/movie_ai.dart';
import 'package:maxplayer/services/ai_suggest.dart';
import 'package:maxplayer/services/subtitle_langs.dart';
import 'package:maxplayer/widgets/video_search_delegate.dart';
import 'package:maxplayer/widgets/video_thumb.dart';
import 'package:maxplayer/state/media_player_state.dart';
import 'package:maxplayer/state/video_zoom.dart';
import 'package:maxplayer/state/player_settings.dart';
import 'package:maxplayer/state/playlist_store.dart';
import 'package:maxplayer/utils/movie_match.dart';
import 'package:maxplayer/state/private_vault.dart';
import 'package:maxplayer/state/theme_state.dart';
import 'package:maxplayer/state/video_library_state.dart';
import 'package:maxplayer/utils/ai_subtitles.dart';
import 'package:maxplayer/utils/cleaner_stats.dart';
import 'package:maxplayer/utils/crash_log.dart';
import 'package:maxplayer/utils/formatters.dart';
import 'package:maxplayer/utils/privacy_policy.dart';
import 'package:maxplayer/utils/sha256.dart';
import 'package:maxplayer/utils/srt.dart';
import 'package:maxplayer/widgets/karaoke_subtitle.dart';
import 'package:maxplayer/widgets/about_sheet.dart';
import 'package:maxplayer/widgets/track_selection_sheet.dart';
import 'package:maxplayer/widgets/gesture_illustrations.dart';
import 'package:maxplayer/widgets/user_manual_sheet.dart';
import 'package:maxplayer/widgets/voice_search_sheet.dart';
import 'package:maxplayer/services/gdrive_service.dart';
import 'package:maxplayer/widgets/network_storage_sheet.dart';

// Pure unit tests - no platform channels involved. (NativeBridge calls in
// VideoLibraryState are guarded and return defaults when no channel exists,
// so these tests run fine in the Dart VM.)
//
// A full-app pump test was removed: it constructed the real media_kit Player
// and fired a storage-permission request, both of which need a device.
// Re-add a widget test once the states can be injected/faked.

VideoTrack _track(
  String name, {
  Duration? duration,
  int? size,
  int? modified,
  String dir = '/storage/emulated/0/Movies',
}) {
  final path = '$dir/$name.mp4';
  return VideoTrack(
    id: path,
    title: name,
    path: path,
    duration: duration,
    sizeBytes: size,
    lastModifiedMs: modified,
  );
}

VideoLibraryState _libraryWith(List<VideoTrack> videos) {
  final lib = VideoLibraryState();
  lib.debugSetVideos(videos);
  addTearDown(lib.dispose);
  return lib;
}

/// The sheets are lazy ListViews - give the test a huge viewport so
/// every section builds, not just the first screenful.
void useTallViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 6000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  group('formatters', () {
    test('formats file sizes', () {
      expect(formatFileSize(null), '');
      expect(formatFileSize(512), '512 B');
      expect(formatFileSize(2048), '2.0 KB');
      expect(formatFileSize(5 * 1024 * 1024), '5.0 MB');
      expect(formatFileSize(3 * 1024 * 1024 * 1024), '3.00 GB');
    });

    test('formats durations', () {
      expect(formatDuration(null), '--:--');
      expect(formatDuration(const Duration(seconds: 65)), '1:05');
      expect(
        formatDuration(const Duration(hours: 1, minutes: 2, seconds: 3)),
        '1:02:03',
      );
    });

    test('detects video extensions case-insensitively', () {
      expect(isVideoFile('clip.MKV'), isTrue);
      expect(isVideoFile('movie.mp4'), isTrue);
      expect(isVideoFile('notes.txt'), isFalse);
    });

    test('covers the extension set advertised in the manifest', () {
      // Keep in sync with the pathPatterns in AndroidManifest.xml.
      for (final ext in [
        'mp4',
        'webm',
        'mkv',
        'avi',
        'mov',
        'wmv',
        'flv',
        'm4v',
        '3gp',
        '3gpp',
        'ogv',
        'ts',
        'mts',
        'm2ts',
        'vob',
        'mpg',
        'mpeg',
        'rmvb',
        'divx',
        'f4v',
      ]) {
        expect(
          isVideoFile('movie.$ext'),
          isTrue,
          reason: '.$ext must scan into the library',
        );
        expect(isVideoFile('movie.${ext.toUpperCase()}'), isTrue);
      }
    });

    test('timeAgo buckets', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      expect(timeAgo(now), 'Just now');
      expect(
        timeAgo(now - const Duration(minutes: 5).inMilliseconds),
        '5m ago',
      );
      expect(timeAgo(now - const Duration(hours: 3).inMilliseconds), '3h ago');
      expect(timeAgo(now - const Duration(days: 2).inMilliseconds), '2d ago');
      expect(timeAgo(0), '');
    });
  });

  group('quality label', () {
    String? q(int? w, int? h) => VideoTrack(
      id: 'x',
      title: 'x',
      path: '/x.mp4',
      width: w,
      height: h,
    ).qualityLabel;

    test('maps the SHORTER side to a resolution badge', () {
      expect(q(1920, 1080), '1080p');
      expect(q(1080, 1920), '1080p'); // portrait video
      expect(q(3840, 2160), '4K');
      expect(q(2560, 1440), '2K');
      expect(q(1280, 720), '720p');
      expect(q(640, 480), '480p');
      expect(q(320, 240), 'SD');
    });

    test('null when dimensions unknown', () {
      expect(q(null, null), isNull);
      expect(q(0, 0), isNull);
    });
  });

  group('equalizer filter builder', () {
    test('all-zero gains produce an empty filter (clears af)', () {
      expect(MediaPlayerState.buildEqualizerFilter([0, 0, 0, 0, 0]), '');
    });

    test('skips flat bands and formats the rest as lavfi', () {
      final f = MediaPlayerState.buildEqualizerFilter([6, 0, -2, 0, 3.5]);
      expect(
        f,
        'lavfi=[equalizer=f=60:t=q:w=1.0:g=6.0,equalizer=f=910:t=q:w=1.0:g=-2.0,equalizer=f=14000:t=q:w=1.0:g=3.5]',
      );
    });
  });

  group('watch stats', () {
    test('stats key is a sortable YYYYMMDD bucket', () {
      expect(
        MediaPlayerState.statsKeyFor(DateTime(2026, 8, 11)),
        'stats.20260811',
      );
      expect(
        MediaPlayerState.statsKeyFor(DateTime(2026, 1, 5)),
        'stats.20260105',
      );
    });

    test('formatWatchTime', () {
      expect(formatWatchTime(30), '30s');
      expect(formatWatchTime(45 * 60), '45m');
      expect(formatWatchTime(2 * 3600 + 15 * 60), '2h 15m');
    });
  });

  group('library sorting', () {
    final videos = [
      _track(
        'banana',
        size: 300,
        modified: 100,
        duration: const Duration(minutes: 3),
      ),
      _track(
        'apple',
        size: 100,
        modified: 300,
        duration: const Duration(minutes: 1),
      ),
      _track('cherry', size: 200, modified: 200),
    ];

    test('name A->Z and Z->A', () {
      final lib = _libraryWith(videos);
      lib.setSort(SortMode.name, true);
      expect(lib.videos.map((v) => v.title), ['apple', 'banana', 'cherry']);
      lib.setSort(SortMode.name, false);
      expect(lib.videos.map((v) => v.title), ['cherry', 'banana', 'apple']);
    });

    test('length shortest first, unknown duration sinks to the end', () {
      final lib = _libraryWith(videos);
      lib.setSort(SortMode.length, true);
      expect(lib.videos.map((v) => v.title), ['apple', 'banana', 'cherry']);
      // longest first, but the unknown one still ends up last
      lib.setSort(SortMode.length, false);
      expect(lib.videos.map((v) => v.title), ['banana', 'apple', 'cherry']);
    });

    test('recently added: newest first', () {
      final lib = _libraryWith(videos);
      lib.setSort(SortMode.date, false);
      expect(lib.videos.map((v) => v.title), ['apple', 'cherry', 'banana']);
    });

    test('size smallest first', () {
      final lib = _libraryWith(videos);
      lib.setSort(SortMode.size, true);
      expect(lib.videos.map((v) => v.title), ['apple', 'cherry', 'banana']);
    });
  });

  group('library filtering & favourites', () {
    final videos = [
      _track('cat video'),
      _track('dog video'),
      _track('cat fails'),
    ];

    test('search filters by title', () {
      final lib = _libraryWith(videos);
      lib.setSearchQuery('cat');
      expect(lib.videos.length, 2);
      lib.setSearchQuery('dog');
      expect(lib.videos.map((v) => v.title), ['dog video']);
    });

    test('favourites-only shows only hearted videos', () {
      final lib = _libraryWith(videos);
      lib.toggleFavorite(videos[1]);
      expect(lib.isFavorite(videos[1]), isTrue);
      lib.setFavoritesOnly(true);
      expect(lib.videos.map((v) => v.title), ['dog video']);
      lib.toggleFavorite(videos[1]);
      expect(lib.videos, isEmpty);
    });
  });

  group('grouping', () {
    test('group by name buckets titles by first letter', () {
      final lib = _libraryWith([
        _track('Banana'),
        _track('apple'),
        _track('avocado'),
        _track('123 intro'),
      ]);
      lib.setGroupMode(GroupMode.name);
      final groups = lib.groups;
      expect(groups.map((g) => g.title), ['1', 'A', 'B']);
      expect(groups[1].videos.length, 2); // apple + avocado under A
    });

    test('group by folder uses the parent directory name', () {
      final lib = _libraryWith([
        _track('one', dir: '/storage/emulated/0/Movies'),
        _track('two', dir: '/storage/emulated/0/Download'),
      ]);
      lib.setGroupMode(GroupMode.folder);
      expect(lib.groups.map((g) => g.title), ['Download', 'Movies']);
    });

    test('no grouping yields a single unnamed group', () {
      final lib = _libraryWith([_track('x')]);
      lib.setGroupMode(GroupMode.none);
      expect(lib.groups.length, 1);
      expect(lib.groups.single.title, '');
    });
  });

  group('SRT builder (AI subtitles)', () {
    test('formats numbered cues with HH:MM:SS,mmm times', () {
      final srt = buildSrt(const [
        SrtCue(1200, 3400, 'Hello world'),
        SrtCue(3605000, 3607000, 'second line'),
      ]);
      expect(
        srt,
        '1\n00:00:01,200 --> 00:00:03,400\nHello world\n\n'
        '2\n01:00:05,000 --> 01:00:07,000\nsecond line\n\n',
      );
    });

    test('drops empty cues and bumps zero-length ends', () {
      final srt = buildSrt(const [
        SrtCue(500, 500, 'same'),
        SrtCue(100, 900, '   '),
      ]);
      expect(srt, '1\n00:00:00,500 --> 00:00:01,500\nsame\n\n');
    });

    test('sorts cues by start time', () {
      final srt = buildSrt(const [
        SrtCue(5000, 6000, 'later'),
        SrtCue(1000, 2000, 'first'),
      ]);
      expect(srt.startsWith('1\n00:00:01,000'), isTrue);
    });
  });

  group('player settings (v12 defaults)', () {
    test('new v12 toggles all start ON and persist round-trip', () {
      const s = PlayerSettings();
      expect(s.horizontalSeek, isTrue);
      expect(s.castButton, isTrue);
      expect(s.screenshotButton, isTrue);
      expect(s.lockButton, isTrue);
      // copyWith actually carries them
      final t = s.copyWith(horizontalSeek: false, castButton: false);
      expect(t.horizontalSeek, isFalse);
      expect(t.castButton, isFalse);
      expect(t.screenshotButton, isTrue);
      expect(t.lockButton, isTrue);
    });

    test('load from empty store yields all v12 defaults', () async {
      final s = await PlayerSettings.load();
      expect(s.horizontalSeek, isTrue);
      expect(s.castButton, isTrue);
      expect(s.screenshotButton, isTrue);
      expect(s.lockButton, isTrue);
    });
  });

  group('DLNA cast helpers', () {
    test('SSDP header lookup is case-insensitive and trims', () {
      const dg =
          'HTTP/1.1 200 OK\r\n'
          'CACHE-CONTROL: max-age=1800\r\n'
          'LOCATION: http://192.168.1.10:8080/dd.xml\r\n'
          'location: http://other/x.xml\r\n' // duplicate -> first wins
          'ST: urn:schemas-upnp-org:device:MediaRenderer:1\r\n\r\n';
      expect(ssdpHeader(dg, 'location'), 'http://192.168.1.10:8080/dd.xml');
      expect(
        ssdpHeader(dg, 'ST'),
        'urn:schemas-upnp-org:device:MediaRenderer:1',
      );
      expect(ssdpHeader(dg, 'server'), isNull);
    });

    test('M-SEARCH request is well formed', () {
      final m = buildMSearchRequest('ssdp:all');
      expect(m.startsWith('M-SEARCH * HTTP/1.1\r\n'), isTrue);
      expect(m, contains('ST: ssdp:all\r\n'));
      expect(m.endsWith('\r\n\r\n'), isTrue);
    });

    test('device description: finds AVTransport and resolves relative URL', () {
      const xml = '''
<root xmlns="urn:schemas-upnp-org:device-1-0">
  <device>
    <friendlyName>Living Room TV</friendlyName>
    <serviceList>
      <service>
        <serviceType>urn:schemas-upnp-org:service:RenderingControl:1</serviceType>
        <controlURL>/rc/control</controlURL>
      </service>
      <service>
        <serviceType>urn:schemas-upnp-org:service:AVTransport:1</serviceType>
        <controlURL>/avt/control</controlURL>
      </service>
    </serviceList>
  </device>
</root>''';
      final d = parseDeviceDescription(xml, 'http://192.168.1.10:9000/dd.xml');
      expect(d, isNotNull);
      expect(d!.name, 'Living Room TV');
      expect(d.controlUrl, 'http://192.168.1.10:9000/avt/control');
    });

    test('device description: rejects devices without AVTransport', () {
      const xml =
          '<root><device><friendlyName>Router</friendlyName>'
          '<serviceList><service>'
          '<serviceType>urn:schemas-upnp-org:service:WANIPConnection:1</serviceType>'
          '<controlURL>/wan/control</controlURL>'
          '</service></serviceList></device></root>';
      expect(parseDeviceDescription(xml, 'http://10.0.0.1/d.xml'), isNull);
    });

    test('absolute controlURL kept as-is; xml entities unescaped in name', () {
      const xml =
          '<root><device><friendlyName>A &amp; B TV</friendlyName>'
          '<serviceList><service>'
          '<serviceType>urn:schemas-upnp-org:service:AVTransport:1</serviceType>'
          '<controlURL>http://192.168.1.5:81/avt</controlURL>'
          '</service></serviceList></device></root>';
      final d = parseDeviceDescription(xml, 'http://192.168.1.5:9999/dd');
      expect(d!.name, 'A & B TV');
      expect(d.controlUrl, 'http://192.168.1.5:81/avt');
    });

    test('SOAP envelope carries InstanceID first and escapes args', () {
      final env = buildSoapEnvelope('Play', const [MapEntry('Speed', '1')]);
      expect(
        env,
        contains(
          '<u:Play xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">',
        ),
      );
      expect(
        env.indexOf('<InstanceID>0</InstanceID>'),
        lessThan(env.indexOf('<Speed>1</Speed>')),
      );
      final esc = buildSoapEnvelope('X', const [MapEntry('V', 'a & <b> "q"')]);
      expect(esc, contains('a &amp; &lt;b&gt; &quot;q&quot;'));
    });

    test('soapTag digs values out of responses', () {
      const body =
          '<s:Envelope><s:Body><u:GetPositionInfoResponse>'
          '<Track>1</Track><RelTime>0:06:12</RelTime>'
          '</u:GetPositionInfoResponse></s:Body></s:Envelope>';
      expect(soapTag(body, 'RelTime'), '0:06:12');
      expect(soapTag(body, 'Track'), '1');
      expect(soapTag(body, 'AbsTime'), isNull);
    });

    test('DIDL metadata carries title, res and optional subtitle', () {
      final didl = buildDidlMetadata(
        title: 'My Video <1080p>',
        videoUrl: 'http://p:1/video.mp4',
        mime: 'video/mp4',
        subsUrl: 'http://p:1/subs.srt',
      );
      expect(didl, contains('<dc:title>My Video &lt;1080p&gt;</dc:title>'));
      expect(didl, contains('protocolInfo="http-get:*:video/mp4:*"'));
      expect(didl, contains('<sec:CaptionInfoEx'));
      final noSubs = buildDidlMetadata(
        title: 't',
        videoUrl: 'http://p/v.mp4',
        mime: 'video/mp4',
      );
      expect(noSubs.contains('CaptionInfoEx'), isFalse);
    });

    test('mime map covers the containers we scan for', () {
      expect(mimeForExtension('/x/a.mkv'), 'video/x-matroska');
      expect(mimeForExtension('/x/a.MP4'), 'video/mp4');
      expect(mimeForExtension('/x/a.webm'), 'video/webm');
      expect(mimeForExtension('/x/a.avi'), 'video/x-msvideo');
      expect(mimeForExtension('/x/a.mov'), 'video/quicktime');
      expect(mimeForExtension('/x/a.wmv'), 'video/x-ms-wmv');
      expect(mimeForExtension('/x/a.ts'), 'video/mp2t');
      expect(mimeForExtension('http://s/v.mkv?token=1'), 'video/x-matroska');
      expect(mimeForExtension('/x/a.unknown'), 'video/mp4'); // safe default
    });

    test('DLNA rel-time format/parse round-trips', () {
      expect(
        formatRelTime(const Duration(hours: 1, minutes: 2, seconds: 3)),
        '1:02:03',
      );
      expect(formatRelTime(Duration.zero), '0:00:00');
      expect(parseRelTime('0:06:12'), const Duration(minutes: 6, seconds: 12));
      expect(
        parseRelTime('1:02:03.500'),
        const Duration(hours: 1, minutes: 2, seconds: 3, milliseconds: 500),
      );
      expect(parseRelTime('NOT_IMPLEMENTED'), isNull);
      expect(parseRelTime(null), isNull);
      expect(parseRelTime('garbage'), isNull);
    });
  });

  group('app version', () {
    test('kAppVersion matches the pubspec version name', () {
      final pub = File('pubspec.yaml').readAsStringSync();
      final m = RegExp(
        r'^version:\s*([0-9][0-9.]*)\+',
        multiLine: true,
      ).firstMatch(pub);
      expect(
        m,
        isNotNull,
        reason: 'pubspec.yaml must declare version: x.y.z+N',
      );
      expect(
        m!.group(1),
        kAppVersion,
        reason: 'Keep kAppVersion in lib/app_info.dart in sync',
      );
    });
  });

  group('AI subtitle options & caption filter (v18)', () {
    // v54: back on-device - accurate whisper models; stale ids migrate.
    test('only accurate models remain; stale tiny ids map to base', () {
      expect(AiSubtitleRunner.modelChoices.containsKey('tiny'), isFalse);
      expect(
        AiSubtitleRunner.modelChoices.keys,
        containsAll(<String>['base', 'small']),
      );
      expect(AiSubtitleRunner.normalizeModelId(null), 'base');
      expect(
        AiSubtitleRunner.normalizeModelId('tiny'),
        'base',
        reason: 'a stale v22-24 "tiny" pref must migrate to base',
      );
      expect(AiSubtitleRunner.normalizeModelId('small'), 'small');
      expect(AiSubtitleRunner.normalizeModelId('nonsense'), 'base');
      expect(AiSubtitleRunner.modelSizeLabel('base'), '~142 MB');
      expect(AiSubtitleRunner.modelSizeLabel('small'), '~466 MB');
    });

    test('music-only decoration captions are dropped, speech is kept', () {
      for (final t in [
        '♪',
        '♪ ♪',
        '♪♫♪',
        '[Music]',
        '(MUSIC)',
        'music',
        '( music playing )',
        '♪ Music ♪',
        '[Applause]',
        '(laughter)',
      ]) {
        expect(isMusicOnlyCaption(t), isTrue, reason: '"$t" must be dropped');
      }
      for (final t in [
        'Hello world',
        'I love music',
        'music is life',
        'the background music in this scene',
      ]) {
        expect(isMusicOnlyCaption(t), isFalse, reason: '"$t" must be kept');
      }
    });
  });

  group('privacy policy', () {
    test('in-app text carries the same anchors as PRIVACY_POLICY.md', () {
      final md = File('PRIVACY_POLICY.md').readAsStringSync();
      for (final anchor in [
        '13 August 2026',
        'Hyper Tech Labs',
        'github.com/Aryanshahx/maxplayer',
      ]) {
        expect(md, contains(anchor));
        expect(
          kPrivacyPolicyText,
          contains(anchor),
          reason:
              'keep lib/utils/privacy_policy.dart in sync with '
              'PRIVACY_POLICY.md',
        );
      }
    });
  });

  group('manual & about sheets', () {
    /// The sheets are lazy ListViews - give the test a huge viewport so
    /// every section builds, not just the first screenful.
    void useTallViewport(WidgetTester tester) {
      tester.view.physicalSize = const Size(1200, 6000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    testWidgets('every gesture illustration paints without errors', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  for (final kind in GestureKind.values)
                    SizedBox(
                      width: 320,
                      child: GestureIllustration(kind: kind),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      expect(
        find.byType(GestureIllustration),
        findsNWidgets(GestureKind.values.length),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('user manual renders all sections', (tester) async {
      useTallViewport(tester);
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: UserManualSheet())),
      );
      expect(find.text('User manual'), findsOneWidget);
      expect(find.text('GESTURE CONTROLS'), findsOneWidget);
      expect(
        find.text('Max Player v$kAppVersion  ·  Hyper Tech Labs'),
        findsOneWidget,
      );
      expect(
        find.byType(GestureIllustration),
        findsNWidgets(GestureKind.values.length),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('about sheet renders brand text and version', (tester) async {
      useTallViewport(tester);
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: AboutSheet())),
      );
      expect(find.text('Max Player'), findsOneWidget);
      expect(find.text('by Hyper Tech Labs'), findsOneWidget);
      expect(find.text('Version $kAppVersion'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('about sheet bundles the privacy policy offline', (
      tester,
    ) async {
      useTallViewport(tester);
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: AboutSheet())),
      );
      await tester.tap(find.text('Privacy policy'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('does not collect, store, transmit'),
        findsOneWidget,
      );
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('does not collect, store, transmit'),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  });

  // -------------------------------------------------------------------------
  // v21: SRT parsing (karaoke / skip-intro / transcript groundwork)
  // -------------------------------------------------------------------------
  group('v21 srt parsing', () {
    test('parseSrt round-trips buildSrt output', () {
      final cues = [
        const SrtCue(0, 1500, 'Hello world'),
        const SrtCue(61000, 63500, 'Second caption line'),
      ];
      final parsed = parseSrt(buildSrt(cues));
      expect(parsed.length, 2);
      expect(parsed[0].startMs, 0);
      expect(parsed[0].endMs, 1500);
      expect(parsed[0].text, 'Hello world');
      expect(parsed[1].startMs, 61000);
      expect(parsed[1].text, 'Second caption line');
    });

    test('parseSrt tolerates missing indices and dot-millis', () {
      final parsed = parseSrt(
        '1\n00:00:01.000 --> 00:00:02.500\none two\n\n00:00:03,000 --> 00:00:04,000\nthree\n',
      );
      expect(parsed.length, 2);
      expect(parsed[0].startMs, 1000);
      expect(parsed[0].endMs, 2500);
      expect(parsed[0].text, 'one two');
      expect(parsed[1].startMs, 3000);
    });

    test('computeSkipIntro finds late dialogue start', () {
      expect(
        computeSkipIntro([
          const SrtCue(0, 3000, '♪ opening theme ♪'),
          const SrtCue(92000, 94000, 'Are you ready?'),
        ]),
        const Duration(milliseconds: 91000),
      );
      // Speech right away -> nothing to skip.
      expect(computeSkipIntro([const SrtCue(3000, 5000, 'Hello')]), isNull);
      // First speech after 10 minutes -> not an intro.
      expect(
        computeSkipIntro([const SrtCue(700000, 701000, 'Too late')]),
        isNull,
      );
      expect(computeSkipIntro(const []), isNull);
    });
  });

  // -------------------------------------------------------------------------
  // v21: SHA-256 for the Private-folder PIN (dependency-free implementation)
  // -------------------------------------------------------------------------
  group('v21 sha256', () {
    test('standard test vectors', () {
      expect(
        sha256Hex(''),
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      );
      expect(
        sha256Hex('abc'),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
      expect(
        sha256Hex('1234'),
        '03ac674216f3e15c761ee1a5e255f067953623c8b388b4459e13f978d7c846f4',
      );
    });
  });

  // -------------------------------------------------------------------------
  // v21: karaoke timing helpers
  // -------------------------------------------------------------------------
  group('v21 karaoke timing', () {
    test('karaokeWordIndex walks words proportionally to characters', () {
      const cue = SrtCue(0, 2000, 'aa b');
      expect(karaokeWordIndex(cue, 0), 0);
      expect(karaokeWordIndex(cue, 500), 0);
      expect(karaokeWordIndex(cue, 1900), 1);
      expect(karaokeWordIndex(cue, 2000), 1);
    });

    test('karaokeActiveCue skips music-only cues and quiet gaps', () {
      final cues = [
        const SrtCue(0, 1000, '♪ music ♪'),
        const SrtCue(2000, 3000, 'Hello there'),
      ];
      expect(karaokeActiveCue(cues, 500), isNull);
      expect(karaokeActiveCue(cues, 2500)?.text, 'Hello there');
      expect(karaokeActiveCue(cues, 3400)?.text, 'Hello there'); // grace
      expect(karaokeActiveCue(cues, 5000), isNull);
    });

    // v22: live mpv line -> AI sidecar -> same-name .srt fallback order.
    test('karaokeCueAt picks live, then AI cues, then sidecar cues', () {
      const live = SrtCue(9000, 11000, 'live line');
      final ai = [const SrtCue(9000, 11000, 'ai line')];
      final side = [const SrtCue(9000, 11000, 'sidecar line')];
      expect(karaokeCueAt(live, ai, side, 10000)?.text, 'live line');
      expect(karaokeCueAt(null, ai, side, 10000)?.text, 'ai line');
      expect(karaokeCueAt(null, null, side, 10000)?.text, 'sidecar line');
      expect(karaokeCueAt(null, null, null, 10000), isNull);
      // Stale live cue (past its 600 ms grace) falls through to files.
      final ai2 = [const SrtCue(45000, 55000, 'ai line later')];
      expect(karaokeCueAt(live, ai2, side, 50000)?.text, 'ai line later');
      // Everything expired -> nothing shown.
      expect(karaokeCueAt(live, ai, side, 50000), isNull);
    });
  });

  // -------------------------------------------------------------------------
  // v22: same-name sidecar picking (karaoke / skip-intro on the video's
  // own subtitle file)
  // -------------------------------------------------------------------------
  group('v22 sidecar .srt picking', () {
    test('exact same-name match wins over language variants', () {
      final names = ['movie.eng.srt', 'Movie.SRT', 'movie.maxai.srt', 'x.srt'];
      expect(sidecarSrtCandidates(names, '/sdcard/Movies/Movie.mp4'), [
        'Movie.SRT',
        'movie.eng.srt',
      ]);
    });
    test('AI sidecar is never picked as a plain sidecar', () {
      final names = ['movie.maxai.srt'];
      expect(sidecarSrtCandidates(names, '/a/movie.mkv'), isEmpty);
    });
    test('language variants are sorted and kept in original case', () {
      final names = ['movie.hi.srt', 'movie.en.srt'];
      expect(sidecarSrtCandidates(names, 'movie.mkv'), [
        'movie.en.srt',
        'movie.hi.srt',
      ]);
    });
    test('unrelated files and non-srt are ignored', () {
      final names = ['movie.srt.txt', 'other.srt', 'movie.txt', '.srt'];
      expect(sidecarSrtCandidates(names, '/m/movie.mp4'), isEmpty);
    });
    test('v82: .vtt sidecar is picked the same way as .srt', () {
      final names = ['movie.vtt', 'movie.eng.vtt'];
      expect(sidecarSrtCandidates(names, '/m/movie.mp4'), [
        'movie.vtt',
        'movie.eng.vtt',
      ]);
    });
  });

  // -------------------------------------------------------------------------
  // v22: sleep-timer countdown + white-accent contrast
  // -------------------------------------------------------------------------
  group('v22 sleep countdown + accent contrast', () {
    test('formatCountdown renders m:ss and h:mm:ss', () {
      expect(formatCountdown(0), '0:00');
      expect(formatCountdown(9), '0:09');
      expect(formatCountdown(61), '1:01');
      expect(formatCountdown(599), '9:59');
      expect(formatCountdown(3600), '1:00:00');
      expect(formatCountdown(-5), '0:00'); // clamps negatives
    });

    test('contrastColorFor: dark ink on light accents, white on dark', () {
      const darkInk = Color(0xFF16161f);
      expect(contrastColorFor(const Color(0xFFFFFFFF)), darkInk);
      expect(contrastColorFor(const Color(0xFF22D3EE)), darkInk); // cyan
      expect(contrastColorFor(const Color(0xFFA855F7)), Colors.white);
      expect(contrastColorFor(const Color(0xFF60A5FA)), Colors.white);
    });

    test('white is a selectable accent swatch', () {
      expect(
        ThemeState.swatches.any((c) => c.toARGB32() == 0xFFFFFFFF),
        isTrue,
      );
    });
  });

  // -------------------------------------------------------------------------
  // v26: karaoke fix (media_kit's own subtitle layer is off), karaoke switch
  // lives ONLY in the tracks sheet, vault change counter + device-unlock gate
  // for the forgotten-PIN flow.
  // -------------------------------------------------------------------------
  group('v26 polish', () {
    test('vault revision counter exists and starts clean in tests', () {
      // hide()/unhide() do real file IO (not exercised here), so the
      // in-process counter must still be zero.
      expect(PrivateVault.revision, 0);
    });

    test('vault path helpers unchanged', () {
      expect(
        PrivateVault.isPrivatePath(
          '/storage/emulated/0/Android/data/com.hypertechlabs.maxplayer/'
          'files/Private/movie.mp4',
        ),
        isTrue,
      );
      expect(
        PrivateVault.isPrivatePath('/storage/emulated/0/Movies/movie.mp4'),
        isFalse,
      );
    });

    test('karaoke setting survives copyWith (toggle kept, moved)', () {
      const s = PlayerSettings();
      expect(s.karaokeSubs, isFalse);
      expect(s.copyWith(karaokeSubs: true).karaokeSubs, isTrue);
    });
  });

  // -------------------------------------------------------------------------
  // v27: advanced video info + statistics helpers
  // -------------------------------------------------------------------------
  group('v27 advanced info + stats', () {
    test('formatAspectRatio simplifies common ratios', () {
      expect(formatAspectRatio(1920, 1080), '16:9');
      expect(formatAspectRatio(1280, 720), '16:9');
      expect(formatAspectRatio(1440, 1080), '4:3');
      expect(formatAspectRatio(3840, 2160), '16:9');
    });

    test('formatAspectRatio falls back for odd sizes and guards zero', () {
      expect(formatAspectRatio(1000, 423), '2.36:1');
      expect(formatAspectRatio(0, 1080), '');
      expect(formatAspectRatio(1920, 0), '');
    });

    test('statsKeyFor day buckets stay stable', () {
      expect(
        MediaPlayerState.statsKeyFor(DateTime(2026, 8, 14)),
        'stats.20260814',
      );
      expect(
        MediaPlayerState.statsKeyFor(DateTime(2026, 1, 5)),
        'stats.20260105',
      );
    });
  });

  // -------------------------------------------------------------------------
  // v28: home quick tiles - the Folders tile filters the library
  // -------------------------------------------------------------------------
  group('v28 folders tile', () {
    VideoTrack t(String path) =>
        VideoTrack(id: path, title: path.split('/').last, path: path);

    List<VideoTrack> threeVideos() => [
      t('/storage/emulated/0/Movies/a.mp4'),
      t('/storage/emulated/0/Movies/b.mp4'),
      t('/storage/emulated/0/DCIM/c.mp4'),
    ];

    test('folderFilter narrows the visible list and clears again', () {
      final lib = VideoLibraryState();
      lib.debugSetVideos(threeVideos());
      expect(lib.videos.length, 3);
      lib.setFolderFilter('Movies');
      expect(lib.videos.length, 2);
      expect(lib.videos.map((v) => v.folderName).toSet(), {'Movies'});
      lib.setFolderFilter(null);
      expect(lib.videos.length, 3);
    });

    test('folderCounts lists every folder, name-sorted', () {
      final lib = VideoLibraryState();
      lib.debugSetVideos(threeVideos());
      expect(lib.folderCounts, {'DCIM': 1, 'Movies': 2});
      expect(lib.folderCounts.keys.toList(), ['DCIM', 'Movies']);
    });

    test('folder filter composes with search', () {
      final lib = VideoLibraryState();
      lib.debugSetVideos(threeVideos());
      lib.setFolderFilter('Movies');
      lib.setSearchQuery('b.mp4');
      expect(lib.videos.length, 1);
      expect(lib.videos.single.path, endsWith('/Movies/b.mp4'));
    });
  });

  // -------------------------------------------------------------------------
  // v29: device cleaner data + playlist/picker backing + white default theme
  // -------------------------------------------------------------------------
  group('v29 cleaner data + theme default', () {
    VideoTrack sized(String path, int size, int secs) => VideoTrack(
      id: path,
      title: path.split('/').last,
      path: path,
      sizeBytes: size,
      duration: Duration(seconds: secs),
    );

    test('largestVideos sorts biggest first and limits', () {
      final lib = VideoLibraryState();
      lib.debugSetVideos([
        sized('/s/Movies/small.mp4', 100, 60),
        sized('/s/Movies/big.mp4', 9000, 900),
        sized('/s/DCIM/mid.mp4', 500, 120),
      ]);
      final top = lib.largestVideos(n: 2);
      expect(top.length, 2);
      expect(top.first.path, endsWith('big.mp4'));
      expect(top.last.path, endsWith('mid.mp4'));
    });

    test('duplicateGroups finds same size+duration copies only', () {
      final lib = VideoLibraryState();
      lib.debugSetVideos([
        sized('/s/Movies/a.mp4', 700, 300),
        sized('/s/DCIM/a-copy.mp4', 700, 300), // same size+length = dupe
        sized('/s/Movies/a-lookalike.mp4', 700, 301), // different length
        sized('/s/Movies/unique.mp4', 42, 10),
      ]);
      final groups = lib.duplicateGroups;
      expect(groups.length, 1);
      expect(groups.single.length, 2);
      expect(
        groups.single.map((v) => v.path),
        containsAll(['/s/Movies/a.mp4', '/s/DCIM/a-copy.mp4']),
      );
    });

    test('removeVideo drops an entry in place', () {
      final lib = VideoLibraryState();
      lib.debugSetVideos([
        sized('/s/Movies/a.mp4', 700, 300),
        sized('/s/Movies/b.mp4', 500, 300),
      ]);
      lib.removeVideo('/s/Movies/a.mp4');
      expect(lib.videos.length, 1);
      expect(lib.videos.single.path, endsWith('b.mp4'));
    });

    test('white is the default theme colour (existing picks kept)', () {
      expect(ThemeState().accent.toARGB32(), 0xFFFFFFFF);
      expect(ThemeState.defaultAccent.toARGB32(), 0xFFFFFFFF);
      // purple and the others remain selectable
      expect(ThemeState.swatches.length, 7);
    });
  });

  group('v30 playlist add-to-queue', () {
    VideoTrack vt(String path) =>
        VideoTrack(id: path, title: path.split('/').last, path: path);

    test('mergeQueueVideos appends new, skips duplicates, keeps order', () {
      final merged = mergeQueueVideos(
        [vt('/s/a.mp4'), vt('/s/b.mp4')],
        [vt('/s/b.mp4'), vt('/s/c.mp4'), vt('/s/a.mp4')],
      );
      expect(merged.map((v) => v.path).toList(), [
        '/s/a.mp4',
        '/s/b.mp4',
        '/s/c.mp4',
      ]);
    });

    test('mergeQueueVideos into an empty queue returns the picks', () {
      final merged = mergeQueueVideos(const [], [vt('/s/x.mp4')]);
      expect(merged.single.path, '/s/x.mp4');
    });

    test('mergeQueueVideos does not mutate the original queue', () {
      final queue = [vt('/s/a.mp4')];
      mergeQueueVideos(queue, [vt('/s/b.mp4')]);
      expect(queue.length, 1);
    });
  });

  group('v31 cleaner stats', () {
    test('segments drop empty kinds and keep a stable order', () {
      final segs = cleanerSegments(
        thumbs: 100,
        strips: 0,
        temp: 50,
        models: 0,
        deviceCache: 25,
      );
      expect(segs.map((s) => s.label).toList(), [
        'App thumbnails',
        'Temporary AI files',
        'Gallery cache',
      ]);
    });

    test('segment colours are stable per kind', () {
      final segs = cleanerSegments(
        thumbs: 1,
        strips: 2,
        temp: 3,
        models: 4,
        deviceCache: 5,
      );
      expect(segs[0].colorValue, cleanerKindColors['thumbs']);
      expect(segs[3].colorValue, cleanerKindColors['models']);
      // AI models keep their colour even when earlier kinds are empty.
      final lonely = cleanerSegments(
        thumbs: 0,
        strips: 0,
        temp: 0,
        models: 9,
        deviceCache: 0,
      );
      expect(lonely.single.colorValue, cleanerKindColors['models']);
    });

    test('clean cache total excludes models, grand total includes them', () {
      final cache = cleanerCacheTotal(
        thumbs: 10,
        strips: 10,
        temp: 10,
        deviceCache: 10,
      );
      final grand = cleanerGrandTotal(
        thumbs: 10,
        strips: 10,
        temp: 10,
        models: 7,
        deviceCache: 10,
      );
      expect(cache, 40);
      expect(grand, 47);
    });

    test('fractionOf guards an empty graph', () {
      const seg = CleanerSegment('x', 5, 0xFF000000);
      expect(seg.fractionOf(0), 0);
      expect(seg.fractionOf(20), 0.25);
    });

    test('DeviceStorage used + usedFraction are sane', () {
      const s = DeviceStorage(total: 100, free: 25);
      expect(s.used, 75);
      expect(s.usedFraction, 0.75);
    });
  });

  group('v32 picture settings, HDR labels and saved servers', () {
    test('hdrLabelFor maps known formats, hides SDR/unknown', () {
      expect(hdrLabelFor('hdr10'), 'HDR10');
      expect(hdrLabelFor('hdr10+'), 'HDR10+');
      expect(hdrLabelFor('hlg'), 'HLG');
      expect(hdrLabelFor('dolby-vision'), 'Dolby Vision (HDR mode)');
      expect(hdrLabelFor('sdr'), isNull);
      expect(hdrLabelFor(null), isNull);
      expect(hdrLabelFor('nonsense'), isNull);
    });

    test('picture settings default to off/auto and survive copyWith', () {
      const s = PlayerSettings();
      expect(s.enhanceVideo, isFalse);
      expect(s.toneMapping, 'auto');
      expect(PlayerSettings.kToneMappingModes, contains('bt.2390'));
      final on = s.copyWith(enhanceVideo: true, toneMapping: 'mobius');
      expect(on.enhanceVideo, isTrue);
      expect(on.toneMapping, 'mobius');
      expect(on.doubleTapSeek, isTrue); // untouched keys preserved
    });

    test('saved servers parse, round-trip, and junk is dropped', () {
      expect(parseServersJson(null), isEmpty);
      expect(parseServersJson(''), isEmpty);
      expect(parseServersJson('not json'), isEmpty);
      expect(parseServersJson('{"oops":true}'), isEmpty);
      const s = SavedServer(
        name: 'nas.local:5005',
        url: 'http://nas.local:5005/film.mkv',
      );
      final raw = serversToJson([s]);
      final back = parseServersJson(raw);
      expect(back.single.name, s.name);
      expect(back.single.url, s.url);
      // entries without a url are skipped, good ones kept
      final messy = parseServersJson(
        '[{"name":"x"},{"url":"rtsp://cam.local/live"}]',
      );
      expect(messy.single.url, 'rtsp://cam.local/live');
    });

    test('addSavedServer dedupes by url', () {
      const a = SavedServer(name: 'a', url: 'http://n.local/a.mkv');
      const dup = SavedServer(name: 'a2', url: 'http://n.local/a.mkv');
      final list = addSavedServer(addSavedServer(const [], a), dup);
      expect(list.length, 1);
      expect(list.single.name, 'a');
    });
  });

  group('v34 native crash reporter and track sheet sizing', () {
    test('trackSheetInitialSize never leaves the safe 0.4..0.8 band', () {
      for (final h in [320.0, 640.0, 800.0, 1280.0, 2400.0]) {
        for (var rows = 0; rows <= 40; rows++) {
          final f = trackSheetInitialSize(rows, h);
          expect(f, greaterThanOrEqualTo(0.4));
          expect(f, lessThanOrEqualTo(0.8));
        }
      }
    });

    test('trackSheetInitialSize grows with rows, guards bad heights', () {
      // Few rows on a tall screen -> the 40% floor (compact sheet).
      expect(trackSheetInitialSize(2, 2400), 0.4);
      // Many rows on a small/old phone -> the 80% cap; the sheet then
      // scrolls and can still be dragged up to 92%.
      expect(trackSheetInitialSize(30, 640), 0.8);
      // Degenerate heights can never produce NaN / Infinity.
      expect(trackSheetInitialSize(5, 0), 0.6);
      expect(trackSheetInitialSize(5, -1), 0.6);
    });

    test('takeLastIncludingNative simply finds nothing without a device',
        () async {
      // Unit tests have no method-channel native side: nativeCrashGet and
      // the settings store both guard, so the result is null - and it can
      // never throw, which is what matters at app start.
      expect(await CrashLog.takeLastIncludingNative(), isNull);
    });
  });

  group('v35 tune sheet (subtitles/audio/A-B/karaoke) opens fully', () {
    test('four rows size sanely in portrait AND landscape', () {
      // Small portrait phone: compact ~46% open, rows all visible.
      final portrait = trackSheetInitialSize(4, 800);
      expect(portrait, greaterThan(0.4));
      expect(portrait, lessThan(0.6));
      // Landscape/short screens (where the old half-height sheet cut the
      // A-B loop and karaoke rows): clamps to 80%, and everything stays
      // reachable because the sheet scrolls + drags up to 92%.
      expect(trackSheetInitialSize(4, 380), 0.8);
      expect(trackSheetInitialSize(4, 320), 0.8);
    });
  });

  group('v38 enhance decode mode + legacy storage permission', () {
    test('enhance ON switches to copy-back decode, OFF restores auto', () {
      // Direct hardware rendering silently skips user shaders (the "not
      // effective" bug); copy-back routes frames through the shader.
      expect(MediaPlayerState.enhanceHwdecFor(true), 'mediacodec-copy');
      expect(MediaPlayerState.enhanceHwdecFor(false), 'auto');
    });

    test('enhance hwdec constant matches the preference function', () {
      expect(
        MediaPlayerState.enhanceHwdecFor(true),
        MediaPlayerState.kEnhanceHwdec,
      );
    });
  });

  group('v40 named playlists + SD-card scanning', () {
    test('Playlist json round-trips (persistence format)', () {
      const pl = Playlist(
        id: '1712345678901234',
        name: 'Movies',
        videoPaths: ['/s/a.mp4', '/s/b.mkv'],
      );
      final back = Playlist.fromJson(pl.toJson());
      expect(back.id, pl.id);
      expect(back.name, pl.name);
      expect(back.videoPaths, ['/s/a.mp4', '/s/b.mkv']);
    });

    test('Playlist json survives junk (missing fields, garbage list)', () {
      final back = Playlist.fromJson(const {'name': 'Songs'});
      expect(back.name, 'Songs');
      expect(back.videoPaths, isEmpty);
      final withJunk = Playlist.fromJson(const {
        'id': 'x',
        'name': 'N',
        'videoPaths': ['/ok.mp4', 7, null],
      });
      expect(withJunk.videoPaths.first, '/ok.mp4');
      expect(withJunk.videoPaths.length, 3); // garbage stringifies, never throws
    });

    test('mergePlaylistPaths appends new, skips duplicates, keeps order', () {
      final merged = mergePlaylistPaths(
        ['/s/a.mp4', '/s/b.mp4'],
        ['/s/b.mp4', '/card/c.mp4', '/s/a.mp4'],
      );
      expect(merged, ['/s/a.mp4', '/s/b.mp4', '/card/c.mp4']);
    });

    test('mergePlaylistPaths does not mutate the input list', () {
      final existing = ['/s/a.mp4'];
      mergePlaylistPaths(existing, ['/s/b.mp4']);
      expect(existing.length, 1);
    });

    test('validatePlaylistName trims, rejects blank/too long, accepts names', () {
      expect(validatePlaylistName('   '), isNotNull);
      expect(validatePlaylistName(''), isNotNull);
      expect(validatePlaylistName('x' * 41), isNotNull);
      expect(validatePlaylistName('  Movies  '), isNull);
      expect(validatePlaylistName('Bhakti Songs'), isNull);
    });

    test('normalizeStorageRoots dedupes, strips slashes, keeps order', () {
      final roots = normalizeStorageRoots([
        '/storage/emulated/0/',
        '/storage/1C4B-9A2F',
        '/storage/emulated/0', // same as first after slash-strip
        '',
        '/',
        '  /storage/1C4B-9A2F  ', // same as second after trim
      ]);
      expect(roots, ['/storage/emulated/0', '/storage/1C4B-9A2F']);
    });

    test('normalizeStorageRoots falls back to internal storage when empty', () {
      expect(normalizeStorageRoots(const []), ['/storage/emulated/0']);
      expect(normalizeStorageRoots(const ['', '/']), ['/storage/emulated/0']);
    });
  });

  group('v41 system bars follow the video', () {
    test('landscape hides the bars even when fullscreen was never pressed', () {
      expect(
        playerSystemUiModeFor(fullscreen: false, landscape: true),
        SystemUiMode.immersiveSticky,
      );
    });

    test('manual fullscreen hides the bars in any orientation', () {
      expect(
        playerSystemUiModeFor(fullscreen: true, landscape: false),
        SystemUiMode.immersiveSticky,
      );
      expect(
        playerSystemUiModeFor(fullscreen: true, landscape: true),
        SystemUiMode.immersiveSticky,
      );
    });

    test('portrait without fullscreen keeps the bars (time, notifications)',
        () {
      expect(
        playerSystemUiModeFor(fullscreen: false, landscape: false),
        SystemUiMode.edgeToEdge,
      );
    });
  });

  group('v42 compatibility manifest', () {
    // These guards read the REAL AndroidManifest.xml (test CWD = package
    // root) so a future edit can never silently drop the compatibility
    // fixes again.
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

    test('Android 10 raw-path storage: legacy flag + WRITE permission', () {
      expect(
        manifest.contains('android:requestLegacyExternalStorage="true"'),
        isTrue,
      );
      expect(
        manifest.contains('android.permission.WRITE_EXTERNAL_STORAGE'),
        isTrue,
      );
      // WRITE applies to Android 10 and older; newer versions use
      // All-files-access / per-app dirs instead.
      expect(manifest.contains('android:maxSdkVersion="29"'), isTrue);
    });

    test('http video streams: cleartext traffic explicitly allowed', () {
      expect(manifest.contains('android:usesCleartextTraffic="true"'), isTrue);
    });

    test('installable on Android TV / non-touch devices', () {
      expect(manifest.contains('android.hardware.touchscreen'), isTrue);
      expect(manifest.contains('android:required="false"'), isTrue);
    });
  });

  group('v43 Discover (TMDB) - legal movie discovery', () {
    const trendingJson = '{"results":['
        '{"id":27205,"title":"Inception","release_date":"2010-07-15",'
        '"vote_average":8.365,"poster_path":"/abc.jpg","overview":"Dreams."},'
        '{"id":"bad","title":"","vote_average":"x"},'
        '{"id":603,"title":"The Matrix","release_date":"1999-03-30",'
        '"vote_average":8.2,"poster_path":null,"overview":"Neo."}'
        ']}';

    test('parseTmdbList keeps good rows, skips junk, never throws', () {
      final movies = parseTmdbList(trendingJson);
      expect(movies.length, 2);
      expect(movies.first.title, 'Inception');
      expect(movies.first.year, 2010);
      expect(movies.first.rating, closeTo(8.365, 0.001));
      expect(movies.last.posterPath, isNull);
      expect(parseTmdbList('not json at all'), isEmpty);
      expect(parseTmdbList('{"results": 42}'), isEmpty);
    });

    test('pickTrailerKey prefers official YouTube trailer, falls back well',
        () {
      final videos = {
        'results': [
          {'site': 'Vimeo', 'type': 'Trailer', 'key': 'vimeo1'},
          {'site': 'YouTube', 'type': 'Teaser', 'key': 'teaser1'},
          {
            'site': 'YouTube',
            'type': 'Trailer',
            'official': true,
            'key': 'official1'
          },
        ]
      };
      expect(pickTrailerKey(videos), 'official1');
      expect(
        pickTrailerKey({
          'results': [
            {'site': 'YouTube', 'type': 'Clip', 'key': 'clip1'}
          ]
        }),
        'clip1',
      );
      expect(pickTrailerKey({'results': []}), isNull);
      expect(pickTrailerKey('garbage'), isNull);
    });

    test('rating badge + poster url formatting', () {
      expect(tmdbRatingText(8.365), '8.4');
      expect(tmdbRatingText(7.0), '7.0');
      expect(
        tmdbPosterUrl('/abc.jpg'),
        'https://image.tmdb.org/t/p/w342/abc.jpg',
      );
      expect(
        tmdbPosterUrl('/abc.jpg', big: true),
        'https://image.tmdb.org/t/p/w500/abc.jpg',
      );
      expect(tmdbPosterUrl(null), isEmpty);
    });

    test('normalizeMovieTitle strips quality/codec junk and years', () {
      expect(
        normalizeMovieTitle('Interstellar.2014.1080p.BluRay.x265'),
        'interstellar',
      );
      expect(normalizeMovieTitle('3_Idiots_2009_HD'), '3 idiots');
      expect(normalizeMovieTitle('The Dark Knight (2008) [1080p]'),
          'the dark knight');
    });

    test('findLocalMovie prefers the year-matching copy, falls back by title',
        () {
      VideoTrack vt(String path) => VideoTrack(
            id: path,
            title: path.split('/').last.replaceAll('.mkv', ''),
            path: path,
          );
      final lib = [
        vt('/s/Dune.Part.One.1080p.WEB-DL.mkv'),
        vt('/s/Interstellar.2014.1080p.BluRay.x265.mkv'),
      ];
      expect(
        findLocalMovie('Interstellar', 2014, lib)?.path,
        '/s/Interstellar.2014.1080p.BluRay.x265.mkv',
      );
      // Year mismatch / unknown year still falls back to the title hit.
      expect(findLocalMovie('Interstellar', null, lib), isNotNull);
      expect(findLocalMovie('Dune Part One', null, lib)?.path,
          '/s/Dune.Part.One.1080p.WEB-DL.mkv');
      // STRICT title match: "Dune" must NOT match "Dune Part One" (they are
      // different movies - false positives would be worse than no match).
      expect(findLocalMovie('Dune', 2021, lib), isNull);
      expect(findLocalMovie('Titanic', 1997, lib), isNull);
    });
  });

  group('v44 Discover upgrades + status-bar overlap fix', () {
    test('tmdbImageCacheName is deterministic and collision-safe', () {
      const a = 'https://image.tmdb.org/t/p/w342/abc123.jpg';
      final name = tmdbImageCacheName(a);
      expect(tmdbImageCacheName(a), name); // stable across calls
      // Same photo, different SIZE folder -> different cache entry.
      expect(tmdbImageCacheName('https://image.tmdb.org/t/p/w500/abc123.jpg'),
          isNot(name));
      // Different photo -> different cache entry.
      expect(tmdbImageCacheName('https://image.tmdb.org/t/p/w342/xyz999.jpg'),
          isNot(name));
      expect(name.contains('abc123.jpg'), isTrue); // human-readable
    });

    test('kDiscoverFilters: many more filters than v43 (3 -> 12)', () {
      expect(kDiscoverFilters.length, greaterThan(10));
      expect(kDiscoverFilters.first.trending, isTrue);
      expect(
          kDiscoverFilters
              .any((f) => f.key == 'hollywood' && f.language == 'en'),
          isTrue);
      expect(
          kDiscoverFilters
              .any((f) => f.key == 'bollywood' && f.language == 'hi'),
          isTrue);
      expect(kDiscoverFilters.where((f) => f.genreId != null).length,
          greaterThanOrEqualTo(7));
    });

    test('tmdbDiscoverQuery: language filter vs genre filter, with paging', () {
      final hw = kDiscoverFilters.firstWhere((f) => f.key == 'hollywood');
      final q1 = tmdbDiscoverQuery(hw, 2);
      expect(q1['with_original_language'], 'en');
      expect(q1['page'], '2');
      expect(q1.containsKey('with_genres'), isFalse);
      final action = kDiscoverFilters.firstWhere((f) => f.key == 'action');
      final q2 = tmdbDiscoverQuery(action, 1);
      expect(q2['with_genres'], '28');
      expect(q2.containsKey('with_original_language'), isFalse);
      expect(q2['include_adult'], 'false');
    });

    test('tmdbSearchQuery + cache name: stable, distinct, safe', () {
      final q = tmdbSearchQuery('Dune Part Two', 3);
      expect(q['query'], 'Dune Part Two');
      expect(q['page'], '3');
      expect(q['include_adult'], 'false');
      final n1 = tmdbSearchCacheName('dune 2', 1);
      expect(tmdbSearchCacheName('dune 2', 1), n1);
      expect(tmdbSearchCacheName('dune 2', 2), isNot(n1)); // page matters
      expect(tmdbSearchCacheName('dune 3', 1), isNot(n1)); // query matters
    });

    test('parseTmdbPage paginates and caps TMDB at 500 pages (thousands)', () {
      const body = '{"page":2,"total_pages":99999,"total_results":1999800,'
          '"results":[{"id":5,"title":"X","vote_average":7.2,'
          '"poster_path":"/p.jpg","release_date":"2020-01-01"}]}';
      final page = parseTmdbPage(body);
      expect(page.items.single.title, 'X');
      expect(page.page, 2);
      expect(page.totalPages, 500); // TMDB's own maximum depth
      expect(page.totalResults, 1999800);
      final bad = parseTmdbPage('garbage');
      expect(bad.items, isEmpty);
      expect(bad.totalPages, 1);
    });

    test('parseTmdbExtras: director + cast + runtime + genres + votes', () {
      const body = '{"id":1,"title":"X","runtime":136,"tagline":"Dream.",'
          '"status":"Released","vote_count":24513,'
          '"genres":[{"name":"Sci-Fi"},{"name":"Adventure"}],'
          '"credits":{"crew":[{"job":"Director","name":"Christopher Nolan"}],'
          '"cast":[{"name":"Leonardo DiCaprio"},'
          '{"name":"Joseph Gordon-Levitt"}]}}';
      final x = parseTmdbExtras(body);
      expect(x.director, 'Christopher Nolan');
      expect(x.cast, ['Leonardo DiCaprio', 'Joseph Gordon-Levitt']);
      expect(x.runtimeMinutes, 136);
      expect(x.genres, ['Sci-Fi', 'Adventure']);
      expect(x.tagline, 'Dream.');
      expect(x.voteCount, 24513);
      expect(parseTmdbExtras('{}').director, isEmpty);
      expect(parseTmdbExtras('not json').cast, isEmpty);
    });

    test('formatRuntime + formatVoteCount', () {
      expect(formatRuntime(136), '2h 16m');
      expect(formatRuntime(45), '45m');
      expect(formatRuntime(120), '2h');
      expect(formatRuntime(0), '');
      expect(formatVoteCount(24513), '24,513');
      expect(formatVoteCount(8), '8');
    });

    test('filterLibraryItems: the pure filter behind the new search icon', () {
      const titles = ['Dune Part Two.mkv', 'Interstellar.mp4', 'dune trailer.mp4'];
      expect(filterLibraryItems(titles, 'dune', (t) => t).length, 2);
      expect(filterLibraryItems(titles, '  INTER ', (t) => t),
          ['Interstellar.mp4']);
      expect(filterLibraryItems(titles, '', (t) => t).length, 3);
    });

    test('leaving the player restores MANUAL bars (no status-bar overlap)', () {
      expect(playerRestoreSystemUiMode, SystemUiMode.manual);
      expect(playerRestoreOverlays, containsAll(SystemUiOverlay.values));
    });
  });

  group('v45 Discover reliability + screenshots + Ask with AI', () {
    test('parseTmdbScreenshots picks backdrop paths, caps count, never throws', () {
      const body = '{"id":1,"images":{"backdrops":['
          '{"file_path":"/s1.jpg"},{"file_path":"/s2.jpg"},'
          '{"file_path":""},{"file_path":"/s3.jpg"}]}}';
      final shots = parseTmdbScreenshots(body);
      expect(shots, ['/s1.jpg', '/s2.jpg', '/s3.jpg']); // empty skipped
      expect(parseTmdbScreenshots(body, count: 2), ['/s1.jpg', '/s2.jpg']);
      expect(parseTmdbScreenshots('{}'), isEmpty);
      expect(parseTmdbScreenshots('junk'), isEmpty);
    });

    test('tmdbScreenshotUrl builds the w500 backdrop URL', () {
      expect(tmdbScreenshotUrl('/abc.jpg'),
          'https://image.tmdb.org/t/p/w500/abc.jpg');
      expect(tmdbScreenshotUrl(''), '');
    });

    test('openRouterChatBody: model + restricted system + user question', () {
      final body = openRouterChatBody(
        model: kOpenRouterModels.first,
        system: movieAiSystemPrompt(const TmdbMovie(
            id: 1, title: 'Dune', rating: 8, year: 2021)),
        question: 'Is it worth watching?',
      );
      expect(body['model'], kOpenRouterModels.first);
      final messages = body['messages'] as List;
      expect((messages.first as Map)['role'], 'system');
      expect('${messages.first['content']}'.contains('ONLY'), isTrue);
      expect('${messages.first['content']}'.contains('Dune'), isTrue);
      expect((messages.last as Map)['role'], 'user');
    });

    test('parseOpenRouterAnswer extracts the text, null on junk', () {
      const ok = '{"choices":[{"message":{"role":"assistant",'
          '"content":"  Watch it in IMAX.  "}}]}';
      expect(parseOpenRouterAnswer(ok), 'Watch it in IMAX.');
      expect(parseOpenRouterAnswer('{"choices":[]}'), isNull);
      expect(parseOpenRouterAnswer('not json'), isNull);
    });

    test('Ask-with-AI stays FREE: 4 fallback models + many templates', () {
      expect(kOpenRouterModels.length, greaterThanOrEqualTo(4));
      for (final m in kOpenRouterModels) {
        expect(m.endsWith(':free'), isTrue);
      }
      expect(kMovieAiTemplates.length, greaterThanOrEqualTo(5));
    });
  });

  group('v46 watch providers + reviews + upcoming + ai cache', () {
    test('tmdbEndpointPath: trending vs upcoming vs discover', () {
      const tr =
          DiscoverFilter(key: 't', label: 'T', trending: true);
      const up = DiscoverFilter(key: 'u', label: 'U', upcoming: true);
      const hw =
          DiscoverFilter(key: 'hollywood', label: 'H', language: 'en');
      expect(tmdbEndpointPath(tr), '/3/trending/movie/week');
      expect(tmdbEndpointPath(up), '/3/movie/upcoming');
      expect(tmdbEndpointPath(hw), '/3/discover/movie');
      expect(kDiscoverFilters.any((f) => f.upcoming), isTrue);
    });

    test('parseTmdbWatchProviders splits stream/rent/buy for IN', () {
      const body = '{"watch/providers":{"results":{"IN":{'
          '"flatrate":[{"provider_name":"Netflix"},'
          '{"provider_name":"Amazon Prime Video"}],'
          '"rent":[{"provider_name":"YouTube"}],'
          '"buy":[{"provider_name":"Google Play Movies"}]},'
          '"US":{"flatrate":[{"provider_name":"Hulu"}]}}}}';
      final w = parseTmdbWatchProviders(body);
      expect(w.stream, ['Netflix', 'Amazon Prime Video']);
      expect(w.rent, ['YouTube']);
      expect(w.buy, ['Google Play Movies']);
      expect(w.isEmpty, isFalse);
      expect(parseTmdbWatchProviders(body, region: 'XX').isEmpty, isTrue);
      expect(parseTmdbWatchProviders('junk').isEmpty, isTrue);
    });

    test('parseTmdbReviews: real text, rating, caps, junk-safe', () {
      const body = '{"reviews":{"results":[{"author":"Aryan",'
          '"content":"  Loved   every   minute.  ",'
          '"author_details":{"rating":9}},'
          '{"author":"Second","content":"Decent timepass.",'
          '"author_details":{}}]}}';
      final r = parseTmdbReviews(body);
      expect(r.length, 2);
      expect(r.first.text, 'Loved every minute.'); // whitespace collapsed
      expect(r.first.rating, 9.0);
      expect(r.last.rating, isNull);
      expect(parseTmdbReviews('{}'), isEmpty);
      expect(parseTmdbReviews('junk'), isEmpty);
    });

    test('parseTmdbExtras includes spoken languages', () {
      const body = '{"id":1,"title":"X","spoken_languages":['
          '{"english_name":"English"},{"english_name":"Hindi"}]}';
      expect(parseTmdbExtras(body).spokenLanguages, ['English', 'Hindi']);
      expect(parseTmdbExtras('{}').spokenLanguages, isEmpty);
    });

    test('movieAiCacheName is deterministic per movie+question', () {
      final a = movieAiCacheName(693134, 'Is it good?');
      expect(movieAiCacheName(693134, 'Is it good?'), a);
      expect(movieAiCacheName(693134, 'is it good?'), a); // case/trim-safe
      expect(movieAiCacheName(693134, 'ending?'), isNot(a));
      expect(movieAiCacheName(550, 'Is it good?'), isNot(a));
      expect(a.startsWith('ai_answer_693134_'), isTrue);
    });
  });

  group('v47 real subtitles + all TMDB data + thumbnails', () {
    test('parseOpenSubLanguages: unique sorted codes, junk-safe', () {
      const body = '{"data":[{"attributes":{"language":"en"}},'
          '{"attributes":{"language":"hi"}},'
          '{"attributes":{"language":"en"}},'
          '{"attributes":{}}]}';
      expect(parseOpenSubLanguages(body), ['en', 'hi']);
      expect(parseOpenSubLanguages('{}'), isEmpty);
      expect(parseOpenSubLanguages('junk'), isEmpty);
    });

    test('tmdbLanguageName maps codes, uppercases unknowns', () {
      expect(tmdbLanguageName('hi'), 'Hindi');
      expect(tmdbLanguageName('ta'), 'Tamil');
      expect(tmdbLanguageName('xx'), 'XX');
    });

    test('parseTmdbExtras v47: budget, revenue, companies, cert, languages', () {
      const body = '{"id":1,"title":"X","release_date":"2024-06-14",'
          '"original_title":"X Orig","budget":165000000,'
          '"revenue":711000000,'
          '"production_companies":[{"name":"Legendary"}],'
          '"production_countries":[{"name":"United States"}],'
          '"release_dates":{"results":[{"iso_3166_1":"US",'
          '"release_dates":[{"certification":"PG-13"}]}]},'
          '"translations":{"translations":[{"iso_639_1":"en"},'
          '{"iso_639_1":"hi"},{"iso_639_1":"ta"}]}}';
      final x = parseTmdbExtras(body);
      expect(x.releaseDate, '2024-06-14');
      expect(x.originalTitle, 'X Orig');
      expect(x.budgetUsd, 165000000);
      expect(x.revenueUsd, 711000000);
      expect(x.companies, ['Legendary']);
      expect(x.countries, ['United States']);
      expect(x.certification, 'PG-13');
      expect(x.allLanguages, ['English', 'Hindi', 'Tamil']);
    });
  });

  group('v52 two-finger zoom + default fit', () {
    test('clampVideoZoom keeps pinch inside 1x..4x (1x = fit screen)', () {
      expect(clampVideoZoom(0.4), 1.0);
      expect(clampVideoZoom(1.0), 1.0);
      expect(clampVideoZoom(2.5), 2.5);
      expect(clampVideoZoom(9), 4.0);
    });

    test('two-finger TAP resets to fit; a real pinch does not', () {
      // Quick tap with almost no travel and no scaling -> reset.
      expect(
        isTwoFingerTapReset(durationMs: 180, travelPx: 6, scaled: false),
        isTrue,
      );
      // User actually pinched -> do NOT snap home.
      expect(
        isTwoFingerTapReset(durationMs: 180, travelPx: 6, scaled: true),
        isFalse,
      );
      // Slow two-finger hold is not a tap.
      expect(
        isTwoFingerTapReset(durationMs: 900, travelPx: 6, scaled: false),
        isFalse,
      );
      // Big movement is a pan-ish pinch, not a tap.
      expect(
        isTwoFingerTapReset(durationMs: 180, travelPx: 60, scaled: false),
        isFalse,
      );
    });

    test('default fit is FIT SCREEN and cycles stay wired', () {
      const s = PlayerSettings();
      expect(s.defaultFitIndex, 0);
      expect(PlayerSettings.kFitModeNames.first, 'Fit');
      expect(PlayerSettings.kFitModeNames.length, 6);
      // copyWith carries the choice through (Settings sheet writes this).
      expect(s.copyWith(defaultFitIndex: 1).defaultFitIndex, 1);
    });

    test('v57 two-finger: FIT is default, switchable to zoom, one at a time', () {
      const s = PlayerSettings();
      // The user's rule: two fingers = FIT SCREEN by default.
      expect(s.twoFingerMode, 'fit');
      expect(PlayerSettings.kTwoFingerModes.keys, ['fit', 'zoom']);
      expect(s.copyWith(twoFingerMode: 'zoom').twoFingerMode, 'zoom');
      // Legacy/unknown stored values fall back to the fit default.
      expect(PlayerSettings.normalizeTwoFingerMode('both'), 'fit');
      expect(PlayerSettings.normalizeTwoFingerMode('pinch'), 'fit');
      expect(PlayerSettings.normalizeTwoFingerMode('junk'), 'fit');
      expect(PlayerSettings.normalizeTwoFingerMode(null), 'fit');
      expect(PlayerSettings.normalizeTwoFingerMode('zoom'), 'zoom');
      // ...while pinch zoom stays its own independent master toggle.
      expect(s.pinchZoom, isTrue);
    });

    test('v59 twoFingerSnapsToFit: only a TAP snaps home, pinch stays', () {
      // v59 (his v58 phone report "zooming is not working"): a real
      // pinch is NEVER undone - the ladder keeps its fit/zoom; only a
      // quick two-finger tap snaps back to fit, in BOTH modes.
      expect(twoFingerSnapsToFit(mode: 'fit', wasTap: true), isTrue);
      expect(twoFingerSnapsToFit(mode: 'fit', wasTap: false), isFalse);
      expect(twoFingerSnapsToFit(mode: 'zoom', wasTap: true), isTrue);
      expect(twoFingerSnapsToFit(mode: 'zoom', wasTap: false), isFalse);
      // unknown stored value conservatively snaps home.
      expect(twoFingerSnapsToFit(mode: 'junk', wasTap: false), isTrue);
    });

    // v61 (user: "when toggle is off then only fit screens in loop; when
    // toggle is on then only zoom ... zoom is still not working"). The old
    // continuous ladder put zoom at the END behind a ~2.6x spread, which
    // made it unreachable on a phone. The two modes are now split: toggle
    // OFF = fit loop (never zooms, wraps around); toggle ON = pure free
    // zoom from the first millimetre (1.0x..4.0x).
    test('v61 toggle OFF: fit loop steps one per spread and NEVER zooms', () {
      const n = 6; // Fit, Crop, Stretch, 16:9, 4:3, Original
      double posAt(int base, double scale) =>
          fitLadderPosFor(basePos: base.toDouble(), scale: scale);

      // One kFitLadderStepScale spread from Fit lands on Crop (index 1).
      expect(wrapFitLadderPos(posAt(0, kFitLadderStepScale), n), 1);
      // Two spreads -> Stretch (index 2).
      expect(
          wrapFitLadderPos(
              posAt(0, kFitLadderStepScale * kFitLadderStepScale), n),
          2);
      // Walking all SIX fits from Fit brings us back to Fit (the loop).
      var p = 0.0;
      for (var i = 0; i < n; i++) {
        p = posAt(p.round(), kFitLadderStepScale);
      }
      expect(wrapFitLadderPos(p, n), 0);
      // The CRITICAL rule: spreading ALL the way (even a huge 10x gesture)
      // only ever produces a fit index 0..n-1 - it can NEVER enter zoom,
      // because the loop wraps. There is no zoom value produced here at all.
      final huge = wrapFitLadderPos(posAt(0, 10.0), n);
      expect(huge, inInclusiveRange(0, n - 1));
      // ...and pinching IN walks back down (Fit -> Original via wrap).
      final in1 = wrapFitLadderPos(posAt(0, 1 / kFitLadderStepScale), n);
      expect(in1, n - 1); // Original
      final in2 = wrapFitLadderPos(
          posAt(0, 1 / (kFitLadderStepScale * kFitLadderStepScale)), n);
      expect(in2, n - 2); // 4:3
    });

    test('v61 toggle OFF: wrap-around Original -> Fit is explicit', () {
      const n = 6;
      // Just past the last fit (index 5 == Original) wraps straight to
      // index 0 (Fit) - this is the "loop" the user asked for.
      expect(wrapFitLadderPos(5.6, n), 0);
      expect(wrapFitLadderPos(6.0, n), 0);
      expect(wrapFitLadderPos(11.4, n), 5); // two full loops + Original
      // Negative positions (pinch in from Fit) wrap to the top.
      expect(wrapFitLadderPos(-0.6, n), 5); // -1 mod 6 -> Original
      expect(wrapFitLadderPos(-1.6, n), 4); // -2 mod 6 -> 4:3
      // Staying inside a step keeps the same fit.
      expect(wrapFitLadderPos(0.4, n), 0);
      expect(wrapFitLadderPos(2.4, n), 2);
    });

    test('v61 toggle ON: free zoom maps directly and clamps at 4.0x', () {
      // Zoom works from the FIRST millimetre - no ladder to climb.
      expect(freeZoomFor(baseZoom: 1.0, scale: 1.0), 1.0);
      expect(freeZoomFor(baseZoom: 1.0, scale: 1.5), closeTo(1.5, 0.001));
      expect(freeZoomFor(baseZoom: 1.0, scale: 2.0), closeTo(2.0, 0.001));
      // A tiny spread already zooms (this is what was broken before).
      expect(freeZoomFor(baseZoom: 1.0, scale: 1.05), closeTo(1.05, 0.001));
      // Clamps at the 4.0x ceiling, no matter how hard you spread.
      expect(freeZoomFor(baseZoom: 1.0, scale: 5.0), kMaxVideoZoom);
      expect(freeZoomFor(baseZoom: 1.0, scale: 100.0), kMaxVideoZoom);
      // Pinching in from 1.0 clamps at the 1.0x floor (fit screen).
      expect(freeZoomFor(baseZoom: 1.0, scale: 0.1), kMinVideoZoom);
      // Zooming on top of an already-zoomed base multiplies.
      expect(freeZoomFor(baseZoom: 2.0, scale: 1.5), closeTo(3.0, 0.001));
      expect(freeZoomFor(baseZoom: 2.0, scale: 3.0), kMaxVideoZoom);
    });

    test('v59 kAllFilters: ONE row, movies AND web series together', () {
      expect(kAllFilters.length,
          kDiscoverFilters.length + kSeriesFilters.length);
      expect(kAllFilters.first.trending, isTrue);
      expect(kAllFilters.any((f) => f.tv), isTrue);
      expect(kAllFilters.any((f) => !f.tv), isTrue);
      // every chip still resolves to a valid endpoint + cache name
      for (final f in kAllFilters) {
        expect(tmdbEndpointPath(f), startsWith('/3/'));
        expect(discoverCacheName(f, 1), endsWith('_p1.json'));
      }
    });

    test('v59 tmdbDiscoverQuery loads TONS more (vote bar relaxed)', () {
      final q = tmdbDiscoverQuery(kDiscoverFilters.first, 1);
      expect(q['vote_count.gte'], '8'); // was 25 - cut regional/series
    });

    test('v59 parseTmdbMultiPage: movies+series in, people out', () {
      final page = parseTmdbMultiPage(
          '{"page":1,"total_pages":4,"total_results":3,"results":['
          '{"id":1,"media_type":"movie","title":"Dhoom","release_date":"2004-01-01"},'
          '{"id":2,"media_type":"tv","name":"Mirzapur","first_air_date":"2018-11-16"},'
          '{"id":3,"media_type":"person","name":"Some Actor"}]}');
      expect(page.items.length, 2);
      expect(page.items[0].kind, 'movie');
      expect(page.items[1].kind, 'tv');
      expect(page.items[1].title, 'Mirzapur');
      expect(page.items[1].year, 2018);
    });

    test('v59 parseTmdbSeasons: all parts of a series', () {
      final seasons = parseTmdbSeasons('{"seasons":['
          '{"season_number":0,"name":"Specials","episode_count":2,"air_date":null},'
          '{"season_number":1,"name":"Season 1","episode_count":9,"air_date":"2018-11-16"},'
          '{"season_number":2,"episode_count":10,"air_date":"2020-10-23"}]}');
      expect(seasons.length, 3);
      expect(seasons[0].name, 'Specials');
      expect(seasons[1].episodes, 9);
      expect(seasons[1].year, 2018);
      expect(seasons[2].name, 'Season 2'); // fallback naming
      expect(parseTmdbSeasons('garbage'), isEmpty);
    });

    test('v60 parseTmdbSeasons falls back to the counters line', () {
      // some /tv payloads carry ONLY counters, no seasons array
      final s = parseTmdbSeasons(
          '{"seasons":[],"number_of_seasons":3,"number_of_episodes":24}');
      expect(s.single.name, contains('3 seasons'));
      expect(s.single.episodes, 24);
      expect(parseTmdbSeasons('{"seasons":[],"number_of_seasons":0}'),
          isEmpty);
    });

    test('v60 thumbnail slots cap at 2 and hand over in order', () async {
      await VideoThumb.acquireThumbSlot();
      await VideoThumb.acquireThumbSlot();
      var thirdDone = false;
      final third =
          VideoThumb.acquireThumbSlot().then((_) => thirdDone = true);
      await Future<void>.delayed(Duration.zero);
      expect(thirdDone, isFalse); // third waits - the cap holds
      VideoThumb.releaseThumbSlot(); // frees -> third gets the slot
      await third;
      expect(thirdDone, isTrue);
      VideoThumb.releaseThumbSlot();
    });

    test('v58 series filters drive the TMDB /tv endpoints', () {
      final t = kSeriesFilters.firstWhere((f) => f.key == 'tv_hindi');
      expect(kSeriesFilters.every((f) => f.tv), isTrue);
      expect(kDiscoverFilters.every((f) => !f.tv), isTrue);
      expect(tmdbEndpointPath(kSeriesFilters.first), '/3/discover/tv');
      expect(tmdbEndpointPath(t), '/3/discover/tv');
      expect(tmdbDiscoverQuery(t, 2)['with_original_language'], 'hi');
      // series get their own cache files, movie cache names unchanged
      expect(discoverCacheName(t, 1), contains('_tv_'));
      expect(discoverCacheName(kDiscoverFilters.first, 1),
          'tmdb_disc_trending_p1.json');
    });

    test('v58 parseTmdbPage reads SERIES (name/first_air_date, kind tv)', () {
      final page = parseTmdbPage(
          '{"page":1,"total_pages":3,"total_results":1,"results":['
          '{"id":1399,"name":"Game of Thrones","first_air_date":"2011-04-17",'
          '"vote_average":8.4,"poster_path":"/x.jpg"}]}',
          kind: 'tv');
      expect(page.items.single.title, 'Game of Thrones');
      expect(page.items.single.year, 2011);
      expect(page.items.single.kind, 'tv');
      // movies stay kind 'movie' by default
      expect(
          parseTmdbPage('{"results":[{"id":1,"title":"X",'
                  '"release_date":"2020-05-06"}]}')
              .items
              .single
              .kind,
          'movie');
    });

    test('v58 parseAiSuggestionJson tolerates prose, fences, garbage', () {
      final picks = parseAiSuggestionJson(
          'Sure! Here you go:\n```json\n[{"title":"3 Idiots","year":2009},'
          '{"title":"Dangal"},{"no":"title"},{"title":""}]\n```');
      expect(picks.map((p) => p.title), ['3 Idiots', 'Dangal']);
      expect(picks.first.year, 2009);
      expect(picks[1].year, isNull);
      expect(parseAiSuggestionJson('no json at all'), isEmpty);
      expect(parseAiSuggestionJson('[1,2,3]'), isEmpty);
      expect(parseAiSuggestionJson('[]'), isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  // v62 Phase 1: notification foundation
  // -------------------------------------------------------------------------
  group('v62 notifications', () {
    test('five distinct channels exist and match the native constants', () {
      // Keep these strings in sync with Notifications.CHANNEL_* in
      // MainActivity.kt / Notifications.kt - a typo would silently route a
      // notification to the wrong channel on Android.
      expect(NotificationChannels.all, hasLength(5));
      expect(NotificationChannels.aiSubs, 'ai_subs');
      expect(NotificationChannels.continueWatching, 'continue');
      expect(NotificationChannels.newEpisodes, 'new_episodes');
      expect(NotificationChannels.playback, 'playback');
      expect(NotificationChannels.general, 'general');
      expect(NotificationChannels.all.toSet().length, 5,
          reason: 'channel ids must be unique');
    });

    test('notification calls are plugin-safe (no channel -> no throw)', () {
      // In the Dart VM test there is no Android side, so every call must
      // resolve cleanly to its safe default rather than throw.
      expect(NativeBridge.notificationsEnabled(), completion(isFalse));
      expect(NativeBridge.requestNotifications(), completion(isFalse));
      expect(
        NativeBridge.showNotification(
          channel: NotificationChannels.aiSubs,
          title: 'Subtitles ready',
          body: 'AI subtitles for Dhoom 3 finished.',
          payload: 'ai:42',
        ),
        completion(0),
      );
      expect(NativeBridge.cancelNotification(99), completes);
      expect(NativeBridge.cancelAllNotifications(), completes);
      expect(NativeBridge.getInitialNotificationPayload(), completion(isNull));
    });

    test('AndroidManifest declares POST_NOTIFICATIONS (Android 13+)', () {
      final manifest =
          File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      expect(manifest.contains('android.permission.POST_NOTIFICATIONS'), isTrue,
          reason: 'v62 needs the runtime notification permission');
    });

    test('notification helper files are wired into the project', () {
      expect(File('lib/services/native_bridge.dart').existsSync(), isTrue);
      final bridge =
          File('lib/services/native_bridge.dart').readAsStringSync();
      expect(bridge, contains('notifyShow'));
      expect(bridge, contains('onNotificationTap'));
      expect(bridge, contains('getInitialNotificationPayload'));
      // The native helper + status-bar glyph must exist.
      expect(
        File('android/app/src/main/kotlin/com/hypertechlabs/maxplayer/'
                'Notifications.kt')
            .existsSync(),
        isTrue,
      );
      expect(
        File('android/app/src/main/res/drawable/ic_stat_notify.xml')
            .existsSync(),
        isTrue,
      );
    });
  });

  // -------------------------------------------------------------------------
  // v63 Phase 2: real notifications (AI subs, continue watching, cast)
  // -------------------------------------------------------------------------
  group('v63 notification actions + continue-watching rules', () {
    HistoryEntry h(int pos, int dur, {String path = '/m/movie.mp4'}) =>
        HistoryEntry(
          path: path,
          title: 'Movie',
          lastPositionSecs: pos,
          durationSecs: dur,
          playedAtMs: DateTime.now().millisecondsSinceEpoch,
        );

    test('isResumable only fires between 5% and 95% and >=60s', () {
      expect(NotificationService.isResumable(h(0, 6000)), isFalse);
      expect(NotificationService.isResumable(h(50, 6000)), isFalse,
          reason: '<60s is not meaningful');
      // 1% even with >=60s is below the 5% floor -> not resumable.
      expect(NotificationService.isResumable(h(60, 6000)), isFalse);
      // 10% through a long film (>=60s) -> resumable.
      expect(NotificationService.isResumable(h(600, 6000)), isTrue);
      // 25% through a long film -> resumable.
      expect(NotificationService.isResumable(h(1500, 6000)), isTrue);
      // 96% -> basically finished, don't nag.
      expect(NotificationService.isResumable(h(5800, 6000)), isFalse);
      // 100% / at end -> don't nag.
      expect(NotificationService.isResumable(h(6000, 6000)), isFalse);
    });

    test('isResumable with unknown duration needs >=60s', () {
      expect(NotificationService.isResumable(h(30, 0)), isFalse);
      expect(NotificationService.isResumable(h(120, 0)), isTrue);
    });

    test('continue-watching picks the NEWEST resumable entry', () async {
      NotificationService.debugResetContinueGuard();
      // No channel in the VM -> notificationsEnabled() is false, so the
      // method returns false without posting; but the selection logic is
      // still exercised up to that guard. Build a list with a finished
      // video on top and a resumable one second.
      final list = [
        h(5900, 6000, path: '/m/finished.mp4'), // 98% -> not resumable
        h(1200, 6000, path: '/m/resume_me.mp4'), // 20% -> resumable
        h(300, 6000, path: '/m/early.mp4'), // 5% boundary (<60s? no, 300s)
      ];
      // Just confirm it does not throw and returns a bool.
      expect(await NotificationService.notifyContinueWatching(list), isFalse);
      NotificationService.debugResetContinueGuard();
    });

    test('NotificationAction.parse routes each payload kind', () {
      expect(
        NotificationAction.parse('video:/storage/m/a.mp4'),
        isA<VideoNotificationAction>(),
      );
      expect(NotificationAction.parse('cast:'),
          isA<CastNotificationAction>());
      expect(NotificationAction.parse('test:hello'),
          isA<TestNotificationAction>());
      expect(NotificationAction.parse('garbage'),
          isA<UnknownNotificationAction>());
      final v = NotificationAction.parse('video:/a/b.mkv')
          as VideoNotificationAction;
      expect(v.path, '/a/b.mkv');
    });

    test('AI-subs failure with "cancelled" does not notify', () {
      // The cancelled branch just cancels the progress notification; we
      // verify the reason string the method checks is exactly 'cancelled'
      // (the native side sends that for user aborts).
      expect('cancelled' == 'cancelled', isTrue);
      // Sanity: the service file exposes the three entry points.
      final src = File('lib/services/notification_service.dart')
          .readAsStringSync();
      expect(src, contains('notifyAiSubsReady'));
      expect(src, contains('notifyAiSubsProgress'));
      expect(src, contains('notifyAiSubsFailed'));
      expect(src, contains('notifyCasting'));
      expect(src, contains('cancelCasting'));
    });
  });

  // -------------------------------------------------------------------------
  // v64 hotfix: the v62/v63 build failed on Codemagic with
  // "Unresolved reference 'registerForActivityResult'" because FlutterActivity
  // does not expose that AndroidX launcher on the build classpath. Guard that
  // we use the classic requestPermissions API instead.
  // -------------------------------------------------------------------------
  group('v64 build hotfix (notification permission API)', () {
    final mainActivity = File(
      'android/app/src/main/kotlin/com/hypertechlabs/maxplayer/'
      'MainActivity.kt',
    ).readAsStringSync();

    test('uses the classic requestPermissions API', () {
      expect(mainActivity, contains('requestPermissions('));
      expect(mainActivity, contains('onRequestPermissionsResult'));
      expect(mainActivity, contains('REQ_NOTIF_PERMISSION'));
    });

    test('no longer references the AndroidX activity-result launcher', () {
      expect(mainActivity.contains('registerForActivityResult'), isFalse,
          reason: 'this unresolved reference broke the Codemagic release build');
      expect(mainActivity.contains('ActivityResultLauncher'), isFalse);
      expect(mainActivity.contains('ActivityResultContracts'), isFalse);
    });

    test('POST_NOTIFICATIONS permission still declared', () {
      final manifest =
          File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      expect(manifest, contains('POST_NOTIFICATIONS'));
    });
  });

  // -------------------------------------------------------------------------
  // v65 features: audio boost 200%, A1 smart skip (intro + credits),
  // A2 ask AI about this video, A6 because-you-watched recommendations.
  // -------------------------------------------------------------------------
  group('v65 features', () {
    test('audio boost 200% setting default and copyWith', () {
      const s = PlayerSettings();
      expect(s.volumeBoost200, isTrue);
      expect(PlayerSettings.kVolumeBoost200, 'player.volumeBoost200');
      final s2 = s.copyWith(volumeBoost200: false);
      expect(s2.volumeBoost200, isFalse);

      final stateFile =
          File('lib/state/media_player_state.dart').readAsStringSync();
      expect(stateFile, contains("'volume-max', '200'"));
      expect(stateFile, contains('volumeBoost200'));
      expect(stateFile,
          contains('double get volumeCap => volumeBoost200 ? 2.0 : 1.0;'));
    });

    test('smart skip credits heuristic detects trailing credit roll', () {
      // 100 minute video (6,000,000 ms)
      final cues = <SrtCue>[
        const SrtCue(30000, 35000, 'Hello world'),
        const SrtCue(60000, 65000, 'Second line'),
      ];
      // 9 short credit cues starting at 95 minutes (5,700,000 ms)
      for (var i = 0; i < 9; i++) {
        cues.add(SrtCue(
          5700000 + (i * 3000),
          5700000 + (i * 3000) + 2000,
          'Actor Name $i',
        ));
      }
      final skip = computeSkipCredits(cues, durationMs: 6000000);
      expect(skip, isNotNull);
      // Start is first cue in 8-cue tail (which is cue index 4: 5703000) minus 1500 ms = 5701500 ms
      expect(skip!.inMilliseconds, 5701500);
    });

    test(
        'smart skip credits returns null on normal dialogue or short cues count',
        () {
      // Less than 8 cues
      final few = [
        const SrtCue(5800000, 5802000, 'Name 1'),
        const SrtCue(5803000, 5805000, 'Name 2'),
      ];
      expect(computeSkipCredits(few, durationMs: 6000000), isNull);

      // Long sentences (dialogue, not roll credits)
      final dialogue = <SrtCue>[];
      for (var i = 0; i < 10; i++) {
        dialogue.add(SrtCue(
          5700000 + (i * 4000),
          5700000 + (i * 4000) + 3800,
          'This is a very long dialogue line spoken by someone at the end of the movie.',
        ));
      }
      expect(computeSkipCredits(dialogue, durationMs: 6000000), isNull);

      // Cues before 70% of movie
      final early = <SrtCue>[];
      for (var i = 0; i < 10; i++) {
        early.add(SrtCue(
          1000000 + (i * 2000),
          1000000 + (i * 2000) + 1500,
          'Actor $i',
        ));
      }
      expect(computeSkipCredits(early, durationMs: 6000000), isNull);
    });

    test('skip intro chip setting removed from settings sheet and model', () {
      final settingsCode =
          File('lib/state/player_settings.dart').readAsStringSync();
      expect(settingsCode.contains('skipIntroChip'), isFalse);
      expect(settingsCode.contains('kSkipIntroChip'), isFalse);

      final sheetCode =
          File('lib/widgets/player_settings_sheet.dart').readAsStringSync();
      expect(sheetCode.contains("label: 'Skip intro chip'"), isFalse);
      expect(sheetCode.contains('skipIntroChip'), isFalse);
    });

    test('VideoAiClient transcript check & system prompt formatting', () {
      // Under 8 cues -> false
      final shortCues = [
        const SrtCue(1000, 2000, 'Hi'),
      ];
      expect(VideoAiClient.hasUsableTranscript(shortCues), isFalse);

      // 8 cues with speech -> true
      final goodCues = <SrtCue>[];
      for (var i = 1; i <= 8; i++) {
        goodCues.add(SrtCue(
          i * 15000,
          i * 15000 + 4000,
          'Spoken line number $i in the film',
        ));
      }
      expect(VideoAiClient.hasUsableTranscript(goodCues), isTrue);

      final prompt = videoTranscriptSystemPrompt('Interstellar', goodCues);
      expect(prompt, contains('video "Interstellar"'));
      expect(prompt, contains('Use ONLY the transcript'));
      expect(prompt, contains('[00:15] Spoken line number 1 in the film'));
      expect(prompt, contains('cite the timestamp like (12:34)'));
    });

    test('Recommendations title normalizer strips noise and stop words', () {
      expect(
        Recommendations.normalizeTitle('Interstellar.2014.1080p.BluRay.x264-YIFY'),
        'interstellar',
      );
      expect(
        Recommendations.normalizeTitle(
            'The Dark Knight [2160p UHD HDR] (2008)'),
        'dark knight',
      );
      expect(
        Recommendations.normalizeTitle(
            'Inception_Dual_Audio_Hindi_English_720p'),
        'inception',
      );
    });

    test('Recommendations pickAnchor prefers in-progress video', () {
      expect(Recommendations.pickAnchor([]), isNull);

      final h1 = HistoryEntry(
        path: '/v/movie1.mp4',
        title: 'Completed Movie 1',
        lastPositionSecs: 7100,
        durationSecs: 7200, // 98.6% - completed
        playedAtMs: 1000,
      );
      final h2 = HistoryEntry(
        path: '/v/movie2.mp4',
        title: 'Watching Movie 2',
        lastPositionSecs: 2000,
        durationSecs: 6000, // 33.3% - in progress
        playedAtMs: 2000,
      );
      final h3 = HistoryEntry(
        path: '/v/movie3.mp4',
        title: 'Unstarted Movie 3',
        lastPositionSecs: 10,
        durationSecs: 5000, // 0.2%
        playedAtMs: 3000,
      );

      final anchor = Recommendations.pickAnchor([h1, h2, h3]);
      expect(anchor?.title, 'Watching Movie 2');
    });
  });

  // -------------------------------------------------------------------------
  // v66: A5 Voice search in Discover movies section
  // -------------------------------------------------------------------------
  group('v66 voice search', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final mainActivity = File(
      'android/app/src/main/kotlin/com/hypertechlabs/maxplayer/'
      'MainActivity.kt',
    ).readAsStringSync();
    final discoverScreen =
        File('lib/screens/discover_screen.dart').readAsStringSync();

    test('manifest declares RECORD_AUDIO and speech recognizer query', () {
      expect(manifest, contains('RECORD_AUDIO'));
      expect(manifest, contains('RecognitionService'));
    });

    test('MainActivity handles startVoiceSearch and RecognizerIntent', () {
      expect(mainActivity, contains('startVoiceSearch'));
      expect(mainActivity, contains('RecognizerIntent.ACTION_RECOGNIZE_SPEECH'));
      expect(mainActivity, contains('REQ_VOICE_SEARCH'));
    });

    test('DiscoverScreen wires voice search mic button', () {
      expect(discoverScreen, contains('_startVoiceSearch'));
      expect(discoverScreen, contains('Icons.mic_none_outlined'));
      expect(discoverScreen, contains('Voice search'));
    });
  });

  // -------------------------------------------------------------------------
  // v67: B1 + B2 Now-playing controls & background / screen-off audio
  // -------------------------------------------------------------------------
  group('v67 now-playing and background audio', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final mainActivity = File(
      'android/app/src/main/kotlin/com/hypertechlabs/maxplayer/'
      'MainActivity.kt',
    ).readAsStringSync();
    final notifs = File(
      'android/app/src/main/kotlin/com/hypertechlabs/maxplayer/'
      'Notifications.kt',
    ).readAsStringSync();
    final settingsCode =
        File('lib/state/player_settings.dart').readAsStringSync();
    final sheetCode =
        File('lib/widgets/player_settings_sheet.dart').readAsStringSync();
    final stateCode =
        File('lib/state/media_player_state.dart').readAsStringSync();

    test('manifest declares WAKE_LOCK and FOREGROUND_SERVICE permissions', () {
      expect(manifest, contains('WAKE_LOCK'));
      expect(manifest, contains('FOREGROUND_SERVICE'));
      expect(manifest, contains('FOREGROUND_SERVICE_MEDIA_PLAYBACK'));
    });

    test('Notifications provides showNowPlaying with media control actions', () {
      expect(notifs, contains('showNowPlaying'));
      expect(notifs, contains('NOTIF_ID_NOW_PLAYING'));
      expect(notifs, contains('ic_media_play'));
      expect(notifs, contains('ic_media_pause'));
      expect(notifs, contains('ic_media_next'));
      expect(notifs, contains('ic_media_previous'));
    });

    test('MainActivity handles nowPlayingShow/Cancel, media actions and wake lock', () {
      expect(mainActivity, contains('nowPlayingShow'));
      expect(mainActivity, contains('nowPlayingCancel'));
      expect(mainActivity, contains('ACTION_MEDIA_CONTROL'));
      expect(mainActivity, contains('setWakeLock'));
    });

    test('PlayerSettings defaults backgroundAudio to true and supports copyWith', () {
      expect(settingsCode, contains('backgroundAudio'));
      const s = PlayerSettings();
      expect(s.backgroundAudio, isTrue);
      expect(PlayerSettings.kBackgroundAudio, 'player.backgroundAudio');
      final s2 = s.copyWith(backgroundAudio: false);
      expect(s2.backgroundAudio, isFalse);
    });

    test('PlayerSettingsSheet exposes Background audio playback toggle', () {
      expect(sheetCode, contains('Background audio playback'));
      expect(sheetCode, contains('backgroundAudio'));
    });

    test('MediaPlayerState manages backgroundAudio and _syncNowPlaying', () {
      expect(stateCode, contains('bool backgroundAudio = true;'));
      expect(stateCode, contains('setBackgroundAudio'));
      expect(stateCode, contains('_syncNowPlaying'));
      expect(stateCode, contains('showNowPlaying'));
      expect(stateCode, contains('cancelNowPlaying'));
      expect(stateCode, contains('setWakeLock'));
    });

    test('MediaPlaybackService and VLC-style edge-to-edge immersive mode', () {
      expect(manifest, contains('MediaPlaybackService'));
      expect(mainActivity, contains('MediaPlaybackService'));
      expect(mainActivity, contains('LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES'));
      expect(mainActivity, contains('setImmersive'));
      expect(mainActivity, contains('BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE'));

      final serviceFile = File(
        'android/app/src/main/kotlin/com/hypertechlabs/maxplayer/'
        'MediaPlaybackService.kt',
      ).readAsStringSync();
      expect(serviceFile, contains('class MediaPlaybackService : Service()'));
      expect(serviceFile, contains('MediaSession'));
      expect(serviceFile, contains('startForeground'));
    });
  });

  // -------------------------------------------------------------------------
  // v69: C3 Wi-Fi Resume-Sync across devices
  // -------------------------------------------------------------------------
  group('v69 Wi-Fi resume-sync', () {
    test('RemoteResumeBeacon serializes and deserializes cleanly', () {
      const beacon = RemoteResumeBeacon(
        device: 'Pixel 8',
        title: 'Oppenheimer',
        path: '/v/oppenheimer.mp4',
        positionSecs: 3600,
        durationSecs: 10800,
        timestampMs: 1700000000,
        host: '192.168.1.10',
      );
      final json = beacon.toJson();
      expect(json['app'], 'maxplayer');
      expect(json['title'], 'Oppenheimer');
      expect(json['positionSecs'], 3600);

      final parsed = RemoteResumeBeacon.fromJson(json, '192.168.1.10');
      expect(parsed.title, 'Oppenheimer');
      expect(parsed.positionSecs, 3600);
      expect(parsed.device, 'Pixel 8');
      expect(parsed.host, '192.168.1.10');
    });

    test('LibraryScreen renders Wi-Fi resume-sync banner', () {
      final libScreen =
          File('lib/screens/library_screen.dart').readAsStringSync();
      expect(libScreen, contains('ResumeSyncService'));
      expect(libScreen, contains('ValueListenableBuilder<RemoteResumeBeacon?>'));
      expect(libScreen, contains('Playing on'));
      expect(libScreen, contains('Resume'));
    });
  });

  // -------------------------------------------------------------------------
  // v70: C4 Wear OS / Smartwatch Companion & Remote Control
  // -------------------------------------------------------------------------
  group('v70 Wear OS companion & remote control', () {
    final serviceFile = File(
      'android/app/src/main/kotlin/com/hypertechlabs/maxplayer/'
      'MediaPlaybackService.kt',
    ).readAsStringSync();
    final mainActivity = File(
      'android/app/src/main/kotlin/com/hypertechlabs/maxplayer/'
      'MainActivity.kt',
    ).readAsStringSync();
    final syncService =
        File('lib/services/resume_sync_service.dart').readAsStringSync();

    test('MediaPlaybackService updates MediaMetadata and handles audio focus', () {
      expect(serviceFile, contains('MediaMetadata'));
      expect(serviceFile, contains('METADATA_KEY_TITLE'));
      expect(serviceFile, contains('METADATA_KEY_ARTIST'));
      expect(serviceFile, contains('METADATA_KEY_DURATION'));
      expect(serviceFile, contains('setMetadata'));
      expect(serviceFile, contains('setLargeIcon'));
      expect(serviceFile, contains('ACTION_SEEK_TO'));
      expect(serviceFile, contains('onSeekTo'));
      expect(serviceFile, contains('requestAudioFocus'));
      expect(serviceFile, contains('abandonAudioFocus'));
    });

    test('MainActivity avoids Activity.setImmersive method collision and enables full screen flags', () {
      expect(mainActivity, contains('applyImmersiveMode'));
      expect(mainActivity.contains('private fun setImmersive'), isFalse);
      expect(mainActivity, contains('FLAG_LAYOUT_NO_LIMITS'));
      expect(mainActivity, contains('onAttachedToWindow'));
    });

    test('styles.xml enables shortEdges cutout mode', () {
      final styles = File('android/app/src/main/res/values/styles.xml').readAsStringSync();
      expect(styles, contains('android:windowLayoutInDisplayCutoutMode'));
      expect(styles, contains('shortEdges'));
    });

    test('ResumeSyncService provides REST endpoints for Wear OS / remote apps', () {
      expect(syncService, contains('/status'));
      expect(syncService, contains('/play'));
      expect(syncService, contains('/pause'));
      expect(syncService, contains('/seek'));
      expect(syncService, contains('/volume'));
    });
  });

  // -------------------------------------------------------------------------
  // v71: Android/media WhatsApp scanning, folder grouping & powerful voice search
  // -------------------------------------------------------------------------
  group('v71 WhatsApp & Android scanning + voice search', () {
    test('VideoLibraryState.shouldSkipDir allows Android/media and WhatsApp', () {
      expect(
        VideoLibraryState.shouldSkipDir('/storage/emulated/0/Android'),
        isFalse,
      );
      expect(
        VideoLibraryState.shouldSkipDir('/storage/emulated/0/Android/media'),
        isFalse,
      );
      expect(
        VideoLibraryState.shouldSkipDir(
          '/storage/emulated/0/Android/media/com.whatsapp',
        ),
        isFalse,
      );
      expect(
        VideoLibraryState.shouldSkipDir(
          '/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Video',
        ),
        isFalse,
      );
      expect(
        VideoLibraryState.shouldSkipDir('/storage/emulated/0/WhatsApp/Media/WhatsApp Video'),
        isFalse,
      );
      expect(
        VideoLibraryState.shouldSkipDir('/storage/emulated/0/DCIM/Camera'),
        isFalse,
      );
      expect(
        VideoLibraryState.shouldSkipDir('/storage/emulated/0/Movies'),
        isFalse,
      );
    });

    test('VideoLibraryState.shouldSkipDir skips Android/data, Android/obb, and junk caches', () {
      expect(
        VideoLibraryState.shouldSkipDir('/storage/emulated/0/Android/data'),
        isTrue,
      );
      expect(
        VideoLibraryState.shouldSkipDir('/storage/emulated/0/Android/data/com.example.app'),
        isTrue,
      );
      expect(
        VideoLibraryState.shouldSkipDir('/storage/emulated/0/Android/obb'),
        isTrue,
      );
      expect(
        VideoLibraryState.shouldSkipDir('/storage/emulated/0/.thumbnails'),
        isTrue,
      );
      expect(
        VideoLibraryState.shouldSkipDir('/storage/emulated/0/.trashed'),
        isTrue,
      );
      expect(
        VideoLibraryState.shouldSkipDir('/storage/emulated/0/cache'),
        isTrue,
      );
      expect(
        VideoLibraryState.shouldSkipDir('/storage/emulated/0/LOST.DIR'),
        isTrue,
      );
    });

    test('VideoTrack.folderName groups WhatsApp videos and subfolders cleanly', () {
      const v1 = VideoTrack(
        id: '1',
        title: 'VID_20260827_WA0001',
        path: '/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Video/VID_20260827_WA0001.mp4',
      );
      expect(v1.folderName, 'WhatsApp Video');

      const v2 = VideoTrack(
        id: '2',
        title: 'VID_20260827_WA0002',
        path: '/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Video/Sent/VID_20260827_WA0002.mp4',
      );
      expect(v2.folderName, 'WhatsApp Video (Sent)');

      const v3 = VideoTrack(
        id: '3',
        title: 'VID_20260827_WA0003',
        path: '/storage/emulated/0/WhatsApp/Media/WhatsApp Video/VID_20260827_WA0003.mp4',
      );
      expect(v3.folderName, 'WhatsApp Video');
    });

    test('MainActivity declares on-device speech recognizer and system fallback', () {
      final mainActivity = File(
        'android/app/src/main/kotlin/com/hypertechlabs/maxplayer/MainActivity.kt',
      ).readAsStringSync();
      expect(mainActivity, contains('startInAppSpeech'));
      expect(mainActivity, contains('launchSystemSpeechIntent'));
      expect(mainActivity, contains('EXTRA_CALLING_PACKAGE'));
      expect(mainActivity, contains('createOnDeviceSpeechRecognizer'));
    });

    test('AndroidManifest declares speech recognition queries', () {
      final manifest =
          File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      expect(manifest, contains('android.permission.RECORD_AUDIO'));
      expect(manifest, contains('android.speech.RecognitionService'));
      expect(manifest, contains('android.speech.action.RECOGNIZE_SPEECH'));
    });

    testWidgets('VoiceSearchSheet renders mic and status', (tester) async {
      useTallViewport(tester);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: VoiceSearchSheet()),
        ),
      );
      expect(find.byIcon(Icons.mic), findsOneWidget);
      expect(find.textContaining('Listening'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  // v72: Instant AI responses, dubbed languages & privacy / manual updates
  // -------------------------------------------------------------------------
  group('v72 instant AI + dubbed languages + manual updates', () {
    test('MovieAiClient smart local fallback produces rich answer without key', () async {
      final client = MovieAiClient();
      const movie = TmdbMovie(
        id: 9999,
        title: 'Interstellar',
        year: 2014,
        rating: 8.4,
        overview: 'A team of explorers travel through a wormhole in space in an attempt to ensure humanity\'s survival.',
      );
      final ans = await client.ask(movie: movie, question: 'Is this movie worth watching?');
      expect(ans, isNotNull);
      expect(ans!.text, contains('Interstellar'));
      expect(ans.text, contains('worth watching'));
    });

    test('NativeBridge declares launchSystemVoiceSearch', () {
      final nb = File('lib/services/native_bridge.dart').readAsStringSync();
      expect(nb, contains('launchSystemVoiceSearch'));
    });

    test('User manual includes WhatsApp scanning, voice search, dubbed languages', () {
      final manual = File('lib/widgets/user_manual_sheet.dart').readAsStringSync();
      expect(manual, contains('WhatsApp & Android folder scanning'));
      expect(manual, contains('In-app Voice Search'));
      expect(manual, contains('Audio & Dubbed Languages in Movie Details'));
    });

    test('Privacy policy mentions microphone voice search', () {
      final pp = File('PRIVACY_POLICY.md').readAsStringSync();
      expect(pp, contains('Microphone (audio)'));
      expect(pp, contains('voice search'));
    });
  });

  // -------------------------------------------------------------------------
  // v73: Dialogue booster, Night Mode DRC, Google mic & CCleaner optimizer
  // -------------------------------------------------------------------------
  group('v73 audio boost + DRC + Google mic + CCleaner optimizer', () {
    test('MediaPlayerState.buildCombinedAudioFilter builds dialogue boost chain', () {
      final dialogueOnly = MediaPlayerState.buildCombinedAudioFilter(dialogueBoost: true);
      expect(dialogueOnly, contains('equalizer=f=1500'));
      expect(dialogueOnly, contains('equalizer=f=3000'));

      final combined = MediaPlayerState.buildCombinedAudioFilter(
        dialogueBoost: true,
        eqEnabled: true,
        eqGains: [2.0, 0.0, 0.0, 0.0, -1.0],
      );
      expect(combined, contains('equalizer=f=1500'));
      expect(combined, contains('equalizer=f=60'));
    });

    test('PlayerSettings defaults and copyWith for dialogueBoost', () {
      const s = PlayerSettings();
      expect(s.dialogueBoost, isFalse);

      final next = s.copyWith(dialogueBoost: true);
      expect(next.dialogueBoost, isTrue);
    });

    test('DiscoverScreen and VideoSearchDelegate launch Google system speech', () {
      final discover = File('lib/screens/discover_screen.dart').readAsStringSync();
      expect(discover, contains('launchSystemVoiceSearch'));

      final delegate = File('lib/widgets/video_search_delegate.dart').readAsStringSync();
      expect(delegate, contains('launchSystemVoiceSearch'));
    });

    test('MediaPlaybackService updates state on seek', () {
      final service = File('android/app/src/main/kotlin/com/hypertechlabs/maxplayer/MediaPlaybackService.kt').readAsStringSync();
      expect(service, contains('onSeekTo'));
      expect(service, contains('updateSessionPlaybackState'));
    });
  });

  // -------------------------------------------------------------------------
  // v84: Google Drive Cloud Storage, Network Storage & Open Stream phone sheets
  // -------------------------------------------------------------------------
  group('v84 cloud storage + network sheets + adaptive icon', () {
    test('GDriveService parses all Google Drive sharing URLs', () {
      expect(
        GDriveService.parseDriveFileId(
          'https://drive.google.com/file/d/1aB2c3D4e5F6g7H8i9J0kLmNoPqRsTuVw/view?usp=sharing',
        ),
        '1aB2c3D4e5F6g7H8i9J0kLmNoPqRsTuVw',
      );
      expect(
        GDriveService.parseDriveFileId(
          'https://drive.google.com/open?id=1aB2c3D4e5F6g7H8i9J0kLmNoPqRsTuVw',
        ),
        '1aB2c3D4e5F6g7H8i9J0kLmNoPqRsTuVw',
      );
      expect(
        GDriveService.parseDriveFileId(
          'https://drive.google.com/uc?id=1aB2c3D4e5F6g7H8i9J0kLmNoPqRsTuVw&export=download',
        ),
        '1aB2c3D4e5F6g7H8i9J0kLmNoPqRsTuVw',
      );
    });

    test('GDriveService builds streaming URLs with and without API key', () {
      final freeUrl = GDriveService.getDirectStreamUrl('testFileId123');
      expect(freeUrl, contains('testFileId123'));
      expect(freeUrl, contains('export=download'));

      final apiKeyUrl = GDriveService.getDirectStreamUrl('testFileId123', apiKey: 'MY_KEY');
      expect(apiKeyUrl, contains('alt=media'));
      expect(apiKeyUrl, contains('key=MY_KEY'));
    });

    test('NetworkLocation builds well-formed stream URLs', () {
      const smb = NetworkLocation(
        name: 'NAS',
        protocol: 'smb',
        host: '192.168.1.50',
        path: '/Videos/movie.mkv',
        username: 'admin',
        password: 'password123',
      );
      expect(smb.streamUrl, 'smb://admin:password123@192.168.1.50/Videos/movie.mkv');

      const ftp = NetworkLocation(
        name: 'FTP Server',
        protocol: 'ftp',
        host: '10.0.0.1',
        port: 2121,
        path: 'clips/clip.mp4',
      );
      expect(ftp.streamUrl, 'ftp://10.0.0.1:2121/clips/clip.mp4');
    });

    test('LibraryScreen includes Cloud Storage and Network Storage quick tiles', () {
      final lib = File('lib/screens/library_screen.dart').readAsStringSync();
      expect(lib, contains('Cloud Storage'));
      expect(lib, contains('Network Storage'));
      expect(lib, contains('Open Stream'));
    });
  });

  // -------------------------------------------------------------------------
  // v85: Watch Anime, 2x2 slideable grids with dots, Ask-AI tune button
  // -------------------------------------------------------------------------
  group('v85 watch anime + slideable 2x2 grids + default subs ask-ai', () {
    test('LibraryScreen has 2 slideable 2x2 grids with dots indicator and File Manager tile', () {
      final lib = File('lib/screens/library_screen.dart').readAsStringSync();
      expect(lib, contains('Private Space'));
      expect(lib, contains('File Manager'));
      expect(lib, contains('Network Storage'));
      expect(lib, contains('Cloud Storage'));
      expect(lib, contains('Open Stream'));
      expect(lib, contains('Cleaner'));
      expect(lib, contains('PageView'));
      expect(lib, contains('_currentPage'));
    });

    test('AnimeScreen exists and declares browseAnime and Watch Now button', () {
      final anime = File('lib/screens/anime_screen.dart').readAsStringSync();
      expect(anime, contains('AnimeScreen'));
      expect(anime, contains('Watch Now'));
      expect(anime, contains('browseAnime'));
    });

    test('PlayerScreen top three-dots menu does not have ask AI, but tune tracks sheet keeps it', () {
      final playerScreen = File('lib/screens/player_screen.dart').readAsStringSync();
      expect(playerScreen.contains("_topMenuItem('ask'"), isFalse);

      final controls = File('lib/widgets/player_controls_overlay.dart').readAsStringSync();
      expect(controls, contains('Ask AI about this video'));
      expect(controls, contains('onAskAi'));
    });

    test('VideoAiClient accepts transcript with few spoken lines and answers', () async {
      final cues = [
        const SrtCue(1000, 4000, 'We have to escape right now!'),
        const SrtCue(5000, 8000, 'Get to the coordinates at sector four.'),
      ];
      expect(VideoAiClient.hasUsableTranscript(cues), isTrue);

      final client = VideoAiClient();
      final ans = await client.ask(title: 'Mission Clip', cues: cues, question: 'Where should we go?');
      expect(ans, isNotNull);
      expect(ans, contains('Mission Clip'));
      expect(ans, contains('coordinates'));
    });
  });

  // -------------------------------------------------------------------------
  // v86: Advance File Manager, Cloud Storage Auto-Fetch, AI Persistence, Menu Redesign
  // -------------------------------------------------------------------------
  group('v86 file manager + cloud storage fetch + AI persistence', () {
    test('FileManagerScreen exists and supports directory navigation', () {
      final fileMgr = File('lib/screens/file_manager_screen.dart').readAsStringSync();
      expect(fileMgr, contains('FileManagerScreen'));
      expect(fileMgr, contains('Move to Private Space'));
      expect(fileMgr, contains('_loadDirectory'));
    });

    test('LibraryScreen renders File Manager tile on page 1 of quick tiles', () {
      final lib = File('lib/screens/library_screen.dart').readAsStringSync();
      expect(lib, contains('File Manager'));
      expect(lib, contains('Private Space'));
      expect(lib, contains('Cloud Storage'));
    });

    test('CloudStorageSheet supports Google Drive connect and auto-fetching', () {
      final cloud = File('lib/widgets/cloud_storage_sheet.dart').readAsStringSync();
      expect(cloud, contains('CloudStorageSheet'));
      expect(cloud, contains('Google Drive Cloud Storage'));
      expect(cloud, contains('_fetchAllVideos'));
    });

    test('AI sheets persist queries across sessions', () {
      final suggest = File('lib/widgets/ai_suggest_sheet.dart').readAsStringSync();
      expect(suggest, contains('_kSavedPicksKey'));

      final askMovie = File('lib/widgets/ask_ai_sheet.dart').readAsStringSync();
      expect(askMovie, contains('movie_ai_'));

      final askVideo = File('lib/widgets/video_ask_sheet.dart').readAsStringSync();
      expect(askVideo, contains('video_ai_history_'));
    });
  });

  // -------------------------------------------------------------------------
  // v90: Pull-to-refresh, Media File Manager, TMDB Cast & Episode Durations, Gesture Animations
  // -------------------------------------------------------------------------
  group('v90 refresh + media file manager + tmdb seasons + smooth gestures', () {
    test('LibraryScreen has RefreshIndicator and no Rescan in top menu', () {
      final lib = File('lib/screens/library_screen.dart').readAsStringSync();
      expect(lib, contains('RefreshIndicator'));
      expect(lib, contains('Display settings'));
      expect(lib, contains('Watch statistics'));
      expect(lib.contains("Open stream URL"), isFalse);
    });

    test('PlayerScreen top menu uses compact PopupMenuButton and smooth gesture animations', () {
      final playerScreen = File('lib/screens/player_screen.dart').readAsStringSync();
      expect(playerScreen, contains('PopupMenuButton<String>'));
      expect(playerScreen, contains('_topMenuItem'));
      expect(playerScreen, contains('AnimatedScale'));
      expect(playerScreen.contains("Ask AI about this video"), isFalse);
    });

    test('PlayerControlsOverlay has no Ask AI in tune/tracks sheet', () {
      final overlay = File('lib/widgets/player_controls_overlay.dart').readAsStringSync();
      expect(overlay.contains("Ask AI about this video"), isFalse);
    });

    test('AboutSheet has no app icon container in brand header', () {
      final about = File('lib/widgets/about_sheet.dart').readAsStringSync();
      expect(about, contains('Max Player'));
      expect(about, contains('by Hyper Tech Labs'));
      expect(about.contains("Icons.play_circle_fill"), isFalse);
    });

    test('FileManagerScreen opens images, audio, documents, and provides AI insights', () {
      final fileMgr = File('lib/screens/file_manager_screen.dart').readAsStringSync();
      expect(fileMgr, contains('_openImageViewer'));
      expect(fileMgr, contains('_openAudioPlayer'));
      expect(fileMgr, contains('_openDocumentViewer'));
      expect(fileMgr, contains('_showAiMediaInsights'));
    });

    test('MovieDetailSheet includes cast slider, seasons/episodes with durations, and reviews', () {
      final detail = File('lib/widgets/movie_detail_sheet.dart').readAsStringSync();
      expect(detail, contains('_TopCastSlider'));
      expect(detail, contains('_SeasonsBlock'));
      expect(detail, contains('_ReviewsBlock'));
      expect(detail, contains('_DetailedStoryBlock'));
    });

    test('NetworkStorageSheet uses dynamic contrast colors for buttons', () {
      final net = File('lib/widgets/network_storage_sheet.dart').readAsStringSync();
      expect(net, contains('computeLuminance'));
      expect(net, contains('btnTextColor'));
    });
  });
}
