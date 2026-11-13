import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'services/push_service.dart';
import 'services/notification_destination.dart';
import 'screens/discover_screen.dart';
import 'screens/notification_movie_screen.dart';

import 'screens/private_screen.dart';

import 'screens/folders_screen.dart';

import 'screens/playlists_screen.dart';

import 'screens/audio_screen.dart';

import 'screens/network_storage_screen.dart';

import 'screens/cloud_storage_screen.dart';

import 'screens/quick_share_screen.dart';

import 'screens/open_stream_screen.dart';

import 'screens/iptv_screen.dart';

import 'screens/statistics_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:media_kit/media_kit.dart';

import 'screens/library_screen.dart';
import 'services/native_bridge.dart';
import 'theme.dart';
import 'utils/crash_log.dart';
import 'services/ad_service.dart';
import 'services/app_analytics.dart';
import 'utils/settings.dart';

/// Root navigator key (kept for future system-level pushes; the
/// notification deep links that used it are gone).
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

Future<void> _flushCapturedCrash() async {
  if (!AppAnalytics.ready.value) return;
  try {
    final report = await CrashLog.peekCrashReport();
    if (report != null &&
        await AppAnalytics.instance.uploadCapturedCrash(report)) {
      await CrashLog.clearCrashReport(report);
    }
  } catch (_) {
    /* keep the report for a later launch */
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // v0.6: the whole app rotates — library included (tablet landscape).
  SystemChrome.setPreferredOrientations(DeviceOrientation.values);
  MediaKit.ensureInitialized(); // MPV core
  await CrashLog.init(); // forensics armed before first frame
  await AppSettings.instance.load(); // display settings + accent
  // Single dispatcher for every `maxplayer/native` incoming event
  // (PiP button, whisper AI-subtitle progress, voice-search callbacks).
  // Must be registered once, before any screen tries to handle the same
  // channel - a second setMethodCallHandler silently replaces the first.
  NativeBridge.ensureNativeHandler();
  CrashLog.crumb('app.start');
  // v1.0.1+65: fold framework errors into CrashLog so the next launch
  // can upload them to the admin panel as crash reports.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    CrashLog.captureCrash(
      'flutter.error',
      details.exceptionAsString(),
      details.stack,
      fatal: false,
    );
    unawaited(_flushCapturedCrash());
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    CrashLog.captureCrash('dart.error', error, stack, fatal: true);
    return false; // still let the default handler act
  };
  FirebaseMessaging.onBackgroundMessage(maxPlayerPushBackground);
  runApp(const MaxPlayerApp());
  // v1.0.1+50: AdMob warms up AFTER the first frame — it can never
  // block or crash startup (no Play services? → the app stays ad-free).
  unawaited(AdService.instance.safeInit());
  // v1.0.1+63: anonymous activity counters for the admin dashboard
  // (aggregates only — no names, no URLs, no personal data).
  unawaited(() async {
    await AppAnalytics.instance.trackAppOpen();
    unawaited(_flushCapturedCrash());
    await PushService.instance.start();
  }());
}

class MaxPlayerApp extends StatefulWidget {
  const MaxPlayerApp({super.key});

  @override
  State<MaxPlayerApp> createState() => _MaxPlayerAppState();
}

class _MaxPlayerAppState extends State<MaxPlayerApp>
    with WidgetsBindingObserver {
  DateTime _resumedAt = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // After the first frame: upload crash report and attach tray-tap handling.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_postLaunchTasks());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // v1.0.1+65: "how much time they are spending on app" — foreground
    // seconds, flushed every time the app backgrounds (Firestore queues
    // offline, so no network is fine).
    if (state == AppLifecycleState.resumed) {
      _resumedAt = DateTime.now();
      unawaited(() async {
        await PushService.instance.start();
        await PushService.instance.requestOnForeground();
      }());
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      if (state == AppLifecycleState.paused ||
          state == AppLifecycleState.detached) {
        PushService.instance.backgrounded();
      }
      final secs = DateTime.now().difference(_resumedAt).inSeconds;
      if (secs > 0) AppAnalytics.instance.trackSession(secs);
      _resumedAt = DateTime.now();
    }
  }

  Future<void> _postLaunchTasks() async {
    PushService.instance.onTap = (data) {
      final navigator = rootNavigatorKey.currentState;
      if (navigator == null) return;
      final screen = notificationDestination(data);
      if (screen == 'external') {
        final link = notificationExternalLink(data);
        if (link != null) {
          unawaited(launchUrl(link, mode: LaunchMode.externalApplication));
        }
        return;
      }
      if (screen == 'home') {
        navigator.popUntil((route) => route.isFirst);
        return;
      }
      final Widget page = switch (screen) {
        'movie' => NotificationMovieScreen(data: data),
        'discover' => const DiscoverScreen(videos: []),
        'private' => const PrivateScreen(),
        'folders' => const FoldersScreen(),
        'playlists' => const PlaylistsScreen(),
        'audio' => const AudioScreen(),
        'network' => const NetworkStorageScreen(),
        'cloud' => const CloudStorageScreen(),
        'quickShare' => const QuickShareScreen(),
        'stream' => const OpenStreamScreen(),
        'iptv' => const IptvScreen(),
        'statistics' => const StatisticsScreen(),
        _ => const LibraryScreen(),
      };
      navigator.push(MaterialPageRoute<void>(builder: (_) => page));
    };
    // Read the local notification tap before Firebase auth/token/network work.
    unawaited(PushService.instance.readLaunchTap());
    if (PushService.instance.pendingTap != null) {
      final pending = PushService.instance.pendingTap!;
      PushService.instance.pendingTap = null;
      PushService.instance.onTap?.call(pending);
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    // Rebuilds MaterialApp when accent changes (Display Settings wheel).
    return ListenableBuilder(
      listenable: AppSettings.instance,
      builder: (context, _) {
        AppColors.accent = AppSettings.instance.accentColor;
        return MaterialApp(
          title: 'Max Player',
          navigatorKey: rootNavigatorKey,
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(accent: AppColors.accent),
          home: const LibraryScreen(),
        );
      },
    );
  }
}
