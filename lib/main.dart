import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'services/push_service.dart';
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
    CrashLog.error('flutter.error', details.exceptionAsString());
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    CrashLog.error('dart.error', error, {'stack': stack.toString()});
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
    try {
      final report = await CrashLog.takeReport();
      if (report != null) {
        AppAnalytics.instance.sendReport(type: 'crash', text: report);
      }
    } catch (_) {}
    PushService.instance.onTap = (data) {
      // A tray tap opens MaxPlayer, or an explicitly supplied safe HTTPS link.
      final link = Uri.tryParse(data['link'] as String? ?? '');
      if (link != null &&
          link.scheme == 'https' &&
          link.host.isNotEmpty &&
          link.userInfo.isEmpty) {
        unawaited(launchUrl(link, mode: LaunchMode.externalApplication));
      }
    };
    if (PushService.instance.pendingTap != null) {
      final pending = PushService.instance.pendingTap!;
      PushService.instance.pendingTap = null;
      PushService.instance.onTap?.call(pending);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Rebuilds MaterialApp when accent changes (Display Settings wheel).
    return ListenableBuilder(
      listenable: AppSettings.instance,
      builder: (context, _) {
        AppColors.accent = AppSettings.instance.accentColor;
        return MaterialApp(
          title: 'Max Player',
          navigatorKey: rootNavigatorKey,
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(accent: AppSettings.instance.accentColor),
          home: const LibraryScreen(),
        );
      },
    );
  }
}
