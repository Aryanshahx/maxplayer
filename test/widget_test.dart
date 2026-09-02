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

void main() {
  group('formatters', () {
    test('formats file sizes', () {
      expect(formatFileSize(0), '0 B');
      expect(formatFileSize(512), '512 B');
      expect(formatFileSize(1024), '1.0 KB');
      expect(formatFileSize(1536), '1.5 KB');
      expect(formatFileSize(1024 * 1024), '1.0 MB');
      expect(formatFileSize(1024 * 1024 * 1024), '1.0 GB');
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
      final now = DateTime.now();
      expect(timeAgo(now.subtract(const Duration(minutes: 5))), 'Just now');
      expect(timeAgo(now.subtract(const Duration(hours: 2))), '2h ago');
      expect(timeAgo(now.subtract(const Duration(days: 3))), '3d ago');
    });

    test('maps the SHORTER side to a resolution badge', () {
      expect(resolutionBadge(1920, 1080), '1080p');
      expect(resolutionBadge(1280, 720), '720p');
      expect(resolutionBadge(3840, 2160), '4K');
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

    test('Formatters define tmdbRatingText, formatRuntime and formatVoteCount', () {
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
}
