import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

import 'screens/library_screen.dart';
import 'services/native_bridge.dart';
import 'theme.dart';
import 'utils/crash_log.dart';
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
  runApp(const MaxPlayerApp());
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

