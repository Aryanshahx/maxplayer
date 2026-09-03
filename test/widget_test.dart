import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// v94: v93 imported 45 app libraries but this suite only ever touches five
// of them - the other 40 were unused_import warnings that drowned out real
// problems. (They were invisible in v93 only because the file's resolution
// errors suppressed the hint.)
import 'package:maxplayer/models/video_track.dart';
import 'package:maxplayer/services/media_ai.dart';
import 'package:maxplayer/services/tmdb_client.dart';
import 'package:maxplayer/utils/formatters.dart';

void main() {
  group('formatters', () {
    test('formats file sizes', () {
      expect(formatFileSize(0), '0 B');
      expect(formatFileSize(512), '512 B');
      expect(formatFileSize(1024), '1.0 KB');
      expect(formatFileSize(1536), '1.5 KB');
      expect(formatFileSize(1024 * 1024), '1.0 MB');
      expect(formatFileSize(1024 * 1024 * 1024), '1.00 GB');
    });

    test('formats durations', () {
      expect(formatDuration(Duration.zero), '0:00');
      expect(formatDuration(const Duration(seconds: 45)), '0:45');
      expect(formatDuration(const Duration(minutes: 3, seconds: 5)), '3:05');
      expect(
          formatDuration(const Duration(hours: 1, minutes: 2, seconds: 3)),
          '1:02:03');
    });

    test('detects video extensions case-insensitively', () {
      expect(isVideoFile('movie.mp4'), isTrue);
      expect(isVideoFile('MOVIE.MP4'), isTrue);
      expect(isVideoFile('clip.mkv'), isTrue);
      expect(isVideoFile('song.mp3'), isFalse);
    });

    test('timeAgo buckets', () {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      expect(
          timeAgo(nowMs - const Duration(minutes: 5).inMilliseconds), '5m ago');
      expect(
          timeAgo(nowMs - const Duration(hours: 2).inMilliseconds), '2h ago');
      expect(
          timeAgo(nowMs - const Duration(days: 3).inMilliseconds), '3d ago');
    });

    test('maps the SHORTER side to a resolution badge', () {
      String? badge(int w, int h) => VideoTrack(
            id: 'x',
            title: 'x',
            path: '/sdcard/Movies/x.mp4',
            width: w,
            height: h,
          ).qualityLabel;
      expect(badge(1920, 1080), '1080p');
      expect(badge(1280, 720), '720p');
      expect(badge(3840, 2160), '4K');
    });
  });

  group('v93 complete suite tests', () {
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
      // v95: Ask AI is REMOVED from the player entirely (developer
      // request: "remove ask ai about this video from three dots").
      // lib/widgets/video_ask_sheet.dart stays on disk, unwired.
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
      expect(fileMgr, contains('widget.player.seekBy'));
      expect(fileMgr, contains('widget.player.togglePlay'));
      expect(fileMgr.contains('seekRelative'), isFalse);
    });

    test('MovieDetailSheet includes cast slider, seasons/episodes with durations, and reviews', () {
      final detail = File('lib/widgets/movie_detail_sheet.dart').readAsStringSync();
      expect(detail, contains('_TopCastSlider'));
      expect(detail, contains('_SeasonsBlock'));
      expect(detail, contains('_ReviewsBlock'));
      expect(detail, contains('_DetailedStoryBlock'));
    });

    test('TmdbClient defines tmdbRatingText, formatRuntime and formatVoteCount', () {
      expect(tmdbRatingText(8.365), '8.4');
      expect(formatRuntime(136), '2h 16m');
      expect(formatRuntime(45), '45m');
      expect(formatVoteCount(24513), '24,513');
    });

    test('NetworkStorageSheet uses dynamic contrast colors for buttons', () {
      final net = File('lib/widgets/network_storage_sheet.dart').readAsStringSync();
      expect(net, contains('computeLuminance'));
      expect(net, contains('btnTextColor'));
    });
  });

  group('v95 media_ai - real File Manager insights', () {
    test('finds orphaned subtitles, duplicates and the largest file', () {
      final stats = MediaFolderStats(
        folderName: 'Movies',
        dirs: 1,
        files: const [
          MediaFileInfo('Dune.mkv', 2147483648, MediaKind.video),
          MediaFileInfo('Dune.mkv', 2147483648, MediaKind.video),
          MediaFileInfo('Dune.srt', 40960, MediaKind.subtitle),
          MediaFileInfo('Orphan.srt', 30720, MediaKind.subtitle),
          MediaFileInfo('notes.xyz', 1024, MediaKind.other),
        ],
      );
      expect(stats.videos, 2);
      expect(stats.subtitles, 2);
      expect(stats.others, 1);
      // 'Dune.srt' pairs with 'Dune.mkv'; 'Orphan.srt' has nothing to attach to.
      expect(stats.orphanedSubtitles.map((f) => f.name).toList(), ['Orphan.srt']);
      // Two byte-identical videos over the 1 MB floor = one duplicate group.
      expect(stats.duplicateCandidates.length, 1);
      expect(stats.largest!.bytes, 2147483648);
      expect(stats.topExtensions['mkv'], 2);
    });

    test('insights come from the data, never from one fixed sentence', () {
      final empty = MediaFolderStats(folderName: 'A', dirs: 0, files: const []);
      final one = MediaFolderStats(
        folderName: 'B',
        dirs: 0,
        files: const [MediaFileInfo('Orphan.srt', 1024, MediaKind.subtitle)],
      );
      final emptyText = localMediaInsights(empty).join(' ');
      final oneText = localMediaInsights(one).join(' ');
      expect(emptyText, isNot(oneText));
      expect(oneText, contains('Orphan.srt'));
      // The v93 hardcoded marketing line must never come back.
      expect(oneText, isNot(contains('fully accelerated by libmpv')));
      expect(emptyText, isNot(contains('fully accelerated by libmpv')));
    });

    test('File Manager wires the real service, not a static string', () {
      final fm = File('lib/screens/file_manager_screen.dart').readAsStringSync();
      expect(fm, contains("import '../services/media_ai.dart';"));
      expect(fm, contains('MediaAiClient.ask('));
      expect(fm, contains('localMediaInsights('));
      expect(fm, isNot(contains('fully accelerated by libmpv')));
    });
  });
}
