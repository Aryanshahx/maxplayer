import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// v94: v93 imported 45 app libraries but this suite only ever touches five
// of them - the other 40 were unused_import warnings that drowned out real
// problems. (They were invisible in v93 only because the file's resolution
// errors suppressed the hint.)
import 'package:maxplayer/models/video_track.dart';
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

    test('FileManagerScreen opens images, audio and documents', () {
      final fileMgr = File('lib/screens/file_manager_screen.dart').readAsStringSync();
      expect(fileMgr, contains('_openImageViewer'));
      expect(fileMgr, contains('_openAudioPlayer'));
      expect(fileMgr, contains('_openDocumentViewer'));
      // v96: the developer asked for the File Manager's AI to be removed
      // entirely, so pin its absence instead of its presence.
      expect(fileMgr.contains('_showAiMediaInsights'), isFalse);
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

  group('v96 removals and regression guards', () {
    test('File Manager AI and its service are gone', () {
      expect(File('lib/services/media_ai.dart').existsSync(), isFalse);
      final fm = File('lib/screens/file_manager_screen.dart').readAsStringSync();
      expect(fm.contains('media_ai.dart'), isFalse);
      expect(fm.contains('_showAiMediaInsights'), isFalse);
      expect(fm.contains('AI Media Insights'), isFalse);
      expect(fm.contains('_aiStatRow'), isFalse);
      expect(fm.contains('_mediaKind'), isFalse);
    });

    test('season chips are tappable again (v95 dropped onSelected)', () {
      // A ChoiceChip with a null onSelected is DISABLED. v95 lost that line,
      // which is why season buttons stopped responding to taps. This guard
      // exists because `flutter analyze` structurally cannot catch it.
      final detail = File('lib/widgets/movie_detail_sheet.dart').readAsStringSync();
      expect(detail, contains('onSelected: (_) => _loadSeasonDetail(s.number)'));
    });

    test('no white-on-white buttons survive on an accent background', () {
      // Both the season chips (v95) and the Resume button (v96) painted
      // hardcoded white on themeState.accent, and the default accent IS white.
      final lib = File('lib/screens/library_screen.dart').readAsStringSync();
      expect(lib, contains('foregroundColor: themeState.onAccent'));
    });

    test('episode and season synopses are no longer clamped', () {
      final detail = File('lib/widgets/movie_detail_sheet.dart').readAsStringSync();
      expect(detail.contains('_seasonDetail!.overview,\n                      maxLines'), isFalse);
      expect(detail.contains('ep.overview,\n                                  maxLines'), isFalse);
    });
  });
  group('v97 low-end performance', () {
    test('hardware decoding is enabled at startup, not left to the default', () {
      final s = File('lib/state/media_player_state.dart').readAsStringSync();
      // libmpv's own default for hwdec is `no` (software). Before v97 nothing
      // set it at startup - it was only touched when toggling Enhance - so a
      // cold launch could software-decode every video.
      expect(s, contains("'hwdec': 'auto-safe'"));
      // The software fallback for buggy decoders must still exist.
      expect(s, contains('_hwFallbackForPath'));
      expect(s, contains("unawaited(plat.setProperty('hwdec', 'no'))"));
    });

    test('mpv render-side scalers take the cheap path', () {
      final s = File('lib/state/media_player_state.dart').readAsStringSync();
      for (final k in ['scale', 'cscale', 'dscale']) {
        expect(s, contains("'$k': 'bilinear'"));
      }
      expect(s, contains("'deband': 'no'"));
      // The v51 demuxer/decode caps must not have been lost.
      expect(s, contains("'demuxer-max-bytes': '32MiB'"));
      expect(s, contains("'vd-lavc-skiploopfilter': 'nonref'"));
    });

    test('position events no longer rebuild the UI at 10-30 Hz', () {
      final s = File('lib/state/media_player_state.dart').readAsStringSync();
      expect(s, contains('static const int kPosNotifyMs'));
      expect(s, contains('_lastPosNotify'));
      // Seeks must still notify at once so scrubbing stays responsive.
      expect(s, contains('final jumped = (v - prev).abs()'));
      // The per-event logic that genuinely needs full precision must survive.
      expect(s, contains('_checkSleepAtEnd(v);'));
      expect(s, contains('_maybeAutoSkipCredits(v);'));
      expect(s, contains('_maybeCaptureThumb(v);'));
      // The 500ms guaranteed pulse is what keeps the bar from looking frozen.
      expect(s, contains('Timer.periodic(const Duration(milliseconds: 500)'));
    });
  });
  group('v99 tile swap, indicator cross-fade, settings-only Cast/Screenshot removal', () {
    test('Cloud Storage and File Manager swapped pages', () {
      final lib = File('lib/screens/library_screen.dart').readAsStringSync();
      // Page 1 now ends with Cloud Storage; File Manager moved to page 2.
      // Both labels occur exactly once, so index order == page order.
      expect(
          lib.indexOf("'Cloud Storage'") < lib.indexOf("'File Manager'"),
          isTrue);
      expect(
          lib,
          contains(
              'Page 1: Private Space, Playlists, Folders, Cloud Storage'));
      expect(
          lib,
          contains(
              'Page 2: Network Storage, File Manager, Open Stream(iptv), Cleaner'));
    });

    test('indicator content cross-fades on every change', () {
      final ps = File('lib/screens/player_screen.dart').readAsStringSync();
      expect(ps, contains('AnimatedSwitcher'));
      // v100 removed the old blink pill (ValueKey(_indicatorKey..) wrapper +
      // reverseDuration); the switcher that remains is the speed badge with
      // a fade+scale transition on every change.
      expect(ps.contains("ValueKey(_indicatorKey ?? 'hidden')"), isFalse);
      expect(ps.contains('reverseDuration'), isFalse);
      expect(ps, contains("ValueKey('speedBadge')"));
      expect(ps, contains('FadeTransition'));
      expect(ps, contains('ScaleTransition'));
      // The pill show/hide animation must survive.
      expect(ps, contains('AnimatedScale'));
      expect(ps, contains('AnimatedOpacity'));
    });

    test('Cast/Screenshot leave Player settings but stay in the player menu',
        () {
      final sheet =
          File('lib/widgets/player_settings_sheet.dart').readAsStringSync();
      expect(sheet.contains('Cast to TV (DLNA)'), isFalse);
      expect(sheet.contains('Screenshot button'), isFalse);
      final ps = File('lib/screens/player_screen.dart').readAsStringSync();
      // Ungated: no setting left to hide behind.
      expect(
          ps,
          contains(
              "_topMenuItem('shot', Icons.camera_alt_outlined, 'Screenshot')"));
      expect(
          ps,
          contains("_topMenuItem('cast', Icons.cast_outlined, 'Cast to TV')"));
      expect(ps.contains('if (_settings.screenshotButton)'), isFalse);
      expect(ps.contains('if (_settings.castButton)'), isFalse);
    });
  });
  group('v100 blink removal, audio helpers', () {
    test('volume/brightness values swap instantly again (no blink)', () {
      final ps = File('lib/screens/player_screen.dart').readAsStringSync();
      // The v99 wrapper (and only it) is gone - a pre-existing, unrelated
      // AnimatedSwitcher lives on elsewhere in this file.
      expect(ps.contains("ValueKey(_indicatorKey ?? 'hidden')"), isFalse);
      // The pill pop itself must survive.
      expect(ps, contains('AnimatedScale'));
      expect(ps, contains('AnimatedOpacity'));
      expect(ps, contains('_indicatorKey'));
    });

    test('v105 camera features are fully removed', () {
      // Source files deleted (git history keeps them if ever needed).
      expect(File('lib/services/drowsy_detector.dart').existsSync(), isFalse);
      expect(File('lib/utils/air_gestures.dart').existsSync(), isFalse);
      // No plugin left behind (storage permission stays - File Manager
      // scans folders through it, nothing to do with the camera).
      final pub = File('pubspec.yaml').readAsStringSync();
      for (final k in [
        'hand_landmarker',
        'google_mlkit_face_detection',
        'camera_android',
        'camera:',
      ]) {
        expect(pub.contains(k), isFalse);
      }
      expect(pub, contains('permission_handler'));
      final manifest =
          File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      expect(manifest.contains('android.permission.CAMERA'), isFalse);
      // No dangling references in the six touched files.
      final s = File('lib/state/media_player_state.dart').readAsStringSync();
      for (final k in [
        'DrowsyDetector',
        'drowsy_detector',
        'DrowsyEvent',
        'AirAction',
        'air_gestures',
        'drowsyStatus',
        'applyAirAction',
        'onAirAction',
        'autoSleepDetect',
        'lookAwayPause',
        'airGestures',
        'setDrowsyForeground',
        '_onAirAction',
        '_syncDrowsy',
        '_handsSub',
        'HandLandmarkerPlugin',
        'landmarkStream',
        'processFrame',
        'setAirGestures',
        'Permission.camera',
        'permission_handler',
        'Camera will pause',
      ]) {
        expect(s.contains(k), isFalse);
      }
      for (final f in [
        'lib/state/player_settings.dart',
        'lib/widgets/player_controls_overlay.dart',
        'lib/widgets/user_manual_sheet.dart',
        'lib/screens/player_screen.dart',
        'lib/widgets/player_settings_sheet.dart',
      ]) {
        final src = File(f).readAsStringSync();
        for (final k in [
          'autoSleepDetect',
          'lookAwayPause',
          'airGestures',
          'kAutoSleepDetect',
          'kLookAwayPause',
          'kAirGestures',
          'Air gestures',
          'Look-away auto-pause',
          'Auto-detect sleep',
          'Permission.camera',
        ]) {
          expect(src.contains(k), isFalse);
        }
      }
      // The relocated picture rows persist through the kept settings keys.
      final settings =
          File('lib/state/player_settings.dart').readAsStringSync();
      for (final k in [
        'kEnhanceVideo',
        'kToneMapping',
        'player.enhanceVideo',
        'player.toneMapping',
        'kDialogueBoost',
        'kKaraokeSubs',
      ]) {
        expect(settings, contains(k));
      }
      // Screenshot icons are not camera features - they must survive.
      final ps = File('lib/screens/player_screen.dart').readAsStringSync();
      expect(ps, contains('Icons.camera_alt'));
      // Leveling deleted everywhere (settings keys die with it).
      for (final f in [
        'lib/state/media_player_state.dart',
        'lib/state/player_settings.dart',
        'lib/widgets/player_controls_overlay.dart',
        'lib/widgets/user_manual_sheet.dart',
      ]) {
        final src = File(f).readAsStringSync();
        expect(src.contains('autoLeveling'), isFalse);
        expect(src.contains('dynaudnorm'), isFalse);
        expect(src.contains('Auto volume leveling'), isFalse);
      }
      // Dialogue subtitle trimmed as requested.
      final overlaySrc =
          File('lib/widgets/player_controls_overlay.dart').readAsStringSync();
      expect(
          overlaySrc,
          contains(
              "'Lifts quiet speech (1-4 kHz). Off by default.'"));
      expect(overlaySrc.contains('Same on-device filter as before'), isFalse);
    });

    test('sleep sheet keeps plain timers, camera rows gone', () {
      final ps = File('lib/screens/player_screen.dart').readAsStringSync();
      expect(ps.contains('Auto-detect sleep'), isFalse);
      expect(ps.contains('Permission.camera.request'), isFalse);
      // The plain sleep timer rows stay.
      expect(ps, contains('Until end of this video'));
      final overlay =
          File('lib/widgets/player_controls_overlay.dart').readAsStringSync();
      expect(overlay.contains('Look-away auto-pause'), isFalse);
      expect(overlay, contains('Dialogue boost'));
    });

    test('v105 picture rows live below Karaoke', () {
      final overlay =
          File('lib/widgets/player_controls_overlay.dart').readAsStringSync();
      final karaoke = overlay.indexOf('Karaoke subtitles');
      final enhance = overlay.indexOf('Enhance video');
      final tone = overlay.indexOf('HDR tone-mapping');
      final dialogue = overlay.indexOf('Dialogue boost');
      expect(karaoke, greaterThanOrEqualTo(0));
      // Karaoke, then Enhance, then tone-mapping, then dialogue.
      expect(enhance, greaterThan(karaoke));
      expect(tone, greaterThan(enhance));
      expect(dialogue, greaterThan(tone));
      // Rows are wired to the player state + persisted settings keys.
      // (Tone persistence lives in the state setter - single writer - so
      // the overlay only calls setToneMapping.)
      for (final k in [
        'player.enhanceVideoOn',
        'setEnhanceVideo',
        'PlayerSettings.kEnhanceVideo',
        'player.toneMappingMode',
        'setToneMapping',
      ]) {
        expect(overlay, contains(k));
      }
      final state =
          File('lib/state/media_player_state.dart').readAsStringSync();
      expect(state, contains('PlayerSettings.kToneMapping'));
      // Gone from Player settings (moved, not duplicated).
      final sheet =
          File('lib/widgets/player_settings_sheet.dart').readAsStringSync();
      expect(sheet.contains("_SectionHeader('Picture')"), isFalse);
      expect(sheet.contains('Enhance video'), isFalse);
      expect(sheet.contains('HDR tone-mapping'), isFalse);
    });

    test('v106 Google Sign-In powers Drive', () {
      // v111: the Google Sign-In / Drive-API path was REMOVED (developer
      // request: "remove sign in with google from cloud storage"); import
      // runs fully through the SAF picker. These pins flipped to absence.
      final pub = File('pubspec.yaml').readAsStringSync();
      expect(pub.contains('google_sign_in'), isFalse);
      expect(File('lib/services/gdrive_service.dart').existsSync(), isFalse);
      final sheet =
          File('lib/widgets/cloud_storage_sheet.dart').readAsStringSync();
      expect(sheet.contains('Sign in with Google'), isFalse);
      expect(sheet.contains('GDriveAuth'), isFalse);
      expect(sheet.contains('google_sign_in'), isFalse);
      expect(sheet.contains('Access Key'), isFalse);
      expect(sheet.contains('gdrive.access_token'), isFalse);
      // Authed playback path: headers ride the track into mpv.
      final track =
          File('lib/models/video_track.dart').readAsStringSync();
      expect(track, contains('httpHeaders'));
      final state =
          File('lib/state/media_player_state.dart').readAsStringSync();
      expect('httpHeaders: track.httpHeaders'.allMatches(state).length, 2);
      expect(state, contains('playStream(String url, String title'));
      expect(state, contains('httpHeaders: httpHeaders'));
    });

    test('v106 fix: mic prompt, media permissions, sign-in details', () {
      final discover =
          File('lib/screens/discover_screen.dart').readAsStringSync();
      expect(discover, contains('Permission.microphone.request'));
      expect(discover, contains('Microphone needed for voice search'));
      final delegate =
          File('lib/widgets/video_search_delegate.dart').readAsStringSync();
      expect(delegate, contains('Permission.microphone.request'));
      final storage =
          File('lib/utils/storage_permission.dart').readAsStringSync();
      for (final k in [
        'Permission.videos.request',
        'Permission.photos.request',
        'Permission.audio.request',
      ]) {
        expect(storage, contains(k));
      }
      final sheet =
          File('lib/widgets/cloud_storage_sheet.dart').readAsStringSync();
      // v111: sign-in error reporting is gone with the sign-in screen.
      expect(sheet.contains('GoogleSignInException'), isFalse);
    });

    test('v106-fix2 sleep scrolls, silent sign-in gated', () {
      final ps = File('lib/screens/player_screen.dart').readAsStringSync();
      final sleepStart = ps.indexOf('void _showSleepSheet()');
      final sleepEnd =
          ps.indexOf('Widget build(BuildContext context)', sleepStart);
      final sleepSheet = ps.substring(sleepStart, sleepEnd);
      expect(sleepSheet, contains('isScrollControlled: true'));
      expect(sleepSheet, contains('SingleChildScrollView'));
      final sheet =
          File('lib/widgets/cloud_storage_sheet.dart').readAsStringSync();
      // v111: the import-only sheet has no sessions left to gate.
      expect(sheet, contains('_importVideo'));
      expect(sheet.contains('email == null || email.isEmpty'), isFalse);
    });

    test('v107 forced updates, sticky sign-in, branding docs', () {
      final pub = File('pubspec.yaml').readAsStringSync();
      expect(pub, contains('in_app_update'));
      final lib = File('lib/screens/library_screen.dart').readAsStringSync();
      for (final k in [
        'InAppUpdate.checkForUpdate',
        'performImmediateUpdate',
        'UpdateAvailability.updateAvailable',
      ]) {
        expect(lib, contains(k));
      }
      final sheet =
          File('lib/widgets/cloud_storage_sheet.dart').readAsStringSync();
      // v111: picker-only - none of the sticky sign-in machinery remains.
      expect(sheet.contains('email == null || email.isEmpty'), isFalse);
      expect(sheet.contains('stop trying on future opens'), isFalse);
      for (final f in [
        'docs/index.html',
        'docs/privacy.html',
        'docs/terms.html',
      ]) {
        expect(File(f).existsSync(), isTrue);
      }
      final privacy = File('docs/privacy.html').readAsStringSync();
      expect(privacy, contains('Drive'));
      final terms = File('docs/terms.html').readAsStringSync();
      expect(terms, contains('as is'));
    });

    test('v108 karaoke switch, iptv label, docs, sticky session', () {
      final overlay =
          File('lib/widgets/player_controls_overlay.dart').readAsStringSync();
      final karaokeStart = overlay.indexOf('Karaoke subtitles');
      final karaokeEnd = overlay.indexOf('HDR tone-mapping', karaokeStart);
      final karaokeRow = overlay.substring(karaokeStart, karaokeEnd);
      expect(karaokeRow, contains('SwitchListTile'));
      expect(karaokeRow, contains('onToggleKaraoke'));
      expect(karaokeRow.contains('Navigator.of(sheetContext).pop'), isFalse);
      final lib = File('lib/screens/library_screen.dart').readAsStringSync();
      expect(lib, contains("'Open Stream(iptv)'"));
      final streamSheet =
          File('lib/widgets/open_stream_sheet.dart').readAsStringSync();
      expect(streamSheet, contains('Open Stream(iptv)'));
      expect(File('TERMS_OF_SERVICE.md').existsSync(), isTrue);
      final termsMd = File('TERMS_OF_SERVICE.md').readAsStringSync();
      expect(termsMd, contains('HyperTech Labs'));
      final manual =
          File('lib/widgets/user_manual_sheet.dart').readAsStringSync();
      for (final k in [
        'on/off ',
        'Import from cloud storage',
      ]) {
        expect(manual, contains(k));
      }
      // v111: gdrive_service.dart was deleted along with the sign-in flow.
      expect(File('lib/services/gdrive_service.dart').existsSync(), isFalse);
      final sheet =
          File('lib/widgets/cloud_storage_sheet.dart').readAsStringSync();
      expect(sheet.contains('GDriveAuth.remember'), isFalse);
      final md = File('PRIVACY_POLICY.md').readAsStringSync();
      expect(md, contains('Google Drive'));
      expect(md, contains('5 September 2026'));
    });
    test('v109 instant karaoke, manual trim, sticky sign-in kept', () {
      final overlay =
          File('lib/widgets/player_controls_overlay.dart').readAsStringSync();
      // Switch reads LIVE player state -> flips the instant it is tapped.
      expect(overlay, contains('value: player.karaokeMode'));
      // No '(on)' label anymore - fixed text in both states.
      expect(overlay.contains('Karaoke subtitles (on)'), isFalse);
      expect(overlay, contains("'Karaoke subtitles'"));
      final manual =
          File('lib/widgets/user_manual_sheet.dart').readAsStringSync();
      expect(manual.contains('Automatic app updates'), isFalse);
      expect(manual.contains('Some thumbnails missing?'), isFalse);
      // v111: sign-in manual entry replaced by the import-only entry.
      expect(manual.contains('Google Drive sign-in'), isFalse);
      expect(manual, contains('Import from cloud storage'));
      final sheet =
          File('lib/widgets/cloud_storage_sheet.dart').readAsStringSync();
      expect(sheet.contains('GDriveAuth.recall()'), isFalse);
      expect(sheet.contains('GDriveAuth.remember'), isFalse);
      expect(File('lib/services/gdrive_service.dart').existsSync(), isFalse);
    });

    group('v110 SAF picker, lock-screen media notification, docs', () {
      test('system file picker is wired end-to-end', () {
        final pub = File('pubspec.yaml').readAsStringSync();
        expect(pub, contains('version: 1.0.0+'));
        final bridge =
            File('lib/services/native_bridge.dart').readAsStringSync();
        for (final k in [
          'pickVideoDocument',
          'saveDocumentToDevice',
          'savePickedVideoToDevice',
        ]) {
          expect(bridge, contains(k));
        }
        final sheet =
            File('lib/widgets/cloud_storage_sheet.dart').readAsStringSync();
        expect(sheet, contains('Import from cloud storage'));
        expect(sheet, contains('_importVideo'));
        expect(sheet, contains('Save to device'));
        final mainKt = File(
                'android/app/src/main/kotlin/com/hypertechlabs/maxplayer/MainActivity.kt')
            .readAsStringSync();
        for (final k in [
          'ACTION_OPEN_DOCUMENT',
          'REQ_SAF_PICK',
          'takePersistableUriPermission',
          'private fun saveDocumentToDevice',
        ]) {
          expect(mainKt, contains(k));
        }
      });

      test('now-playing is a lock-screen MediaStyle notification', () {
        final svc = File(
                'android/app/src/main/kotlin/com/hypertechlabs/maxplayer/MediaPlaybackService.kt')
            .readAsStringSync();
        expect(
            svc, contains('androidx.media.app.NotificationCompat.MediaStyle'));
        expect(svc, contains('MediaSessionCompat.Token.fromToken'));
        expect(svc, contains('Notifications.CHANNEL_PLAYBACK_V2'));
        final notifs = File(
                'android/app/src/main/kotlin/com/hypertechlabs/maxplayer/Notifications.kt')
            .readAsStringSync();
        expect(notifs, contains('playback_v2'));
        expect(
            notifs,
            contains(
                'lockscreenVisibility = Notification.VISIBILITY_PUBLIC'));
        final gradle =
            File('android/app/build.gradle.kts').readAsStringSync();
        expect(gradle, contains('androidx.media'));
      });

      test('v110 docs updated; older pinned strings still intact', () {
        final md = File('PRIVACY_POLICY.md').readAsStringSync();
        expect(md, contains('5 September 2026'));
        expect(md, contains('file picker'));
        expect(md, contains('Movies/Max Player'));
        final inApp =
            File('lib/utils/privacy_policy.dart').readAsStringSync();
        expect(inApp, contains('CLOUD STORAGE IMPORT (ANDROID FILE PICKER)'));
        final terms = File('TERMS_OF_SERVICE.md').readAsStringSync();
        expect(terms, contains('HyperTech Labs'));
        final manual =
            File('lib/widgets/user_manual_sheet.dart').readAsStringSync();
        expect(manual, contains('Import from cloud storage'));
        expect(manual, contains('lock screen'));
        expect(manual.contains('Google Drive sign-in'), isFalse);
        expect(File('docs/privacy.html').readAsStringSync(),
            contains('file picker'));
      });
    });

    group('v111 import-only Cloud Storage with copy progress', () {
      test('sheet imports via picker with a cancellable progress bar', () {
        final sheet =
            File('lib/widgets/cloud_storage_sheet.dart').readAsStringSync();
        expect(sheet, contains('Import from cloud storage'));
        expect(sheet, contains('_importVideo'));
        expect(sheet, contains('LinearProgressIndicator'));
        expect(sheet, contains('pickProgressListener'));
        expect(sheet, contains('abortPickCopy'));
        expect(sheet, contains('Save to device'));
        expect(sheet.contains('Sign in with Google'), isFalse);
        final bridge =
            File('lib/services/native_bridge.dart').readAsStringSync();
        expect(bridge, contains('pickProgressListener'));
        expect(bridge, contains("case 'onPickProgress'"));
        expect(bridge, contains('abortPickCopy'));
        final mainKt = File(
                'android/app/src/main/kotlin/com/hypertechlabs/maxplayer/MainActivity.kt')
            .readAsStringSync();
        expect(mainKt, contains('onPickProgress'));
        expect(mainKt, contains('queryDocumentSize'));
        expect(mainKt, contains('safCopyAborted'));
        expect(mainKt, contains('"abortPickCopy"'));
      });

      test('sign-in docs are gone; import docs stay', () {
        final md = File('PRIVACY_POLICY.md').readAsStringSync();
        expect(md.contains('Sign in with Google'), isFalse);
        expect(md, contains('file picker'));
        expect(md, contains('Google Drive'));
        final inApp =
            File('lib/utils/privacy_policy.dart').readAsStringSync();
        expect(inApp.contains('Sign in with Google'), isFalse);
        expect(inApp, contains('CLOUD STORAGE IMPORT'));
        final terms = File('TERMS_OF_SERVICE.md').readAsStringSync();
        expect(terms.contains('Google OAuth'), isFalse);
        expect(terms, contains('file picker'));
        final manual =
            File('lib/widgets/user_manual_sheet.dart').readAsStringSync();
        expect(manual, contains('Import from cloud storage'));
        expect(manual.contains('Google Drive sign-in'), isFalse);
      });
    });

    group('v112 Play policy: MANAGE_EXTERNAL_STORAGE removed', () {
      test('no all-files permission survives anywhere user-facing', () {
        final manifest = File('android/app/src/main/AndroidManifest.xml')
            .readAsStringSync();
        expect(manifest.contains('MANAGE_EXTERNAL_STORAGE'), isFalse);
        expect(manifest, contains('v112: All-files access removed'));
        final storage =
            File('lib/utils/storage_permission.dart').readAsStringSync();
        expect(storage.contains('manageExternalStorage'), isFalse);
        final vault = File('lib/state/private_vault.dart').readAsStringSync();
        expect(vault.contains('All files access'), isFalse);
        final fm =
            File('lib/screens/file_manager_screen.dart').readAsStringSync();
        expect(fm.contains('All files access'), isFalse);
        expect(fm, contains('media storage permission'));
        final guide = File('PLAY_STORE_GUIDE.md').readAsStringSync();
        expect(guide.contains('MANAGE_EXTERNAL_STORAGE'), isFalse);
        final privacy = File('docs/privacy.html').readAsStringSync();
        expect(privacy.contains('All files access'), isFalse);
        expect(privacy, contains('MediaStore'));
        final pubspec = File('pubspec.yaml').readAsStringSync();
        expect(pubspec, contains('version: 1.0.0+112'));
      });

      test('scoped replacements are wired end-to-end', () {
        final state = File('lib/state/video_library_state.dart')
            .readAsStringSync();
        expect(state.contains('manageExternalStorage'), isFalse);
        expect(state, contains('_scanMediaStore'));
        expect(state, contains('listMediaStoreVideos'));
        final bridge =
            File('lib/services/native_bridge.dart').readAsStringSync();
        expect(bridge, contains('listMediaStoreVideos'));
        expect(bridge, contains('requestMediaDelete'));
        expect(bridge, contains('relativePath'));
        final mainKt = File(
                'android/app/src/main/kotlin/com/hypertechlabs/maxplayer/MainActivity.kt')
            .readAsStringSync();
        expect(mainKt, contains('queryMediaStoreVideoPaths'));
        expect(mainKt, contains('resolveVideoUri'));
        expect(mainKt, contains('createDeleteRequest'));
        expect(mainKt, contains('RecoverableSecurityException'));
        expect(mainKt, contains('REQ_MEDIA_DELETE'));
        expect(mainKt, contains('finishMediaDelete'));
        expect(mainKt, contains('pendingMediaDeleteResult'));
        final vault = File('lib/state/private_vault.dart').readAsStringSync();
        expect(vault, contains('requestMediaDelete'));
        expect(vault, contains("relativePath: 'Movies'"));
      });
    });
  });
}
