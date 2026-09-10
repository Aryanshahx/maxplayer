import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

import 'screens/library_screen.dart';
import 'theme.dart';
import 'utils/crash_log.dart';
import 'utils/settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // v0.6: the whole app rotates — library included (tablet landscape).
  SystemChrome.setPreferredOrientations(DeviceOrientation.values);
  MediaKit.ensureInitialized(); // MPV core
  await CrashLog.init(); // forensics armed before first frame
  await AppSettings.instance.load(); // display settings + accent
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
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(accent: AppSettings.instance.accentColor),
          home: const LibraryScreen(),
        );
      },
    );
  }
}
