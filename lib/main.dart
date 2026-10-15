import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

import 'screens/library_screen.dart';
import 'services/native_bridge.dart';
import 'theme.dart';
import 'utils/crash_log.dart';
import 'services/ad_service.dart';
import 'services/app_analytics.dart';
import 'services/referral_service.dart';
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
  // v1.0.1+58: Refer & Earn — load local state (incl. the OFFLINE-usable
  // ad-free flag) BEFORE the first frame so ads never flash; the
  // Firestore sync continues unawaited in the background.
  await ReferralService.instance.init();
  runApp(const MaxPlayerApp());
  // v1.0.1+50: AdMob warms up AFTER the first frame — it can never
  // block or crash startup (no Play services? → the app stays ad-free).
  unawaited(AdService.instance.safeInit());
  // v1.0.1+58: behavior counters for the admin dashboard.
  AppAnalytics.instance.log('app_open');
  AppAnalytics.instance.bumpDaily(appOpens: 1);
  AppAnalytics.instance.bumpTotal('installs');
}

class MaxPlayerApp extends StatelessWidget {
  const MaxPlayerApp({super.key});

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
