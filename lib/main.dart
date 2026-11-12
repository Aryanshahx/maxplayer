import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  runApp(const MaxPlayerApp());
  // v1.0.1+50: AdMob warms up AFTER the first frame — it can never
  // block or crash startup (no Play services? → the app stays ad-free).
  unawaited(AdService.instance.safeInit());
  // v1.0.1+63: anonymous activity counters for the admin dashboard
  // (aggregates only — no names, no URLs, no personal data).
  unawaited(AppAnalytics.instance.trackAppOpen());
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
    // After the first frame: upload any queued crash report, then check
    // for an admin broadcast ("notification with image").
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
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
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
    try {
      final b = await AppAnalytics.instance.fetchBroadcast();
      if (b == null) return;
      final prefs = await SharedPreferences.getInstance();
      if ((prefs.getString('bc.seen') ?? '') == b['id']) return; // seen
      await prefs.setString('bc.seen', b['id']!);
      final ctx = rootNavigatorKey.currentContext;
      if (ctx == null || !ctx.mounted) return;
      await showDialog<void>(context: ctx, builder: (_) => _BroadcastDialog(b));
    } catch (_) {}
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

/// v1.0.1+65: admin broadcast ("notification with image") — shown once
/// per message id on the next app open.
class _BroadcastDialog extends StatelessWidget {
  const _BroadcastDialog(this.data);

  final Map<String, String> data;

  @override
  Widget build(BuildContext context) {
    final image = data['image'] ?? '';
    return AlertDialog(
      backgroundColor: const Color(0xFF16161F),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text(
        data['title'] ?? '',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (image.isNotEmpty) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                image,
                height: 150,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if ((data['body'] ?? '').isNotEmpty)
            Text(
              data['body']!,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('OK', style: TextStyle(color: AppColors.accent)),
        ),
      ],
    );
  }
}
